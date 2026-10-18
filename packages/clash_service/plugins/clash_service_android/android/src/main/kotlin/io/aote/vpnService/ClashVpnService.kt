package io.aote.vpnService

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.os.ResultReceiver
import android.util.Log
import java.io.File
import java.util.concurrent.Executors

/**
 * Android-only VpnService.
 *
 * Runtime state is only the live TUN descriptors owned by this service
 * instance. The last requested on/off switch and the configDir are
 * persisted in SharedPreferences so a sticky restart (intent == null, e.g.
 * after the process is killed) can restore the configuration — and refuse
 * to come back up when the user left the VPN off.
 */
class ClashVpnService : VpnService() {

    companion object {
        private const val TAG = "ClashVpnService"
        private const val CHANNEL_ID = "clash_vpn_service"
        private const val NOTIFICATION_ID = 0x434C4153 // "CLAS"

        private const val DEFAULT_CONFIG_DIR = "clashy/clash_config"

        private const val PREFS_NAME = "clash_vpn_state"
        private const val KEY_ENABLED = "enabled"
        private const val KEY_CONFIG_DIR = "configDir"
        private const val KEY_ALLOWED_APPS = "allowedApplications"
        private const val KEY_DISALLOWED_APPS = "disallowedApplications"

        private const val TUN_ADDRESS = "172.19.0.1"
        private const val TUN_ADDRESS_PREFIX = 30
        private const val TUN_DNS = "172.19.0.2"
        private const val TUN_MTU = 9000
    }

    private val executor = Executors.newSingleThreadExecutor()

    private val prefs by lazy { getSharedPreferences(PREFS_NAME, MODE_PRIVATE) }

    private var tunDescriptor: ParcelFileDescriptor? = null

    @Volatile
    private var nativeTunFd = -1

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val receiver = intent?.getResultReceiver()
        try {
            startForeground(NOTIFICATION_ID, buildNotification())
        } catch (t: Throwable) {
            val message = "Failed to start foreground service: ${t.message ?: t.javaClass.simpleName}"
            Log.e(TAG, message, t)
            sendResult(receiver, false, message)
            stopSelf()
            return START_NOT_STICKY
        }

