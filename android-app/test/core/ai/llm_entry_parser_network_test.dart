import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:qingji/core/ai/ai_provider_config.dart';
import 'package:qingji/core/ai/llm_entry_parser.dart';
import 'package:qingji/core/media/chat_attachment.dart';

AiProviderConfig _configFor(HttpServer server) => AiProviderConfig(
      type: AiProviderType.custom,
      apiKey: 'test-key',
      baseUrl: 'http://${server.address.address}:${server.port}/v1',
      model: 'vision-model',
      endpointType: AiEndpointType.chatCompletions,
    );

Map<String, Object?> _successBody() => {
      'choices': [
        {
          'message': {
            'content': jsonEncode({
              'intent': 'record',
              'entries': [
                {
                  'amount': 18,
                  'kind': 'expense',
                  'categoryKey': 'dining',
                  'date': '2026-08-26',
                  'note': '图片账单',
                  'confidence': 0.95,
                },
              ],
            }),
          },
        },
      ],
    };

Future<void> _writeSuccess(HttpRequest request) async {
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(_successBody()));
  await request.response.close();
}

void main() {
  test('主页记账首个网络连接失败时自动重试同一模型一次', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requestCount = 0;
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      requestCount++;
      if (requestCount == 1) {
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.destroy();
        return;
      }
      await _writeSuccess(request);
      unawaited(server.close(force: true));
    });

    final result = await LlmEntryParser.parseWithLLM(
      text: '奶茶 18',
      config: _configFor(server),
      expenseCats: const [(key: 'dining', name: '餐饮')],
      incomeCats: const [(key: 'otherIncome', name: '其他收入')],
      forceRecord: true,
    );

    expect(requestCount, 2);
    expect(result.entries.single.note, '图片账单');
  });

  test('主页图片记账把持久化图片字节真正放入请求体', () async {
    final temp = await Directory.systemTemp.createTemp('feimiao-image-wire-');
    addTearDown(() => temp.delete(recursive: true));
    final image = File('${temp.path}${Platform.pathSeparator}bill.png');
    final original = img.encodePng(img.Image(width: 2, height: 2));
    await image.writeAsBytes(original);
    final attachment = ChatAttachment(
      kind: ChatAttachmentKind.image,
      path: image.path,
      name: 'bill.png',
      mimeType: 'image/png',
      sizeBytes: original.length,
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requestBody = Completer<Map<String, dynamic>>();
    server.listen((request) async {
      final decoded = jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, dynamic>;
      requestBody.complete(decoded);
      await _writeSuccess(request);
      unawaited(server.close(force: true));
    });

    await LlmEntryParser.parseWithLLM(
      text: '识别这张账单',
      config: _configFor(server),
      expenseCats: const [(key: 'dining', name: '餐饮')],
      incomeCats: const [(key: 'otherIncome', name: '其他收入')],
      attachments: [attachment],
      forceRecord: true,
    );

    final body = await requestBody.future;
    final messages = body['messages'] as List;
    final content = (messages.last as Map)['content'] as List;
    final imagePart = content.cast<Map>().singleWhere(
          (part) => part['type'] == 'image_url',
        );
    expect(
      (imagePart['image_url'] as Map)['url'],
      'data:image/png;base64,${base64Encode(original)}',
    );
  });

  test('主页大图记账发送缩放副本且保留原图', () async {
    final temp = await Directory.systemTemp.createTemp('feimiao-image-resize-');
    addTearDown(() => temp.delete(recursive: true));
    final image = File('${temp.path}${Platform.pathSeparator}bill.png');
    final original = img.encodePng(img.Image(width: 4100, height: 16));
    await image.writeAsBytes(original);
    final attachment = ChatAttachment(
      kind: ChatAttachmentKind.image,
      path: image.path,
      name: 'bill.png',
      mimeType: 'image/png',
      sizeBytes: original.length,
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requestBody = Completer<Map<String, dynamic>>();
    server.listen((request) async {
      requestBody.complete(jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, dynamic>);
      await _writeSuccess(request);
      unawaited(server.close(force: true));
    });

    await LlmEntryParser.parseWithLLM(
      text: '识别这张宽账单',
      config: _configFor(server),
      expenseCats: const [(key: 'dining', name: '餐饮')],
      incomeCats: const [(key: 'otherIncome', name: '其他收入')],
      attachments: [attachment],
      forceRecord: true,
    );

    final body = await requestBody.future;
    final content = ((body['messages'] as List).last as Map)['content'] as List;
    final imagePart = content.cast<Map>().singleWhere(
          (part) => part['type'] == 'image_url',
        );
    final dataUrl = (imagePart['image_url'] as Map)['url'] as String;
    expect(dataUrl, startsWith('data:image/png;base64,'));
    final sentBytes = base64Decode(dataUrl.substring(dataUrl.indexOf(',') + 1));
    final sent = img.decodePng(sentBytes)!;
    expect(sent.width, 4096);
    expect(sent.height, 16);
    expect(sentBytes, isNot(orderedEquals(original)));
    expect(await image.readAsBytes(), orderedEquals(original));
    final cache =
        Directory('${temp.path}${Platform.pathSeparator}.ai_prepared_v1');
    final copy = cache.listSync().whereType<File>().singleWhere(
          (file) => file.path.endsWith('.png'),
        );
    expect(await copy.readAsBytes(), orderedEquals(sentBytes));
  });
}
