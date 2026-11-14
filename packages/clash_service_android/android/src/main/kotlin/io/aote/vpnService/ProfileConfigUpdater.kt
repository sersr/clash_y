package io.aote.vpnService

import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import java.util.logging.Level
import java.util.logging.Logger
import com.google.gson.Gson
import com.google.gson.JsonElement
import com.google.gson.JsonNull
import com.google.gson.JsonObject
import com.google.gson.JsonPrimitive
import org.mozilla.javascript.Context
import org.yaml.snakeyaml.DumperOptions
import org.yaml.snakeyaml.LoaderOptions
import org.yaml.snakeyaml.Yaml
import org.yaml.snakeyaml.constructor.SafeConstructor

/**
 * The profile the VPN service keeps up to date while the Flutter app is gone.
 *
 * The app persists the same values, so a sticky restart can resume the
 * schedule without help from Dart.
 */
internal data class ProfileUpdate(
    val url: String,
    val intervalMinutes: Int,
    val updateTimeMs: Long,
    val script: String = "",
) {
    val isScheduled: Boolean
        get() = url.isNotEmpty() && intervalMinutes > 0

    /**
     * Milliseconds until the next download, or `null` when not scheduled.
     *
     * An overdue (or never downloaded) profile still waits [MIN_DELAY_MS] so a
     * service start is not immediately followed by another restart.
     */
    fun nextDelayMs(now: Long = System.currentTimeMillis()): Long? {
        if (!isScheduled) return null
        val due = if (updateTimeMs <= 0L) {
            now
        } else {
            updateTimeMs + intervalMinutes * 60_000L
        }
        return (due - now).coerceAtLeast(MIN_DELAY_MS)
    }

    companion object {
        const val MIN_DELAY_MS = 5_000L

        fun fromExtras(
            url: String?,
            interval: String?,
            updateTime: String?,
            script: String? = null,
        ): ProfileUpdate? {
            val profileUrl = url?.trim().orEmpty()
            val minutes = interval?.trim()?.toIntOrNull() ?: 0
            if (profileUrl.isEmpty() || minutes <= 0) return null
            return ProfileUpdate(
                url = profileUrl,
                intervalMinutes = minutes,
                updateTimeMs = updateTime?.trim()?.toLongOrNull() ?: 0L,
                script = script.orEmpty(),
            )
        }
    }
}

/**
 * Rewrites `config.yaml` with a freshly downloaded subscription.
 *
 * The subscription only provides proxies and rules; the device specific
 * settings written by the app (ports, TUN, DNS, controller socket...) are
 * carried over from the running config before the profile script is applied.
 */
internal object ConfigUpdater {
    private const val CONFIG_NAME = "config.yaml"
    private const val TAG = "ClashVpnService"
    private val logger = Logger.getLogger(TAG)

    /** Top-level keys owned by the app rather than the subscription. */
    val overrideKeys = listOf(
        "external-controller-unix",
        "external-controller-pipe",
        "log-level",
        "mixed-port",
        "mode",
        "ipv6",
        "allow-lan",
        "tun",
        "dns",
    )

    /**
     * Downloads [url] and writes it to `<configDir>/config.yaml`.
     *
     * Returns the backup holding the previous config so the caller can roll
     * back when the core rejects the new one.
     */
    fun updateConfig(configDir: String, url: String, script: String = ""): File {
        val configFile = File(configDir, CONFIG_NAME)
        val current = configFile.readText()
        val downloaded = download(url)
        val merged = applyOverrides(downloaded, current)
        val configured = if (script.isBlank()) merged else applyScript(merged, script)

        val backup = File(configDir, "$CONFIG_NAME.bak")
        configFile.copyTo(backup, overwrite = true)
        writeAtomically(configFile, configured)
        return backup
    }

