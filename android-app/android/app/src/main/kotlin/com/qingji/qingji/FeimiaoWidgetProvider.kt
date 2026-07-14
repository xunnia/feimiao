package com.qingji.qingji

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

private const val PREFS_NAME = "feimiao_widget_snapshot"
private const val SNAPSHOT_KEY = "snapshot"

private const val COLOR_TEXT = 0xFF191A1C.toInt()
private const val COLOR_SECONDARY = 0xFF74777D.toInt()
private const val COLOR_MUTED = 0xFF9A9CA1.toInt()
private const val COLOR_BLUE = 0xFF0A84FF.toInt()
private const val COLOR_BAR_LIGHT = 0xFFF2F3F5.toInt()
private const val COLOR_BAR_DARK = 0xFF666A70.toInt()
private const val COLOR_DIVIDER = 0x1A000000

class FeimiaoWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
            appWidgetManager.updateAppWidget(appWidgetId, buildOverviewViews(context, options))
        }
    }

    companion object {
        fun updateAll(context: Context) {
            updateProvider(context, FeimiaoWidgetProvider::class.java)
            updateProvider(context, FeimiaoQuickAddWidgetProvider::class.java)
            updateProvider(context, FeimiaoBudgetWidgetProvider::class.java)
            updateProvider(context, FeimiaoCategoriesWidgetProvider::class.java)
        }
    }
}

class FeimiaoQuickAddWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            appWidgetManager.updateAppWidget(appWidgetId, buildQuickAddViews(context))
        }
    }
}

class FeimiaoBudgetWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
            appWidgetManager.updateAppWidget(appWidgetId, buildBudgetViews(context, options))
        }
    }
}

class FeimiaoCategoriesWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            appWidgetManager.updateAppWidget(appWidgetId, buildCategoriesViews(context))
        }
    }
}

private fun updateProvider(
    context: Context,
    providerClass: Class<out AppWidgetProvider>
) {
    val manager = AppWidgetManager.getInstance(context)
    val component = ComponentName(context, providerClass)
    val ids = manager.getAppWidgetIds(component)
    if (ids.isNotEmpty()) {
        val provider = providerClass.getDeclaredConstructor().newInstance()
        provider.onUpdate(context, manager, ids)
    }
}

private fun buildOverviewViews(context: Context, options: Bundle? = null): RemoteViews {
    val views = RemoteViews(context.packageName, R.layout.widget_feimiao)
    val snapshot = readSnapshot(context)

    views.setOnClickPendingIntent(R.id.widget_root, launchIntent(context, "home", 1))
    views.setOnClickPendingIntent(R.id.widget_add_button, launchIntent(context, "quick_add", 2))
    views.setOnClickPendingIntent(R.id.widget_stats_button, launchIntent(context, "statistics", 3))

    if (snapshot == null) {
        overviewEmpty(views)
        return views
    }

    val overview = snapshot.module("overview")
    if (overview == null) {
        overviewV1(views, snapshot)
        return views
    }
    if (applyRenderedImage(
            views = views,
            imageId = R.id.widget_rendered_image,
            fallbackId = R.id.widget_fallback_content,
            render = overview.optJSONObject("render")
        )
    ) {
        views.setContentDescription(R.id.widget_root, "肥喵总览，点按打开主页")
        return views
    }

    val primary = overview.optJSONObject("primary")
    val secondary = overview.optJSONArray("secondary")
    val firstSecondary = secondary?.optJSONObject(0)
    val today = secondary.metricByLabel("今日")
    val income = secondary.metricByLabel("收入")
    val balance = secondary.metricByLabel("结余")
    val progress = overview.optJSONObject("progress")
    val progressVisible = progress?.optBoolean("visible", false) == true
    val mode = overview.optString("mode", "normal")
    val secondaryMetric = if (mode == "budget") firstSecondary else income ?: firstSecondary
    val secondaryLabel = secondaryMetric.optStringCompat("label", if (mode == "budget") "支出" else "收入")

    views.setTextViewText(R.id.widget_book_name, snapshot.bookName())
    views.setTextViewText(R.id.widget_date, snapshot.monthText())
    views.setTextViewText(R.id.widget_primary_label, primary.optStringCompat("label", if (mode == "budget") "预算剩余" else "支出"))
    views.setTextViewText(R.id.widget_month_expense, primary.optStringCompat("amountText", "--"))
    views.setTextViewText(R.id.widget_secondary_label, secondaryLabel)
    views.setTextViewText(R.id.widget_month_income, secondaryMetric.optStringCompat("amountText", "--"))
    views.setTextColor(R.id.widget_month_income, if (secondaryLabel.contains("收入")) 0xFF1F9A69.toInt() else COLOR_TEXT)
    views.setTextViewText(R.id.widget_bottom_text, if (mode == "budget") snapshot.optString("budgetHint", "") else "结余 ${balance.optStringCompat("amountText", "--")}")
    views.setTextViewText(R.id.widget_today_expense, "今日 ${today.optStringCompat("amountText", "--")}")
    views.setViewVisibility(R.id.widget_budget_progress, if (progressVisible) View.VISIBLE else View.GONE)
    views.setProgressBar(
        R.id.widget_budget_progress,
        100,
        progress?.optInt("value", 0)?.coerceIn(0, 100) ?: 0,
        false
    )
    views.setContentDescription(
        R.id.widget_root,
        "肥喵总览，${primary.optStringCompat("semanticText", "")}" 
    )
    return views
}

