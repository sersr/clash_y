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
}
