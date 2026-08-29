package com.qingji.qingji

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.io.BufferedReader
import java.io.File
import java.io.IOException
import java.io.InputStreamReader
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URI
import java.nio.charset.StandardCharsets
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Owns the ChatGPT OAuth localhost callback while Chrome is in the foreground.
 *
 * This is deliberately a native service in its own Android process. A Dart
 * HttpServer disappears when FlutterActivity/its engine is reclaimed, which
 * was the cause of Chrome showing ERR_CONNECTION_REFUSED at localhost:1455.
 * The service writes the raw callback URL to app-private storage; Flutter
 * later reads it, validates state/PKCE, exchanges the code and stops us.
 */
class OAuthKeepAliveService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private val timeout = Runnable {
        callbackServer?.stop()
        callbackServer = null
        stopForeground(true)
        stopSelf()
    }
    private var callbackServer: NativeOAuthCallbackServer? = null

    companion object {
        const val DEFAULT_PORT = 1455
        const val FALLBACK_PORT = 1457
        private const val CHANNEL_ID = "oauth_keep_alive"
        private const val NOTIFICATION_ID = 1455
        private const val ACTION_START = "com.qingji.qingji.oauth.START"
        private const val ACTION_STOP = "com.qingji.qingji.oauth.STOP"
        private const val EXTRA_PORTS = "oauth_ports"
        private const val EXTRA_FLOW_ID = "oauth_flow_id"
        private const val READY_FILE = "oauth_callback_ready"
        private const val CALLBACK_FILE = "oauth_callback_url"

        fun start(context: Context, ports: List<Int>, flowId: String? = null): Boolean {
            return try {
                val intent = Intent(context, OAuthKeepAliveService::class.java)
                    .setAction(ACTION_START)
                    .putIntegerArrayListExtra(EXTRA_PORTS, ArrayList(ports))
                    .putExtra(EXTRA_FLOW_ID, flowId)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    ContextCompat.startForegroundService(context, intent)
                } else {
                    context.startService(intent)
                }
                true
            } catch (_: Exception) {
                false
            }
        }

        /** Start the isolated service and wait until a port is really bound. */
        fun startAndWait(
            context: Context,
            ports: List<Int>,
            flowId: String? = null,
        ): Int? {
            val normalized = ports.filter { it in 1..65535 }.distinct()
                .ifEmpty { listOf(DEFAULT_PORT, FALLBACK_PORT) }
            val existing = flowId?.let { readyPort(context, it) }
            if (existing != null && existing in normalized && isPortReachable(existing)) {
                return existing
            }

            // Activity recreation/resume must not tear down a listener owned by
            // the active OAuth flow. The old implementation called
            // stopService() whenever the marker was momentarily missing or a
            // probe raced the service process. Chrome could then reach
            // localhost during that gap and show ERR_CONNECTION_REFUSED.
            // Nudge the service first; its onStartCommand() repairs a dead
            // listener and replaces a listener from an older flow. If that
            // repair cannot publish a live port, leave the service alone and
            // let the next foreground resume retry instead of creating another
            // refusal window.
            if (flowId != null) {
                if (!start(context, normalized, flowId)) return null
                repeat(100) {
                    val ready = readyPort(context, flowId)
                    if (ready != null && ready in normalized && isPortReachable(ready)) {
                        return ready
                    }
                    try {
                        Thread.sleep(100)
                    } catch (_: InterruptedException) {
                        Thread.currentThread().interrupt()
                        return null
                    }
                }
                return null
            }

            // A different OAuth attempt may still be winding down while a new
            // one is being started (for example, cancel() immediately followed
            // by start()). Stop it through the component API and wait until its
            // ready marker disappears before binding the next listener. Sending
            // a synthetic STOP intent here races startForegroundService() and
            // can trigger ForegroundServiceDidNotStartInTimeException.
            stopAndWait(context)
            // A previous service process may have died leaving a stale ready
            // marker. The next START command rewrites it once the live socket
            // is confirmed, so never trust the marker from before this call.
            File(context.applicationContext.filesDir, READY_FILE).delete()
            if (!start(context, normalized, flowId)) return null
            // Slow ROMs may need several seconds to create the isolated
            // foreground-service process. Never fall back to a Dart listener
            // on Android: it disappears as soon as Flutter is backgrounded
            // and produces the misleading localhost refusal page.
            repeat(100) {
                val ready = readyPort(context, flowId)
                if (ready != null && ready in normalized && isPortReachable(ready)) return ready
                try {
                    Thread.sleep(100)
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                    return null
                }
            }
            stopAndWait(context)
            return null
        }

        private fun isPortReachable(port: Int): Boolean {
            return try {
                Socket().use { socket ->
                    socket.connect(InetSocketAddress("127.0.0.1", port), 350)
                }
                true
            } catch (_: Exception) {
                false
            }
        }

        fun stop(context: Context, expectedFlowId: String? = null): Boolean {
            return try {
                if (!expectedFlowId.isNullOrBlank() &&
                    readyFlowId(context) != expectedFlowId
                ) {
                    // A late stop from an older OAuth flow must never stop a
                    // service that has already published a newer flow marker.
                    return false
                }
                // Do not enqueue an ACTION_STOP start request. On Android O+
                // that request can be treated as a foreground-service start,
                // and if it arrives before onStartCommand() calls
                // startForeground(), Android kills the service with
                // ForegroundServiceDidNotStartInTimeException. stopService()
                // asks ActivityManager to stop the existing component directly.
                context.stopService(Intent(context, OAuthKeepAliveService::class.java))
            } catch (_: Exception) {
                false
            }
        }

        /** Stop the service and wait for its ready marker to be removed. */
        fun stopAndWait(
            context: Context,
            expectedFlowId: String? = null,
            timeoutMs: Long = 2_500L,
        ): Boolean {
            if (!expectedFlowId.isNullOrBlank() &&
                readyFlowId(context) != expectedFlowId
            ) {
                return false
            }
            val requested = stop(context, expectedFlowId)
            if (!requested) return false
            val ready = File(context.applicationContext.filesDir, READY_FILE)
            val deadline = System.currentTimeMillis() + timeoutMs
            while (ready.exists() && System.currentTimeMillis() < deadline) {
                try {
                    Thread.sleep(25)
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                    break
                }
            }
            // A stale marker is safe to remove only after the component stop
            // request has been issued and the bounded wait has elapsed. The
            // listener itself is closed by onDestroy(); startAndWait() performs
            // a fresh bind and will fail over to 1457 if a port is still busy.
            if (ready.exists() && System.currentTimeMillis() >= deadline &&
                (expectedFlowId.isNullOrBlank() ||
                    readyFlowId(context) == expectedFlowId)
            ) {
                ready.delete()
            }
            return !ready.exists()
        }

        fun readyPort(context: Context): Int? = readyPort(context, null)

        fun readyPort(context: Context, expectedFlowId: String?): Int? {
            val file = File(context.applicationContext.filesDir, READY_FILE)
            return try {
                val lines = file.readLines(StandardCharsets.UTF_8)
                if (lines.isEmpty()) return null
                // Older development builds wrote only the port. Continue to
                // accept that shape when no flow id is requested, but a new
                // flow must never consume an old marker from another attempt.
                val (flowId, portText) = if (lines.size >= 2) {
                    lines.first().trim().ifEmpty { null } to lines.last()
                } else {
                    null to lines.first()
                }
                if (expectedFlowId != null && flowId != expectedFlowId) return null
                portText.trim().toIntOrNull()
            } catch (_: Exception) {
                null
            }
        }

        private fun readyFlowId(context: Context): String? {
            val file = File(context.applicationContext.filesDir, READY_FILE)
            return try {
                val lines = file.readLines(StandardCharsets.UTF_8)
                if (lines.size >= 2) lines.first().trim().ifEmpty { null } else null
            } catch (_: Exception) {
                null
            }
        }

        fun clearCallback(context: Context, expectedFlowId: String? = null): Boolean {
            return try {
                val file = File(context.applicationContext.filesDir, CALLBACK_FILE)
                if (!file.isFile) return false
                if (!expectedFlowId.isNullOrBlank() &&
                    callbackState(file.readText(StandardCharsets.UTF_8)) != expectedFlowId
                ) {
                    return false
                }
                file.delete()
            } catch (_: Exception) {
                false
            }
        }

        private fun callbackState(value: String): String? {
            return try {
                Uri.parse(value).getQueryParameter("state")?.trim()
            } catch (_: Exception) {
                null
            }
        }

        /**
         * Read the callback captured by the native listener without deleting
         * it. Flutter persists the URL before exchanging the code; keeping a
         * native copy until token exchange succeeds lets a reclaimed process
         * recover the callback on the next foreground resume.
         */
        fun takeCallback(context: Context, expectedFlowId: String? = null): String? {
            val file = File(context.applicationContext.filesDir, CALLBACK_FILE)
            return try {
                if (!file.isFile) return null
                val value = file.readText(StandardCharsets.UTF_8).trim()
                if (!expectedFlowId.isNullOrBlank()) {
                    val callbackFlowId = try {
                        Uri.parse(value).getQueryParameter("state")?.trim()
                    } catch (_: Exception) {
                        null
                    }
                    // A poller from an older Flutter flow must not consume
                    // the callback that belongs to the newer flow. Leave the
                    // file in place so the current poller can claim it.
                    if (callbackFlowId != expectedFlowId) return null
                }
                value.takeIf { it.isNotEmpty() }
            } catch (_: Exception) {
                null
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "GPT 授权连接",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "GPT 授权跳转期间保持本机回调连接"
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java)
                ?.createNotificationChannel(channel)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            handler.removeCallbacks(timeout)
            callbackServer?.stop()
            callbackServer = null
            stopForeground(true)
            stopSelf()
            return START_NOT_STICKY
        }

        startForeground(NOTIFICATION_ID, notification())
        val requestedFlowId = intent?.getStringExtra(EXTRA_FLOW_ID)?.trim()
            ?.ifEmpty { null }
            ?: readyFlowId(this)
        val sameFlow = callbackServer?.flowId == requestedFlowId
        if (!sameFlow || callbackServer?.isHealthy() != true) {
            callbackServer?.stop()
            val requested = intent?.getIntegerArrayListExtra(EXTRA_PORTS)
                ?.filter { it in 1..65535 }
                ?.distinct()
                ?.ifEmpty { null }
                ?: (readyPort(this, requestedFlowId)?.let { listOf(it) }
                    ?: listOf(DEFAULT_PORT, FALLBACK_PORT))
            callbackServer = NativeOAuthCallbackServer(
                filesDir,
                requested,
                requestedFlowId,
            ).also {
                it.start()
            }
        } else {
            // startAndWait clears the marker before every new flow. Re-publish
            // it for a healthy listener instead of returning a stale refusal
            // window while the service process is reused.
            callbackServer?.rewriteReady()
        }
        // Match Cockpit's ten-minute browser OAuth window and keep one extra
        // minute for the final localhost redirect/token hand-off.
        handler.removeCallbacks(timeout)
        handler.postDelayed(timeout, 11 * 60 * 1000L)
        return START_STICKY
    }

    private fun notification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_warning)
            .setContentTitle("GPT 授权进行中")
            .setContentText("完成授权后返回肥喵记账")
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        handler.removeCallbacks(timeout)
        callbackServer?.stop()
        callbackServer = null
        stopForeground(true)
        super.onDestroy()
    }

    /** Small HTTP/1.1 listener for the fixed localhost OAuth redirect. */
    private class NativeOAuthCallbackServer(
        private val filesDir: File,
        private val ports: List<Int>,
        val flowId: String?,
    ) {
        private val running = AtomicBoolean(false)
        private val callbackCaptured = AtomicBoolean(false)
        @Volatile private var boundPort: Int? = null
        private val sockets = mutableListOf<ServerSocket>()
        private val workers = mutableListOf<Thread>()
        private val lock = Any()

        private val readyFile get() = File(filesDir, READY_FILE)
        private val callbackFile get() = File(filesDir, CALLBACK_FILE)

        fun start() {
            if (!running.compareAndSet(false, true)) return
            readyFile.delete()
            // A callback file can survive a killed Flutter process. It may
            // belong to an older OAuth flow; treating any existing file as a
            // captured callback would make the next valid redirect return a
            // misleading success page without recording its new code. Keep a
            // file only when its state belongs to this exact flow.
            val retainsCallback = if (flowId.isNullOrBlank() || !callbackFile.isFile) {
                false
            } else {
                val existingState = try {
                    callbackState(callbackFile.readText(StandardCharsets.UTF_8))
                } catch (_: Exception) {
                    null
                }
                existingState == flowId
            }
            if (!retainsCallback) callbackFile.delete()
            callbackCaptured.set(retainsCallback)
            val worker = Thread({ bindAndServe() }, "feimiao-oauth-listener")
            synchronized(lock) { workers += worker }
            worker.start()
        }

        fun stop() {
            if (!running.compareAndSet(true, false)) return
            synchronized(lock) {
                sockets.toList().forEach { socket ->
                    try {
                        socket.close()
                    } catch (_: Exception) {
                    }
                }
                sockets.clear()
                workers.toList().forEach { it.interrupt() }
                workers.clear()
            }
            val port = boundPort
            boundPort = null
            if (port != null && ownsReadyMarker(port)) readyFile.delete()
        }

        fun rewriteReady() {
            val port = boundPort
            if (running.get() && port != null) {
                writeAtomic(readyFile, readyPayload(flowId, port))
            }
        }

        private fun bindAndServe() {
            var port: Int? = null
            for (candidate in ports) {
                // OAuth redirects must remain device-local. Binding 0.0.0.0
                // would expose the callback endpoint to the LAN while Chrome
                // only needs the loopback interface.
                val ipv4 = tryBind(candidate, "127.0.0.1")
                if (ipv4 != null) {
                    port = candidate
                    addSocket(ipv4)
                    // Android Chrome may resolve localhost to ::1. Keep a
                    // second IPv6 listener when the platform permits it.
                    tryBind(candidate, "::1")?.let { addSocket(it) }
                    break
                }
                // Do not accept an IPv6-only bind. The registered localhost
                // redirect must have a working IPv4 listener on Android; an
                // IPv6 socket is only an optional companion to that listener.
            }
            val boundPort = port
            if (boundPort == null) {
                running.set(false)
                readyFile.delete()
                return
            }
            synchronized(lock) {
                // stop() can race the bind worker before the socket is ready.
                // Never publish a ready marker (or leave a socket open) after
                // the service has already been stopped.
                if (!running.get()) {
                    sockets.toList().forEach { socket ->
                        try {
                            socket.close()
                        } catch (_: Exception) {
                        }
                    }
                    sockets.clear()
                    return
                }
                this.boundPort = boundPort
                writeAtomic(readyFile, readyPayload(flowId, boundPort))
            }
            val boundSockets = synchronized(lock) { sockets.toList() }
            boundSockets.forEach { socket ->
                val acceptor = Thread({ acceptLoop(socket, boundPort) },
                    "feimiao-oauth-accept-$boundPort")
                synchronized(lock) { workers += acceptor }
                acceptor.start()
            }
        }

        private fun tryBind(port: Int, address: String): ServerSocket? {
            return try {
                ServerSocket().apply {
                    // Re-authentication can follow cancellation immediately;
                    // allowing the loopback socket to be reused avoids a short
                    // TIME_WAIT window being mistaken for a listener failure.
                    reuseAddress = true
                    bind(InetSocketAddress(InetAddress.getByName(address), port), 32)
                }
            } catch (_: Exception) {
                null
            }
        }

        private fun addSocket(socket: ServerSocket) {
            synchronized(lock) {
                if (running.get()) sockets += socket else socket.close()
            }
        }

        fun isHealthy(): Boolean = synchronized(lock) {
            running.get() && boundPort != null && sockets.any { !it.isClosed }
        }

        private fun acceptLoop(server: ServerSocket, port: Int) {
            while (running.get()) {
                try {
                    val client = server.accept()
                    Thread({ handle(client, port) }, "feimiao-oauth-request")
                        .start()
                } catch (_: IOException) {
                    if (running.get()) continue
                    return
                } catch (_: Exception) {
                    if (!running.get()) return
                }
            }
        }

        private fun handle(client: Socket, port: Int) {
            client.use { socket ->
                try {
                    socket.soTimeout = 5000
                    val reader = BufferedReader(
                        InputStreamReader(socket.getInputStream(), StandardCharsets.ISO_8859_1),
                    )
                    val requestLine = reader.readLine() ?: return
                    // Consume headers so Chrome can finish its request cleanly.
                    while (true) {
                        val line = reader.readLine() ?: break
                        if (line.isEmpty()) break
                    }
                    val parts = requestLine.split(' ')
                    val target = parts.getOrNull(1) ?: ""
                    val uri = try {
                        URI(target)
                    } catch (_: Exception) {
                        null
                    }
                    val path = uri?.rawPath ?: ""
                    if (uri == null || path != "/auth/callback") {
                        writeResponse(socket, 404, "未找到授权回调")
                        return
                    }
                    val callbackState = Uri.parse(target).getQueryParameter("state")?.trim()
                    if (flowId != null && callbackState != flowId) {
                        writeResponse(socket, 400, "授权状态不匹配，请返回肥喵记账重试")
                        return
                    }
                    if (!callbackCaptured.compareAndSet(false, true)) {
                        // Chrome can retry the redirect or request the page's
                        // favicon after the first response. It is still the
                        // same valid callback; returning 409 makes Chrome
                        // show an error page even though OAuth succeeded.
                        writeResponse(socket, 200, "授权已接收，请返回肥喵记账")
                        return
                    }
                    val callback = if (target.startsWith("http://") ||
                        target.startsWith("https://")) {
                        target
                    } else {
                        "http://localhost:$port$target"
                    }
                    writeAtomic(callbackFile, callback)
                    writeResponse(socket, 200, "授权成功，请返回肥喵记账")
                } catch (_: Exception) {
                    try {
                        writeResponse(socket, 400, "授权回调处理失败")
                    } catch (_: Exception) {
                    }
                }
            }
        }

        private fun ownsReadyMarker(port: Int): Boolean {
            return try {
                val lines = readyFile.readLines(StandardCharsets.UTF_8)
                val markerFlow = if (lines.size >= 2) {
                    lines.first().trim().ifEmpty { null }
                } else {
                    null
                }
                val markerPort = lines.lastOrNull()?.trim()?.toIntOrNull()
                markerFlow == flowId && markerPort == port
            } catch (_: Exception) {
                false
            }
        }

        private fun writeResponse(socket: Socket, status: Int, message: String) {
            val body = """
                <!doctype html><html lang=\"zh-CN\"><meta charset=\"utf-8\">
                <meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">
                <title>授权${if (status == 200) "成功" else "未完成"}</title>
                <body style=\"font-family:sans-serif;text-align:center;padding:20vh 8vw;color:#fff;background:#6b61c7\">
                <h1>${if (status == 200) "✅ 授权成功" else "授权未完成"}</h1><p>$message</p></body></html>
            """.trimIndent().toByteArray(StandardCharsets.UTF_8)
            val header = "HTTP/1.1 $status ${if (status == 200) "OK" else "Bad Request"}\r\n" +
                "Content-Type: text/html; charset=utf-8\r\n" +
                "Content-Length: ${body.size}\r\n" +
                "Connection: close\r\n\r\n"
            socket.getOutputStream().use { output ->
                output.write(header.toByteArray(StandardCharsets.ISO_8859_1))
                output.write(body)
                output.flush()
            }
        }

        private fun writeAtomic(file: File, value: String) {
            val temp = File(file.parentFile, "${file.name}.tmp")
            try {
                temp.writeText(value, StandardCharsets.UTF_8)
                if (!temp.renameTo(file)) {
                    file.writeText(value, StandardCharsets.UTF_8)
                    temp.delete()
                }
            } catch (_: Exception) {
                temp.delete()
            }
        }

        private fun readyPayload(flowId: String?, port: Int): String =
            "${flowId.orEmpty()}\n$port"
    }
}