private fun overviewEmpty(views: RemoteViews) {
    views.setTextViewText(R.id.widget_book_name, "肥喵记账")
    views.setTextViewText(R.id.widget_date, "本月")
    views.setTextViewText(R.id.widget_today_expense, "今日 --")
    views.setTextViewText(R.id.widget_bottom_text, "结余 --")
    views.setTextViewText(R.id.widget_month_expense, "--")
    views.setTextViewText(R.id.widget_month_income, "--")
    views.setTextViewText(R.id.widget_primary_label, "支出")
    views.setTextViewText(R.id.widget_secondary_label, "收入")
    views.setTextColor(R.id.widget_month_income, 0xFF1F9A69.toInt())
    views.setViewVisibility(R.id.widget_budget_progress, View.GONE)
    views.setProgressBar(R.id.widget_budget_progress, 100, 0, false)
    views.setContentDescription(R.id.widget_root, "肥喵总览，打开 App 后同步小组件")
}

private fun overviewV1(views: RemoteViews, snapshot: JSONObject) {
    val budgetTitle = snapshot.optString("budgetTitle", "本月支出")
    val hasBudget = budgetTitle.contains("预算")
    views.setTextViewText(R.id.widget_book_name, snapshot.optString("bookName", "肥喵记账"))
    views.setTextViewText(R.id.widget_date, snapshot.monthText())
    views.setTextViewText(R.id.widget_today_expense, "今日 ${snapshot.optString("todayExpenseText", "--")}")
    views.setViewVisibility(R.id.widget_budget_progress, if (hasBudget) View.VISIBLE else View.GONE)
    views.setProgressBar(
        R.id.widget_budget_progress,
        100,
        if (hasBudget) snapshot.optInt("budgetProgress", 0).coerceIn(0, 100) else 0,
        false
    )
    views.setTextViewText(R.id.widget_primary_label, if (hasBudget) budgetTitle else "支出")
    views.setTextViewText(R.id.widget_secondary_label, if (hasBudget) "支出" else "收入")
    views.setTextColor(R.id.widget_month_income, if (hasBudget) COLOR_TEXT else 0xFF1F9A69.toInt())
    views.setTextViewText(
        R.id.widget_month_expense,
        if (hasBudget) snapshot.optString("budgetText", "--")
        else snapshot.optString("monthExpenseText", "--")
    )
    views.setTextViewText(
        R.id.widget_month_income,
        if (hasBudget) snapshot.optString("monthExpenseText", "--")
        else snapshot.optString("monthIncomeText", "--")
    )
    views.setTextViewText(
        R.id.widget_bottom_text,
        if (hasBudget) snapshot.optString("budgetHint", "")
        else "结余 ${snapshot.optString("balanceText", "--")}"
    )
}
private fun buildQuickAddViews(context: Context): RemoteViews {
    val views = RemoteViews(context.packageName, R.layout.widget_quick_add)
    val snapshot = readSnapshot(context)
    val quickAdd = snapshot?.module("quickAdd")
    views.setOnClickPendingIntent(R.id.widget_quick_root, launchIntent(context, "quick_add", 10))
    views.setTextViewText(R.id.widget_quick_title, quickAdd?.optString("title", "记一笔") ?: "记一笔")
    views.setTextViewText(
        R.id.widget_quick_date,
        quickAdd?.optString("subtitle", snapshot?.optString("dateText", "今日") ?: "今日")
            ?: "今日"
    )
    // 右侧一眼信息：今日支出（隐私模式下快照里已是 ••••）。
    val todayText = snapshot?.optString("todayExpenseText", "")?.takeIf { it.isNotBlank() }
    views.setTextViewText(
        R.id.widget_quick_today,
        if (todayText == null) "" else "今日 $todayText"
    )
    views.setContentDescription(R.id.widget_quick_root, "肥喵快速记账，点按记一笔")
    return views
}

