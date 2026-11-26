package io.aote.vpnService

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * Only the scheduling half of the updater is covered here.
 *
 * The download, the profile script and the app-owned key overlay moved into the
 * Go core (`refreshProfile`) and are tested in
 * `packages/clash_core/core/internal/profilerefresh`, so there is no Kotlin
 * implementation left to test for those.
 */
class ProfileConfigUpdaterTest {
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