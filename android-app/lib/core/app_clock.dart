/// Clock used by date-sensitive UI and deterministic parity captures.
///
/// Normal builds always use the device clock. The parity driver supplies
/// QINGJI_PARITY_CAPTURE and QINGJI_DEMO_NOW at compile time so both apps use
/// the same logical "today" without changing production behaviour.
class AppClock {
  AppClock._();

  static const bool _parityCapture =
      bool.fromEnvironment('QINGJI_PARITY_CAPTURE');
  static const String _demoNowRaw = String.fromEnvironment('QINGJI_DEMO_NOW');
  static final DateTime? _demoNow = parseDemoNow(_demoNowRaw);

  static DateTime get now =>
      _parityCapture && _demoNow != null ? _demoNow! : DateTime.now();

  static DateTime? parseDemoNow(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    try {
      return DateTime.parse(value).toLocal();
    } on FormatException {
      return null;
    }
  }
}