private fun buildBudgetViews(context: Context, options: Bundle? = null): RemoteViews {
    val views = RemoteViews(context.packageName, R.layout.widget_budget)
    val snapshot = readSnapshot(context)

    views.setOnClickPendingIntent(R.id.widget_budget_root, launchIntent(context, "statistics", 20))
    views.setOnClickPendingIntent(R.id.widget_budget_add, launchIntent(context, "quick_add", 21))

    if (snapshot == null) {
        budgetEmpty(views)
        return views
    }

    val pace = snapshot.module("pace")
    if (pace == null) {
        budgetV1(views, snapshot, context, options)
        return views
    }
    if (applyRenderedImage(
            views = views,
            imageId = R.id.widget_budget_rendered_image,
            fallbackId = R.id.widget_budget_fallback_content,
            render = pace.optJSONObject("render")
        )
    ) {
        views.setContentDescription(
            R.id.widget_budget_root,
            pace.optString("semanticText", "肥喵本月进度")
        )
        return views
    }

    val average = pace.optJSONObject("average")
    val current = pace.optJSONObject("current")
    views.setTextViewText(R.id.widget_budget_book, snapshot.bookName())
    views.setTextViewText(R.id.widget_budget_date, snapshot.dateText())
    views.setTextViewText(R.id.widget_budget_title_text, pace.optString("title", "截至今日"))
    views.setTextViewText(R.id.widget_budget_average_label, average.optStringCompat("label", "平均"))
    views.setTextViewText(R.id.widget_budget_current_label, current.optStringCompat("label", "本月"))
    views.setTextViewText(R.id.widget_budget_today_expense, average.optStringCompat("amountText", "--"))
    views.setTextViewText(R.id.widget_budget_main_text, current.optStringCompat("amountText", "--"))
    views.setImageViewBitmap(R.id.widget_budget_chart, renderPaceChart(context, pace, options))
    views.setContentDescription(
        R.id.widget_budget_root,
        pace.optString("semanticText", "肥喵本月进度")
    )
    return views
}

private fun budgetEmpty(views: RemoteViews) {
    views.setTextViewText(R.id.widget_budget_book, "肥喵记账")
    views.setTextViewText(R.id.widget_budget_date, "打开 App 后更新")
    views.setTextViewText(R.id.widget_budget_title_text, "截至今日")
    views.setTextViewText(R.id.widget_budget_average_label, "平均")
    views.setTextViewText(R.id.widget_budget_current_label, "本月")
    views.setTextViewText(R.id.widget_budget_main_text, "--")
    views.setTextViewText(R.id.widget_budget_today_expense, "--")
    views.setImageViewBitmap(R.id.widget_budget_chart, emptyBitmap(1, 1))
    views.setContentDescription(R.id.widget_budget_root, "肥喵本月进度，打开 App 后同步")
}

