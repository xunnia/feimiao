import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qingji/core/ai/ai_attachment_pipeline.dart';
import 'package:qingji/core/ai/ai_provider_config.dart';
import 'package:qingji/core/ai/llm_query.dart';
import 'package:qingji/core/ai/llm_query_v2.dart';
import 'package:qingji/core/media/chat_attachment.dart';
import 'package:qingji/core/update/app_update.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/views/home/chat_add_sheet.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<({AiProviderConfig config, List<Map<String, dynamic>> bodies})>
    _reportLoopbackServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  final bodies = <Map<String, dynamic>>[];
  server.listen((request) async {
    final raw = await utf8.decoder.bind(request).join();
    bodies.add(jsonDecode(raw) as Map<String, dynamic>);
    final bytes = utf8.encode(jsonEncode({
      'output_text': '# 2026年8月报告\n\n## 本月一句话\n支出稳定。',
    }));
    request.response.headers.contentType = ContentType.json;
    request.response.headers.contentLength = bytes.length;
    request.response.add(bytes);
    await request.response.close();
  });
  return (
    config: AiProviderConfig(
      type: AiProviderType.custom,
      apiKey: 'sk-test-report',
      baseUrl: 'http://${server.address.address}:${server.port}/v1',
      model: 'gpt-5',
      endpointType: AiEndpointType.responses,
      webSearchEnabled: true,
    ),
    bodies: bodies,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('高优安全与边界回归', () {
    test('报告请求 LlmQuery.askReport 与 LlmQueryV2.askReport 强制单次关闭联网搜索', () async {
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);

      final server = await _reportLoopbackServer();

      await LlmQuery.askReport(
        reportTitle: '2026年8月账单报告',
        reportType: 'monthly',
        config: server.config,
        transactionsText: '本期准确合计：支出 ¥1000',
      );
      await LlmQueryV2.askReport(
        reportTitle: '2026年8月账单报告',
        reportType: 'monthly',
        config: server.config,
        transactionsText: '本期准确合计：支出 ¥1000',
      );

      expect(server.bodies, hasLength(2));
      for (final body in server.bodies) {
        expect(body.containsKey('tools'), isFalse,
            reason: '含全量账单上下文的报告请求不得附带 web_search tools');
      }
      // 不修改用户的全局配置对象。
      expect(server.config.webSearchEnabled, isTrue);
    });

    test('AiAttachmentPipeline.validate 限制单条消息附件总大小不超过 50 MB', () async {
      final dir = await Directory.systemTemp.createTemp('feimiao_attach_cap_');
      addTearDown(() => dir.delete(recursive: true));

      Future<ChatAttachment> makeImage(String name, int bytes) async {
        final file = File(p.join(dir.path, name));
        final raf = await file.open(mode: FileMode.write);
        await raf.truncate(bytes);
        await raf.close();
        return ChatAttachment(
          kind: ChatAttachmentKind.image,
          path: file.path,
          name: name,
          mimeType: 'image/jpeg',
          sizeBytes: bytes,
        );
      }

      // 3 张各 18MB = 54MB：单张都 <=20MB 且 <=4 张，但第 3 张会突破 50MB 总上限。
      final img1 = await makeImage('a.jpg', 18 * 1024 * 1024);
      final img2 = await makeImage('b.jpg', 18 * 1024 * 1024);
      final img3 = await makeImage('c.jpg', 18 * 1024 * 1024);

      final batch = await AiAttachmentPipeline.validate([img1, img2, img3]);
      expect(batch.accepted, hasLength(2));
      expect(batch.rejected, hasLength(1));
      expect(batch.rejected.single.error, contains('总大小不能超过 50 MB'));
    });

    test('AppUpdateInfo.fromJson 拒绝非 HTTPS 的更新包地址', () {
      expect(
        AppUpdateInfo.fromJson({
          'versionName': '1.319.0',
          'versionCode': 334,
          'url': 'http://updates.xunni.dpdns.org/app.apk',
        }),
        isNull,
      );
      final ok = AppUpdateInfo.fromJson({
        'versionName': '1.319.0',
        'versionCode': 334,
        'url': 'https://updates.xunni.dpdns.org/app.apk',
      });
      expect(ok, isNotNull);
      expect(ok!.url, 'https://updates.xunni.dpdns.org/app.apk');
    });

    test('冷启动收敛无新增折旧或周期记账时不重复二次全表加载交易', () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final dir = await Directory.systemTemp.createTemp('feimiao_cold_reload_');
      addTearDown(() => dir.delete(recursive: true));
      await databaseFactory.setDatabasesPath(dir.path);

      final repo = AppRepository();
      await repo.init();
      addTearDown(repo.closeForTest);

      // 普通冷启动下只应在 _loadAll 里执行 1 次全表 _loadTransactions，不再无条件查第 2 遍。
      expect(repo.transactionFullReloadCount, 1);
    });

    testWidgets('深色模式下 showChatAddSheet 与主题表面对比度正常', (tester) async {
      final dark = AppTheme.dark();
      await tester.pumpWidget(
        MaterialApp(
          theme: dark,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showChatAddSheet(
                    context,
                    onAttachmentsPicked: (_) async {},
                    webSearchEnabled: false,
                    onWebSearchChanged: (_) async {},
                    recentPhotos: Future.value(const []),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('联网搜索'), findsOneWidget);
      expect(
        (dark.colorScheme.onSurface.computeLuminance() -
                dark.colorScheme.surface.computeLuminance())
            .abs(),
        greaterThan(0.5),
      );
    });

    test('ChatAttachmentStore.pruneOrphanFiles 只删过期孤儿附件与缓存，保留被引用和新文件',
        () async {
      final dir = await Directory.systemTemp.createTemp('feimiao_att_prune_');
      addTearDown(() => dir.delete(recursive: true));

      final referenced = File(p.join(dir.path, 'live.jpg'))
        ..writeAsBytesSync([1, 2, 3]);
      final oldOrphan = File(p.join(dir.path, 'old_orphan.jpg'))
        ..writeAsBytesSync([4, 5, 6]);
      final freshDraft = File(p.join(dir.path, 'fresh_draft.jpg'))
        ..writeAsBytesSync([7, 8, 9]);
      final preparedDir = Directory(p.join(dir.path, '.ai_prepared_v1'))
        ..createSync();
      final oldCache = File(p.join(preparedDir.path, 'stale.jpg'))
        ..writeAsBytesSync([1, 1, 1]);

      final now = DateTime(2026, 11, 22, 12, 0);
      await oldOrphan
          .setLastModified(now.subtract(const Duration(minutes: 10)));
      await freshDraft
          .setLastModified(now.subtract(const Duration(seconds: 30)));
      await oldCache.setLastModified(now.subtract(const Duration(days: 10)));

      final deleted = await ChatAttachmentStore.pruneOrphanFiles(
        referencedPaths: {referenced.path},
        attachmentsDirectory: dir,
        minAge: const Duration(minutes: 5),
        now: now,
      );

      expect(deleted, 2);
      expect(referenced.existsSync(), isTrue);
      expect(freshDraft.existsSync(), isTrue);
      expect(oldOrphan.existsSync(), isFalse);
      expect(oldCache.existsSync(), isFalse);

      // 删除草稿文件：仅允许删目录内的文件，目录外的绝不碰。
      final outside = File(p.join(dir.parent.path,
          'feimiao_outside_${DateTime.now().microsecondsSinceEpoch}.tmp'))
        ..writeAsBytesSync([9]);
      addTearDown(() async {
        if (outside.existsSync()) await outside.delete();
      });
      await ChatAttachmentStore.deletePersistedDraftFile(
        freshDraft.path,
        attachmentsDirectory: dir,
      );
      await ChatAttachmentStore.deletePersistedDraftFile(
        outside.path,
        attachmentsDirectory: dir,
      );
      expect(freshDraft.existsSync(), isFalse);
      expect(outside.existsSync(), isTrue);
    });
  });
}
