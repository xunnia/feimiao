import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qingji/core/update/app_update.dart';

void main() {
  group('AppUpdateInfo.sanitizeSha256', () {
    const clean =
        '27664317590107ff6bbf538f6189612d951b5b899be264d1539d238a0cef6d0f';

    test('干净的 64 位 hex 原样通过（大写归一为小写）', () {
      expect(AppUpdateInfo.sanitizeSha256(clean), clean);
      expect(AppUpdateInfo.sanitizeSha256(clean.toUpperCase()), clean);
      expect(AppUpdateInfo.sanitizeSha256('  $clean  '), clean);
    });

    test(r'v177 事故形态：sha256sum 反斜杠前缀被剥掉', () {
      expect(AppUpdateInfo.sanitizeSha256('\\$clean'), clean);
      expect(AppUpdateInfo.sanitizeSha256('\\\\$clean'), clean);
    });

    test('格式不对宁可当没有（空串=跳过/走响应头兜底），不能拿脏值比对', () {
      expect(AppUpdateInfo.sanitizeSha256(null), '');
      expect(AppUpdateInfo.sanitizeSha256(''), '');
      expect(AppUpdateInfo.sanitizeSha256('abc123'), '');
      expect(AppUpdateInfo.sanitizeSha256('${clean}00'), ''); // 66 位
      expect(AppUpdateInfo.sanitizeSha256(clean.substring(2)), ''); // 62 位
      expect(
        AppUpdateInfo.sanitizeSha256('g${clean.substring(1)}'), // 非 hex 字符
        '',
      );
    });

    test('fromJson 用的就是清洗后的值', () {
      final info = AppUpdateInfo.fromJson({
        'versionCode': 177,
        'url': 'https://example.com/a.apk',
        'sha256': '\\$clean',
      });
      expect(info, isNotNull);
      expect(info!.sha256, clean);
    });
  });

  group('AppRollbackInfo', () {
    test('保留历史显示版本，同时要求独立的递增安装序号', () {
      final entry = AppRollbackInfo.fromJson({
        'versionName': '1.279.0',
        'sourceVersionCode': 293,
        'installVersionCode': 304,
        'url': 'https://archive.example.test/feimiao-1.279.0.apk',
        'releaseId': 'v304-${'a' * 12}',
        'sha256': 'B' * 64,
        'databaseVersion': 49,
      });
      expect(entry, isNotNull);
      expect(entry!.sourceVersionCode, 293);
      expect(entry.installVersionCode, 304);
      expect(entry.installInfo.versionCode, 304);
      expect(entry.sha256, 'b' * 64);
      expect(entry.databaseVersion, 49);
    });

    test('拒绝 HTTP、缺安装序号和空 releaseId', () {
      final base = <String, dynamic>{
        'versionName': '1.279.0',
        'sourceVersionCode': 293,
        'url': 'https://archive.example.test/old.apk',
        'releaseId': 'v304-${'a' * 12}',
      };
      expect(
        AppRollbackInfo.fromJson({...base, 'installVersionCode': 304}),
        isNotNull,
      );
      expect(
        AppRollbackInfo.fromJson({
          ...base,
          'installVersionCode': 304,
          'url': 'http://archive.example.test/old.apk',
        }),
        isNull,
      );
      expect(AppRollbackInfo.fromJson(base), isNull);
      expect(
        AppRollbackInfo.fromJson(
            {...base, 'installVersionCode': 304, 'releaseId': ''}),
        isNull,
      );
    });
  });

  test('更新地址只接受 HTTPS', () {
    expect(isSecureUpdateUrl('https://updates.example.test/app.apk'), isTrue);
    expect(isSecureUpdateUrl('HTTP://updates.example.test/app.apk'), isFalse);
    expect(isSecureUpdateUrl('https:///missing-host.apk'), isFalse);
  });

  test('前台兜底下载会用 Range 接续 part 文件并校验完整包', () async {
    final payload = List<int>.generate(4096, (index) => index % 251);
    final expectedHash = sha256.convert(payload).toString();
    final splitAt = payload.length ~/ 2;
    String? receivedRange;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      receivedRange = request.headers.value(HttpHeaders.rangeHeader);
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $splitAt-${payload.length - 1}/${payload.length}',
        )
        ..headers.set('x-feimiao-sha256', expectedHash)
        ..contentLength = payload.length - splitAt
        ..add(payload.sublist(splitAt));
      await request.response.close();
    });
    final temp =
        await Directory.systemTemp.createTemp('feimiao_update_resume_');
    try {
      const versionCode = 9999;
      final partial = File(
        p.join(temp.path, 'feimiao-update-$versionCode.apk.part'),
      );
      await partial.writeAsBytes(payload.sublist(0, splitAt), flush: true);
      final info = AppUpdateInfo(
        versionName: 'test',
        versionCode: versionCode,
        url: 'http://${server.address.host}:${server.port}/app.apk',
        notes: '',
        sizeBytes: payload.length,
        sha256: '',
        releaseId: 'test',
      );

      final output = await AppUpdate.download(
        info,
        downloadDirectory: temp,
      );

      expect(receivedRange, 'bytes=$splitAt-');
      expect(await output.readAsBytes(), payload);
      expect(await partial.exists(), isFalse);
    } finally {
      await server.close(force: true);
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  });
}
