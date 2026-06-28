package com.qingji.qingji

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// 「分享到肥喵」原生桥：
/// 接收别的 App（微信/支付宝/淘宝等）通过系统分享发来的截图或文字，
/// 复制/取出后经 MethodChannel 交给 Flutter 去解析记账。
/// 冷启动：configureFlutterEngine 里先存起来，Flutter 主动来取（consumeInitialShare）。
/// 热启动：onNewIntent 直接推给 Flutter（onShare）。
class MainActivity : FlutterActivity() {
    private val channelName = "feimiao/share"
    private var channel: MethodChannel? = null
    private var pending: Map<String, String?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            if (call.method == "consumeInitialShare") {
                result.success(pending)
                pending = null
            } else {
                result.notImplemented()
            }
        }
        // 自动记账通道：取通知队列 / 查授权状态 / 跳系统设置。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "feimiao/autorecord")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "consumePending" -> {
                        val sp = getSharedPreferences("feimiao_autorecord", Context.MODE_PRIVATE)
                        val data = sp.getString("pending", "[]")
                        sp.edit().putString("pending", "[]").apply()
                        result.success(data)
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

        // 冷启动带进来的分享：先存着，等 Dart 起来主动取。
        handleIntent(intent, push = false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent, push = true)
    }

    private fun handleIntent(intent: Intent?, push: Boolean) {
        if (intent == null) return
        if (intent.action != Intent.ACTION_SEND &&
            intent.action != Intent.ACTION_SEND_MULTIPLE
        ) return
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
        } ?: return

        if (push) {
            channel?.invokeMethod("onShare", payload)
        } else {
            pending = payload
        }
    }

    /// 把分享进来的 content:// 图片复制到 App 缓存目录，返回可读文件路径（供 ML Kit OCR）。
    private fun copyToCache(uri: Uri): String? {
        return try {
            val input = contentResolver.openInputStream(uri) ?: return null
            val file = File(cacheDir, "shared_${System.currentTimeMillis()}.jpg")
            file.outputStream().use { out -> input.copyTo(out) }
            input.close()
            file.absolutePath
        } catch (e: Exception) {
            null
        }
    }
}
