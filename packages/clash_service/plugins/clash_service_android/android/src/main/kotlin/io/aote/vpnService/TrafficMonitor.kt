package io.aote.vpnService

import android.net.LocalSocket
import android.net.LocalSocketAddress
import android.util.Base64
import android.util.Log
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.EOFException
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Locale

internal class TrafficMonitor(
    private val socketPath: String,
    private val onTraffic: (up: Long, down: Long) -> Unit,
) {
    @Volatile
    private var stopped = false

    @Volatile
    private var socket: LocalSocket? = null

    private var thread: Thread? = null

    @Synchronized
    fun start() {
        if (thread?.isAlive == true || socketPath.isBlank()) return
        stopped = false
        thread = Thread(::runLoop, "ClashTrafficMonitor").apply {
            isDaemon = true
            start()
        }
    }

    @Synchronized
    fun stop() {
        stopped = true
        try {
            socket?.close()
        } catch (e: IOException) {
            Log.w(TAG, "Failed to close traffic monitor socket", e)
        }
        thread?.interrupt()
        thread = null
    }

    private fun runLoop() {
        while (!stopped) {
            val connection = LocalSocket()
            socket = connection
            try {
                connection.connect(
                    LocalSocketAddress(socketPath, LocalSocketAddress.Namespace.FILESYSTEM),
                )
                val input = connection.inputStream
                val output = connection.outputStream
                openWebSocket(input, output)
                while (!stopped) {
                    val frame = readFrame(input)
                    when (frame.opcode) {
                        OP_TEXT -> parseTraffic(frame.payload)
                        OP_PING -> writeClientFrame(output, OP_PONG, frame.payload)
                        OP_CLOSE -> break
                    }
                }
            } catch (e: IOException) {
                if (!stopped) Log.w(TAG, "Traffic socket disconnected; reconnecting", e)
            } catch (e: Exception) {
                if (!stopped) Log.e(TAG, "Failed to read traffic data", e)
            } finally {
                socket = null
                try {
                    connection.close()
                } catch (e: IOException) {
                    if (!stopped) Log.w(TAG, "Failed to close traffic socket", e)
                }
            }

            if (!stopped) {
                try {
                    Thread.sleep(RECONNECT_DELAY_MS)
                } catch (_: InterruptedException) {
                    if (stopped) return
                }
            }
        }
    }

    private fun openWebSocket(input: InputStream, output: OutputStream) {
        val nonceBytes = ByteArray(16).also(SecureRandom()::nextBytes)
        val nonce = Base64.encodeToString(nonceBytes, Base64.NO_WRAP)
        output.write(
            ("GET /traffic HTTP/1.1\r\n" +
                    "Host: localhost\r\n" +
                    "Upgrade: websocket\r\n" +
                    "Connection: Upgrade\r\n" +
                    "Sec-WebSocket-Key: $nonce\r\n" +
                    "Sec-WebSocket-Version: 13\r\n\r\n")
                .toByteArray(StandardCharsets.US_ASCII),
        )
        output.flush()

        val headers = readHeaders(input)
        if (!headers.startsWith("HTTP/1.1 101") && !headers.startsWith("HTTP/1.0 101")) {
            throw IOException("Unexpected traffic WebSocket response: ${headers.lineSequence().firstOrNull()}")
        }
        val accept = headers.lineSequence()
            .drop(1)
            .firstNotNullOfOrNull { line ->
                if (line.startsWith("Sec-WebSocket-Accept:", ignoreCase = true)) {
                    line.substringAfter(':').trim()
                } else {
                    null
                }
            }
        val expected = Base64.encodeToString(
            MessageDigest.getInstance("SHA-1")
                .digest((nonce + WEBSOCKET_GUID).toByteArray(StandardCharsets.US_ASCII)),
            Base64.NO_WRAP,
        )
        if (accept != expected) throw IOException("Invalid traffic WebSocket handshake")
    }

    private fun readHeaders(input: InputStream): String {
        val bytes = ByteArrayOutputStream()
        var state = 0
        while (bytes.size() < MAX_HEADER_SIZE) {
            val byte = input.read()
            if (byte < 0) throw EOFException("Traffic socket closed during WebSocket handshake")
            bytes.write(byte)
            state = when {
                state == 0 && byte == '\r'.code -> 1
                state == 1 && byte == '\n'.code -> 2
                state == 2 && byte == '\r'.code -> 3
                state == 3 && byte == '\n'.code -> 4
                byte == '\r'.code -> 1
                else -> 0
            }
            if (state == 4) {
                return bytes.toString(StandardCharsets.US_ASCII.name())
            }
        }
        throw IOException("Traffic WebSocket response headers are too large")
    }

    private fun readFrame(input: InputStream): WebSocketFrame {
        val first = input.readRequiredByte()
        val second = input.readRequiredByte()
        val fin = first and 0x80 != 0
        val opcode = first and 0x0f
        if (!fin && opcode != OP_PING && opcode != OP_CLOSE) {
            throw IOException("Fragmented traffic WebSocket frames are unsupported")
        }

        val masked = second and 0x80 != 0
        var length = (second and 0x7f).toLong()
        if (length == 126L) {
            length = ((input.readRequiredByte() shl 8) or input.readRequiredByte()).toLong()
        } else if (length == 127L) {
            length = 0
            repeat(8) {
                length = (length shl 8) or input.readRequiredByte().toLong()
            }
        }
        if (length < 0 || length > MAX_FRAME_SIZE) {
            throw IOException("Traffic WebSocket frame is too large")
        }

        val mask = if (masked) ByteArray(4).also { input.readFully(it) } else null
        val payload = ByteArray(length.toInt()).also { input.readFully(it) }
        if (mask != null) {
            payload.indices.forEach { index ->
                payload[index] = (payload[index].toInt() xor mask[index % mask.size].toInt()).toByte()
            }
        }
        return WebSocketFrame(opcode, payload)
    }

    private fun writeClientFrame(output: OutputStream, opcode: Int, payload: ByteArray) {
        val mask = ByteArray(4).also(SecureRandom()::nextBytes)
        output.write(0x80 or opcode)
        output.write(0x80 or payload.size)
        output.write(mask)
        payload.indices.forEach { index ->
            output.write(payload[index].toInt() xor mask[index % mask.size].toInt())
        }
        output.flush()
    }

    private fun parseTraffic(payload: ByteArray) {
        val json = JSONObject(String(payload, StandardCharsets.UTF_8))
        onTraffic(
            json.optLong("up").coerceAtLeast(0L),
            json.optLong("down").coerceAtLeast(0L),
        )
    }

    private fun InputStream.readRequiredByte(): Int {
        val value = read()
        if (value < 0) throw EOFException("Traffic WebSocket closed")
        return value
    }

    private fun InputStream.readFully(target: ByteArray) {
        var offset = 0
        while (offset < target.size) {
            val count = read(target, offset, target.size - offset)
            if (count < 0) throw EOFException("Traffic WebSocket closed")
            offset += count
        }
    }

    private data class WebSocketFrame(val opcode: Int, val payload: ByteArray)

    private companion object {
        const val TAG = "ClashVpnService"
        const val OP_TEXT = 0x1
        const val OP_CLOSE = 0x8
        const val OP_PING = 0x9
        const val OP_PONG = 0xA
        const val MAX_HEADER_SIZE = 16 * 1024
        const val MAX_FRAME_SIZE = 1024 * 1024
        const val RECONNECT_DELAY_MS = 1_000L
        const val WEBSOCKET_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    }
}

internal fun formatTrafficRate(bytesPerSecond: Long): String {
    val value = bytesPerSecond.coerceAtLeast(0L)
    if (value < 1024) return "$value B/s"
    val units = arrayOf("KB/s", "MB/s", "GB/s", "TB/s")
    var rate = value.toDouble()
    var unit = -1
    while (rate >= 1024 && unit < units.lastIndex) {
        rate /= 1024
        unit++
    }
    return String.format(Locale.ROOT, "%.1f %s", rate, units[unit])
}
