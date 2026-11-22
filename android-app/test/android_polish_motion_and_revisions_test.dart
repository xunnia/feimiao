import 'dart:convert';
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/core/ai/ai_provider_config.dart';
import 'package:qingji/core/ai/llm_query.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/widgets/animated_money.dart';
import 'package:qingji/widgets/budget_progress.dart';
import 'package:qingji/widgets/glass_input.dart';
import 'package:qingji/widgets/mascot.dart';
import 'package:qingji/widgets/pressable_scale.dart';
import 'package:qingji/widgets/settings_ui.dart';
import 'package:qingji/widgets/sliding_segment.dart';
import 'package:qingji/widgets/tag_selector.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('按域订阅与动效无障碍回归', () {
    test('AppRepository.financialViewVersion 不随聊天会话或 AI 记忆通知抖动', () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final dir =
          await Directory.systemTemp.createTemp('feimiao_domain_revision_');
      addTearDown(() => dir.delete(recursive: true));
      await databaseFactory.setDatabasesPath(dir.path);

      final repo = AppRepository();
      await repo.init();
      addTearDown(repo.closeForTest);

      final before = repo.financialViewVersion;
      final chatBefore = repo.chatRevision;
      final aiBefore = repo.aiRevision;
      final settingsBefore = repo.settingsViewVersion;

      // 聊天会话写入与 AI 记忆写入只会推进 chat/ai 域，不改变 financial/settings 域。
      await repo.createChatSession(title: '股市讨论');
      await repo.addAiMemory(
        phrase: '股市',
        content: '偏好结构化要点',
        consent: true,
      );

      expect(repo.chatRevision, greaterThan(chatBefore));
      expect(repo.aiRevision, greaterThan(aiBefore));
      expect(repo.settingsViewVersion, settingsBefore);
      expect(repo.financialViewVersion, before);
    });

    testWidgets('减弱动态（disableAnimations）下金额滚动与按压反馈即时生效且不报错', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: Column(
                children: [
                  AnimatedMoney(value: Decimal.parse('128.50')),
                  const SizedBox(
                    width: 200,
                    child: BudgetProgressBar(value: 0.45),
                  ),
                  const SizedBox(
                    width: 60,
                    height: 60,
                    child: BudgetProgressRing(
                      value: 0.45,
                      activeColor: Color(0xFF7FB069),
                    ),
                  ),
                  PressableScale(
                    onPressed: () => tapped = true,
                    child: const Text('按压测试'),
                  ),
                  AppSwitch(value: true, onChanged: (_) {}),
                  AppCheckmark(value: true, onChanged: (_) {}),
                  const MascotBreath(child: SizedBox(width: 24, height: 24)),
                ],
              ),
            ),
          ),
        ),
      );

      // 减弱动态下首帧即直接展示目标金额，而不是 ¥0.00。
      expect(find.text('¥128.50'), findsOneWidget);
      await tester.tap(find.text('按压测试'));
      await tester.pump();
      expect(tapped, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('200% 大字 + 320dp 窄屏下分段条、标签行与输入按钮无溢出且具备读屏语义', (tester) async {
      late Directory dir;
      late AppRepository repo;
      await tester.runAsync(() async {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        dir = await Directory.systemTemp.createTemp('feimiao_motion_a11y_');
        await databaseFactory.setDatabasesPath(dir.path);
        repo = AppRepository();
        await repo.init();
        await repo.addTag(name: '报销测试', colorValue: 0xFF7D8B9B);
      });
      addTearDown(() async {
        await tester.runAsync(() async {
          await repo.closeForTest();
          await dir.delete(recursive: true);
        });
      });

      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var selected = 0;
      await tester.pumpWidget(
        ChangeNotifierProvider<AppRepository>.value(
          value: repo,
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2.0)),
              child: child!,
            ),
            home: Scaffold(
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SlidingSegment<int>(
                    items: const [(0, '全部'), (1, '支出'), (2, '收入')],
                    value: selected,
                    onChanged: (v) => selected = v,
                  ),
                  const SizedBox(height: 8),
                  TagSelector(selectedIds: const [], onChanged: (_) {}),
                  const SizedBox(height: 8),
                  AppGlassInputIconButton(
                    icon: Icons.add,
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // SlidingSegment 与 TagSelector 在 200% 大字下动态撑高（大于默认 34dp），不裁字。
      expect(tester.getSize(find.byType(SlidingSegment<int>)).height,
          greaterThan(34));
      expect(tester.getSize(find.byType(TagSelector)).height, greaterThan(34));
      // 输入栏图标按钮具备默认读屏 Tooltip/语义。
      expect(find.byTooltip('添加到聊天'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('LlmQuery.askReport 按思考强度动态扩容 max_tokens 且错误体脱敏密钥', () async {
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final bodies = <Map<String, dynamic>>[];
      var failNext = false;
      server.listen((request) async {
        final raw = await utf8.decoder.bind(request).join();
        bodies.add(jsonDecode(raw) as Map<String, dynamic>);
        if (failNext) {
          final errBytes = utf8.encode(
              '{"error":"invalid api key sk-secret-leak-999999999999"}');
          request.response.statusCode = 401;
          request.response.headers.contentType = ContentType.json;
          request.response.headers.contentLength = errBytes.length;
          request.response.add(errBytes);
          await request.response.close();
          return;
        }
        final okBytes = utf8.encode(jsonEncode({
          'choices': [
            {
              'message': {'content': '# 报告\n\n## 本月一句话\n一切平稳。'}
            }
          ],
        }));
        request.response.headers.contentType = ContentType.json;
        request.response.headers.contentLength = okBytes.length;
        request.response.add(okBytes);
        await request.response.close();
      });

      final config = AiProviderConfig(
        type: AiProviderType.custom,
        apiKey: 'sk-secret-leak-999999999999',
        baseUrl: 'http://${server.address.address}:${server.port}/v1',
        model: 'deepseek-chat',
        endpointType: AiEndpointType.chatCompletions,
        reasoningEffort: AiReasoningEffort.high,
      );

      await LlmQuery.askReport(
        reportTitle: '2026年8月报告',
        reportType: 'monthly',
        config: config,
        transactionsText: '本期准确合计：支出 ¥100',
      );
      expect(bodies.single['max_tokens'], 6144);

      failNext = true;
      await expectLater(
        () => LlmQuery.askReport(
          reportTitle: '2026年8月报告',
          reportType: 'monthly',
          config: config,
          transactionsText: '本期准确合计：支出 ¥100',
        ),
        throwsA(
          isA<LlmQueryException>().having(
            (e) => e.message,
            'sanitized message',
            isNot(contains('sk-secret-leak-999999999999')),
          ),
        ),
      );
    });
  });
}
