package io.aote.vpnService

/**
 * Thin JNI bridge to the mihomo C shared library built by `clash_core`.
 *
 * The native library is bundled by the Dart native-assets build hook as
 * `libclash.so`. Keep the class and method names in sync with the exported
 * `Java_io_aote_vpnService_ClashCore_*` symbols in
 * `packages/clash_core/core/jni_android.go`.
 */
class ClashCore {
    external fun start(configDir: String): String?

    external fun startTun(configDir: String, tunFd: Int): String?

    external fun stop(): String?

    companion object {
        init {
            System.loadLibrary("clash")
        }
    }
}
