import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:flutter/services.dart' show FontLoader;

/// Flutter 的 Windows 离屏测试引擎不会自动使用系统 CJK fallback。
/// 截图测试必须显式注册应用真实使用的字体和图标字体；否则缺字会被
/// 渲染成方框，而不是让截图看起来像真实设备。
const screenshotCjkFontFamily = 'NotoSansSC';

bool _screenshotFontsLoaded = false;

Future<void> loadScreenshotFonts() async {
  final candidates = <String?>[
    Platform.environment['FEIMIAO_CJK_FONT'],
    r'C:\Windows\Fonts\NotoSansSC-VF.ttf',
    r'C:\Windows\Fonts\Noto Sans SC (TrueType).otf',
  ];
  final screenshotRequested = Platform.environment.entries.any(
    (entry) =>
        entry.key.startsWith('UPDATE_') &&
        entry.key.endsWith('_SCREENSHOTS') &&
        entry.value == '1',
  );
  if (!screenshotRequested) return;
  if (_screenshotFontsLoaded) return;

  String? path;
  for (final candidate in candidates) {
    if (candidate != null && File(candidate).existsSync()) {
      path = candidate;
      break;
    }
  }
  if (path == null) {
    throw StateError(
      '截图需要 CJK 字体。请设置 FEIMIAO_CJK_FONT 指向 Noto Sans SC 字体文件。',
    );
  }

  await _loadFont(screenshotCjkFontFamily, path);

  // 这些是应用实际声明的 Nunito 字体。截图主题仍以 Nunito 为主字体，
  // Noto Sans SC 只作为中文 fallback，避免截图把拉丁字母也换成系统字体。
  final nunitoCandidates = <String?>[
    Platform.environment['FEIMIAO_NUNITO_FONT'],
    p.join(Directory.current.path, 'assets', 'fonts', 'Nunito-Regular.ttf'),
    r'C:\src\xunni-codex\android-app\assets\fonts\Nunito-Regular.ttf',
  ];
  String? nunitoPath;
  for (final candidate in nunitoCandidates) {
    if (candidate != null && File(candidate).existsSync()) {
      nunitoPath = candidate;
      break;
    }
  }
  if (nunitoPath == null) {
    throw StateError(
      '截图需要应用 Nunito 字体，请设置 FEIMIAO_NUNITO_FONT。',
    );
  } else {
    await _loadFont('Nunito', nunitoPath);
  }

  final materialIconPath = _findMaterialIcons();
  if (materialIconPath == null) {
    throw StateError(
      '截图需要 Flutter Material Icons 字体。请设置 '
      'FEIMIAO_MATERIAL_ICON_FONT 指向 materialicons-regular.otf。',
    );
  }
  // Flutter's IconData uses the exact family name `MaterialIcons` (without
  // a space). Using `Material Icons` silently falls back to tofu boxes.
  await _loadFont('MaterialIcons', materialIconPath);

  final cupertinoIconPath = _findCupertinoIcons();
  if (cupertinoIconPath == null) {
    throw StateError(
      '截图需要 cupertino_icons 的 CupertinoIcons.ttf 字体。请设置 '
      'FEIMIAO_CUPERTINO_ICON_FONT 指向该文件。',
    );
  }
  await _loadFont(
    'packages/cupertino_icons/CupertinoIcons',
    cupertinoIconPath,
  );

  _screenshotFontsLoaded = true;
}

Future<void> _loadFont(String family, String path) async {
  final bytes = File(path).readAsBytesSync();
  await (FontLoader(family)
        ..addFont(
          Future<ByteData>.value(
            ByteData.view(
                bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes),
          ),
        ))
      .load();
}

String? _findMaterialIcons() {
  final env = Platform.environment['FEIMIAO_MATERIAL_ICON_FONT'];
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final candidates = <String?>[
    env,
    if (flutterRoot != null)
      p.join(
        flutterRoot,
        'bin',
        'cache',
        'artifacts',
        'material_fonts',
        'materialicons-regular.otf',
      ),
    r'C:\src\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf',
  ];
  for (final candidate in candidates) {
    if (candidate != null && File(candidate).existsSync()) return candidate;
  }
  return null;
}

String? _findCupertinoIcons() {
  final env = Platform.environment['FEIMIAO_CUPERTINO_ICON_FONT'];
  if (env != null && File(env).existsSync()) return env;

  final localAppData = Platform.environment['LOCALAPPDATA'];
  final hostedRoots = <String?>[
    if (localAppData != null) p.join(localAppData, 'Pub', 'Cache', 'hosted'),
    if (localAppData != null) p.join(localAppData, '.pub-cache', 'hosted'),
  ];
  for (final rootPath in hostedRoots) {
    if (rootPath == null) continue;
    final root = Directory(rootPath);
    if (!root.existsSync()) continue;
    for (final registry in root.listSync(followLinks: false)) {
      if (registry is! Directory) continue;
      for (final package in registry.listSync(followLinks: false)) {
        if (package is! Directory ||
            !p.basename(package.path).startsWith('cupertino_icons-')) {
          continue;
        }
        final candidate = p.join(package.path, 'assets', 'CupertinoIcons.ttf');
        if (File(candidate).existsSync()) return candidate;
      }
    }
  }
  return null;
}
