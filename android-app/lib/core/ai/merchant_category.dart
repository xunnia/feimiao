import '../models/category_seed.dart';
import '../models/transaction_kind.dart';

/// 商户 / 关键词 → 分类 的「确定性词典」。
///
/// 对高频、明确的商户和关键词（瑞幸→饮料、滴滴→打车、地铁→公共交通…），
/// 用这张人工维护的表直接定类，**比大模型猜更稳、且省 token**。
/// 命中即用，优先级介于「用户纠正记忆」与「大模型猜测」之间：
///   用户记忆 > 本词典 > 大模型 categoryKey > 兜底。
///
/// 规则：
/// - key 必须是 [CategorySeed] 里真实存在的分类 key（否则匹配不到会回落）。
/// - 触发词按「最长匹配」生效，避免"车"先于"打车"误命中。
/// - 按 kind 过滤：同一个词在收/支下落到不同分类（如"红包"）。
/// - 只收**明确**的词，宁缺毋滥；模糊的（如"苹果"可能是水果或手机）不进表。
class MerchantCategory {
  MerchantCategory._();

  /// 分类 key → 触发词列表。英文触发词用小写（匹配时整体转小写）。
  static const Map<String, List<String>> triggers = {
    // ── 食品餐饮 ──
    'dining': ['美团外卖', '饿了么', '外卖', '麦当劳', '肯德基', 'kfc', '汉堡王', '海底捞', '必胜客', '食堂', '正餐'],
    'dining_drink': [
      '瑞幸', 'luckin', '星巴克', 'starbucks', '喜茶', '奈雪', '蜜雪冰城', '蜜雪',
      '库迪', 'coco', '一点点', '茶百道', '古茗', '沪上阿姨', '霸王茶姬', '奶茶', '咖啡', '拿铁', '美式'
    ],
    'groceries': ['买菜', '菜市场', '菜场', '生鲜', '盒马', '叮咚买菜', '每日优鲜'],
    'dining_snack': ['零食', '薯片', '辣条'],
    // ── 购物消费 ──
    'shop_home': ['抽纸', '纸巾', '卫生纸', '洗衣液', '名创优品', '宜家', '百洁布', '垃圾袋', '收纳'],
    'shop_beauty': ['屈臣氏', '丝芙兰', '化妆品', '口红', '面膜', '洗面奶', '沐浴露', '洗发水', '护肤品'],
    'shop_digital': ['iphone', 'apple', '华为', '数码', '耳机', '显示器', '机械键盘', '鼠标', '充电宝'],
    'subscription': [
      '爱奇艺', '腾讯视频', '优酷', '网易云', 'qq音乐', '百度网盘', 'icloud',
      'steam', 'q币', '点卡', '会员', 'vip',
      // 苹果数字服务（账单里几乎都是 App Store/iCloud 订阅，不是买硬件）
      'app store', 'appstore', 'apple.com', 'itunes',
      // 游戏充值：米哈游/原神、腾讯/网易游戏
      '米哈游', 'mihoyo', '原神', '崩坏', 'genshin', '腾讯游戏', '天游科技',
      '网易游戏', '游戏充值', '手游充值',
    ],
    // 电商平台（笼统购物，细分不到子类就归大类购物消费）
    'shopping': ['京东', '淘宝', '天猫', '拼多多', '苏宁', '唯品会', '得物', '闲鱼', '1688'],
    'shop_clothes': ['优衣库', 'uniqlo', 'zara', 'nike', 'adidas', '耐克', '阿迪', '李宁', '安踏', '卫衣', '裤子', '鞋子'],
    'pets': ['猫粮', '狗粮', '猫砂', '宠物', '铲屎'],
    'shop_baby': ['尿不湿', '纸尿裤', '奶粉', '玩具'],
    // ── 出行交通 ──
    'trans_taxi': ['滴滴', '高德打车', 't3出行', '曹操出行', '花小猪', '享道', '出租车', '网约车', '打车'],
    'trans_public': ['地铁', '公交车', '公交', '一卡通', 'brt', '公共交通'],
    'trans_park': ['停车费', '停车'],
    'trans_fuel': ['加油站', '加油', '中石化', '中石油', '油费'],
    'trans_train': ['高铁', '动车', '火车票', '12306', '火车'],
    'trans_flight': ['机票', '飞机票', '东航', '南航', '国航', '航空'],
    // ── 休闲娱乐 ──
    'travel': ['酒店', '民宿', 'airbnb', '客栈', '度假', '景区门票'],
    'ent_movie': ['电影票', '电影', '猫眼', '淘票票', 'ktv', '唱歌'],
    'ent_sport': ['健身房', '健身', '瑜伽', '游泳'],
    'ent_bar': ['酒吧', '清吧'],
    // ── 居家生活 ──
    'house_phone': ['话费', '流量', '宽带', '充话费', '手机充值', '话费充值', '中国移动', '中国联通', '中国电信'],
    'utilities': ['电费', '国家电网'],
    'house_water': ['水费'],
    'house_gas': ['燃气费', '燃气', '天然气', '煤气'],
    'house_property': ['物业费', '物业'],
    'house_rent': ['房租', '房贷', '租金'],
    'house_clean': ['家政', '保洁', '钟点工'],
    // ── 医疗健康 ──
    'med_drug': ['大药房', '药店', '买药', '药品'],
    'med_clinic': ['挂号', '门诊', '看病', '医院'],
    'med_checkup': ['体检'],
    // ── 教育学习 ──
    'edu_book': ['当当', '买书', '书店', '图书'],
    'edu_course': ['网课', '培训', '学费', '报班', '课程'],
    'edu_print': ['打印', '复印', '文具'],
    // ── 人情往来 ──
    'gift_red': ['随礼', '份子钱', '礼金', '发红包', '红包'],
    'gift_present': ['送礼', '礼物'],
    // ── 其他 ──
    'other_fine': ['罚款', '违章', '赔偿', '法院', '诉讼', '罚金'],
    // 快递运费（个人寄件/运费，归其他）
    'other': ['顺丰', '快递', '运费', '圆通', '中通', '韵达', '申通', '极兔', 'ems'],
    // ── 收入 ──
    'salary': ['发工资', '工资', '薪水', '月薪', '发薪'],
    'bonus': ['年终奖', '奖金', '提成'],
    'investment': ['利息', '分红', '基金收益', '理财收益', '股息'],
    'redPacket': ['抢红包', '收红包', '红包'],
    'refund': ['退款', '退货'],
  };

  /// 在 [text] 里找命中的分类 key（限定 [kind]，取最长触发词），无则 null。
  static String? classify(String text, TransactionKind kind) {
    final t = text.toLowerCase().trim();
    if (t.isEmpty) return null;
    String? bestKey;
    int bestLen = 0;
    triggers.forEach((key, words) {
      final seed = CategorySeed.byKey(key);
      if (seed == null || seed.kind != kind) return;
      for (final w in words) {
        if (w.length > bestLen && t.contains(w)) {
          bestLen = w.length;
          bestKey = key;
        }
      }
    });
    return bestKey;
  }
}
