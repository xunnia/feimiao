import Foundation

/// 安卓与 iOS 共用的两级分类树。
///
/// key 永远稳定，历史交易只保存 key；名称、emoji 和父级可以随产品演进，
/// 但不应改变已有 key 的含义。
public struct CategorySeed: Equatable, Sendable {
    public let key: String
    public let nameZh: String
    public let nameEn: String
    public let emoji: String
    public let kind: TransactionKind
    public let parentKey: String?
    public let symbol: String

    public var isTopLevel: Bool { parentKey == nil }

    public init(
        key: String,
        nameZh: String,
        nameEn: String,
        emoji: String,
        kind: TransactionKind,
        parentKey: String? = nil,
        symbol: String = "tag"
    ) {
        self.key = key
        self.nameZh = nameZh
        self.nameEn = nameEn
        self.emoji = emoji
        self.kind = kind
        self.parentKey = parentKey
        self.symbol = symbol
    }

    public func localizedName(languageCode: String) -> String {
        languageCode.lowercased().hasPrefix("zh") ? nameZh : nameEn
    }

    public static let fallbackExpenseKey = "other"

    public static let expenses: [CategorySeed] = [
        // 食品餐饮
        .init(key: "dining", nameZh: "食品餐饮", nameEn: "Food", emoji: "🍜", kind: .expense, symbol: "fork.knife"),
        .init(key: "dining_breakfast", nameZh: "早餐", nameEn: "Breakfast", emoji: "🍳", kind: .expense, parentKey: "dining"),
        .init(key: "dining_lunch", nameZh: "午餐", nameEn: "Lunch", emoji: "🍱", kind: .expense, parentKey: "dining"),
        .init(key: "dining_dinner", nameZh: "晚餐", nameEn: "Dinner", emoji: "🍚", kind: .expense, parentKey: "dining"),
        .init(key: "dining_drink", nameZh: "饮料酒水", nameEn: "Drinks", emoji: "🧋", kind: .expense, parentKey: "dining"),
        .init(key: "dining_snack", nameZh: "休闲零食", nameEn: "Snacks", emoji: "🍿", kind: .expense, parentKey: "dining"),
        .init(key: "groceries", nameZh: "生鲜食品", nameEn: "Groceries", emoji: "🥬", kind: .expense, parentKey: "dining"),
        .init(key: "dining_treat", nameZh: "请客吃饭", nameEn: "Treat", emoji: "🍻", kind: .expense, parentKey: "dining"),
        .init(key: "dining_cook", nameZh: "粮油调味", nameEn: "Cooking", emoji: "🧂", kind: .expense, parentKey: "dining"),
        .init(key: "dining_tobacco", nameZh: "烟草", nameEn: "Tobacco", emoji: "🚬", kind: .expense, parentKey: "dining"),

        // 购物消费
        .init(key: "shopping", nameZh: "购物消费", nameEn: "Shopping", emoji: "🛍️", kind: .expense, symbol: "bag"),
        .init(key: "shop_home", nameZh: "日常家居", nameEn: "Home", emoji: "🛋️", kind: .expense, parentKey: "shopping"),
        .init(key: "shop_beauty", nameZh: "个护美妆", nameEn: "Beauty", emoji: "💄", kind: .expense, parentKey: "shopping"),
        .init(key: "shop_digital", nameZh: "手机数码", nameEn: "Digital", emoji: "📱", kind: .expense, parentKey: "shopping"),
        .init(key: "shop_digital_acc", nameZh: "数码配件", nameEn: "Accessories", emoji: "🎧", kind: .expense, parentKey: "shopping"),
        .init(key: "subscription", nameZh: "虚拟充值", nameEn: "Top-up", emoji: "🎟️", kind: .expense, parentKey: "shopping"),
        .init(key: "shop_appliance", nameZh: "生活电器", nameEn: "Appliances", emoji: "📺", kind: .expense, parentKey: "shopping"),
        .init(key: "shop_watch", nameZh: "配饰腕表", nameEn: "Accessories", emoji: "⌚", kind: .expense, parentKey: "shopping"),
        .init(key: "shop_jewelry", nameZh: "珠宝首饰", nameEn: "Jewelry", emoji: "💍", kind: .expense, parentKey: "shopping"),
        .init(key: "shop_baby", nameZh: "母婴玩具", nameEn: "Baby", emoji: "🧸", kind: .expense, parentKey: "shopping"),
        .init(key: "shop_clothes", nameZh: "服饰运动", nameEn: "Clothing", emoji: "👟", kind: .expense, parentKey: "shopping"),
        .init(key: "pets", nameZh: "宠物用品", nameEn: "Pets", emoji: "🐾", kind: .expense, parentKey: "shopping"),
        .init(key: "shop_office", nameZh: "办公用品", nameEn: "Office", emoji: "📎", kind: .expense, parentKey: "shopping"),

        // 出行交通
        .init(key: "transport", nameZh: "出行交通", nameEn: "Transport", emoji: "🚌", kind: .expense, symbol: "bus"),
        .init(key: "trans_taxi", nameZh: "打车", nameEn: "Taxi", emoji: "🚕", kind: .expense, parentKey: "transport"),
        .init(key: "trans_public", nameZh: "公共交通", nameEn: "Transit", emoji: "🚌", kind: .expense, parentKey: "transport"),
        .init(key: "trans_bike", nameZh: "共享单车", nameEn: "Bike", emoji: "🚲", kind: .expense, parentKey: "transport"),
        .init(key: "trans_train", nameZh: "火车", nameEn: "Train", emoji: "🚄", kind: .expense, parentKey: "transport"),
        .init(key: "trans_flight", nameZh: "飞机", nameEn: "Flight", emoji: "✈️", kind: .expense, parentKey: "transport"),

        // 车辆支出
        .init(key: "car", nameZh: "车辆支出", nameEn: "Car", emoji: "🚗", kind: .expense, symbol: "car"),
        .init(key: "trans_fuel", nameZh: "加油", nameEn: "Fuel", emoji: "⛽", kind: .expense, parentKey: "car"),
        .init(key: "trans_park", nameZh: "停车费", nameEn: "Parking", emoji: "🅿️", kind: .expense, parentKey: "car"),
        .init(key: "house_park", nameZh: "车位费", nameEn: "Parking Lot", emoji: "🚙", kind: .expense, parentKey: "car"),
        .init(key: "trans_repair", nameZh: "保养修车", nameEn: "Car Service", emoji: "🔧", kind: .expense, parentKey: "car"),
        .init(key: "car_toll", nameZh: "过路过桥", nameEn: "Toll", emoji: "🛣️", kind: .expense, parentKey: "car"),
        .init(key: "car_wash", nameZh: "洗车", nameEn: "Car Wash", emoji: "🧼", kind: .expense, parentKey: "car"),
        .init(key: "car_tax", nameZh: "车船税年检", nameEn: "Car Tax", emoji: "📋", kind: .expense, parentKey: "car"),

        // 休闲娱乐
        .init(key: "entertainment", nameZh: "休闲娱乐", nameEn: "Leisure", emoji: "🎮", kind: .expense, symbol: "gamecontroller"),
        .init(key: "travel", nameZh: "旅游度假", nameEn: "Travel", emoji: "🧳", kind: .expense, parentKey: "entertainment"),
        .init(key: "ent_movie", nameZh: "电影唱歌", nameEn: "Movie/KTV", emoji: "🎤", kind: .expense, parentKey: "entertainment"),
        .init(key: "ent_sport", nameZh: "运动健身", nameEn: "Sports", emoji: "🏋️", kind: .expense, parentKey: "entertainment"),
        .init(key: "ent_spa", nameZh: "足浴按摩", nameEn: "Spa", emoji: "💆", kind: .expense, parentKey: "entertainment"),
        .init(key: "ent_game", nameZh: "棋牌桌游", nameEn: "Games", emoji: "🀄", kind: .expense, parentKey: "entertainment"),
        .init(key: "ent_bar", nameZh: "酒吧", nameEn: "Bar", emoji: "🍸", kind: .expense, parentKey: "entertainment"),
        .init(key: "ent_show", nameZh: "演出", nameEn: "Show", emoji: "🎭", kind: .expense, parentKey: "entertainment"),
        .init(key: "ent_photo", nameZh: "摄影写真", nameEn: "Photo", emoji: "📸", kind: .expense, parentKey: "entertainment"),

        // 居家住房
        .init(key: "housing", nameZh: "居家住房", nameEn: "Living", emoji: "🏠", kind: .expense, symbol: "house"),
        .init(key: "house_phone", nameZh: "话费宽带", nameEn: "Phone/Net", emoji: "📶", kind: .expense, parentKey: "housing"),
        .init(key: "utilities", nameZh: "电费", nameEn: "Electricity", emoji: "💡", kind: .expense, parentKey: "housing"),
        .init(key: "house_water", nameZh: "水费", nameEn: "Water", emoji: "🚰", kind: .expense, parentKey: "housing"),
        .init(key: "house_gas", nameZh: "燃气费", nameEn: "Gas", emoji: "🔥", kind: .expense, parentKey: "housing"),
        .init(key: "house_property", nameZh: "物业费", nameEn: "Property", emoji: "🏢", kind: .expense, parentKey: "housing"),
        .init(key: "house_rent", nameZh: "房租", nameEn: "Rent", emoji: "🏘️", kind: .expense, parentKey: "housing"),
        .init(key: "house_loan", nameZh: "房贷利息", nameEn: "Mortgage", emoji: "🏦", kind: .expense, parentKey: "housing"),
        .init(key: "house_clean", nameZh: "家政清洁", nameEn: "Cleaning", emoji: "🧹", kind: .expense, parentKey: "housing"),
        .init(key: "shop_deco", nameZh: "装修维修", nameEn: "Decor", emoji: "🧰", kind: .expense, parentKey: "housing"),

        // 医疗健康
        .init(key: "medical", nameZh: "医疗健康", nameEn: "Medical", emoji: "💊", kind: .expense, symbol: "cross.case"),
        .init(key: "med_drug", nameZh: "药品", nameEn: "Medicine", emoji: "💊", kind: .expense, parentKey: "medical"),
        .init(key: "med_clinic", nameZh: "门诊挂号", nameEn: "Clinic", emoji: "🩺", kind: .expense, parentKey: "medical"),
        .init(key: "med_hospital", nameZh: "住院手术", nameEn: "Hospital", emoji: "🏥", kind: .expense, parentKey: "medical"),
        .init(key: "med_dental", nameZh: "牙科", nameEn: "Dental", emoji: "🦷", kind: .expense, parentKey: "medical"),
        .init(key: "med_eye", nameZh: "眼科配镜", nameEn: "Optical", emoji: "👓", kind: .expense, parentKey: "medical"),
        .init(key: "med_mental", nameZh: "心理咨询", nameEn: "Mental", emoji: "🧠", kind: .expense, parentKey: "medical"),
        .init(key: "med_beauty", nameZh: "医美", nameEn: "Aesthetic", emoji: "💉", kind: .expense, parentKey: "medical"),
        .init(key: "med_health", nameZh: "保健品", nameEn: "Supplement", emoji: "🌿", kind: .expense, parentKey: "medical"),
        .init(key: "med_checkup", nameZh: "体检", nameEn: "Checkup", emoji: "📋", kind: .expense, parentKey: "medical"),

        // 教育学习
        .init(key: "education", nameZh: "教育学习", nameEn: "Education", emoji: "📚", kind: .expense, symbol: "book"),
        .init(key: "edu_book", nameZh: "书籍", nameEn: "Books", emoji: "📖", kind: .expense, parentKey: "education"),
        .init(key: "edu_course", nameZh: "课程", nameEn: "Course", emoji: "🎓", kind: .expense, parentKey: "education"),
        .init(key: "edu_tuition", nameZh: "学费", nameEn: "Tuition", emoji: "🏫", kind: .expense, parentKey: "education"),
        .init(key: "edu_exam", nameZh: "考试考证", nameEn: "Exam", emoji: "📝", kind: .expense, parentKey: "education"),
        .init(key: "edu_print", nameZh: "文具打印", nameEn: "Stationery", emoji: "🖨️", kind: .expense, parentKey: "education"),

        // 保险保障
        .init(key: "insurance", nameZh: "保险保障", nameEn: "Insurance", emoji: "🛡️", kind: .expense, symbol: "shield"),
        .init(key: "ins_car", nameZh: "车险", nameEn: "Car Ins", emoji: "🚗", kind: .expense, parentKey: "insurance"),
        .init(key: "ins_medical", nameZh: "医疗险", nameEn: "Medical Ins", emoji: "⚕️", kind: .expense, parentKey: "insurance"),
        .init(key: "ins_critical", nameZh: "重疾险", nameEn: "Critical Ins", emoji: "🎗️", kind: .expense, parentKey: "insurance"),
        .init(key: "ins_accident", nameZh: "意外险", nameEn: "Accident Ins", emoji: "🚑", kind: .expense, parentKey: "insurance"),
        .init(key: "ins_life", nameZh: "寿险", nameEn: "Life Ins", emoji: "🕊️", kind: .expense, parentKey: "insurance"),
        .init(key: "ins_property", nameZh: "财产险", nameEn: "Property Ins", emoji: "🏠", kind: .expense, parentKey: "insurance"),
        .init(key: "ins_other", nameZh: "其他保险", nameEn: "Other Ins", emoji: "📑", kind: .expense, parentKey: "insurance"),

        // 人情家庭
        .init(key: "gifts", nameZh: "人情家庭", nameEn: "Gifts", emoji: "🎁", kind: .expense, symbol: "gift"),
        .init(key: "gift_red", nameZh: "随礼红包", nameEn: "Gift Money", emoji: "🧧", kind: .expense, parentKey: "gifts"),
        .init(key: "gift_present", nameZh: "礼物", nameEn: "Present", emoji: "🎀", kind: .expense, parentKey: "gifts"),
        .init(key: "gift_parents", nameZh: "孝敬父母", nameEn: "Parents", emoji: "👵", kind: .expense, parentKey: "gifts"),

        // 其他
        .init(key: "other", nameZh: "其他", nameEn: "Other", emoji: "📦", kind: .expense, symbol: "ellipsis.circle"),
        .init(key: "other_fine", nameZh: "罚款赔偿", nameEn: "Fine", emoji: "⚖️", kind: .expense, parentKey: "other"),
        .init(key: "other_fee", nameZh: "手续费", nameEn: "Fee", emoji: "🧾", kind: .expense, parentKey: "other"),
        .init(key: "other_tax", nameZh: "税费", nameEn: "Tax", emoji: "🏛️", kind: .expense, parentKey: "other"),
        .init(key: "other_invest", nameZh: "投资费用", nameEn: "Invest Fee", emoji: "📉", kind: .expense, parentKey: "other"),
        .init(key: "other_loss", nameZh: "意外损失", nameEn: "Loss", emoji: "💥", kind: .expense, parentKey: "other"),
        .init(key: "other_charity", nameZh: "慈善捐助", nameEn: "Charity", emoji: "❤️", kind: .expense, parentKey: "other"),
    ]

