package io.aote.vpnService

import java.io.File
import java.io.IOException

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
 * The download, the profile script and the overlay of app-owned keys all run in
 * the Go core (`refreshProfile`), the same code the desktop daemon and the iOS
 * Packet Tunnel use. Keeping one implementation guarantees a background refresh
 * produces the same file as a refresh started from the app.
 */
internal object ConfigUpdater {
    private const val CONFIG_NAME = "config.yaml"
    private const val BACKUP_NAME = "$CONFIG_NAME.bak"

    /**
     * Asks the core to refresh [configDir]'s `config.yaml` from [url].
     *
     * Returns the `.bak` file the core wrote next to the config so the caller
     * can roll back when the core rejects the new one.
     *
     * @throws IOException when the refresh fails; the config on disk is then
     *   left untouched.
     */
    fun updateConfig(configDir: String, url: String, script: String = ""): File {
        val configFile = File(configDir, CONFIG_NAME)
        if (!configFile.exists()) {
            throw IOException("config.yaml is missing in $configDir")
        }

        // The core writes both the backup and the new config, so the app only
        // holds the snapshot it needs to roll back to.
        val error = ClashCore().refreshProfile(configDir, url, script)
        if (error != null) {
            throw IOException(error)
        }
        return File(configDir, BACKUP_NAME)
    }

    /** Replaces [file] with [content], via a temporary file in the same dir. */
    fun writeAtomically(file: File, content: String) {
        val temp = File(file.parentFile, "${file.name}.tmp")
        temp.writeText(content)
        if (!temp.renameTo(file)) {
            file.writeText(content)
            temp.delete()
        }
    }
}