        return when (intent?.action) {
            VpnServiceContract.ACTION_START, null -> {
                // intent == null：系统 sticky 重启（进程被杀后自启）。
                // 从持久化状态恢复：开关为关则不拉起 VPN，直接退出。
                if (intent == null && !isVpnEnabled()) {
                    Log.i(TAG, "sticky restart with the persisted switch off, not starting VPN")
                    stopForegroundCompat()
                    stopSelf()
                    return START_NOT_STICKY
                }
                handleStart(intent)
                START_STICKY
            }

            VpnServiceContract.ACTION_STOP -> {
                handleStop(intent)
                START_NOT_STICKY
            }

            else -> {
                sendResult(receiver, false, "Unknown VpnService action")
                stopSelf()
                START_NOT_STICKY
            }
        }
    }

    override fun onRevoke() {
        Log.i(TAG, "VPN permission revoked")
        // 授权被撤销：持久化开关同步关闭，避免 sticky 重启再拉起
        setEnabled(false)
        executor.execute {
            cleanup()
            stopForegroundCompat()
            stopSelf()
        }
        super.onRevoke()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // OEM ROM（MIUI/EMUI/ColorOS 等）在用户划掉 App 时会连前台服务和
        // 进程一起杀掉，并取消 START_STICKY 的系统重启。这里显式重新拉起
        // 自己（依赖用户授予的自启动权限），让服务在划掉后继续存活：
        // - 进程实际被杀：重启请求由系统投递到新实例，按持久化状态恢复；
        // - 进程未死（原生 ROM）：resumeOnly 标记让新指令跳过重建 TUN。
        // 持久化开关为关时不复活，划掉即彻底退出。
        if (isVpnEnabled()) {
            Log.i(TAG, "task removed while VPN enabled, restarting self")
            try {
                val restart = Intent(applicationContext, ClashVpnService::class.java).apply {
                    action = VpnServiceContract.ACTION_START
                    putExtra(VpnServiceContract.EXTRA_RESUME_ONLY, true)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(restart)
                } else {
                    startService(restart)
                }
            } catch (t: Throwable) {
                Log.w(TAG, "failed to restart after task removed", t)
            }
        } else {
            Log.i(TAG, "task removed with the persisted switch off, letting the service die")
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        Log.i(TAG, "onDestroy")
        cleanup()
        executor.shutdownNow()
        super.onDestroy()
    }

    private fun handleStart(intent: Intent?) {
        val receiver = intent?.getResultReceiver()

        // onTaskRemoved 自恢复：进程未被杀、TUN 还在时无需重建
        if (intent?.getBooleanExtra(VpnServiceContract.EXTRA_RESUME_ONLY, false) == true &&
            nativeTunFd > 0
        ) {
            Log.i(TAG, "resume-only restart, TUN still up (nativeFd=$nativeTunFd)")
            return
        }

        // 显式传入优先；sticky 重启（intent == null）时从持久化恢复
        val configDir = intent
            ?.getStringExtra(VpnServiceContract.EXTRA_CONFIG_DIR)
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: prefs.getString(KEY_CONFIG_DIR, null)?.trim()
            ?: defaultConfigDir()

        if (configDir.isEmpty()) {
            sendResult(receiver, false, "configDir is empty")
            stopSelf()
            return
        }

        val allowedApplications = intent?.getStringArrayListExtra(
            VpnServiceContract.EXTRA_ALLOWED_APPLICATIONS
        ) ?: prefs.getStringSet(KEY_ALLOWED_APPS, null)?.toList().orEmpty()
        val disallowedApplications = intent?.getStringArrayListExtra(
            VpnServiceContract.EXTRA_DISALLOWED_APPLICATIONS
        ) ?: prefs.getStringSet(KEY_DISALLOWED_APPS, null)?.toList().orEmpty()

        executor.execute {
            startCore(configDir, receiver, allowedApplications, disallowedApplications)
        }
    }

    private fun startCore(
        configDir: String,
        receiver: ResultReceiver?,
        allowedApplications: List<String>,
        disallowedApplications: List<String>,
    ) {
        Log.i(TAG, "startCore configDir=$configDir")
        var detachedNativeFd = -1
        try {
            // Replace any previous instance cleanly. This is a no-op on the
            // first start.
            stopCore()
            releaseNativeTunFd()
            closeTunDescriptor()

            val descriptor = establishTun(allowedApplications, disallowedApplications)
                ?: throw IllegalStateException("VpnService.establish() returned null")
            tunDescriptor = descriptor

            // Keep ownership of the original fd and let mihomo own a duplicate.
            val nativeDescriptor = descriptor.dup()
            detachedNativeFd = nativeDescriptor.detachFd()
            nativeTunFd = detachedNativeFd

            val error = ClashCore().startTun(configDir, detachedNativeFd) { protectFd ->
                protect(protectFd)
            }
            if (error != null) {
                throw IllegalStateException(error)
            }

            persistState(configDir, allowedApplications, disallowedApplications, enabled = true)
            sendResult(receiver, true)
            Log.i(TAG, "mihomo started, configDir=$configDir nativeFd=$detachedNativeFd")
        } catch (t: Throwable) {
            releaseNativeTunFd(detachedNativeFd)
            closeTunDescriptor()
            val message = t.message ?: t.javaClass.simpleName
            Log.e(TAG, "Failed to start VpnService", t)
            sendResult(receiver, false, message)
            stopForegroundCompat()
            stopSelf()
        }
    }

    private fun handleStop(intent: Intent?) {
        val receiver = intent?.getResultReceiver()
        executor.execute {
            // 先关持久化开关：即使随后进程被杀，sticky 重启也不会再拉起
            setEnabled(false)
            val error = stopCore()
            releaseNativeTunFd()
            closeTunDescriptor()
            val message = error ?: ""
            sendResult(receiver, message.isEmpty(), message)
            stopForegroundCompat()
            stopSelf()
        }
    }

    private fun cleanup() {
        stopCore()
        releaseNativeTunFd()
        closeTunDescriptor()
    }

    private fun stopCore(): String? {
        Log.i(TAG, "stopCore")
        return try {
            val error = ClashCore().stop()
            Log.i(TAG, "stopCore result: ${error ?: "ok"}")
            error
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to stop mihomo", t)
            t.message ?: t.javaClass.simpleName
        }
    }

    private fun establishTun(
        allowedApplications: List<String>,
        disallowedApplications: List<String>,
    ): ParcelFileDescriptor? {
        val builder = Builder()
            .setSession("clashy")
            .setMtu(TUN_MTU)
            .addAddress(TUN_ADDRESS, TUN_ADDRESS_PREFIX)
            .addDnsServer(TUN_DNS)
            .addRoute("0.0.0.0", 0)
            .setBlocking(false)

        val effectiveAllowed = if (disallowedApplications.isEmpty()) {
            allowedApplications
        } else {
            emptyList()
        }
        effectiveAllowed.forEach { packageName ->
            try {
                builder.addAllowedApplication(packageName)
            } catch (t: Throwable) {
                Log.w(TAG, "addAllowedApplication failed: $packageName", t)
            }
        }
        disallowedApplications.forEach { packageName ->
            try {
                builder.addDisallowedApplication(packageName)
            } catch (t: Throwable) {
                Log.w(TAG, "addDisallowedApplication failed: $packageName", t)
            }
        }

        return builder.establish()
    }


    private fun releaseNativeTunFd(fd: Int = nativeTunFd) {
        if (fd <= 0) {
            return
        }
        if (fd == nativeTunFd) {
            nativeTunFd = -1
        }
        try {
            val link = android.system.Os.readlink("/proc/self/fd/$fd")
            if (link.contains("tun", ignoreCase = true)) {
                ParcelFileDescriptor.adoptFd(fd).close()
                Log.i(TAG, "closed leaked native TUN fd $fd ($link)")
            } else {
                Log.i(TAG, "native TUN fd $fd already released ($link)")
            }
        } catch (t: Throwable) {
            Log.i(TAG, "native TUN fd $fd already closed")
        }
    }

    private fun closeTunDescriptor() {
        val descriptor = tunDescriptor ?: return
        tunDescriptor = null
        try {
            descriptor.close()
            Log.i(TAG, "closed original VpnService fd")
        } catch (t: Throwable) {
            Log.w(TAG, "Failed to close VpnService fd", t)
        }
    }

    private fun defaultConfigDir(): String {
        return File(filesDir, DEFAULT_CONFIG_DIR).absolutePath
    }

    private fun isVpnEnabled(): Boolean = prefs.getBoolean(KEY_ENABLED, false)

    private fun setEnabled(enabled: Boolean) {
        prefs.edit().putBoolean(KEY_ENABLED, enabled).apply()
    }

    private fun persistState(
        configDir: String,
        allowedApplications: List<String>,
        disallowedApplications: List<String>,
        enabled: Boolean,
    ) {
        prefs.edit()
            .putBoolean(KEY_ENABLED, enabled)
            .putString(KEY_CONFIG_DIR, configDir)
            .putStringSet(KEY_ALLOWED_APPS, allowedApplications.toSet())
            .putStringSet(KEY_DISALLOWED_APPS, disallowedApplications.toSet())
            .apply()
    }

    @Suppress("DEPRECATION")
    private fun stopForegroundCompat() {
        stopForeground(true)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Clash VPN",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Clash mihomo VpnService"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = launchIntent?.let {
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        PendingIntent.FLAG_IMMUTABLE
                    } else {
                        0
                    }
            PendingIntent.getActivity(this, 0, it, flags)
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }

        return builder
            .setContentTitle("Clash VPN")
            .setContentText("mihomo is running")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
            .setContentIntent(contentIntent)
            .build()
    }

    @Suppress("DEPRECATION")
    private fun Intent.getResultReceiver(): ResultReceiver? {
        return getParcelableExtra(VpnServiceContract.EXTRA_RESULT_RECEIVER)
    }

    private fun sendResult(receiver: ResultReceiver?, success: Boolean, error: String = "") {
        if (receiver == null) {
            return
        }
        val bundle = Bundle().apply {
            putBoolean("success", success)
            putString("error", error)
        }
        receiver.send(if (success) 0 else 1, bundle)
    }
}
