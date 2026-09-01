import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show FlutterError, kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';

/// Bridges Android's system HTTP proxy into Dart's IO clients.
///
/// A full-device VPN already routes every socket through the VPN and needs no
/// special handling. Some mobile VPN/proxy apps instead expose an Android
/// system HTTP proxy that Chrome follows while a plain Dart client does not.
/// Installing this override makes OAuth, model discovery, and AI requests use
/// the same system proxy when one is actually configured.
class SystemNetworkProxy {
  SystemNetworkProxy._();

  static const MethodChannel _channel = MethodChannel('feimiao/network');
  static _SystemProxyOverrides? _installed;
  static DateTime? _lastRefresh;
  static Future<void>? _refreshing;
  static final Map<String, DateTime> _routeRefreshes = {};
  static final Map<String, Future<void>> _routeRefreshInFlight = {};

  static Future<void> install() async {
    if (kIsWeb || !Platform.isAndroid) return;
    // Respect another package's explicit override. Once ours is installed,
    // refresh the same mutable callback instead of replacing live clients.
    if (_installed == null && HttpOverrides.current != null) return;
    _installed ??= _SystemProxyOverrides();
    if (HttpOverrides.current == null) {
      HttpOverrides.global = _installed;
    }
    await refresh(force: true);
  }

  /// Refresh the Android system proxy without replacing already-created
  /// HttpClients. The findProxy callback reads the mutable values below, so a
  /// VPN/proxy enabled after app startup is picked up by subsequent requests.
  /// A short throttle avoids a platform-channel round trip for every streamed
  /// token while still reacting quickly to a network toggle.
  static Future<void> refresh({bool force = false}) async {
    if (kIsWeb || !Platform.isAndroid) return;
    final override = _installed;
    if (override == null) return;
    final now = DateTime.now();
    final last = _lastRefresh;
    if (!force &&
        last != null &&
        now.difference(last) < const Duration(seconds: 5)) {
      return;
    }
    final active = _refreshing;
    if (active != null) return active;
    final future = _refreshInternal(override);
    _refreshing = future;
    try {
      await future;
    } finally {
      if (identical(_refreshing, future)) _refreshing = null;
    }
  }

  /// Resolve a PAC/system-proxy route for an arbitrary request host. Android
  /// exposes PAC evaluation through ProxySelector, but Dart's synchronous
  /// `findProxy` callback cannot call a platform channel. Resolve the route
  /// immediately before constructing each request client and cache it briefly.
  static Future<void> refreshFor(Uri target, {bool force = false}) async {
    if (kIsWeb || !Platform.isAndroid) return;
    final override = _installed;
    final host = target.host.trim().toLowerCase();
    if (override == null || host.isEmpty || _isLoopbackHost(host)) return;
    final now = DateTime.now();
    final last = _routeRefreshes[host];
    if (!force &&
        last != null &&
        now.difference(last) < const Duration(seconds: 5)) {
      return;
    }
    final active = _routeRefreshInFlight[host];
    if (active != null) return active;
    final future = _refreshForInternal(override, target, host);
    _routeRefreshInFlight[host] = future;
    try {
      await future;
    } finally {
      if (identical(_routeRefreshInFlight[host], future)) {
        _routeRefreshInFlight.remove(host);
      }
    }
  }

  static Future<void> _refreshForInternal(
    _SystemProxyOverrides override,
    Uri target,
    String host,
  ) async {
    try {
      final raw = await _channel.invokeMethod<Object?>(
        'getSystemProxyForUrl',
        <String, dynamic>{'url': target.toString()},
      ).timeout(const Duration(seconds: 2));
      final route = _ProxyRoute.fromMap(raw) ?? const _ProxyRoute.direct();
      override.setRoute(host, route);
      _routeRefreshes[host] = DateTime.now();
    } on MissingPluginException {
      // Older builds do not expose per-host PAC evaluation; retain the
      // process-wide route obtained by `refresh()`.
    } on PlatformException {
      // A proxy lookup failure must never block an AI request.
    } on FlutterError {
      // Keep the last known route when the platform channel is unavailable.
    } on TimeoutException {
      // Full-device TUN VPNs still route direct sockets automatically.
    } on Object {
      // A malformed platform result must not escape into the startup future.
      // Keep the last known route and let the request proceed directly.
    }
  }

