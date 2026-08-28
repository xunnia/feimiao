import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all compact option menus use the shared Claude/iOS surface', () {
    final forbidden = <RegExp>[
      RegExp(r'\bPopupMenuButton\s*(?:<|\()'),
      RegExp(r'\bPopupMenuItem\s*(?:<|\()'),
      RegExp(r'\bshowMenu\s*(?:<|\()'),
      RegExp(r'\bDropdownButton(?:FormField)?\s*(?:<|\()'),
      RegExp(r'\bDropdownMenu\s*(?:<|\()'),
      RegExp(r'\bSimpleDialog\s*\('),
      RegExp(r'\bCupertinoActionSheet\s*\('),
    ];
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        if (forbidden.any((pattern) => pattern.hasMatch(line))) {
          offenders.add('${entity.path}:${index + 1}: ${line.trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Compact option menus must use showIosMenu or the shared '
          'Claude model/Effort popup so the scrim, icon language, selection '
          'state and haptics cannot drift.\n${offenders.join('\n')}',
    );
  });
}
