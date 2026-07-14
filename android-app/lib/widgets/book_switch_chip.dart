import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import 'glass.dart';
import 'pressable_scale.dart';

class AppBookSwitchChip extends StatelessWidget {
  final String iconText;
  final String label;
  final VoidCallback onPressed;
  final double maxLabelWidth;

  const AppBookSwitchChip({
    super.key,
    required this.iconText,
    required this.label,
    required this.onPressed,
    this.maxLabelWidth = 120,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressableScale(
      onPressed: onPressed,
      child: GlassSurface(
        radius: 18,
        blur: 0,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: SizedBox(
          height: 36,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(iconText, style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 5),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxLabelWidth),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurface,
                      ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                CupertinoIcons.chevron_down,
                size: 14,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
