import Foundation

/// 高频商户与商品关键词的确定性分类词典。
///
/// 这张表故意只收明确的词：分类应先依赖商品和稳定商户信号，拿不准时
/// 交给导入复核页，而不是把错误的子分类静默写进历史账单。
public enum MerchantCategory {
    private static let rules: [(key: String, words: [String])] = [
        ("dining", ["美团外卖", "饿了么", "外卖", "麦当劳", "肯德基", "kfc", "汉堡王", "海底捞", "必胜客", "食堂", "正餐", "吃", "饭", "餐"]),
        ("dining_breakfast", ["早餐", "早饭", "包子", "豆浆", "油条"]),
        ("dining_lunch", ["午餐", "午饭", "中午饭"]),
        ("dining_dinner", ["晚餐", "晚饭", "夜宵", "宵夜"]),
        ("dining_treat", ["请客", "请吃饭", "聚餐", "饭局", "做东"]),
        ("dining_cook", ["粮油", "调味", "食用油", "大米", "酱油", "挂面"]),
        ("dining_drink", ["瑞幸", "luckin", "星巴克", "starbucks", "喜茶", "奈雪", "蜜雪冰城", "蜜雪", "库迪", "coco", "一点点", "茶百道", "古茗", "沪上阿姨", "霸王茶姬", "奶茶", "咖啡", "拿铁", "美式"]),
        ("groceries", ["买菜", "超市", "菜市场", "菜场", "生鲜", "钱大妈", "盒马", "永辉", "便利店", "叮咚买菜", "每日优鲜"]),
        ("dining_snack", ["零食", "薯片", "辣条", "瓜子", "小吃", "坚果"]),
        ("shop_home", ["抽纸", "纸巾", "卫生纸", "洗衣液", "名创优品", "宜家", "百洁布", "垃圾袋", "收纳"]),
        ("shop_beauty", ["屈臣氏", "丝芙兰", "化妆品", "口红", "面膜", "洗面奶", "沐浴露", "洗发水", "护肤品"]),
        ("shop_digital", ["iphone", "华为", "数码", "电脑", "显示器", "手机"]),
        ("shop_digital_acc", ["耳机", "机械键盘", "鼠标", "充电宝", "数据线", "充电头"]),
        ("subscription", ["爱奇艺", "腾讯视频", "优酷", "网易云", "qq音乐", "百度网盘", "icloud", "steam", "q币", "点卡", "会员", "vip", "app store", "appstore", "apple.com", "itunes", "米哈游", "mihoyo", "原神", "崩坏", "genshin", "腾讯游戏", "天游科技", "网易游戏", "游戏充值", "手游充值"]),
        ("shopping", ["京东", "淘宝", "天猫", "拼多多", "苏宁", "唯品会", "得物", "闲鱼", "1688"]),
        ("shop_clothes", ["优衣库", "uniqlo", "zara", "nike", "adidas", "耐克", "阿迪", "李宁", "安踏", "卫衣", "裤子", "鞋子"]),
        ("pets", ["猫粮", "狗粮", "猫砂", "宠物", "铲屎"]),
        ("shop_baby", ["尿不湿", "纸尿裤", "奶粉", "玩具"]),
        ("trans_taxi", ["滴滴", "高德打车", "t3出行", "曹操出行", "花小猪", "享道", "出租车", "网约车", "打车"]),
        ("trans_public", ["地铁", "公交车", "公交", "巴士", "一卡通", "brt", "公共交通", "metro"]),
        ("trans_park", ["停车费", "停车"]),
        ("trans_fuel", ["加油站", "加油", "中石化", "中石油", "油费"]),
        ("trans_train", ["高铁", "动车", "火车票", "12306", "火车"]),
        ("trans_flight", ["机票", "飞机票", "东航", "南航", "国航", "航空"]),
        ("transport", ["青桔", "哈啰", "共享单车", "单车"]),
        ("travel", ["酒店", "民宿", "airbnb", "客栈", "度假", "景区门票"]),
        ("ent_movie", ["电影票", "电影", "影城", "猫眼", "淘票票", "ktv", "唱歌", "演唱会", "音乐会"]),
        ("ent_sport", ["健身房", "健身", "瑜伽", "游泳"]),
        ("ent_bar", ["酒吧", "清吧"]),
        ("ent_spa", ["足浴", "按摩", "spa", "理疗"]),
        ("ent_game", ["剧本杀", "桌游", "棋牌", "麻将"]),
        ("ent_show", ["演出", "话剧", "展览", "livehouse"]),
        ("house_phone", ["话费", "流量", "宽带", "网费", "充话费", "手机充值", "话费充值", "中国移动", "中国联通", "中国电信"]),
        ("utilities", ["电费", "国家电网"]),
        ("house_water", ["水费"]),
        ("house_gas", ["燃气费", "燃气", "天然气", "煤气"]),
        ("house_property", ["物业费", "物业"]),
        ("house_rent", ["房租", "租金"]),
        ("house_park", ["车位"]),
        ("house_loan", ["房贷", "按揭", "月供", "住房贷款"]),
        ("house_clean", ["家政", "保洁", "钟点工"]),
        ("med_drug", ["大药房", "药店", "买药", "药品"]),
        ("med_clinic", ["挂号", "门诊", "看病", "医院"]),
        ("med_checkup", ["体检"]),
        ("med_dental", ["牙科", "洗牙", "补牙", "拔牙", "种植牙", "口腔"]),
        ("med_hospital", ["住院", "手术费"]),
        ("med_eye", ["配镜", "眼镜", "近视", "眼科"]),
        ("edu_book", ["当当", "买书", "书店", "图书"]),
        ("edu_course", ["网课", "培训", "报班", "课程", "课"]),
        ("edu_tuition", ["学费", "报名费", "学杂费"]),
        ("edu_print", ["打印", "复印", "文具"]),
        ("gift_red", ["随礼", "份子钱", "礼金", "发红包", "红包"]),
        ("gift_present", ["送礼", "礼物"]),
        ("other_charity", ["捐款", "慈善", "公益"]),
        ("car_toll", ["过路费", "过桥费", "高速费", "etc通行", "高速通行"]),
        ("car_wash", ["洗车"]),
        ("car_tax", ["车船税", "车辆年检", "车辆年审", "年检"]),
        ("ins_car", ["车险", "交强险", "商业车险", "车辆保险"]),
        ("ins_medical", ["医保", "城乡居民医保", "居民医保", "医疗险", "百万医疗", "医疗保险"]),
        ("ins_critical", ["重疾险", "重大疾病"]),
        ("ins_accident", ["意外险"]),
        ("ins_life", ["寿险", "定期寿险"]),
        ("insurance", ["保险", "保费", "众安保险", "平安保险", "人寿保险"]),
        ("other_fine", ["罚款", "违章", "赔偿", "法院", "诉讼", "罚金"]),
        ("other", ["顺丰", "快递", "运费", "圆通", "中通", "韵达", "申通", "极兔", "ems"]),
        ("salary", ["发工资", "工资", "薪水", "月薪", "发薪"]),
        ("inc_salary_allow", ["餐补", "交通补", "住房补", "通讯补"]),
        ("bonus", ["年终奖", "奖金", "提成"]),
        ("investment", ["利息", "分红", "基金收益", "理财收益", "股息"]),
        ("pension", ["养老金", "退休金"]),
        ("inc_subsidy", ["失业金", "失业保险", "社保", "政府补助", "补助", "补贴", "津贴"]),
        ("redPacket", ["抢红包", "收红包", "红包"]),
        ("refund", ["退款", "退货"]),
        ("otherIncome", ["到账", "到帐", "入账", "入帐", "收款"])
    ]

    /// 在文本中取最长明确触发词对应的分类 key，并按收支方向过滤。
    public static func classify(_ text: String, kind: TransactionKind) -> String? {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        var bestKey: String?
        var bestLength = 0
        for rule in rules {
            guard let seed = CategorySeed.byKey(rule.key), seed.kind == kind else { continue }
            for word in rule.words {
                let candidate = word.lowercased()
                guard candidate.count > bestLength, normalized.contains(candidate) else { continue }
                bestKey = rule.key
                bestLength = candidate.count
            }
        }
        return bestKey
    }
}
