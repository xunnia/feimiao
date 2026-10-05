/// Only append provider-public summary deltas, never inferred/local steps.
/// Keeps paragraph boundaries and the beginning instead of a 420-char tail.
class PublicReasoningSummary {
  static const maxCharacters = 65536;
  final StringBuffer _buffer = StringBuffer();
  bool truncated = false;
  String get text => _buffer.toString();

  bool append(String delta) {
    if (delta.isEmpty) return false;
    final remaining = maxCharacters - _buffer.length;
    if (remaining <= 0) {
      truncated = true;
      return false;
    }
    var end = delta.length > remaining ? remaining : delta.length;
    // Do not split an emoji/supplementary-plane scalar at the storage limit.
    if (end < delta.length &&
        end > 0 &&
        delta.codeUnitAt(end - 1) >= 0xD800 &&
        delta.codeUnitAt(end - 1) <= 0xDBFF) {
      end--;
    }
    _buffer.write(delta.substring(0, end));
    truncated |= end < delta.length;
    return end > 0;
  }
}