    public static let incomes: [CategorySeed] = [
        .init(key: "salary", nameZh: "工资薪酬", nameEn: "Salary", emoji: "💰", kind: .income, symbol: "banknote"),
        .init(key: "inc_salary_base", nameZh: "基本工资", nameEn: "Base Pay", emoji: "💵", kind: .income, parentKey: "salary"),
        .init(key: "inc_salary_ot", nameZh: "加班费", nameEn: "Overtime", emoji: "⏰", kind: .income, parentKey: "salary"),
        .init(key: "inc_salary_allow", nameZh: "补贴", nameEn: "Allowance", emoji: "🎫", kind: .income, parentKey: "salary"),
        .init(key: "inc_salary_commission", nameZh: "提成绩效", nameEn: "Commission", emoji: "📊", kind: .income, parentKey: "salary"),
        .init(key: "bonus", nameZh: "奖金奖励", nameEn: "Bonus", emoji: "🏆", kind: .income, symbol: "star"),
        .init(key: "inc_bonus_year", nameZh: "年终奖", nameEn: "Year Bonus", emoji: "🧧", kind: .income, parentKey: "bonus"),
        .init(key: "inc_bonus_project", nameZh: "项目奖金", nameEn: "Project Bonus", emoji: "🏅", kind: .income, parentKey: "bonus"),
        .init(key: "inc_bonus_full", nameZh: "全勤奖", nameEn: "Attendance", emoji: "✅", kind: .income, parentKey: "bonus"),
        .init(key: "sideline", nameZh: "副业收入", nameEn: "Sideline", emoji: "💼", kind: .income),
        .init(key: "inc_parttime", nameZh: "兼职", nameEn: "Part-time", emoji: "🧑‍💻", kind: .income, parentKey: "sideline"),
        .init(key: "inc_freelance", nameZh: "自由职业", nameEn: "Freelance", emoji: "🎨", kind: .income, parentKey: "sideline"),
        .init(key: "inc_media", nameZh: "自媒体", nameEn: "Media", emoji: "📹", kind: .income, parentKey: "sideline"),
        .init(key: "investment", nameZh: "投资理财", nameEn: "Investment", emoji: "📈", kind: .income, symbol: "chart.line.uptrend.xyaxis"),
        .init(key: "inc_interest", nameZh: "利息", nameEn: "Interest", emoji: "🏦", kind: .income, parentKey: "investment"),
        .init(key: "inc_dividend", nameZh: "分红", nameEn: "Dividend", emoji: "💹", kind: .income, parentKey: "investment"),
        .init(key: "inc_gain", nameZh: "投资收益", nameEn: "Gain", emoji: "📊", kind: .income, parentKey: "investment"),
        .init(key: "inc_rent", nameZh: "租金收入", nameEn: "Rent Income", emoji: "🏘️", kind: .income, parentKey: "investment"),
        .init(key: "pension", nameZh: "养老金", nameEn: "Pension", emoji: "👴", kind: .income),
        .init(key: "familySupport", nameZh: "家庭支持", nameEn: "Family", emoji: "👪", kind: .income),
        .init(key: "redPacket", nameZh: "礼金红包", nameEn: "Red Packet", emoji: "🧧", kind: .income, symbol: "envelope"),
        .init(key: "inc_rp_wx", nameZh: "微信红包", nameEn: "WeChat RP", emoji: "💚", kind: .income, parentKey: "redPacket"),
        .init(key: "inc_rp_ali", nameZh: "支付宝红包", nameEn: "Alipay RP", emoji: "💙", kind: .income, parentKey: "redPacket"),
        .init(key: "inc_rp_gift", nameZh: "人情红包", nameEn: "Gift RP", emoji: "🧧", kind: .income, parentKey: "redPacket"),
        .init(key: "business", nameZh: "经营收入", nameEn: "Business", emoji: "🏪", kind: .income),
        .init(key: "refund", nameZh: "退款报销", nameEn: "Refund", emoji: "↩️", kind: .income, symbol: "arrow.uturn.backward"),
        .init(key: "otherIncome", nameZh: "其他收入", nameEn: "Other", emoji: "💵", kind: .income, symbol: "plus.circle"),
        .init(key: "inc_prize", nameZh: "中奖收入", nameEn: "Prize", emoji: "🎰", kind: .income, parentKey: "otherIncome"),
        .init(key: "inc_subsidy", nameZh: "政府补助", nameEn: "Subsidy", emoji: "🏛️", kind: .income, parentKey: "otherIncome"),
    ]

    public static var all: [CategorySeed] { expenses + incomes }

    public static func byKey(_ key: String) -> CategorySeed? {
        all.first { $0.key == key }
    }

    public static func emojiOf(_ key: String?) -> String {
        guard let key else { return "🏷️" }
        return byKey(key)?.emoji ?? "🏷️"
    }
}
