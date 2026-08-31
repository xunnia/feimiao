import 'dart:io';

/// Validates the network addresses used by user-configured AI providers.
///
/// HTTPS is the default and is accepted for any host with a valid URI. HTTP
/// is intentionally limited to the device itself and private/link-local
/// networks so a local relay such as `192.168.31.254` can be used without
/// turning every imported provider into a public cleartext endpoint.
class AiProviderUrlPolicy {
  AiProviderUrlPolicy._();

  /// Returns a user-facing validation error, or `null` when the value is
  /// empty (not configured yet) or is an allowed provider base URL.
  static AiProviderUrlError? validateBaseUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.trim().isEmpty || uri.userInfo.isNotEmpty) {
      return AiProviderUrlError.invalid;
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'https') return null;
    if (scheme != 'http') return AiProviderUrlError.unsupportedScheme;
    return isPrivateHttpHost(uri.host)
        ? null
        : AiProviderUrlError.insecureRemote;
  }

  /// Request-layer gate used by imported/legacy providers as well as the
  /// settings page. HTTPS is always permitted; cleartext HTTP stays local.
  static bool isAllowedRequestUri(Uri uri) {
    if (uri.host.trim().isEmpty || uri.userInfo.isNotEmpty) return false;
    final scheme = uri.scheme.toLowerCase();
    return scheme == 'https' ||
        (scheme == 'http' && isPrivateHttpHost(uri.host));
  }

  static bool isPrivateHttpHost(String rawHost) {
    var host = rawHost.trim().toLowerCase();
    if (host.endsWith('.')) host = host.substring(0, host.length - 1);
    if (host == 'localhost' || host == 'ip6-localhost') return true;

    final address = InternetAddress.tryParse(host);
    if (address == null) return false;
    final bytes = address.rawAddress;
    if (bytes.length == 4) {
      final first = bytes[0];
      final second = bytes[1];
      return first == 10 ||
          first == 127 ||
          (first == 169 && second == 254) ||
          (first == 172 && second >= 16 && second <= 31) ||
          (first == 192 && second == 168);
    }
    if (bytes.length != 16) return false;

    final loopback = bytes.take(15).every((value) => value == 0) &&
        bytes[15] == 1;
    final uniqueLocal = (bytes[0] & 0xfe) == 0xfc;
    final linkLocal = bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80;
    return loopback || uniqueLocal || linkLocal;
  }
}

enum AiProviderUrlError {
  invalid,
  unsupportedScheme,
  insecureRemote,
}
