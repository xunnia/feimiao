import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/core/ai/ai_provider_config.dart';
import 'package:qingji/core/ai/llm_entry_parser.dart';
import 'package:qingji/core/ai/merchant_category.dart';
import 'package:qingji/core/ai/natural_language_entry_parser.dart';
import 'package:qingji/core/ai/order_list_parser.dart';
import 'package:qingji/core/ai/refund_matcher.dart';
import 'package:qingji/core/ai/responses_protocol.dart';
import 'package:qingji/core/ai/screenshot_layout.dart';
import 'package:qingji/core/budget/budget_rule_engine.dart';
import 'package:qingji/core/budget/budget_rules.dart';
import 'package:qingji/core/models/category_seed.dart';
import 'package:qingji/core/models/transaction_kind.dart';
import 'package:qingji/core/notification_parse.dart';
import 'package:qingji/core/transaction_time.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/views/search/search_view.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AI 记账鲁棒性回归', () {
    test('extractJsonObject 支持 Markdown 代码块、<think> 标签、前后说明与尾逗号', () {
      const fenced = '''
<think>用户记了两笔账，分别是午饭和咖啡</think>
好的，解析结果如下：
```json
{
  "intent": "record",
  "entries": [
    {"amount": "¥1,299.50", "kind": "Expense", "categoryKey": "dining_lunch", "note": "聚餐",},
  ],
}
```
''';
      final decoded = LlmEntryParser.extractJsonObject(fenced);
      expect(decoded['intent'], 'record');
      final entries = decoded['entries'] as List;
      expect(entries, hasLength(1));
      expect((entries.first as Map)['note'], '聚餐');
    });

    test('parseModelAmount 容忍货币符号、千分位逗号、全角数字与元块后缀，并拒绝非有限数', () {
      expect(LlmEntryParser.parseModelAmount('¥1,299.50'),
          Decimal.parse('1299.50'));
      expect(LlmEntryParser.parseModelAmount(' 28.5元 '), Decimal.parse('28.5'));
      expect(
          LlmEntryParser.parseModelAmount('１２３．４５块'), Decimal.parse('123.45'));
      expect(LlmEntryParser.parseModelAmount(double.nan), isNull);
      expect(LlmEntryParser.parseModelAmount(double.infinity), isNull);
    });

    test('非 Codex Responses 记账请求不再发送非法 reasoning.effort=max', () {
      final config = AiProviderConfig(
        type: AiProviderType.custom,
        apiKey: 'sk-test',
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt-5',
        endpointType: AiEndpointType.responses,
        reasoningEffort: AiReasoningEffort.max,
      );
      final body = ResponsesProtocol.bodyFromChat(
        const {
          'model': 'gpt-5',
          'messages': [
            {'role': 'user', 'content': '午饭 25'},
          ],
          'response_format': {'type': 'json_object'},
        },
        config,
        kind: ResponsesRequestKind.entry,
      );
      expect((body['reasoning'] as Map)['effort'], 'xhigh');
    });

    test('MerchantCategory 触发词去重：房贷归 house_loan、学费归 edu_tuition', () {
      expect(
        MerchantCategory.classify('还房贷 5200', TransactionKind.expense),
        'house_loan',
      );
      expect(
        MerchantCategory.classify('交学费 3000', TransactionKind.expense),
        'edu_tuition',
      );
    });

    test('离线解析与截图金额提取不再误把日期时间当金额，且支持千分位与下午12点', () {
      expect(NaturalLanguageEntryParser.extractAmount('7月3日吃了面'), isNull);
      expect(NaturalLanguageEntryParser.extractAmount('昨天下午6点30打车'), isNull);
      expect(
        NaturalLanguageEntryParser.extractAmount('工资 12,000元'),
        Decimal.parse('12000'),
      );
      expect(
        NaturalLanguageEntryParser.extractAmount('买鞋 ¥1,299.50'),
        Decimal.parse('1299.50'),
      );
      expect(
        NaturalLanguageEntryParser.extractAmount('早饭 23块50'),
        Decimal.parse('23.5'),
      );
      final noon = NaturalLanguageEntryParser.parse(
        '下午12点吃午饭 30',
        at: DateTime(2026, 8, 10, 9, 0),
      );
      expect(noon.date.hour, 12);
      expect(noon.date.minute, 0);
      expect(
        PaymentScreenshotParser.extractAmount(
          fromOCRText: '交易时间 2026-1031 12:00\n实付 ¥28.50',
        ),
        Decimal.parse('28.50'),
      );
    });

    test('parseAiTransactionTime 保留带 Z 墙钟时分并兼容斜杠日期', () {
      final fallback = DateTime(2026, 6, 20, 15, 30);
      final zTime = parseAiTransactionTime(
        '2026-06-20T12:30:00Z',
        fallback: fallback,
      );
      expect(zTime.isUtc, isFalse);
      expect(zTime.year, 2026);
      expect(zTime.month, 6);
      expect(zTime.day, 20);
      expect(zTime.hour, 12);
      expect(zTime.minute, 30);

      final slash = parseAiTransactionTime(
        '2026/6/5',
        fallback: fallback,
      );
      expect(slash.year, 2026);
      expect(slash.month, 6);
      expect(slash.day, 5);
      expect(slash.hour, 15);
      expect(slash.minute, 30);
      expect(
        aiTransactionTimePrecision('2026/6/5'),
        TransactionTimePrecision.entryClock,
      );
    });

    test('RefundMatcher 支持跨年 M月D日 且不把时间数字误作退款金额', () {
      expect(RefundMatcher.extractAmount('昨天14点淘宝衣服退款'), isNull);
      expect(RefundMatcher.extractAmount('13号淘宝衣服退款'), isNull);

      final result = RefundMatcher.match(
        text: '12月28日淘宝衣服退款 30',
        amount: RefundMatcher.extractAmount('12月28日淘宝衣服退款 30'),
        now: DateTime(2026, 1, 5, 10, 0),
        candidates: [
          RefundCandidate(
            id: 1,
            label: '淘宝衣服 服饰',
            amount: Decimal.parse('100'),
            refunded: Decimal.zero,
            date: DateTime(2025, 12, 28, 18, 0),
          ),
        ],
      );
      expect(result.status, RefundMatchStatus.matched);
      expect(result.candidate?.id, 1);
    });

    test('OrderListParser 保留屏底被截断的含价订单且不误删部分退款单', () {
      const lines = [
        OcrLine(text: '店铺A', top: 10, bottom: 24, left: 0),
        OcrLine(text: '商品A ¥20.00', top: 30, bottom: 44, left: 0),
        OcrLine(text: '共1件', top: 50, bottom: 64, left: 0),
        OcrLine(text: '店铺B', top: 90, bottom: 104, left: 0),
        OcrLine(text: '商品B ¥100.00 已退款¥5', top: 110, bottom: 124, left: 0),
        OcrLine(text: '共1件', top: 130, bottom: 144, left: 0),
        OcrLine(text: '店铺C', top: 170, bottom: 184, left: 0),
        OcrLine(text: '商品C ¥39.90', top: 190, bottom: 204, left: 0),
      ];
      final blocks = OrderListParser.segment(lines);
      expect(blocks, hasLength(3));
    });

    test('NotificationParse 不把纯余额提醒当成一笔消费', () {
      expect(NotificationParse.pickAmount('账户余额 ¥5,420.00'), isNull);
      expect(
        NotificationParse.pickAmount('微信支付 ¥28.50，余额 ¥5,420.00'),
        Decimal.parse('28.50'),
      );
    });
  });

  group('性能与仓储缓存回归', () {
    test('AppRepository.resolveActiveCategory 跳过已隐藏分类并支持大小写与中文名回退', () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final dir =
          await Directory.systemTemp.createTemp('feimiao_perf_ai_repo_');
      addTearDown(() => dir.delete(recursive: true));
      await databaseFactory.setDatabasesPath(dir.path);

      final repo = AppRepository();
      await repo.init();
      addTearDown(repo.closeForTest);

      final lunch = repo.categories
          .firstWhere((c) => c.key == 'dining_lunch' && !c.hidden);
      await repo.setCategoryHidden(lunch.id, true);

      // 已隐藏子类回退到未隐藏父分类 dining。
      final resolvedHidden = repo.resolveActiveCategory(
        'dining_lunch',
        TransactionKind.expense,
      );
      expect(resolvedHidden?.key, 'dining');

      // 大小写不敏感 key 与中文名均可正确命中未隐藏分类。
      final resolvedCase = repo.resolveActiveCategory(
        'DINING_DRINK',
        TransactionKind.expense,
      );
      expect(resolvedCase?.key, 'dining_drink');

      final resolvedZh = repo.resolveActiveCategory(
        '奶茶咖啡',
        TransactionKind.expense,
      );
      expect(resolvedZh?.hidden, isFalse);

      // 稳定引用缓存：tags / accounts / categoriesForKindRanked 在无写入时保持同一对象。
      expect(identical(repo.tags, repo.tags), isTrue);
      expect(identical(repo.accounts, repo.accounts), isTrue);
      expect(
        identical(
          repo.categoriesForKindRanked(TransactionKind.expense),
          repo.categoriesForKindRanked(TransactionKind.expense),
        ),
        isTrue,
      );
      expect(identical(CategorySeed.all, CategorySeed.all), isTrue);
    });

    test('BudgetRuleEngine.resolveMonth 在默认 reset 模式下跳过多年前置遍历且结果一致', () {
      final rules = [
        BudgetRule(
          id: 1,
          uuid: 'r1',
          bookId: 1,
          kind: BudgetRuleKind.base,
          name: '日常',
          amountCents: 300000,
          unit: BudgetRuleUnit.month,
          startDate: DateTime(2022, 1, 1),
          endDate: null,
          funding: BudgetFunding.extra,
          colorIndex: 0,
          createdMs: 1,
          updatedMs: 1,
          deletedMs: null,
        ),
      ];
      final res = BudgetRuleEngine.resolveMonth(
        rules: rules,
        spendByDay: {20260801: 12000},
        year: 2026,
        month: 8,
        today: DateTime(2026, 8, 10),
      );
      expect(res.budgetCents, 300000);
      expect(res.carryInCents, 0);
      expect(res.spentCents, 12000);
    });

    testWidgets('SearchView 在交易变更后立即刷新列表与汇总（不依赖 didChangeDependencies）',
        (tester) async {
      late Directory dir;
      late AppRepository repo;
      late int txId;
      await tester.runAsync(() async {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        dir = await Directory.systemTemp.createTemp('feimiao_search_live_');
        await databaseFactory.setDatabasesPath(dir.path);
        repo = AppRepository();
        await repo.init();
        final cat = repo.categories
            .firstWhere((c) => c.kind == TransactionKind.expense && !c.hidden);
        final acc = repo.transactionAccounts.first;
        txId = await repo.addTransaction(
          kind: TransactionKind.expense,
          amount: Decimal.parse('32'),
          categoryId: cat.id,
          accountId: acc.id,
          note: '拿铁咖啡',
          date: DateTime(2026, 8, 20, 10, 0),
        );
      });
      addTearDown(() async {
        await tester.runAsync(() async {
          await repo.closeForTest();
          await dir.delete(recursive: true);
        });
      });

      await tester.pumpWidget(
        ChangeNotifierProvider<AppRepository>.value(
          value: repo,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const SearchView(),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '拿铁');
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('拿铁咖啡'), findsOneWidget);

      // 删除该笔交易后，SearchView 应通过 financialViewVersion 自动刷新移除陈旧条目。
      await tester.runAsync(() => repo.deleteTransaction(txId));
      await tester.pump();
      expect(find.text('拿铁咖啡'), findsNothing);
    });

    test('公共 Responses classifyMerchants 无 schema 时保留 json_object 约束', () {
      const config = AiProviderConfig(
        type: AiProviderType.custom,
        apiKey: 'sk-test',
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt-5',
        endpointType: AiEndpointType.responses,
      );
      final body = ResponsesProtocol.bodyFromChat(
        const {
          'model': 'gpt-5',
          'messages': [
            {'role': 'user', 'content': '瑞幸咖啡'},
          ],
          'response_format': {'type': 'json_object'},
        },
        config,
        kind: ResponsesRequestKind.entry,
      );
      expect(body['text'], {
        'format': {'type': 'json_object'},
      });
    });
  });
}
