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
}