  static Future<void> _refreshInternal(_SystemProxyOverrides override) async {
    try {
      final raw = await _channel
          .invokeMethod<Object?>('getSystemProxy')
          .timeout(const Duration(seconds: 2));
      final map = raw is Map ? Map<String, dynamic>.from(raw) : null;
      final host = map?['host']?.toString().trim() ?? '';
      final port = _asInt(map?['port']);
      final exclusions = (map?['exclusionList'] is List)
          ? (map!['exclusionList'] as List)
              .map((value) => value.toString())
              .toList(growable: false)
          : const <String>[];
      final routes = <String, _ProxyRoute>{};
      final rawRoutes = map?['routes'];
      if (rawRoutes is Map) {
        for (final entry in rawRoutes.entries) {
          final target = entry.key.toString().trim().toLowerCase();
          final route = _ProxyRoute.fromMap(entry.value);
          if (target.isNotEmpty && route != null) routes[target] = route;
        }
      }
      final hasDefault =
          host.isNotEmpty && port != null && port > 0 && port <= 65535;
      if (!hasDefault && routes.isEmpty) {
        // No system HTTP proxy is different from a failed query. Clear only
        // after a successful platform response; a transient channel timeout
        // keeps the last known proxy for the in-flight request.
        override.clear();
      } else {
        override.update(
          hasDefault ? host : '',
          hasDefault ? port : 0,
          exclusions,
          routes: routes,
        );
      }
      _lastRefresh = DateTime.now();
    } on MissingPluginException {
      // Desktop, widget tests, and older builds without the bridge use direct
      // sockets as before.
    } on PlatformException {
      // A missing/unsupported Android proxy must never block app startup.
    } on FlutterError {
      // Keep the last known route when the platform channel is unavailable.
    } on TimeoutException {
      // Do not delay a request when a platform implementation is slow or
      // unavailable; a system TUN VPN still applies to direct sockets.
    } on Object {
      // Older ROMs and vendor VPNs occasionally return a non-standard value.
      // Treat it as an unavailable proxy instead of crashing the caller.
    }
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static bool _isLoopbackHost(String host) =>
      host == 'localhost' ||
      host == '::1' ||
      host == '0:0:0:0:0:0:0:1' ||
      host == '127.0.0.1' ||
      host.startsWith('127.');

  @visibleForTesting
  static String findProxyForTest(
    Uri uri, {
    required String host,
    required int port,
    Iterable<String> exclusions = const [],
    Map<String, Map<String, dynamic>> routes = const {},
  }) =>
      _SystemProxyOverrides(
        host,
        port,
        exclusions,
        {
          for (final entry in routes.entries)
            entry.key.toLowerCase(): _ProxyRoute.fromMap(entry.value)!,
        },
      ).findProxy(uri);
}

class _SystemProxyOverrides extends HttpOverrides {
  String host;
  int port;
  List<String> exclusions;
  Map<String, _ProxyRoute> routes;

  _SystemProxyOverrides([
    this.host = '',
    this.port = 0,
    Iterable<String> exclusions = const [],
    Map<String, _ProxyRoute> routes = const {},
  ])  : routes = Map<String, _ProxyRoute>.unmodifiable(routes),
        exclusions = [
          for (final value in exclusions)
            if (value.trim().isNotEmpty) value.trim().toLowerCase(),
        ];

  void update(
    String nextHost,
    int nextPort,
    Iterable<String> nextExclusions, {
    Map<String, _ProxyRoute> routes = const {},
  }) {
    host = nextHost.trim();
    port = nextPort;
    exclusions = [
      for (final value in nextExclusions)
        if (value.trim().isNotEmpty) value.trim().toLowerCase(),
    ];
    this.routes = Map<String, _ProxyRoute>.unmodifiable(routes);
  }

  void clear() {
    host = '';
    port = 0;
    exclusions = const [];
    routes = const {};
    SystemNetworkProxy._routeRefreshes.clear();
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = findProxy;
    return client;
  }

  String findProxy(Uri uri) {
    final target = uri.host.trim().toLowerCase();
    if (_isLoopback(target) || _isExcluded(target)) return 'DIRECT';
    final route = _routeFor(target);
    return route?.asProxyString() ?? 'DIRECT';
  }

  _ProxyRoute? _routeFor(String target) {
    final exact = routes[target];
    if (exact != null) return exact;
    for (final entry in routes.entries) {
      final pattern = entry.key;
      if (pattern.startsWith('*.') &&
          (target == pattern.substring(2) ||
              target.endsWith(pattern.substring(1)))) {
        return entry.value;
      }
      if (pattern.startsWith('.') && target.endsWith(pattern)) {
        return entry.value;
      }
    }
    if (host.isEmpty || port <= 0 || port > 65535) return null;
    return _ProxyRoute(host: host, port: port, type: 'http');
  }

  void setRoute(String target, _ProxyRoute route) {
    final next = Map<String, _ProxyRoute>.from(routes);
    next[target.trim().toLowerCase()] = route;
    routes = Map<String, _ProxyRoute>.unmodifiable(next);
  }

  bool _isExcluded(String target) {
    for (final raw in exclusions) {
      final pattern = raw.trim();
      if (pattern.isEmpty) continue;
      if (pattern == '*' || pattern == target) return true;
      if (pattern.startsWith('*.') &&
          (target == pattern.substring(2) ||
              target.endsWith(pattern.substring(1)))) {
        return true;
      }
      if (pattern.startsWith('.') && target.endsWith(pattern)) return true;
    }
    return false;
  }

  static bool _isLoopback(String host) =>
      host == 'localhost' ||
      host == '::1' ||
      host == '0:0:0:0:0:0:0:1' ||
      host == '127.0.0.1' ||
      host.startsWith('127.');
}

class _ProxyRoute {
  final String host;
  final int port;
  final String type;

  const _ProxyRoute(
      {required this.host, required this.port, this.type = 'http'});

  const _ProxyRoute.direct()
      : host = '',
        port = 0,
        type = 'direct';

  static _ProxyRoute? fromMap(Object? value) {
    if (value is! Map) return null;
    final rawType = value['type']?.toString().trim().toLowerCase() ?? 'http';
    if (rawType == 'direct' || rawType == 'none') {
      return const _ProxyRoute.direct();
    }
    final host = value['host']?.toString().trim() ?? '';
    final rawPort = value['port'];
    final port = rawPort is num
        ? rawPort.toInt()
        : int.tryParse(rawPort?.toString() ?? '');
    if (host.isEmpty || port == null || port <= 0 || port > 65535) {
      return null;
    }
    final type = rawType == 'socks' ? 'socks' : 'http';
    return _ProxyRoute(host: host, port: port, type: type);
  }

  String asProxyString() {
    if (type == 'direct') return 'DIRECT';
    final endpoint = host.contains(':') && !host.startsWith('[')
        ? '[$host]:$port'
        : '$host:$port';
    return type == 'socks' ? 'SOCKS $endpoint' : 'PROXY $endpoint';
  }
}
