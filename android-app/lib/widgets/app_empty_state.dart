import 'package:flutter/material.dart';

import 'mascot.dart';

class AppEmptyState extends StatelessWidget {
  final MascotMood mood;
  final String title;
  final String? message;
  final double mascotSize;

  const AppEmptyState({
    super.key,
    required this.title,
    this.message,
    this.mood = MascotMood.empty,
    this.mascotSize = 96,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Mascot(mood: mood, size: mascotSize, animate: true),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.titleMedium?.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: scheme.onSurface,
              ),
            ),
            if (message != null && message!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  height: 1.45,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.68),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
