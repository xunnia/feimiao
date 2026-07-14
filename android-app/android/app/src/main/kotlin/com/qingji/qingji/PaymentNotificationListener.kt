package com.qingji.qingji

import android.app.Notification
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/// 自动记账核心：监听微信/支付宝的支付通知，粗筛出「像一笔消费」的，
/// 排队存到 SharedPreferences。App 下次打开时由 Flutter 取出、解析、确认记账。
/// 注意：本服务由系统绑定，可在 App 未打开时后台运行（但国产 ROM 可能杀后台，
/// 需引导用户加电池白名单/自启动）。
class PaymentNotificationListener : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val pkg = sbn.packageName ?: return
        if (pkg != WECHAT && pkg != ALIPAY) return

        val extras = sbn.notification?.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val big = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""
        val body = listOf(title, big.ifEmpty { text })
            .filter { it.isNotBlank() }
            .joinToString(" ")
            .trim()
        if (body.isBlank()) return

        // 粗过滤：必须像一笔钱（含 ¥/￥ 或「数字元」），且像支付/收付款。
        if (!MONEY.containsMatchIn(body)) return
        if (!PAY_WORDS.containsMatchIn(body)) return

        val app = if (pkg == WECHAT) "微信" else "支付宝"
        appendPending(this, app, body, sbn.postTime, sbn.key)
    }

    companion object {
        private const val WECHAT = "com.tencent.mm"
        private const val ALIPAY = "com.eg.android.AlipayGphone"
        private const val PREF = "feimiao_autorecord"
        private const val KEY = "pending"
        private const val KEY_SEEN = "seen_events"

        private val MONEY = Regex("[¥￥]|\\d+(\\.\\d+)?\\s*元")
        private val PAY_WORDS = Regex("支付|付款|消费|扣款|到账|收款|收钱|转账|交易")

        @Synchronized
        fun appendPending(
            ctx: Context,
            app: String,
            text: String,
            time: Long,
            notificationKey: String
        ) {
            val sp = ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE)
            val arr = readArray(sp.getString(KEY, "[]"))
            val sourceKey = notificationKey.ifBlank { "$app\u0000$text" }
            val fingerprint = "$sourceKey\u0000$time"

            // 同一个系统通知发生更新时，key + postTime 不变。更新队列里的正文，
            // 不按「同文本若干秒」猜重，避免吞掉两笔真实的同价消费。
            for (i in 0 until arr.length()) {
                val item = arr.optJSONObject(i) ?: continue
                if (item.optString("source_key") == sourceKey &&
                    item.optLong("source_post_time") == time
                ) {
                    item.put("app", app)
                    item.put("text", text)
                    item.put("time", time)
                    if (item.optString("id").isBlank()) {
                        item.put("id", UUID.randomUUID().toString())
                    }
                    sp.edit().putString(KEY, arr.toString()).commit()
                    return
                }
            }

            // 已确认过的同一系统事件也不重新入队；不同 postTime 的同文通知
            // 是不同真实事件，必须保留。
            val seen = readArray(sp.getString(KEY_SEEN, "[]"))
            for (i in 0 until seen.length()) {
                if (seen.optString(i) == fingerprint) return
            }

            // 上限保护：最多保留 100 条待确认通知与 200 个近期事件指纹。
            val out = JSONArray()
            val start = if (arr.length() >= 100) arr.length() - 99 else 0
            for (i in start until arr.length()) out.put(arr.getJSONObject(i))
            out.put(JSONObject().apply {
                put("id", UUID.randomUUID().toString())
                put("app", app)
                put("text", text)
                put("time", time)
                put("source_key", sourceKey)
                put("source_post_time", time)
            })

            val seenOut = JSONArray()
            val seenStart = if (seen.length() >= 200) seen.length() - 199 else 0
            for (i in seenStart until seen.length()) seenOut.put(seen.optString(i))
            seenOut.put(fingerprint)
            sp.edit()
                .putString(KEY, out.toString())
                .putString(KEY_SEEN, seenOut.toString())
                .commit()
        }

        @Synchronized
        fun peekPendingJson(ctx: Context): String {
            val sp = ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE)
            val source = readArray(sp.getString(KEY, "[]"))
            val normalized = JSONArray()
            var changed = false
            for (i in 0 until source.length()) {
                val item = source.optJSONObject(i)
                if (item == null) {
                    changed = true
                    continue
                }
                if (item.optString("id").isBlank()) {
                    item.put("id", UUID.randomUUID().toString())
                    changed = true
                }
                normalized.put(item)
            }
            if (changed) {
                sp.edit().putString(KEY, normalized.toString()).commit()
            }
            return normalized.toString()
        }

        @Synchronized
        fun acknowledgePending(ctx: Context, ids: Set<String>): Int {
            if (ids.isEmpty()) return 0
            val sp = ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE)
            val source = readArray(sp.getString(KEY, "[]"))
            val remaining = JSONArray()
            var removed = 0
            for (i in 0 until source.length()) {
                val item = source.optJSONObject(i) ?: continue
                if (ids.contains(item.optString("id"))) {
                    removed++
                } else {
                    remaining.put(item)
                }
            }
            sp.edit().putString(KEY, remaining.toString()).commit()
            return removed
        }

        private fun readArray(raw: String?): JSONArray {
            return try {
                JSONArray(raw ?: "[]")
            } catch (_: Exception) {
                JSONArray()
            }
        }
    }
}
