package io.aote.vpnService

class ClashCore {
    fun interface Protector {
        fun protect(fd: Int): Boolean
    }

    external fun start(configDir: String): String?

    external fun startTun(configDir: String, tunFd: Int, protector: Protector): String?

    external fun stop(): String?

    companion object {
        init {
            System.loadLibrary("clash")
        }
    }
}
