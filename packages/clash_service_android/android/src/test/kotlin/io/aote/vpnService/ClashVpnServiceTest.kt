package io.aote.vpnService

import kotlin.test.Test
import kotlin.test.assertEquals

class ClashVpnServiceTest {
    @Test
    fun allowListIncludesTheVpnPackage() {
        assertEquals(
            listOf("org.telegram.messenger", "io.aote.clashy"),
            selectedApplications(
                selected = listOf("org.telegram.messenger"),
                allowList = true,
                appPackageName = "io.aote.clashy",
            ),
        )
    }

    @Test
    fun emptyAllowListStillIncludesTheVpnPackage() {
        assertEquals(
            listOf("io.aote.clashy"),
            selectedApplications(
                selected = emptyList(),
                allowList = true,
                appPackageName = "io.aote.clashy",
            ),
        )
    }

    @Test
    fun globalOrDenyListModeKeepsAllApplicationsInsideTheVpn() {
        assertEquals(
            emptyList(),
            selectedApplications(
                selected = listOf("org.telegram.messenger"),
                allowList = false,
                appPackageName = "io.aote.clashy",
            ),
        )
    }

    @Test
    fun disallowListExcludesTheVpnPackage() {
        assertEquals(
            listOf("org.telegram.messenger"),
            effectiveDisallowedApplications(
                selected = listOf("org.telegram.messenger", "io.aote.clashy"),
                appPackageName = "io.aote.clashy",
            ),
        )
    }

    @Test
    fun formatsLiveTrafficRates() {
        assertEquals("0 B/s", formatTrafficRate(0))
        assertEquals("1023 B/s", formatTrafficRate(1023))
        assertEquals("1.0 KB/s", formatTrafficRate(1024))
        assertEquals("1.0 MB/s", formatTrafficRate(1024 * 1024))
    }

    @Test
    fun clampsNegativeTrafficRatesToZero() {
        assertEquals("0 B/s", formatTrafficRate(-1))
    }
}
