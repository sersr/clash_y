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
 * The service keeps no runtime status object. State is only the live TUN
 * descriptors owned by this service instance.
 */
class ClashVpnService : VpnService() {

    companion object {
        private const val TAG = "ClashVpnService"
        private const val CHANNEL_ID = "clash_vpn_service"
        private const val NOTIFICATION_ID = 0x434C4153 // "CLAS"

        private const val DEFAULT_CONFIG_DIR = "clashy/clash_config"

        private const val TUN_ADDRESS = "172.19.0.1"
        private const val TUN_ADDRESS_PREFIX = 30
        private const val TUN_DNS = "172.19.0.2"
        private const val TUN_MTU = 9000
    }

    private val executor = Executors.newSingleThreadExecutor()

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
        executor.execute {
            cleanup()
            stopForegroundCompat()
            stopSelf()
        }
        super.onRevoke()
    }

    override fun onDestroy() {
        Log.i(TAG, "onDestroy")
        cleanup()
        executor.shutdownNow()
        super.onDestroy()
    }

    private fun handleStart(intent: Intent?) {
        val receiver = intent?.getResultReceiver()
        val configDir = intent?.getStringExtra(VpnServiceContract.EXTRA_CONFIG_DIR)?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: defaultConfigDir()

        if (configDir.isEmpty()) {
            sendResult(receiver, false, "configDir is empty")
            stopSelf()
            return
        }

        val allowedApplications = intent?.getStringArrayListExtra(
            VpnServiceContract.EXTRA_ALLOWED_APPLICATIONS
        ).orEmpty()
        val disallowedApplications = intent?.getStringArrayListExtra(
            VpnServiceContract.EXTRA_DISALLOWED_APPLICATIONS
        ).orEmpty()

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
