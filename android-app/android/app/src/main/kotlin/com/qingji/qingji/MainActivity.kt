package com.qingji.qingji

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Uri
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.browser.customtabs.CustomTabsClient
import androidx.browser.customtabs.CustomTabsIntent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.ProxySelector
import java.net.URI
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/// 「分享到肥喵」原生桥：
/// 接收别的 App（微信/支付宝/淘宝等）通过系统分享发来的截图或文字，
/// 复制/取出后经 MethodChannel 交给 Flutter 去解析记账。
/// 冷启动：configureFlutterEngine 里先存起来，Flutter 主动来取（consumeInitialShare）。
/// 热启动：onNewIntent 直接推给 Flutter（onShare）。
class MainActivity : FlutterActivity() {
    private val channelName = "feimiao/share"
    private var channel: MethodChannel? = null
    private var pending: Map<String, String?>? = null
    private var pendingOpen: Map<String, String?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "consumeInitialShare" -> {
                    result.success(pending)
                    pending = null
                }
                "consumeInitialOpen" -> {
                    result.success(pendingOpen)
                    pendingOpen = null
                }
                else -> result.notImplemented()
            }
        }
        // 自动记账通道：取通知队列 / 查授权状态 / 跳系统设置。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "feimiao/autorecord")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "peekPending" -> {
                        result.success(PaymentNotificationListener.peekPendingJson(this))
                    }
                    "ackPending" -> {
                        val ids = call.argument<List<String>>("ids")
                            ?.map { it.trim() }
                            ?.filter { it.isNotEmpty() }
                            ?.toSet()
                            ?: emptySet()
                        result.success(
                            PaymentNotificationListener.acknowledgePending(this, ids)
                        )
                    }
                    "isEnabled" -> {
                        val flat = Settings.Secure.getString(
                            contentResolver, "enabled_notification_listeners"
                        ) ?: ""
                        result.success(flat.contains(packageName))
                    }
                    "openSettings" -> {
                        startActivity(
                            Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // 安全存储通道：把用户自己的 AI API Key 放进 Android Keystore 加密后的本机存储。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "feimiao/secure_store")
            .setMethodCallHandler { call, result ->
                val key = call.argument<String>("key")
                when (call.method) {
                    "read" -> {
                        if (key.isNullOrBlank()) result.success(null)
                        else result.success(secureRead(key))
                    }
                    "write" -> {
                        val value = call.argument<String>("value")
                        if (key.isNullOrBlank() || value == null) result.success(false)
                        else result.success(secureWrite(key, value))
                    }
                    "delete" -> {
                        if (key.isNullOrBlank()) result.success(false)
                        else result.success(secureDelete(key))
                    }
                    else -> result.notImplemented()
                }
            }

        // GPT OAuth callback keep-alive: Chrome is a separate Activity and
        // Android may reclaim the paused Flutter Activity before it follows
        // the localhost redirect. Keep the process alive only for the active
        // OAuth attempt; Flutter stops it after token exchange/cancellation.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "feimiao/oauth")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openEphemeralOAuth" -> {
                        val url = call.argument<String>("url")?.trim()
                        result.success(
                            if (url.isNullOrBlank()) false else openEphemeralOAuth(url)
                        )
                    }
                    "openIncognitoOAuth" -> {
                        val url = call.argument<String>("url")?.trim()
                        result.success(
                            if (url.isNullOrBlank()) false else openIncognitoOAuth(url)
                        )
                    }
                    "openChromeOAuth" -> {
                        val url = call.argument<String>("url")?.trim()
                        result.success(
                            if (url.isNullOrBlank()) false else openChromeOAuth(url)
                        )
                    }
                    "startKeepAlive" -> {
                        val ports = call.argument<List<Int>>("ports")
                            ?.filter { it in 1..65535 }
                            ?.distinct()
                            ?: listOf(
                                OAuthKeepAliveService.DEFAULT_PORT,
                                OAuthKeepAliveService.FALLBACK_PORT,
                            )
                        val flowId = call.argument<String>("flowId")
                            ?.trim()
                            ?.ifEmpty { null }
                        // The service lives in a separate process and binds its
                        // socket asynchronously. Do not tell Dart to open the
                        // browser until the port is actually listening.
                        Thread {
                            val port = OAuthKeepAliveService.startAndWait(this, ports, flowId)
                            runOnUiThread { result.success(port) }
                        }.start()
                    }
                    "stopKeepAlive" -> {
                        // stopAndWait touches the service marker while the
                        // isolated process is shutting down. Keep that bounded
                        // wait off the main thread so the Flutter UI remains
                        // responsive during cancel/completion.
                        val flowId = call.argument<String>("flowId")
                            ?.trim()
                            ?.ifEmpty { null }
                        Thread {
                            val stopped = OAuthKeepAliveService.stopAndWait(this, flowId)
                            runOnUiThread { result.success(stopped) }
                        }.start()
                    }
                    "takeCallback" -> {
                        val flowId = call.argument<String>("flowId")
                            ?.trim()
                            ?.ifEmpty { null }
                        result.success(OAuthKeepAliveService.takeCallback(this, flowId))
                    }
                    "clearCallback" -> {
                        val flowId = call.argument<String>("flowId")
                            ?.trim()
                            ?.ifEmpty { null }
                        result.success(OAuthKeepAliveService.clearCallback(this, flowId))
                    }
                    else -> result.notImplemented()
                }
            }

        // Android system HTTP proxy bridge. Full-device VPNs need no proxy
        // override; proxy-based VPN apps expose this value for Chrome but not
        // to Dart's HttpClient unless it is forwarded explicitly.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "feimiao/network")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSystemProxy" -> result.success(systemProxyInfo())
                    "getSystemProxyForUrl" -> {
                        val url = call.argument<String>("url")?.trim()
                        result.success(
                            if (url.isNullOrBlank()) null else systemProxyRouteForUrl(url)
                        )
                    }
                    else -> result.notImplemented()
                }
            }

        // 检查更新通道：下载走系统 DownloadManager（切后台/锁屏/杀进程都继续，
        // 系统通知栏自带进度），下载完 Flutter 侧校验 SHA256 再交系统安装器。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "feimiao/update")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) result.success(false)
                        else result.success(installApkFile(path))
                    }
                    "startDownload" -> {
                        val url = call.argument<String>("url")
                        val fileName = call.argument<String>("fileName")
                        val title = call.argument<String>("title") ?: "肥喵记账更新"
                        val versionCode = call.argument<Int>("versionCode") ?: 0
                        if (url.isNullOrBlank() || fileName.isNullOrBlank()) {
                            result.success(null)
                        } else {
                            result.success(startUpdateDownload(url, fileName, title, versionCode))
                        }
                    }
                    "queryDownload" -> {
                        val id = call.argument<Number>("id")?.toLong()
                        if (id == null) result.success(null)
                        else result.success(queryUpdateDownload(id))
                    }
                    "cancelDownload" -> {
                        val id = call.argument<Number>("id")?.toLong()
                        if (id != null) {
                            try {
                                (getSystemService(Context.DOWNLOAD_SERVICE) as android.app.DownloadManager)
                                    .remove(id)
                            } catch (_: Exception) {}
                        }
                        clearPendingUpdateDownload()
                        result.success(true)
                    }
                    "pendingDownload" -> result.success(pendingUpdateDownload())
                    "clearPendingDownload" -> {
                        clearPendingUpdateDownload()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "feimiao/widget")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveSnapshot" -> {
                        val snapshot = call.argument<String>("snapshot")
                        if (snapshot.isNullOrBlank()) {
                            result.success(false)
                        } else {
                            getSharedPreferences("feimiao_widget_snapshot", Context.MODE_PRIVATE)
                                .edit()
                                .putString("snapshot", snapshot)
                                .apply()
                            FeimiaoWidgetProvider.updateAll(this)
                            result.success(true)
                        }
                    }
                    "requestUpdate" -> {
                        FeimiaoWidgetProvider.updateAll(this)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // 冷启动带进来的分享：先存着，等 Dart 起来主动取。
        handleIntent(intent, push = false)
    }

    /**
     * Open GPT OAuth in a browser session with an isolated cookie jar.
     *
     * Chrome 137+ exposes Ephemeral Custom Tabs through AndroidX Browser
     * 1.9.0.  Unlike a regular Custom Tab, it cannot reuse the user's current
     * ChatGPT/Google session, which is required when authorizing a second
     * account. Older browsers return false and Dart falls back to the normal
     * browser/manual callback path.
     */
    private fun openEphemeralOAuth(url: String): Boolean {
        return try {
            val preferred = preferredChromePackages()
            val browser = CustomTabsClient.getPackageName(this, preferred)
                ?: return false
            if (!CustomTabsClient.isEphemeralBrowsingSupported(this, browser)) {
                return false
            }
            val customTabs = CustomTabsIntent.Builder()
                .setShowTitle(true)
                .setEphemeralBrowsingEnabled(true)
                .build()
            customTabs.intent.setPackage(browser)
            customTabs.launchUrl(this, Uri.parse(url))
            true
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Older Chrome builds do not expose Ephemeral Custom Tabs but still
     * understand the documented Incognito-tab intent extra. It gives OAuth a
     * fresh cookie jar, so adding a second ChatGPT/Google account does not
     * silently reuse the current personal space.
     */
    private fun openIncognitoOAuth(url: String): Boolean {
        val extra = "com.google.android.apps.chrome.EXTRA_OPEN_NEW_INCOGNITO_TAB"
        for (browser in preferredChromePackages()) {
            try {
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                    setPackage(browser)
                    putExtra(extra, true)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                if (intent.resolveActivity(packageManager) == null) continue
                startActivity(intent)
                return true
            } catch (_: Exception) {
                // Try the next installed Chrome channel before normal browser
                // fallback is selected by the Dart caller.
            }
        }
        return false
    }

    private fun openChromeOAuth(url: String): Boolean {
        for (browser in preferredChromePackages()) {
            try {
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                    setPackage(browser)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                if (intent.resolveActivity(packageManager) == null) continue
                startActivity(intent)
                return true
            } catch (_: Exception) {
                // Try the next installed Chrome channel.
            }
        }
        return false
    }

    private fun preferredChromePackages(): List<String> = listOf(
        "com.android.chrome",
        "com.chrome.beta",
        "com.chrome.dev",
        "com.chrome.canary",
    )

    private fun systemProxyInfo(): Map<String, Any?> {
        val connectivity = getSystemService(Context.CONNECTIVITY_SERVICE)
            as? ConnectivityManager
        val proxy = connectivity?.defaultProxy
        val hasPac = !proxy?.pacFileUrl?.toString().isNullOrBlank()
        // Chrome follows PAC files through Android's ProxySelector, while
        // Dart's HttpClient only sees a fixed host/port. Resolve the common
        // AI endpoints natively so proxy-based VPNs route app traffic the
        // same way as the browser even when ProxyInfo.host is empty.
        val pacRoutes = linkedMapOf<String, Map<String, Any?>>()
        for (host in listOf(
            "auth.openai.com",
            "chatgpt.com",
            "api.openai.com",
            "api.anthropic.com",
            "api.deepseek.com",
            "api.duckduckgo.com",
        )) {
            val route = proxySelectorRoute(host)
            if (route != null) pacRoutes[host] = route
        }
        return mapOf(
            // A PAC-backed ProxyInfo can still expose a host/port fallback.
            // Do not turn that fallback into a global Dart proxy: each target
            // must be evaluated by ProxySelector instead.
            "host" to if (hasPac) null else proxy?.host,
            "port" to if (hasPac) null else proxy?.port,
            "pacUrl" to proxy?.pacFileUrl?.toString(),
            "exclusionList" to proxy?.exclusionList?.toList().orEmpty(),
            "routes" to pacRoutes,
        )
    }

    private fun proxySelectorRoute(host: String): Map<String, Any?>? {
        return try {
            val selected = ProxySelector.getDefault()
                ?.select(URI("https://$host"))
                .orEmpty()
            val proxy = selected.firstOrNull { candidate ->
                candidate.type() != Proxy.Type.DIRECT &&
                    candidate.address() is InetSocketAddress
            } ?: return null
            val address = proxy.address() as InetSocketAddress
            val routeHost = address.hostString.trim()
            val routePort = address.port
            if (routeHost.isEmpty() || routePort <= 0 || routePort > 65535) {
                return null
            }
            mapOf(
                "host" to routeHost,
                "port" to routePort,
                "type" to when (proxy.type()) {
                    Proxy.Type.SOCKS -> "socks"
                    Proxy.Type.HTTP -> "http"
                    else -> "direct"
                },
            )
        } catch (_: Exception) {
            null
        }
    }

    private fun systemProxyRouteForUrl(rawUrl: String): Map<String, Any?> {
        return try {
            val uri = URI(rawUrl)
            val selected = ProxySelector.getDefault()?.select(uri).orEmpty()
            val candidate = selected.firstOrNull { it.type() != Proxy.Type.DIRECT }
            val selectedAddress = candidate
                ?.takeUnless { it.type() == Proxy.Type.DIRECT }
                ?.address() as? InetSocketAddress
            val selectedHost = selectedAddress?.hostString?.trim().orEmpty()
            val selectedPort = selectedAddress?.port ?: 0
            if (selectedHost.isNotEmpty() && selectedPort in 1..65535) {
                return mapOf(
                    "host" to selectedHost,
                    "port" to selectedPort,
                    "type" to when (candidate?.type()) {
                        Proxy.Type.SOCKS -> "socks"
                        Proxy.Type.HTTP -> "http"
                        else -> "direct"
                    },
                )
            }
            // ProxySelector may report DIRECT for a fixed Android default
            // proxy. Preserve that older bridge path before concluding that
            // the target should bypass the proxy.
            val connectivity = getSystemService(Context.CONNECTIVITY_SERVICE)
                as? ConnectivityManager
            val proxy = connectivity?.defaultProxy
            val hasPac = !proxy?.pacFileUrl?.toString().isNullOrBlank()
            if (hasPac || selected.isNotEmpty()) {
                // ProxySelector explicitly returned DIRECT (or could not
                // resolve a proxy for this PAC target); honor that decision.
                return mapOf("type" to "direct")
            }
            val host = proxy?.host?.trim().orEmpty()
            val port = proxy?.port ?: 0
            if (host.isEmpty() || port <= 0 || port > 65535) {
                mapOf("type" to "direct")
            } else {
                mapOf("host" to host, "port" to port, "type" to "http")
            }
        } catch (_: Exception) {
            val connectivity = getSystemService(Context.CONNECTIVITY_SERVICE)
                as? ConnectivityManager
            val proxy = connectivity?.defaultProxy
            val host = proxy?.host?.trim().orEmpty()
            val port = proxy?.port ?: 0
            if (host.isEmpty() || port <= 0 || port > 65535) {
                mapOf("type" to "direct")
            } else {
                mapOf("host" to host, "port" to port, "type" to "http")
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent, push = true)
    }

    private fun handleIntent(intent: Intent?, push: Boolean) {
        if (intent == null) return
        val openTarget = intent.getStringExtra("feimiao_open")
        if (!openTarget.isNullOrBlank()) {
            val payload = mutableMapOf<String, String?>("target" to openTarget)
            if (intent.hasExtra("feimiao_category_id")) {
                payload["categoryId"] = intent.getIntExtra("feimiao_category_id", -1).toString()
            }
            if (push) {
                channel?.invokeMethod("onOpen", payload)
            } else {
                pendingOpen = payload
            }
            intent.removeExtra("feimiao_open")
            intent.removeExtra("feimiao_category_id")
            return
        }
        if (intent.action != Intent.ACTION_SEND &&
            intent.action != Intent.ACTION_SEND_MULTIPLE
        ) return
        // 从最近任务恢复时系统会重放原始 SEND intent（进程被杀后 removeExtra
        // 只改掉进程内副本、写不回 task record），不能当成新分享再 OCR 一遍。
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
        val type = intent.type ?: return
        val payload: Map<String, String?>? = when {
            type.startsWith("image/") -> {
                @Suppress("DEPRECATION")
                val uri: Uri? = if (intent.action == Intent.ACTION_SEND) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM)
                } else {
                    intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                        ?.firstOrNull()
                }
                val path = uri?.let { copyToCache(it) }
                if (path != null) mapOf("type" to "image", "path" to path) else null
            }
            type.startsWith("text/") -> {
                val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                if (!text.isNullOrBlank()) mapOf("type" to "text", "text" to text) else null
            }
            else -> null
        }
        // 参照上面 feimiao_open 分支：处理完立刻把分享数据从 intent 上清掉。
        // Activity 被系统重建时 getIntent() 会原样重放旧 intent，不清会把同一张
        // 截图/同一段文字再次送去记账；清掉后 extras 取不到值，本分支安全跳过。
        intent.removeExtra(Intent.EXTRA_STREAM)
        intent.removeExtra(Intent.EXTRA_TEXT)
        if (payload == null) return

        if (push) {
            channel?.invokeMethod("onShare", payload)
        } else {
            pending = payload
        }
    }

    /// 把分享进来的 content:// 图片复制到 App 缓存目录，返回可读文件路径（供 ML Kit OCR）。
    private fun copyToCache(uri: Uri): String? {
        return try {
            cleanupSharedCache()
            val input = contentResolver.openInputStream(uri) ?: return null
            val file = File(cacheDir, "shared_${System.currentTimeMillis()}.jpg")
            file.outputStream().use { out -> input.copyTo(out) }
            input.close()
            file.absolutePath
        } catch (e: Exception) {
            null
        }
    }

    /// 清掉超过 24 小时的历史分享缓存图（shared_*.jpg），避免 cacheDir 越积越大。
    /// 清理失败不影响本次分享。
    private fun cleanupSharedCache() {
        try {
            val expireBefore = System.currentTimeMillis() - 24L * 60 * 60 * 1000
            cacheDir.listFiles()?.forEach { f ->
                if (f.isFile &&
                    f.name.startsWith("shared_") &&
                    f.name.endsWith(".jpg") &&
                    f.lastModified() < expireBefore
                ) {
                    f.delete()
                }
            }
        } catch (_: Exception) {
        }
    }

    private fun secretKey(): SecretKey {
        val alias = "feimiao_secure_store"
        val ks = KeyStore.getInstance("AndroidKeyStore")
        ks.load(null)
        val existing = ks.getKey(alias, null)
        if (existing is SecretKey) return existing

        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        val spec = KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)
            .build()
        gen.init(spec)
        return gen.generateKey()
    }

    private fun secureWrite(key: String, value: String): Boolean {
        return try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, secretKey())
            val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
            val payload = Base64.encodeToString(cipher.iv + encrypted, Base64.NO_WRAP)
            getSharedPreferences("feimiao_secure_store", Context.MODE_PRIVATE)
                .edit()
                .putString(key, payload)
                .apply()
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun secureRead(key: String): String? {
        return try {
            val payload = getSharedPreferences("feimiao_secure_store", Context.MODE_PRIVATE)
                .getString(key, null) ?: return null
            val bytes = Base64.decode(payload, Base64.NO_WRAP)
            if (bytes.size <= 12) return null
            val iv = bytes.copyOfRange(0, 12)
            val encrypted = bytes.copyOfRange(12, bytes.size)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, iv))
            String(cipher.doFinal(encrypted), Charsets.UTF_8)
        } catch (e: Exception) {
            null
        }
    }

    private fun secureDelete(key: String): Boolean {
        return try {
            getSharedPreferences("feimiao_secure_store", Context.MODE_PRIVATE)
                .edit()
                .remove(key)
                .apply()
            true
        } catch (e: Exception) {
            false
        }
    }

    /// 把更新 APK 交给系统 DownloadManager 下载（App 冻结/被杀不影响）。
    /// 返回 downloadId；失败（个别 ROM 禁用了下载管理器）返回 null，
    /// Flutter 侧回退到进程内下载。挂起记录写 SharedPreferences，
    /// 冷启动后能接上「下载完但还没装」的包。
    private fun startUpdateDownload(
        url: String,
        fileName: String,
        title: String,
        versionCode: Int,
    ): Long? {
        return try {
            val dir = getExternalFilesDir(android.os.Environment.DIRECTORY_DOWNLOADS)
                ?: return null
            val target = File(dir, fileName)
            if (target.exists()) target.delete()
            val dm = getSystemService(Context.DOWNLOAD_SERVICE) as android.app.DownloadManager
            val request = android.app.DownloadManager.Request(Uri.parse(url)).apply {
                setTitle(title)
                setDescription("下载完成后回到肥喵记账即可安装")
                setMimeType("application/vnd.android.package-archive")
                setNotificationVisibility(
                    android.app.DownloadManager.Request.VISIBILITY_VISIBLE,
                )
                setDestinationInExternalFilesDir(
                    this@MainActivity,
                    android.os.Environment.DIRECTORY_DOWNLOADS,
                    fileName,
                )
                setAllowedOverMetered(true)
                setAllowedOverRoaming(true)
            }
            val id = dm.enqueue(request)
            getSharedPreferences("feimiao_update", Context.MODE_PRIVATE)
                .edit()
                .putLong("download_id", id)
                .putInt("version_code", versionCode)
                .putString("file_path", target.absolutePath)
                .apply()
            id
        } catch (e: Exception) {
            null
        }
    }

    /// 查询 DownloadManager 里某次下载的状态与进度。
    private fun queryUpdateDownload(id: Long): Map<String, Any?>? {
        return try {
            val dm = getSystemService(Context.DOWNLOAD_SERVICE) as android.app.DownloadManager
            val cursor = dm.query(android.app.DownloadManager.Query().setFilterById(id))
            cursor.use { c ->
                if (!c.moveToFirst()) return mapOf("status" to "missing")
                val status =
                    when (c.getInt(c.getColumnIndexOrThrow(android.app.DownloadManager.COLUMN_STATUS))) {
                        android.app.DownloadManager.STATUS_SUCCESSFUL -> "successful"
                        android.app.DownloadManager.STATUS_RUNNING -> "running"
                        android.app.DownloadManager.STATUS_PENDING -> "pending"
                        android.app.DownloadManager.STATUS_PAUSED -> "paused"
                        else -> "failed"
                    }
                val received = c.getLong(
                    c.getColumnIndexOrThrow(
                        android.app.DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR,
                    ),
                )
                val total = c.getLong(
                    c.getColumnIndexOrThrow(android.app.DownloadManager.COLUMN_TOTAL_SIZE_BYTES),
                )
                val reason = c.getInt(
                    c.getColumnIndexOrThrow(android.app.DownloadManager.COLUMN_REASON),
                )
                mapOf(
                    "status" to status,
                    "received" to received,
                    "total" to total,
                    "reason" to reason,
                )
            }
        } catch (e: Exception) {
            null
        }
    }

    /// 上次入队且还没被清掉的更新下载（跨启动接续用）。
    private fun pendingUpdateDownload(): Map<String, Any?>? {
        val prefs = getSharedPreferences("feimiao_update", Context.MODE_PRIVATE)
        val id = prefs.getLong("download_id", -1L)
        if (id < 0) return null
        return mapOf(
            "id" to id,
            "versionCode" to prefs.getInt("version_code", 0),
            "path" to prefs.getString("file_path", ""),
        )
    }

    private fun clearPendingUpdateDownload() {
        getSharedPreferences("feimiao_update", Context.MODE_PRIVATE)
            .edit()
            .remove("download_id")
            .remove("version_code")
            .remove("file_path")
            .apply()
    }

    /// 检查更新：用 FileProvider 把缓存里的 APK 交给系统安装器。
    private fun installApkFile(path: String): Boolean {
        return try {
            val file = File(path)
            if (!file.exists()) return false
            val uri = androidx.core.content.FileProvider.getUriForFile(
                this,
                "$packageName.updateprovider",
                file,
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }
}
