import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/widgets/repository_data_gate.dart';

class PendingRepository extends AppRepository {
  bool pending = true;
  @override
  bool get isHydrating => pending;
}

void main() {
  testWidgets('partial history is not rendered as an empty page',
      (tester) async {
    final repo = PendingRepository();
    var builds = 0;
    await tester.pumpWidget(ChangeNotifierProvider<AppRepository>.value(
      value: repo,
      child: MaterialApp(home: Scaffold(body: RepositoryDataGate(builder: (_) {
        builds++;
        return const Text('完整历史');
      }))),
    ));
    expect(builds, 0);
    expect(find.text('正在加载历史账本…'), findsOneWidget);
    repo.pending = false;
    repo.notifyListeners();
    await tester.pump();
    expect(find.text('完整历史'), findsOneWidget);
    expect(builds, 1);
    await tester.pumpWidget(const SizedBox());
    repo.dispose();
  });
}
