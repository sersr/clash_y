package io.aote.vpnService

class ClashCore {
    fun interface Protector {
        fun protect(fd: Int): Boolean
    }

    external fun start(configDir: String): String?

    // prepare fetches the GeoIP/GeoSite databases the config references. Call it
    // before establishTun(): once the VpnService interface owns the default
    // route, every socket of this process lands in a tunnel the core has not
    // started reading yet.
    external fun prepare(configDir: String): String?

    external fun startTun(configDir: String, tunFd: Int, protector: Protector): String?

    // refreshProfile downloads the subscription, runs the profile script and
    // overlays the app-owned keys of the config already in configDir, writing
    // the result back to configDir/config.yaml. Returns null on success, else a
    // message. The core is not restarted; the caller decides that.
    external fun refreshProfile(configDir: String, url: String, script: String): String?

    external fun stop(): String?

    companion object {
        init {
            System.loadLibrary("clash")
        }
    }
}
