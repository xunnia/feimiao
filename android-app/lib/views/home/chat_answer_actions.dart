import 'package:flutter/material.dart';

class ChatAnswerActions extends StatelessWidget {
  final List<Widget> actions;
  final Widget? source;
  final String sourceLabel;
  final double actionExtent;
  const ChatAnswerActions(
      {super.key,
      required this.actions,
      this.source,
      this.sourceLabel = '',
      this.actionExtent = 36});

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, bounds) {
        if (source == null) return Wrap(children: actions);
        final text = TextPainter(
            text: TextSpan(
                text: sourceLabel, style: const TextStyle(fontSize: 12.5)),
            textScaler: MediaQuery.textScalerOf(context),
            textDirection: Directionality.of(context))
          ..layout();
        final sourceWidth = text.width + 48;
        text.dispose();
        if (actions.length * actionExtent + sourceWidth <= bounds.maxWidth) {
          return Row(children: [...actions, const Spacer(), source!]);
        }
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(children: actions),
              Align(alignment: Alignment.centerRight, child: source!),
            ]);
      });
}