private fun budgetV1(
    views: RemoteViews,
    snapshot: JSONObject,
    context: Context,
    options: Bundle?
) {
    views.setTextViewText(R.id.widget_budget_book, snapshot.optString("bookName", "肥喵记账"))
    views.setTextViewText(R.id.widget_budget_date, snapshot.optString("dateText", "今日"))
    views.setTextViewText(R.id.widget_budget_title_text, snapshot.optString("paceCaption", "截至今日"))
    views.setTextViewText(R.id.widget_budget_average_label, "平均")
    views.setTextViewText(R.id.widget_budget_current_label, "本月")
    views.setTextViewText(R.id.widget_budget_main_text, snapshot.optString("monthExpenseText", "--"))
    views.setTextViewText(R.id.widget_budget_today_expense, snapshot.optString("paceAverageText", "--"))
    views.setImageViewBitmap(R.id.widget_budget_chart, renderPaceChart(context, null, options))
}
private fun buildCategoriesViews(context: Context): RemoteViews {
    val views = RemoteViews(context.packageName, R.layout.widget_categories)
    val snapshot = readSnapshot(context)

    views.setOnClickPendingIntent(R.id.widget_categories_root, launchIntent(context, "statistics_categories", 30))
    views.setOnClickPendingIntent(R.id.widget_categories_add, launchIntent(context, "quick_add", 31))
    views.setOnClickPendingIntent(R.id.widget_categories_show_all, launchIntent(context, "statistics_categories", 32))

    views.setTextViewText(
        R.id.widget_categories_book,
        snapshot?.bookName() ?: "肥喵记账"
    )
    views.setTextViewText(
        R.id.widget_categories_date,
        snapshot?.dateText() ?: "打开 App 后更新"
    )
    val module = snapshot?.module("categories")
    val items = module?.optJSONArray("items") ?: snapshot?.optJSONArray("categories")
    views.setTextViewText(R.id.widget_categories_title, module?.optString("title", "分类与支出活动") ?: "分类与支出活动")
    views.setTextViewText(R.id.widget_categories_show_all, module?.optString("showAllText", "查看所有") ?: "查看所有")
    setCategoryRows(context, views, items, R.id.widget_categories_empty, requestCodeBase = 4300)
    views.setContentDescription(R.id.widget_categories_root, categoriesSemantic(items))
    return views
}

private fun readSnapshot(context: Context): JSONObject? {
    val raw = context
        .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .getString(SNAPSHOT_KEY, null)
        ?: return null
    return try {
        JSONObject(raw)
    } catch (_: Exception) {
        null
    }
}

private fun setCategoryRows(
    context: Context,
    views: RemoteViews,
    categories: JSONArray?,
    emptyId: Int? = null,
    requestCodeBase: Int = 4000
) {
    val hasAny = categories != null && categories.length() > 0
    emptyId?.let { views.setViewVisibility(it, if (hasAny) View.GONE else View.VISIBLE) }
    setCategoryRow(context, views, 1, categories?.optJSONObject(0), requestCodeBase)
    setCategoryRow(context, views, 2, categories?.optJSONObject(1), requestCodeBase)
    setCategoryRow(context, views, 3, categories?.optJSONObject(2), requestCodeBase)
}

