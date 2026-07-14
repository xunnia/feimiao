class ReportDocumentFormatter {
  ReportDocumentFormatter._();

  static String markdown(String title, String answer) {
    final trimmed = answer.trim();
    if (trimmed.startsWith('# ')) return trimmed;
    return '# $title\n\n$trimmed';
  }

  static String summary(String markdown) {
    final summaryLines = <String>[];
    var inLeadSection = false;
    for (final raw in markdown.split('\n')) {
      final line = raw.trim();
      if (RegExp(r'^##\s+(本月一句话|摘要)').hasMatch(line)) {
        inLeadSection = true;
        continue;
      }
      if (inLeadSection && RegExp(r'^#{1,6}\s+').hasMatch(line)) break;
      if (!inLeadSection || line.isEmpty || line.startsWith('|')) continue;
      final cleaned = line
          .replaceFirst(RegExp(r'^\s*[-*]\s+'), '')
          .replaceAll('**', '')
          .trim();
      if (cleaned.isNotEmpty) summaryLines.add(cleaned);
    }

    final cleanedLines = summaryLines.isNotEmpty ? summaryLines : <String>[];
    if (cleanedLines.isEmpty) {
      for (final raw in markdown.split('\n')) {
        final line = raw.trim();
        if (line.isEmpty || line.startsWith('|')) continue;
        if (RegExp(r'^#{1,6}\s+').hasMatch(line)) continue;
        final cleaned = line
            .replaceFirst(RegExp(r'^\s*#{1,6}\s+'), '')
            .replaceFirst(RegExp(r'^\s*[-*]\s+'), '')
            .replaceAll('**', '')
            .trim();
        if (cleaned.isNotEmpty) cleanedLines.add(cleaned);
      }
    }
    final cleaned = cleanedLines.join(' ');
    if (cleaned.length <= 160) return cleaned;
    return '${cleaned.substring(0, 160)}…';
  }
}
