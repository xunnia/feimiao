import '../app_version.dart';

/// 肥喵后端（feimiao-server）的连接配置。
///
/// 地址和开关都走编译参数，不写死在代码里（后端 docs/04 要求）：
/// - `--dart-define=FM_API_BASE=http://localhost:8080/v1`：本机联调，
///   配合 `adb reverse tcp:8080 tcp:8080`，手机上的 localhost 就能连到电脑。
///   只能写 `localhost`：网络安全配置只对这个主机名放行明文 HTTP。
/// - `--dart-define=FM_ACCOUNT=true`：显示账号入口。服务端上线前默认关闭，
///   关闭时 App 行为和没有账号体系时完全一样。
class CloudConfig {
  CloudConfig._();

  static const String defaultBaseUrl = 'https://fm-api.xunnia.com/v1';

  static const String baseUrl = String.fromEnvironment(
    'FM_API_BASE',
    defaultValue: defaultBaseUrl,
  );

  static const bool accountEnabled = bool.fromEnvironment('FM_ACCOUNT');

  static const String platform = 'android';

  /// `X-App-Version` 最长 32 个字符。
  static String get appVersion => AppVersion.version;

  static const Duration requestTimeout = Duration(seconds: 20);

  /// 访问令牌剩余不到这么久就先刷新，避免请求到一半过期。
  static const Duration refreshSkew = Duration(seconds: 60);
}
