/// 喵助手意图判断：一句话是「记账(record)」「查账(query)」还是「闲聊(chat)」。
///
/// 纯逻辑、无外部依赖，便于单测。只有高置信的记账或查账表达才拦截，
/// 其余内容交给当前喵助手模型，避免把普通句子里的数字误认成金额。
/// 历史 bug：曾把"花了"当成查账词，导致"坐公交花了一块"被误判成查账。
enum ChatIntentKind { record, query, chat }

class ChatIntent {
  ChatIntent._();

  /// 明确的问句信号（在问数据、要分析）。命中即查账，优先级最高。
  static const queryWords = [
    '多少',
    '排行',
    '排名',
    '最大',
    '最多',
    '最贵',
    '最高',
    '对比',
    '分析',
    '统计',
    '占比',
    '哪类',
    '哪个',
    '哪天',
    '怎么样',
    '什么',
    '为什么',
    '如何',
    '是不是',
    '合理',
    '超支',
    '明细',
    '花销',
    '剩',
    '吗',
    '?',
    '？'
  ];

  /// 只有问句同时涉及账本/收支语义时才算查账。普通知识问答和闲聊即使
  /// 带“多少/怎么样/？”也应交给聊天模型，不能附带账本上下文。
  static const financeQueryWords = [
    '账',
    '支出',
    '收入',
    '消费',
    '花销',
    '花了',
    '预算',
    '余额',
    '结余',
    '金额',
    '一笔',
    '分类',
    '报销',
    '退款',
    '工资',
    '买',
    '餐饮',
    '吃饭',
    '打车',
    '购物',
    '交通',
    '本月',
    '上月',
    '这个月',
    '上个月',
    '今年',
    '去年',
    '周报',
    '月报',
    '年报',
    '报告',
  ];

  static const explicitQueryActions = [
    '查账',
    '查一下账',
    '看看账',
    '生成周报',
    '生成月报',
    '生成年报',
    '账单报告',
    '消费报告',
  ];

  /// 这些动作只有和账本语义同时出现时才算查账，避免“总结这篇文章”误判。
  static const queryActionWords = [
    '查一下',
    '查下',
    '看一下',
    '看看',
    '总结',
    '汇总',
    '复盘',
  ];

  /// 明确指向用户账本或统计周期的范围词。通用财经知识问题不满足这里，
  /// 因此不会附带用户的账本上下文。
  static const ledgerScopeWords = [
    '本月',
    '这月',
    '这个月',
    '上月',
    '上个月',
    '本周',
    '这周',
    '上周',
    '今年',
    '去年',
    '账本',
    '账单',
    '记录',
    '明细',
    '排行',
    '排名',
    '占比',
    '超支',
    '剩余',
    '还剩',
    '结余',
    '花得多',
    '花了多少',
    '我的支出',
    '我的收入',
    '我的消费',
    '我花',
    '我赚',
  ];

  /// 消费/收入动作词。出现即更可能是记账。
  static const recordActionWords = [
    '花了',
    '花费',
    '付了',
    '付款',
    '买了',
    '买',
    '充值',
    '吃了',
    '喝了',
    '收到',
    '发红包',
    '发了',
    '赚',
    '缴',
    '交了',
    '订了',
    '点了',
    '记一笔',
    '记一下',
    '帮我记',
  ];

  /// 裸数字只有和明确消费/收入对象同时出现，才可视为金额。
  /// 例如”午饭 28”是记账，”推荐 3 部电影””写 500 字”仍是闲聊。
  static const recordContextWords = [
    '早餐',
    '午饭',
    '午餐',
    '晚饭',
    '晚餐',
    '夜宵',
    '吃饭',
    '餐饮',
    '外卖',
    '奶茶',
    '咖啡',
    '饮料',
    '打车',
    '公交',
    '地铁',
    '停车',
    '加油',
    '房租',
    '水费',
    '电费',
    '燃气',
    '话费',
    '网费',
    '快递',
    '药费',
    '红包',
    '工资',
    '奖金',
    '报销',
    '退款',
    '支出',
    '收入',
    '买菜',
    '菜',
    '超市',
    '水果',
    '零食',
    '购物',
  ];

  /// 返回 true=查账(query)，false=记账(record)。
  ///
  /// [hasArabicAmount] 由调用方传入（复用既有金额解析器对阿拉伯数字的识别），
  /// 让本模块保持纯净、不绑定具体解析器。
  static bool isQuery(String text, {bool hasArabicAmount = false}) =>
      classify(text, hasArabicAmount: hasArabicAmount) == ChatIntentKind.query;

  /// 本地三态兜底。只有明确金额或收支动作才进入记账，其余普通
  /// 自然语言按闲聊处理，避免在 AI 不可用时把“你好”误写成账单。
  static ChatIntentKind classify(
    String text, {
    bool hasArabicAmount = false,
  }) {
    final t = text.trim();
    if (t.isEmpty) return ChatIntentKind.chat;

    // 1) 明确查账动作，或「问句信号 + 财务语义」→ 查账。
    final hasFinanceContext = financeQueryWords.any(t.contains);
    final hasLedgerScope = ledgerScopeWords.any(t.contains);
    if (explicitQueryActions.any(t.contains) ||
        (hasLedgerScope &&
            hasFinanceContext &&
            queryActionWords.any(t.contains))) {
      return ChatIntentKind.query;
    }
    final hasQuestionSignal = queryWords.any(t.contains);
    if (hasQuestionSignal) {
      return hasFinanceContext && hasLedgerScope
          ? ChatIntentKind.query
          : ChatIntentKind.chat;
    }

    // 2) 带货币单位的金额，或「裸数字 + 明确收支语境」，才算记账。
    final hasExplicitAmount = hasColloquialAmount(t);
    final hasRecordContext = recordContextWords.any(t.contains);
    final hasTrailingChineseAmount = RegExp(r'[零一二两三四五六七八九十百千万]+$').hasMatch(t);
    if (hasExplicitAmount ||
        (hasArabicAmount && hasRecordContext) ||
        (hasTrailingChineseAmount && hasRecordContext) ||
        recordActionWords.any(t.contains)) {
      return ChatIntentKind.record;
    }

    // 3) 其余自然语言交给当前聊天模型。
    return ChatIntentKind.chat;
  }

  /// 口语金额：中文数字/阿拉伯数字 + 块/元/毛/角（"一块""两块五""十块""三十元"）。
  static bool hasColloquialAmount(String t) =>
      RegExp(r'(?:[¥￥]\s*\d+(?:\.\d+)?|[零一二两三四五六七八九十百千万0-9]+\s*[块元毛角])')
          .hasMatch(t);
}