private fun setCategoryRow(
    context: Context,
    views: RemoteViews,
    index: Int,
    item: JSONObject?,
    requestCodeBase: Int
) {
    val rowId = when (index) {
        1 -> R.id.widget_category_row_1
        2 -> R.id.widget_category_row_2
        else -> R.id.widget_category_row_3
    }
    val nameId = when (index) {
        1 -> R.id.widget_category_name_1
        2 -> R.id.widget_category_name_2
        else -> R.id.widget_category_name_3
    }
    val amountId = when (index) {
        1 -> R.id.widget_category_amount_1
        2 -> R.id.widget_category_amount_2
        else -> R.id.widget_category_amount_3
    }
    val percentId = when (index) {
        1 -> R.id.widget_category_percent_1
        2 -> R.id.widget_category_percent_2
        else -> R.id.widget_category_percent_3
    }
    val progressId = when (index) {
        1 -> R.id.widget_category_progress_1
        2 -> R.id.widget_category_progress_2
        else -> R.id.widget_category_progress_3
    }
    val dotId = when (index) {
        1 -> R.id.widget_category_dot_1
        2 -> R.id.widget_category_dot_2
        else -> R.id.widget_category_dot_3
    }
    if (item == null) {
        views.setViewVisibility(rowId, View.GONE)
        return
    }
    views.setViewVisibility(rowId, View.VISIBLE)
    views.setTextViewText(nameId, item.optString("name", "其他"))
    views.setTextViewText(amountId, item.optString("amountText", "--"))
    views.setTextViewText(percentId, item.optString("percentText", ""))
    views.setProgressBar(progressId, 100, item.optInt("progress", 0).coerceIn(0, 100), false)
    views.setTextColor(dotId, item.optInt("colorValue", COLOR_TEXT))
    val categoryId = item.optInt("id", -1)
    val requestCode = requestCodeBase + index + max(categoryId, 0) * 10
    views.setOnClickPendingIntent(
        rowId,
        launchIntent(context, "statistics_category", requestCode, categoryId)
    )
}

private fun renderPaceChart(context: Context, pace: JSONObject?, options: Bundle?): Bitmap {
    val density = context.resources.displayMetrics.density
    val minWidthDp = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 280) ?: 280
    val width = ((minWidthDp - 34).coerceAtLeast(190) * density).roundToInt()
    val height = (56 * density).roundToInt()
    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)

    val chart = pace?.optJSONObject("chart")
    val months = chart?.optJSONArray("months") ?: JSONArray()
    if (months.length() == 0) return bitmap

    val maxValue = max(chart?.optDouble("maxValue", 1.0) ?: 1.0, 0.01)
    val average = pace?.optJSONObject("average")?.optDouble("value", 0.0) ?: 0.0
    val state = pace?.optString("state", "normal") ?: "normal"
    val top = 10f * density
    val bottomLabel = 13f * density
    val chartHeight = height - top - bottomLabel - 2f * density
    val groupWidth = width / months.length().toFloat()
    val fullBarWidth = min(groupWidth * 0.46f, 13f * density)
    val sameBarWidth = min(groupWidth * 0.34f, 10f * density)
    val radius = 3f * density

    val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    for (i in 0 until months.length()) {
        val item = months.optJSONObject(i) ?: continue
        val centerX = groupWidth * i + groupWidth / 2f
        val isCurrent = item.optBoolean("isCurrent", false)
        val fullValue = item.optDouble("fullValue", 0.0)
        val sameValue = item.optDouble("sameProgressValue", 0.0)

        if (!isCurrent && fullValue > 0.0) {
            val fullHeight = (fullValue / maxValue * chartHeight).toFloat().coerceIn(1f, chartHeight)
            paint.color = COLOR_BAR_LIGHT
            val rect = RectF(
                centerX - fullBarWidth / 2f,
                top + chartHeight - fullHeight,
                centerX + fullBarWidth / 2f,
                top + chartHeight
            )
            canvas.drawRoundRect(rect, radius, radius, paint)
        }

        if (sameValue > 0.0) {
            val sameHeight = (sameValue / maxValue * chartHeight).toFloat().coerceIn(1f, chartHeight)
            paint.color = if (isCurrent) COLOR_BLUE else COLOR_BAR_DARK
            val rect = RectF(
                centerX - sameBarWidth / 2f,
                top + chartHeight - sameHeight,
                centerX + sameBarWidth / 2f,
                top + chartHeight
            )
            canvas.drawRoundRect(rect, radius, radius, paint)
        }

        paint.color = if (isCurrent) COLOR_BLUE else COLOR_MUTED
        paint.textSize = 8.5f * density
        paint.textAlign = Paint.Align.CENTER
        canvas.drawText(item.optString("label", ""), centerX, height - 3f * density, paint)
    }

    if (state != "insufficientData" && average > 0.0) {
        val y = top + chartHeight - (average / maxValue * chartHeight).toFloat().coerceIn(0f, chartHeight)
        paint.color = 0xFFC1C4CA.toInt()
        paint.strokeWidth = 2.7f * density
        canvas.drawLine(0f, y, width.toFloat(), y, paint)
        paint.textSize = 9f * density
        paint.textAlign = Paint.Align.RIGHT
        paint.color = COLOR_SECONDARY
        canvas.drawText("平均", width - 2f * density, y - 3f * density, paint)
    }
    return bitmap
}