    internal fun applyScript(config: String, script: String): String {
        val loader = Yaml(SafeConstructor(LoaderOptions()))
        val configMap = loader.load<Any?>(config) as? Map<*, *>
            ?: throw IllegalArgumentException("subscription config must be a YAML map")
        val gson = Gson()
        val inputJson = gson.toJson(configMap)
        val context = Context.enter()
        try {
            try {
                context.optimizationLevel = -1
                context.languageVersion = Context.VERSION_ES6
                val scope = context.initSafeStandardObjects()
                context.evaluateString(scope, script, "profile-script.js", 1, null)
                scope.put("profileConfigJson", scope, inputJson)
                val result = context.evaluateString(
                    scope,
                    "JSON.stringify(main(JSON.parse(profileConfigJson)))",
                    "profile-script-main.js",
                    1,
                    null,
                )
                if (result === org.mozilla.javascript.Undefined.instance) {
                    throw IllegalArgumentException("profile script returned no config")
                }
                val output = gson.fromJson(Context.toString(result), JsonElement::class.java)
                val outputMap = jsonValueToYamlValue(output) as? Map<*, *>
                    ?: throw IllegalArgumentException("profile script must return a config map")
                val options = DumperOptions().apply {
                    defaultFlowStyle = DumperOptions.FlowStyle.BLOCK
                    indent = 2
                }
                return Yaml(options).dump(outputMap)
            } catch (error: Exception) {
                logger.log(
                    Level.SEVERE,
                    "profile script failed; keeping the unmodified config",
                    error,
                )
                return config
            }
        } finally {
            Context.exit()
        }
    }

    private fun jsonValueToYamlValue(value: JsonElement): Any? = when {
        value is JsonNull -> null
        value is JsonObject -> value.entrySet().associate { (key, child) ->
            key to jsonValueToYamlValue(child)
        }
        value.isJsonArray -> value.asJsonArray.map(::jsonValueToYamlValue)
        value is JsonPrimitive -> when {
            value.isBoolean -> value.asBoolean
            value.isNumber -> {
                val number = value.asString
                if (number.matches(Regex("-?(0|[1-9][0-9]*)"))) {
                    number.toBigInteger()
                } else {
                    number.toBigDecimalOrNull()
                        ?: throw IllegalArgumentException(
                            "invalid numeric value in profile script output",
                        )
                }
            }
            else -> value.asString
        }
        else -> throw IllegalArgumentException("unsupported value in profile script output")
    }

    fun download(url: String): String {
        val connection = URI(url).toURL().openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            connection.instanceFollowRedirects = true
            connection.setRequestProperty("User-Agent", "clash/mihomo")

            val status = connection.responseCode
            if (status !in 200..299) {
                throw IOException("unexpected status $status")
            }
            val body = connection.inputStream.bufferedReader().use { it.readText() }
            if (body.isBlank()) throw IOException("empty response")
            return body
        } finally {
            connection.disconnect()
        }
    }

    fun writeAtomically(file: File, content: String) {
        val temporary = File(file.parentFile, "${file.name}.tmp")
        temporary.writeText(content)
        if (!temporary.renameTo(file)) {
            file.writeText(content)
            temporary.delete()
        }
    }

    /** Keeps the app owned top-level blocks of [current] in [downloaded]. */
    fun applyOverrides(downloaded: String, current: String): String {
        var result = downloaded
        for (key in overrideKeys) {
            val block = extractTopLevelBlock(current, key) ?: continue
            result = replaceTopLevelBlock(result, key, block)
        }
        return result
    }

    internal fun extractTopLevelBlock(text: String, key: String): String? {
        val lines = text.lines()
        val start = lines.indexOfFirst { isTopLevelKey(it, key) }
        if (start < 0) return null

        var end = start + 1
        while (end < lines.size && !startsTopLevelNode(lines[end])) end++
        return lines.subList(start, end).joinToString("\n").trimEnd('\n')
    }

    internal fun replaceTopLevelBlock(text: String, key: String, block: String): String {
        val lines = text.lines().toMutableList()
        val blockLines = block.lines()
        var index = 0
        var replaced = false

        while (index < lines.size) {
            if (!isTopLevelKey(lines[index], key)) {
                index++
                continue
            }
            var end = index + 1
            while (end < lines.size && !startsTopLevelNode(lines[end])) end++
            lines.subList(index, end).clear()
            if (!replaced) {
                lines.addAll(index, blockLines)
                index += blockLines.size
            }
            replaced = true
        }

        if (!replaced) {
            if (lines.isNotEmpty() && lines.last().isNotBlank()) lines.add("")
            lines.addAll(blockLines)
        }
        return lines.joinToString("\n")
    }

    private fun isTopLevelKey(line: String, key: String): Boolean {
        if (line.isEmpty() || line[0].isWhitespace() || line[0] == '#') return false
        val colon = line.indexOf(':')
        if (colon <= 0) return false
        return line.substring(0, colon).trim() == key
    }

    private fun startsTopLevelNode(line: String): Boolean =
        line.isNotEmpty() && !line[0].isWhitespace() && line[0] != '#'
}
