package io.aote.vpnService

internal object VpnServiceContract {
    const val ACTION_START = "io.aote.vpnService.action.START"
    const val ACTION_STOP = "io.aote.vpnService.action.STOP"
    const val EXTRA_CONFIG_DIR = "configDir"
    const val EXTRA_RESULT_RECEIVER = "resultReceiver"
    const val EXTRA_ALLOW_LIST = "allowList"
    const val EXTRA_ALLOWED_APPLICATIONS = "allowedApplications"
    const val EXTRA_DISALLOWED_APPLICATIONS = "disallowedApplications"

    /** onTaskRemoved 自恢复重启：核心已在运行时跳过重建 TUN。 */
    const val EXTRA_RESUME_ONLY = "resumeOnly"
}
