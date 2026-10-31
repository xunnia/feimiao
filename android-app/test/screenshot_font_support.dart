import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:flutter/services.dart' show FontLoader;

/// Flutter 的离屏测试引擎（Windows 本机和 Linux CI）不会自动使用系统 CJK fallback。
/// 截图测试必须显式注册应用真实使用的字体和图标字体；否则缺字会被
/// 渲染成方框，而不是让截图看起来像真实设备。
const screenshotCjkFontFamily = 'NotoSansSC';

bool _screenshotFontsLoaded = false;

Future<void> loadScreenshotFonts({bool force = false}) async {
  final candidates = <String?>[
    Platform.environment['FEIMIAO_CJK_FONT'],
    r'C:\Windows\Fonts\NotoSansSC-VF.ttf',
    r'C:\Windows\Fonts\Noto Sans SC (TrueType).otf',
    // Linux CI 装的 fonts-noto-cjk。FontLoader 读字体集合时只用第 0 套，
    // 也就是日文版：汉字字宽与 Windows 用的 Noto Sans SC 一致，但行高偏高
    // （1.448em 对 1.2em），只适合做布局检查。要出截图仍然用
    // FEIMIAO_CJK_FONT 指向真正的 Noto Sans SC。
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    if (force)
      p.join(Directory.current.path, 'assets', 'fonts', 'AssetLabels-VF.ttf'),
  ];
  final screenshotRequested = Platform.environment.entries.any(
    (entry) =>
        entry.key.startsWith('UPDATE_') &&
        entry.key.endsWith('_SCREENSHOTS') &&
        entry.value == '1',
  );
  if (!screenshotRequested && !force) return;
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
  if (env != null && File(env).existsSync()) return env;

  // 本机 Windows SDK 缓存里是 materialicons-regular.otf，CI 用的官方 Linux
  // 发布包里是 MaterialIcons-Regular.otf。Linux 区分大小写，所以按目录
  // 忽略大小写匹配。
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final fontDirs = <String>[
    if (flutterRoot != null)
      p.join(flutterRoot, 'bin', 'cache', 'artifacts', 'material_fonts'),
    r'C:\src\flutter\bin\cache\artifacts\material_fonts',
  ];
  for (final dirPath in fontDirs) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is File &&
          p.basename(entity.path).toLowerCase() ==
              'materialicons-regular.otf') {
        return entity.path;
      }
    }
  }
  return null;
}

String? _findCupertinoIcons() {
  final env = Platform.environment['FEIMIAO_CUPERTINO_ICON_FONT'];
  if (env != null && File(env).existsSync()) return env;

  // 优先用本工程 pub get 实际解析到的那一版，Windows、Linux、macOS 一致。
  final packageRoot = _resolvePackageRoot('cupertino_icons');
  if (packageRoot != null) {
    final candidate = p.join(packageRoot, 'assets', 'CupertinoIcons.ttf');
    if (File(candidate).existsSync()) return candidate;
  }

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

/// 从 `.dart_tool/package_config.json` 找到依赖包在本机的目录。
String? _resolvePackageRoot(String name) {
  final config =
      File(p.join(Directory.current.path, '.dart_tool', 'package_config.json'));
  if (!config.existsSync()) return null;
  final json = jsonDecode(config.readAsStringSync()) as Map<String, dynamic>;
  for (final entry in json['packages'] as List<dynamic>) {
    final package = entry as Map<String, dynamic>;
    if (package['name'] != name) continue;
    return config.uri.resolve(package['rootUri'] as String).toFilePath();
  }
  return null;
}

/// Flutter SDK 引擎源码自带的 Noto Color Emoji。本机 SDK 和 CI 的 Linux
/// 发布包里都有这份文件，截图测试不用再依赖 `.tmp` 下的旧 SDK 副本。
String flutterSdkEmojiFontPath() => p.join(
      Platform.environment['FLUTTER_ROOT'] ?? r'C:\src\flutter',
      'engine',
      'src',
      'flutter',
      'txt',
      'third_party',
      'fonts',
      'NotoColorEmoji.ttf',
    );
