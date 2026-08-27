import Foundation

public enum ChatIntentKind: String, Codable, CaseIterable, Hashable, Sendable {
    case record
    case query
    case chat
}

/// 喵助手的本地三态意图判断。只有明确账本语义才会把个人流水拼进
/// 普通会话；知识问答和闲聊不会携带账本上下文。
public enum ChatIntent {
    private static let queryWords = [
        "多少", "排行", "排名", "最大", "最多", "最贵", "最高", "对比", "分析",
        "统计", "占比", "哪类", "哪个", "哪天", "怎么样", "什么", "为什么",
        "如何", "是不是", "合理", "超支", "明细", "花销", "剩", "吗", "?", "？",
    ]
    private static let financeWords = [
        "账", "支出", "收入", "消费", "花销", "花了", "预算", "余额", "结余",
        "金额", "一笔", "分类", "报销", "退款", "工资", "买", "餐饮", "吃饭",
        "打车", "购物", "交通", "本月", "上月", "这个月", "上个月", "今年",
        "去年", "周报", "月报", "年报", "报告",
    ]
    private static let ledgerScopeWords = [
        "本月", "这月", "这个月", "上月", "上个月", "本周", "这周", "上周",
        "今天", "今日", "昨天", "昨日", "最近", "今年", "去年", "账本", "账单",
        "记录", "明细", "排行", "排名", "占比", "超支", "剩余", "还剩", "结余",
        "花得多", "花了多少", "我的支出", "我的收入", "我的消费", "我花", "我赚",
    ]
    private static let queryActions = ["查一下", "查下", "看一下", "看看", "总结", "汇总", "复盘"]
    private static let explicitQueryActions = [
        "查账", "查一下账", "看看账", "生成周报", "生成月报", "生成年报", "账单报告", "消费报告",
    ]
    private static let recordActions = [
        "花了", "花费", "付了", "付款", "买了", "充值", "吃了", "喝了", "收到", "到账",
        "到帐", "入账", "入帐", "收款", "发红包", "发了", "赚", "缴", "交了", "订了",
        "点了", "记一笔", "记一下", "帮我记",
    ]
    private static let recordContext = [
        "早餐", "午饭", "午餐", "晚饭", "晚餐", "夜宵", "吃饭", "餐饮", "外卖", "奶茶",
        "咖啡", "饮料", "打车", "公交", "地铁", "停车", "加油", "房租", "水费", "电费",
        "燃气", "话费", "网费", "快递", "药费", "失业金", "失业保险", "社保", "补贴",
        "津贴", "养老金", "退休金", "红包", "工资", "奖金", "报销", "退款", "支出", "收入",
        "买菜", "菜", "超市", "水果", "零食", "购物",
    ]

    public static func isQuery(_ text: String, hasArabicAmount: Bool = false) -> Bool {
        classify(text, hasArabicAmount: hasArabicAmount) == .query
    }

    public static func classify(
        _ text: String,
        hasArabicAmount: Bool = false
    ) -> ChatIntentKind {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return .chat }
        let hasFinanceContext = financeWords.contains(where: value.contains)
        let hasScope = ledgerScopeWords.contains(where: value.contains) ||
            value.range(of: #"最近\s*\d{1,3}\s*天"#, options: .regularExpression) != nil

        if explicitQueryActions.contains(where: value.contains) ||
            (hasScope && hasFinanceContext && queryActions.contains(where: value.contains)) {
            return .query
        }
        if queryWords.contains(where: value.contains) {
            return hasFinanceContext && hasScope ? .query : .chat
        }

        let hasAmount = hasColloquialAmount(value)
        let hasRecordContext = recordContext.contains(where: value.contains)
        let hasChineseAmount = value.range(
            of: #"[零一二两三四五六七八九十百千万]+$"#,
            options: .regularExpression
        ) != nil
        let hasRecordAction = recordActions.contains(where: value.contains)
        let summaryFinance = financeWords.filter { $0 != "买" }.contains(where: value.contains)
        if hasScope && summaryFinance && !hasAmount && !hasRecordAction &&
            !(hasArabicAmount && hasRecordContext) &&
            !(hasChineseAmount && hasRecordContext) {
            return .query
        }
        if hasAmount ||
            (hasArabicAmount && hasRecordContext) ||
            (hasChineseAmount && hasRecordContext) ||
            (hasArabicAmount && value.contains("买")) ||
            (hasChineseAmount && value.contains("买")) ||
            hasRecordAction {
            return .record
        }
        return .chat
    }

    public static func hasColloquialAmount(_ text: String) -> Bool {
        text.range(
            of: #"(?:[¥￥]\s*\d+(?:\.\d+)?|[零一二两三四五六七八九十百千万0-9]+\s*[块元毛角])"#,
            options: .regularExpression
        ) != nil
    }
}
