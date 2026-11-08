package io.aote.vpnService

internal object VpnServiceContract {
    const val ACTION_START = "io.aote.vpnService.action.START"
    const val ACTION_START_CORE = "io.aote.vpnService.action.START_CORE"
    const val ACTION_RELOAD_CONFIG = "io.aote.vpnService.action.RELOAD_CONFIG"
    const val ACTION_STOP = "io.aote.vpnService.action.STOP"
    const val ACTION_STOP_VPN = "io.aote.vpnService.action.STOP_VPN"

    /** 只更新自动刷新用的 Profile，不重启内核。 */
    const val ACTION_UPDATE_PROFILE = "io.aote.vpnService.action.UPDATE_PROFILE"

    const val EXTRA_CONFIG_DIR = "configDir"
    const val EXTRA_PROFILE_URL = "profileUrl"
    const val EXTRA_PROFILE_NAME = "profileName"
    const val EXTRA_CONTROLLER_SOCKET = "controllerSocket"
    const val EXTRA_UPDATE_INTERVAL = "updateInterval"
    const val EXTRA_UPDATE_TIME = "updateTime"
    const val EXTRA_RESULT_RECEIVER = "resultReceiver"
    const val EXTRA_ALLOW_LIST = "allowList"
    const val EXTRA_ALLOWED_APPLICATIONS = "allowedApplications"
    const val EXTRA_DISALLOWED_APPLICATIONS = "disallowedApplications"

    /** onTaskRemoved 自恢复重启：核心已在运行时跳过重建 TUN。 */
    const val EXTRA_RESUME_ONLY = "resumeOnly"
}
