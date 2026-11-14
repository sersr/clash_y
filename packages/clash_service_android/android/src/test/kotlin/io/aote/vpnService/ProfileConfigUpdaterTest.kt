package io.aote.vpnService

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ProfileConfigUpdaterTest {
    private val current = """
        mixed-port: 7891
        mode: global
        dns:
          enable: true
          nameserver:
            - 223.5.5.5
        tun:
          enable: true
          stack: system
        proxies: []
    """.trimIndent()

    private val downloaded = """
        mixed-port: 7890
        mode: rule
        dns:
          enable: false
        proxy-groups:
          - name: auto
            type: url-test
            proxies: [a, b]
        proxies:
          - name: a
            type: ss
          - name: b
            type: ss
    """.trimIndent()

    @Test
    fun keepsTheAppOwnedBlocks() {
        val merged = ConfigUpdater.applyOverrides(downloaded, current)

        assertTrue(merged.contains("mixed-port: 7891"), merged)
        assertTrue(merged.contains("mode: global"), merged)
        assertTrue(merged.contains("stack: system"), merged)
        assertFalse(merged.contains("mixed-port: 7890"), merged)
        // Subscription content survives.
        assertTrue(merged.contains("proxy-groups:"), merged)
        assertTrue(merged.contains("name: b"), merged)
        // Duplicates left behind by the subscription are dropped.
        assertEquals(1, merged.lines().count { it.trim() == "dns:" })
    }

    @Test
    fun appendsOverridesMissingFromTheDownload() {
        val merged = ConfigUpdater.applyOverrides("proxies: []", current)

        assertTrue(merged.contains("tun:"), merged)
        assertTrue(merged.contains("mixed-port: 7891"), merged)
    }

    @Test
    fun leavesTheDocumentAloneWithoutOverrides() {
        val plain = "mode: rule\nproxies: []"

        assertEquals(plain, ConfigUpdater.applyOverrides(plain, "proxies: []"))
    }

    @Test
    fun appliesProfileScriptToTheMergedConfig() {
        val merged = ConfigUpdater.applyOverrides(
            "mode: rule\nmixed-port: 7890\nproxies: []",
            current,
        )
        val result = ConfigUpdater.applyScript(
            merged,
            """
                function main(config) {
                    config.mode = "global";
                    config.proxies.push({ name: "scripted", type: "direct" });
                    return config;
                }
            """.trimIndent(),
        )

        assertTrue(result.contains("mode: global"), result)
        assertTrue(result.contains("mixed-port: 7891"), result)
        assertTrue(result.contains("name: scripted"), result)
        assertTrue(result.contains("type: direct"), result)
    }

    @Test
    fun keepsTheOriginalConfigWhenTheScriptFails() {
        val original = "mode: rule\nproxies: []"

        assertEquals(
            original,
            ConfigUpdater.applyScript(
                original,
                "function main(config) { throw new Error('script failed'); }",
            ),
        )
        assertEquals(
            original,
            ConfigUpdater.applyScript(
                original,
                "function main(config) { return null; }",
            ),
        )
    }

    @Test
    fun extractsBlocksThatRunToTheEnd() {
        val block = ConfigUpdater.extractTopLevelBlock(current, "tun")

        assertNotNull(block)
        assertTrue(block.startsWith("tun:"), block)
        assertTrue(block.contains("stack: system"), block)
    }

    @Test
    fun delaysUntilTheIntervalElapsed() {
        val now = 1_000_000L
        val due = ProfileUpdate(
            url = "https://example.com/sub",
            intervalMinutes = 10,
            updateTimeMs = now - 60_000L,
        )

        assertEquals(9 * 60_000L, due.nextDelayMs(now))
    }

    @Test
    fun waitsTheMinimumDelayWhenOverdue() {
        val update = ProfileUpdate("https://example.com/sub", 10, 1L)

        assertEquals(ProfileUpdate.MIN_DELAY_MS, update.nextDelayMs())
    }

    @Test
    fun hasNoScheduleWithoutUrlOrInterval() {
        assertNull(ProfileUpdate("", 10, 0L).nextDelayMs())
        assertNull(ProfileUpdate("https://example.com/sub", 0, 0L).nextDelayMs())
        assertNull(ProfileUpdate.fromExtras("", "10", "0"))
        assertNull(ProfileUpdate.fromExtras("https://example.com/sub", "0", "0"))
        assertEquals(
            ProfileUpdate("https://example.com/sub", 10, 5L),
            ProfileUpdate.fromExtras("https://example.com/sub", "10", "5"),
        )
        assertEquals(
            "function main(config) { return config; }",
            ProfileUpdate.fromExtras(
                "https://example.com/sub",
                "10",
                "5",
                "function main(config) { return config; }",
            )?.script,
        )
    }
}
