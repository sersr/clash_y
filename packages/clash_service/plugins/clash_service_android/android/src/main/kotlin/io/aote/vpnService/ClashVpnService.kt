package io.aote.vpnService

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.ResultReceiver
import android.util.Log
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/**
 * Android-only VpnService.
 *
 * Runs in its own `:vpn` process (see the plugin manifest): the TUN, mihomo
 * and this service survive the Flutter main process being killed when the
 * user swipes the app away.
 *
 * Runtime state is only the live TUN descriptors owned by this service
 * instance. The last requested on/off switch and the configDir are
 * persisted in SharedPreferences so a sticky restart (intent == null, e.g.
 * after the process is killed) can restore the configuration — and refuse
 * to come back up when the user left the VPN off. The prefs file is touched
 * only from this process, so no multi-process modes are needed.
 *
 * Automatic restarts (sticky restart after a kill, onTaskRemoved
 * self-restart) also go through a restart-storm guard: if they arrive
 * within [STORM_WINDOW_MS] of the previous actual core start, the full
 * start is delayed with an exponential backoff so a kill loop cannot pin
 * the CPU with back-to-back config loads.
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
        private const val KEY_ALLOW_LIST = "allowList"
        private const val KEY_ALLOWED_APPS = "allowedApplications"
        private const val KEY_DISALLOWED_APPS = "disallowedApplications"

        /** 上一次真正执行 `startCore` 的时刻（`System.currentTimeMillis()`）。 */
        private const val KEY_LAST_START_AT = "lastStartAt"

        /** 连续快速自动重启的计数（风暴等级）。 */
        private const val KEY_STORM_LEVEL = "stormLevel"

        /**
         * 重启风暴判定窗口与退避参数。
         *
         * 自动重启距上次真正启动不足 [STORM_WINDOW_MS] 即认定为风暴：
         * 第 1 次仍立即执行，之后按 `BACKOFF_BASE_MS * 2^(level-2)`
         * 推迟全量启动，上限 [BACKOFF_MAX_MS]。启动间隔恢复到窗口之上
         * 说明风暴结束，计数清零。
         */
        private const val STORM_WINDOW_MS = 30_000L
        private const val BACKOFF_BASE_MS = 5_000L
        private const val BACKOFF_MAX_MS = 60_000L
        private const val MAX_STORM_LEVEL = 16

        private const val TUN_ADDRESS = "172.19.0.1"
        private const val TUN_ADDRESS_PREFIX = 30
        private const val TUN_DNS = "172.19.0.2"
        private const val TUN_IPV6_ADDRESS = "fdfe:dcba:9876::1"
        private const val TUN_IPV6_ADDRESS_PREFIX = 126
        private const val TUN_IPV6_DNS = "fdfe:dcba:9876::2"
        private const val TUN_MTU = 9000
    }

    private val executor = Executors.newSingleThreadExecutor()
    private val protectCallCount = AtomicInteger(0)

    /** 退避用的主线程调度器（`onStartCommand`/`onDestroy` 都在主线程）。 */
    private val mainHandler = Handler(Looper.getMainLooper())

    /** 排队等待退避到期的自动恢复任务，同一时刻至多一个。 */
    private var pendingAutoStart: Runnable? = null

    private val prefs by lazy { getSharedPreferences(PREFS_NAME, MODE_PRIVATE) }

    private var tunDescriptor: ParcelFileDescriptor? = null

    @Volatile
    private var nativeTunFd = -1

    /** Native mihomo runtime is stopped at most once per successful start. */
    @Volatile
    private var coreStarted = false

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
        cancelPendingAutoStart()
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
        // 先撤掉退避任务：executor 随后 shutdownNow，迟到的任务会抛
        // RejectedExecutionException 并在主线程崩溃
        cancelPendingAutoStart()
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
        val allowList = if (intent?.hasExtra(VpnServiceContract.EXTRA_ALLOW_LIST) == true) {
            intent.getBooleanExtra(VpnServiceContract.EXTRA_ALLOW_LIST, false)
        } else {
            prefs.getBoolean(KEY_ALLOW_LIST, false)
        }

        if (!isAutoRestart(intent)) {
            // 手动启动（Dart 侧显式指令）：风暴状态归零，立即执行
            cancelPendingAutoStart()
            prefs.edit().putInt(KEY_STORM_LEVEL, 0).apply()
            executor.execute {
                startCore(
                    configDir,
                    receiver,
                    allowList,
                    allowedApplications,
                    disallowedApplications,
                )
            }
            return
        }

        // 已有排队中的自动恢复：不重复计数，也不重排计时
        if (pendingAutoStart != null) {
            Log.i(TAG, "auto restart already scheduled, ignoring duplicate")
            return
        }

        val delay = nextBackoffDelayMs()
        if (delay > 0) {
            Log.i(TAG, "restart storm backoff: delaying the full start by ${delay}ms")
            val task = Runnable {
                pendingAutoStart = null
                if (!isVpnEnabled()) {
                    // 等待期间用户把开关关掉了
                    Log.i(TAG, "VPN switched off while waiting out the backoff")
                    stopForegroundCompat()
                    stopSelf()
                    return@Runnable
                }
                executor.execute {
                    startCore(
                        configDir,
                        receiver,
                        allowList,
                        allowedApplications,
                        disallowedApplications,
                    )
                }
            }
            pendingAutoStart = task
            mainHandler.postDelayed(task, delay)
            return
        }

        executor.execute {
            startCore(
                configDir,
                receiver,
                allowList,
                allowedApplications,
                disallowedApplications,
            )
        }
    }

    /**
     * 是否为系统/自恢复触发的自动重启：sticky 重启（intent == null）或
     * `onTaskRemoved` 自拉起（EXTRA_RESUME_ONLY）。手动启动永远不带该标记。
     */
    private fun isAutoRestart(intent: Intent?): Boolean =
        intent == null ||
                intent.getBooleanExtra(VpnServiceContract.EXTRA_RESUME_ONLY, false)

    /**
     * 重启风暴退避：返回本次自动重启应推迟全量启动的毫秒数（0 = 立即）。
     *
     * 以上一次真正执行 `startCore` 的时间（由 [startCore] 落盘）为基准，
     * 落在 [STORM_WINDOW_MS] 之内的自动重启计为风暴并升一级；首次快速
     * 重启（level 1）不推迟，之后按 `5s * 2^(level-2)` 指数增长、封顶
     * [BACKOFF_MAX_MS]。超过窗口说明进程活过了风暴期，计数清零。
     *
     * 这里不写 lastStartAt——时间戳只由真正的启动写入，否则退避本身
     * 拉开的间隔会被误判成"活了很久"，反而让风暴检测失效。
     */
    private fun nextBackoffDelayMs(): Long {
        val now = System.currentTimeMillis()
        val lastStartAt = prefs.getLong(KEY_LAST_START_AT, 0L)
        val level: Int
        if (lastStartAt == 0L || now - lastStartAt >= STORM_WINDOW_MS) {
            level = 0
        } else {
            level = (prefs.getInt(KEY_STORM_LEVEL, 0) + 1).coerceAtMost(MAX_STORM_LEVEL)
        }
        if (level != prefs.getInt(KEY_STORM_LEVEL, 0)) {
            prefs.edit().putInt(KEY_STORM_LEVEL, level).apply()
        }
        if (level <= 1) {
            return 0
        }
        var delay = BACKOFF_BASE_MS
        repeat(level - 2) {
            delay = (delay * 2).coerceAtMost(BACKOFF_MAX_MS)
        }
        return delay.coerceAtMost(BACKOFF_MAX_MS)
    }

    private fun cancelPendingAutoStart() {
        val task = pendingAutoStart ?: return
        pendingAutoStart = null
        mainHandler.removeCallbacks(task)
        Log.i(TAG, "cancelled the pending backoff start")
    }

    private fun startCore(
        configDir: String,
        receiver: ResultReceiver?,
        allowList: Boolean,
        allowedApplications: List<String>,
        disallowedApplications: List<String>,
    ) {
        Log.i(TAG, "startCore configDir=$configDir")
        // 真正的启动时刻是风暴检测的基准，必须在这里落盘
        prefs.edit().putLong(KEY_LAST_START_AT, System.currentTimeMillis()).apply()
        var detachedNativeFd = -1
        try {
            // Replace any previous instance cleanly. This is a no-op on the
            // first start.
            stopCore()
            releaseNativeTunFd()
            closeTunDescriptor()

            val descriptor = establishTun(
                allowList,
                allowedApplications,
                disallowedApplications,
            )
                ?: throw IllegalStateException("VpnService.establish() returned null")
            tunDescriptor = descriptor

            // Keep ownership of the original fd and let mihomo own a duplicate.
            val nativeDescriptor = descriptor.dup()
            detachedNativeFd = nativeDescriptor.detachFd()
            nativeTunFd = detachedNativeFd

            val error = ClashCore().startTun(configDir, detachedNativeFd) { protectFd ->
                val protected = protect(protectFd)
                val call = protectCallCount.incrementAndGet()
                // Log a small sample plus every failure without flooding logcat.
                if (!protected || call <= 5) {
                    Log.i(TAG, "protect(fd=$protectFd)=$protected call=$call")
                }
                protected
            }
            if (error != null) {
                throw IllegalStateException(error)
            }
            coreStarted = true

            persistState(
                configDir,
                allowList,
                allowedApplications,
                disallowedApplications,
                enabled = true,
            )
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
        // 手动停止是一次干净的收场：撤掉排队中的退避启动并清风暴计数
        cancelPendingAutoStart()
        prefs.edit().putInt(KEY_STORM_LEVEL, 0).apply()
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

    @Synchronized
    private fun stopCore(): String? {
        if (!coreStarted) {
            Log.i(TAG, "stopCore skipped: mihomo is not running")
            return null
        }
        // Clear before calling native code so onDestroy or another teardown
        // path cannot issue a duplicate stop while this call is in progress.
        coreStarted = false
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
        allowList: Boolean,
        allowedApplications: List<String>,
        disallowedApplications: List<String>,
    ): ParcelFileDescriptor? {
        val builder = Builder()
            .setSession("clashy")
            .setMtu(TUN_MTU)
            .addAddress(TUN_ADDRESS, TUN_ADDRESS_PREFIX)
            .addAddress(TUN_IPV6_ADDRESS, TUN_IPV6_ADDRESS_PREFIX)
            .addDnsServer(TUN_DNS)
            .addDnsServer(TUN_IPV6_DNS)
            .addRoute("0.0.0.0", 0)
            .addRoute("::", 0)
            .setBlocking(false)

        // selectedApplications() must contain this VPN app in allow-list mode.
        // Outbound core sockets stay outside the TUN through protect(fd).
        val effectiveAllowed = selectedApplications(
            selected = allowedApplications,
            allowList = allowList,
            appPackageName = packageName,
        )
        Log.i(
            TAG,
            "establishTun allowed=${effectiveAllowed.joinToString()} disallowed=${disallowedApplications.joinToString()}"
        )
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
        allowList: Boolean,
        allowedApplications: List<String>,
        disallowedApplications: List<String>,
        enabled: Boolean,
    ) {
        prefs.edit()
            .putBoolean(KEY_ENABLED, enabled)
            .putString(KEY_CONFIG_DIR, configDir)
            .putBoolean(KEY_ALLOW_LIST, allowList)
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

/**
 * Resolves the VpnService allow list.
 *
 * Android cannot combine allow and deny lists, so non-allow-list routing
 * returns an empty list and relies on [Builder.addDisallowedApplication].
 * Allow-list mode always includes the VPN package itself: its core owns the
 * TUN and must remain able to return selected-app traffic.
 */
internal fun selectedApplications(
    selected: List<String>,
    allowList: Boolean,
    appPackageName: String,
): List<String> {
    if (!allowList) {
        return emptyList()
    }
    return (selected + appPackageName).distinct()
}
