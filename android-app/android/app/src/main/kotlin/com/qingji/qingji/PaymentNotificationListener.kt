package com.qingji.qingji

import android.app.Notification
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject

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
        appendPending(this, app, body, sbn.postTime)
    }

    companion object {
        private const val WECHAT = "com.tencent.mm"
        private const val ALIPAY = "com.eg.android.AlipayGphone"
        private const val PREF = "feimiao_autorecord"
        private const val KEY = "pending"

        private val MONEY = Regex("[¥￥]|\\d+(\\.\\d+)?\\s*元")
        private val PAY_WORDS = Regex("支付|付款|消费|扣款|到账|收款|收钱|转账|交易")

        fun appendPending(ctx: Context, app: String, text: String, time: Long) {
            val sp = ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE)
            val arr = JSONArray(sp.getString(KEY, "[]"))

            // 去重：同 app+文本、60 秒内只记一次（微信会重复 post / 更新通知）。
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                if (o.optString("text") == text &&
                    o.optString("app") == app &&
                    Math.abs(o.optLong("time") - time) < 60_000
                ) return
            }

            // 上限保护：最多保留 50 条（旧的丢掉）。
            val out = JSONArray()
            val start = if (arr.length() >= 50) arr.length() - 49 else 0
            for (i in start until arr.length()) out.put(arr.getJSONObject(i))
            out.put(JSONObject().apply {
                put("app", app)
                put("text", text)
                put("time", time)
            })
            sp.edit().putString(KEY, out.toString()).apply()
        }
    }
}
