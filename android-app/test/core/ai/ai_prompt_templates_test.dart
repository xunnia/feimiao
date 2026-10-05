import 'package:flutter_test/flutter_test.dart';
import 'package:qingji/core/ai/ai_prompt_templates.dart';

void main() {
  test('普通问答提示词不强制固定排版或短回复', () {
    const prompt = AiPromptTemplates.systemPrompt;

    expect(prompt, contains('口语化的方式交流'));
    expect(prompt, isNot(contains('口语化、简短亲切')));
    expect(prompt, isNot(contains('长度与排版')));
    expect(prompt, isNot(contains('Markdown')));
    expect(prompt, isNot(contains('控制在')));
    expect(prompt, isNot(contains('每段最多')));
    expect(prompt, isNot(contains('只使用')));
    expect(prompt, isNot(contains('过长回答')));
  });

  test('普通聊天允许通用话题且历史拒答不限制新问题', () {
    const prompt = AiPromptTemplates.systemPrompt;
    expect(prompt, contains('通用 AI 助手'));
    expect(prompt, contains('股市分析'));
    expect(prompt, contains('不要把普通问题强行引回账单'));
    expect(prompt, contains('不构成新的能力限制'));
    expect(prompt, contains('没有实时资料时说明无法核实'));
  });

  test('普通对话的用户记忆不冒充账目上下文', () {
    final messages = AiPromptTemplates.querySystemMessages(
      now: DateTime.utc(2026, 10, 4, 10, 33),
      memoryText: '用户偏好详细分析',
    );
    final content = messages.map((message) => message['content']).join('\n');
    expect(content, contains('没有提供账本数据'));
    expect(content, contains('用户记忆（偏好参考'));
    expect(content, contains('用户偏好详细分析'));
    expect(content, isNot(contains('账目上下文：')));
    expect(content, isNot(contains(AiPromptTemplates.ledgerQueryRules)));
  });

  test('查账提供准确合计和分类锁定规则并单独标识记忆', () {
    final messages = AiPromptTemplates.querySystemMessages(
      now: DateTime.utc(2026, 10, 4),
      ledgerText: '分类筛选已锁定；分类查询准确合计：0',
      memoryText: '用户希望按周对比',
    );
    final ledger = messages.singleWhere(
      (message) => message['content']!.contains('账目上下文：'),
    );
    expect(ledger['content'], contains(AiPromptTemplates.ledgerQueryRules));
    expect(ledger['content'], contains('准确合计为 0 时如实回答 0'));
    expect(ledger['content'], isNot(contains('用户希望按周对比')));
    expect(messages.last['content'], contains('用户希望按周对比'));
  });

  test('相对日期使用带时区的设备时间但不伪造实时证据', () {
    final messages = AiPromptTemplates.querySystemMessages(
      now: DateTime.utc(2026, 10, 4, 10, 33),
    );
    expect(messages[1]['content'], contains('2026-10-04T10:33:00.000Z'));
    expect(messages[1]['content'], contains('UTC+00:00'));
    expect(messages[1]['content'], contains('不代表已获得实时资料'));
  });
}
