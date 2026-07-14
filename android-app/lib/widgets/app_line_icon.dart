import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Small Lucide-style line icons used where Material glyphs look too rigid.
/// Keep one stroke language for drawer navigation and compact tool actions.
class AppLineIconData {
  final String body;
  const AppLineIconData(this.body);
}

class AppLineIcon extends StatelessWidget {
  final AppLineIconData data;
  final double size;
  final Color? color;

  const AppLineIcon(
    this.data, {
    super.key,
    this.size = 22,
    this.color,
  });

  static const _header =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
      'fill="none" stroke="#000" stroke-width="1.8" '
      'stroke-linecap="round" stroke-linejoin="round">';

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return SvgPicture.string(
      '$_header${data.body}</svg>',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
    );
  }
}

abstract final class AppLineIcons {
  static const chart = AppLineIconData(
    '<path d="M4 19V9"/><path d="M10 19V5"/>'
    '<path d="M16 19v-7"/><path d="M22 19H2"/>',
  );
  static const wallet = AppLineIconData(
    '<path d="M19 7V5a2 2 0 0 0-2-2H5a4 4 0 0 0 0 8h15a1 1 0 0 1 1 1v5a2 2 0 0 1-2 2H5a4 4 0 0 1-4-4V7"/>'
    '<path d="M16 14h5"/>',
  );
  static const calendar = AppLineIconData(
    '<path d="M8 2v4M16 2v4"/>'
    '<rect width="18" height="18" x="3" y="4" rx="2"/>'
    '<path d="M3 10h18M8 14h.01M12 14h.01M16 14h.01M8 18h.01M12 18h.01"/>',
  );
  static const savings = AppLineIconData(
    '<circle cx="12" cy="12" r="9"/>'
    '<path d="M16 8h-6a2 2 0 1 0 0 4h4a2 2 0 1 1 0 4H8M12 6v12"/>',
  );
  static const sparkles = AppLineIconData(
    '<path d="m12 3-1.4 3.6L7 8l3.6 1.4L12 13l1.4-3.6L17 8l-3.6-1.4Z"/>'
    '<path d="m5 14-.9 2.1L2 17l2.1.9L5 20l.9-2.1L8 17l-2.1-.9Z"/>'
    '<path d="m19 13-.9 2.1L16 16l2.1.9L19 19l.9-2.1L22 16l-2.1-.9Z"/>',
  );
  static const grid = AppLineIconData(
    '<circle cx="7" cy="7" r="3"/><circle cx="17" cy="7" r="3"/>'
    '<circle cx="7" cy="17" r="3"/><circle cx="17" cy="17" r="3"/>',
  );
  static const tag = AppLineIconData(
    '<path d="M12.6 2.6A2 2 0 0 0 11.2 2H4a2 2 0 0 0-2 2v7.2a2 2 0 0 0 .6 1.4l8.7 8.7a2.4 2.4 0 0 0 3.4 0l6.6-6.6a2.4 2.4 0 0 0 0-3.4Z"/>'
    '<circle cx="7.5" cy="6.5" r=".7" fill="#000" stroke="none"/>',
  );
  static const importExport = AppLineIconData(
    '<path d="m7 7 3-3 3 3M10 4v12"/>'
    '<path d="m17 17-3 3-3-3M14 20V8"/>',
  );
  static const receipt = AppLineIconData(
    '<path d="M15 2H6a2 2 0 0 0-2 2v17l3-2 3 2 3-2 3 2 3-2V6Z"/>'
    '<path d="M8 7h6M8 11h8M8 15h5"/>',
  );
  static const calendarClock = AppLineIconData(
    '<path d="M8 2v4M16 2v4M3 10h18"/>'
    '<path d="M17 22a5 5 0 1 0 0-10 5 5 0 0 0 0 10Z"/>'
    '<path d="M17 14.5V17l1.5 1"/><path d="M13 4H5a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2h7"/>',
  );
  static const bell = AppLineIconData(
    '<path d="M10.3 21a2 2 0 0 0 3.4 0"/>'
    '<path d="M18 8a6 6 0 1 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9"/>'
    '<path d="M4 4 2.5 5.5M20 4l1.5 1.5"/>',
  );
  static const settings = AppLineIconData(
    '<path d="M12.2 2h-.4a2 2 0 0 0-2 2v.2a2 2 0 0 1-1 1.7l-.4.3a2 2 0 0 1-2 0l-.2-.1a2 2 0 0 0-2.7.7l-.2.4a2 2 0 0 0 .7 2.7l.2.1a2 2 0 0 1 1 1.7v.6a2 2 0 0 1-1 1.7l-.2.1a2 2 0 0 0-.7 2.7l.2.4a2 2 0 0 0 2.7.7l.2-.1a2 2 0 0 1 2 0l.4.3a2 2 0 0 1 1 1.7v.2a2 2 0 0 0 2 2h.4a2 2 0 0 0 2-2v-.2a2 2 0 0 1 1-1.7l.4-.3a2 2 0 0 1 2 0l.2.1a2 2 0 0 0 2.7-.7l.2-.4a2 2 0 0 0-.7-2.7l-.2-.1a2 2 0 0 1-1-1.7v-.6a2 2 0 0 1 1-1.7l.2-.1a2 2 0 0 0 .7-2.7l-.2-.4a2 2 0 0 0-2.7-.7l-.2.1a2 2 0 0 1-2 0l-.4-.3a2 2 0 0 1-1-1.7V4a2 2 0 0 0-2-2Z"/>'
    '<circle cx="12" cy="12" r="3"/>',
  );
  static const squarePen = AppLineIconData(
    '<path d="M12 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/>'
    '<path d="M18.4 2.6a1 1 0 0 1 3 3l-9 9a2 2 0 0 1-.9.5l-2.9.9a.5.5 0 0 1-.6-.6l.9-2.9a2 2 0 0 1 .5-.9Z"/>',
  );
}
