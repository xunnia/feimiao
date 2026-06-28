/// 喵助手意图判断：一句话是「记账(record)」还是「查账(query)」。
///
/// 纯逻辑、无外部依赖，便于单测。核心原则：**记账优先**。
/// 只要像在描述一笔花销/收入（有金额，含"一块/两块五"这类口语，或含
/// "花了/吃/打车/收到"等动作词），且不是明显问句，就当记账。
/// 历史 bug：曾把"花了"当成查账词，导致"坐公交花了一块"被误判成查账。
class ChatIntent {
  ChatIntent._();

  /// 明确的问句信号（在问数据、要分析）。命中即查账，优先级最高。
  static const queryWords = [
    '多少', '排行', '排名', '最大', '最多', '最贵', '最高', '对比', '分析',
    '统计', '占比', '哪类', '哪个', '哪天', '怎么样', '是不是', '合理',
    '超支', '明细', '花销', '剩', '吗', '?', '？'
  ];

  /// 消费/收入动作词。出现即更可能是记账。
  static const actionWords = [
    '花了', '花费', '付', '买', '充值', '打车', '吃', '喝', '收到', '工资',
    '报销', '红包', '发了', '赚', '缴', '交了', '订了', '点了'
  ];

  /// 返回 true=查账(query)，false=记账(record)。
  ///
  /// [hasArabicAmount] 由调用方传入（复用既有金额解析器对阿拉伯数字的识别），
  /// 让本模块保持纯净、不绑定具体解析器。
  static bool isQuery(String text, {bool hasArabicAmount = false}) {
    final t = text.trim();
    if (t.isEmpty) return false;

    // 1) 明显问句 → 查账
    if (queryWords.any(t.contains)) return true;

    // 2) 像记账（有金额或动作词）→ 记账
    final hasAmount = hasArabicAmount || hasColloquialAmount(t);
    if (hasAmount || actionWords.any(t.contains)) return false;

    // 3) 既不像问句也不像花销 → 仍交给记账流（会礼貌追问金额，而不是乱查账）
    return false;
  }

  /// 口语金额：中文数字/阿拉伯数字 + 块/元/毛/角（"一块""两块五""十块""三十元"）。
  static bool hasColloquialAmount(String t) =>
      RegExp(r'[零一二两三四五六七八九十百千万0-9]+\s*[块元毛角]').hasMatch(t);
}
