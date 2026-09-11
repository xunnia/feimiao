import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/app_repository.dart';
import 'app_buttons.dart';

/// A partial startup snapshot must never be rendered as an empty full ledger.
class RepositoryDataGate extends StatelessWidget {
  final WidgetBuilder builder;
  const RepositoryDataGate({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository?>();
    if (repo == null ||
        (!repo.isHydrating && repo.initializationError == null)) {
      return builder(context);
    }
    final failed = repo.initializationError != null;
    return Material(
      color: Colors.transparent,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!failed) const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(failed ? '账本加载失败，请重试' : '正在加载历史账本…'),
          if (failed)
            AppPillButton(
                label: '重试',
                onPressed: () async {
                  try {
                    await repo.finishDeferredInitialization();
                  } catch (_) {
                    // Repository publishes its retryable failure state.
                  }
                }),
        ]),
      ),
    );
  }
}