private fun emptyBitmap(width: Int, height: Int): Bitmap =
    Bitmap.createBitmap(max(width, 1), max(height, 1), Bitmap.Config.ARGB_8888)

private fun applyRenderedImage(
    views: RemoteViews,
    imageId: Int,
    fallbackId: Int,
    render: JSONObject?
): Boolean {
    val bitmap = decodeRenderedBitmap(render?.optString("path"))
    if (bitmap == null) {
        views.setViewVisibility(imageId, View.GONE)
        views.setViewVisibility(fallbackId, View.VISIBLE)
        return false
    }
    views.setImageViewBitmap(imageId, bitmap)
    views.setViewVisibility(imageId, View.VISIBLE)
    views.setViewVisibility(fallbackId, View.GONE)
    return true
}

private fun decodeRenderedBitmap(path: String?): Bitmap? {
    if (path.isNullOrBlank()) return null
    val file = File(path)
    if (!file.exists() || !file.isFile) return null
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeFile(file.absolutePath, bounds)
    if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
    var sample = 1
    while ((bounds.outWidth / sample) * (bounds.outHeight / sample) > 1_500_000) {
        sample *= 2
    }
    return BitmapFactory.decodeFile(
        file.absolutePath,
        BitmapFactory.Options().apply { inSampleSize = sample }
    )
}

private fun JSONObject.module(name: String): JSONObject? =
    optJSONObject("modules")?.optJSONObject(name)

private fun JSONObject.bookName(): String =
    optJSONObject("book")?.optString("name")?.takeIf { it.isNotBlank() }
        ?: optString("bookName", "肥喵记账")

private fun JSONObject.monthText(): String {
    val year = optInt("year", 0)
    val month = optInt("month", 0)
    if (year > 0 && month in 1..12) return "${year}年${month}月"
    return optJSONObject("period")?.optString("monthText")?.takeIf { it.isNotBlank() }
        ?: optString("monthText", "本月")
}
private fun JSONObject.dateText(): String =
    optJSONObject("period")?.optString("dateText")?.takeIf { it.isNotBlank() }
        ?: optString("dateText", "今日")

private fun JSONObject?.optStringCompat(name: String, fallback: String): String =
    this?.optString(name, fallback)?.takeIf { it.isNotBlank() } ?: fallback

private fun JSONArray?.metricByLabel(label: String): JSONObject? {
    if (this == null) return null
    for (i in 0 until length()) {
        val item = optJSONObject(i) ?: continue
        if (item.optString("label") == label) return item
    }
    return null
}

private fun categoriesSemantic(items: JSONArray?): String {
    if (items == null || items.length() == 0) return "分类与支出活动，打开 App 后同步最近支出"
    val parts = mutableListOf<String>()
    for (i in 0 until min(items.length(), 3)) {
        val item = items.optJSONObject(i) ?: continue
        parts.add(item.optString("semanticText", item.optString("name", "")))
    }
    return "分类与支出活动，${parts.joinToString("，")}"
}

private fun launchIntent(
    context: Context,
    open: String,
    requestCode: Int,
    categoryId: Int? = null
): PendingIntent {
    val intent = Intent(context, MainActivity::class.java).apply {
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        putExtra("feimiao_open", open)
        if (categoryId != null) putExtra("feimiao_category_id", categoryId)
    }
    val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    return PendingIntent.getActivity(context, requestCode, intent, flags)
}
