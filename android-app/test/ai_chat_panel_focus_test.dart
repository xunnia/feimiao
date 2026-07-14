import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/views/home/ai_chat_panel.dart';
import 'package:qingji/views/home/manual_add_sheet.dart';
import 'package:qingji/views/home/record_entry_sheet.dart';
import 'package:qingji/views/home/record_input_bar.dart';
import 'package:qingji/widgets/glass.dart';

void main() {
  testWidgets('AI input keeps the same focus after user tap', (tester) async {
    final repo = AppRepository();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repo,
        child: MaterialApp(
          home: Scaffold(body: AiChatPanel(onSwitchToManual: () {})),
        ),
      ),
    );
    await tester.pump();

    final fieldFinder = find.byKey(const ValueKey('ai-chat-input-field'));
    expect(fieldFinder, findsOneWidget);

    await tester.tap(fieldFinder);
    await tester.pump();

    final field = tester.widget<TextField>(fieldFinder);
    expect(field.focusNode?.hasFocus, isTrue);
    expect(
      tester.testTextInput.isVisible,
      isTrue,
      reason: tester.testTextInput.log.map((call) => call.method).join(', '),
    );

    await tester.pump(const Duration(milliseconds: 240));

    final settledField = tester.widget<TextField>(fieldFinder);
    expect(settledField.focusNode, same(field.focusNode));
    expect(settledField.focusNode?.hasFocus, isTrue);
    expect(
      tester.testTextInput.isVisible,
      isTrue,
      reason: tester.testTextInput.log.map((call) => call.method).join(', '),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('AI input does not force extra IME show calls after user tap', (
    tester,
  ) async {
    final repo = AppRepository();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repo,
        child: MaterialApp(
          home: Scaffold(body: AiChatPanel(onSwitchToManual: () {})),
        ),
      ),
    );
    await tester.pump();

    final fieldFinder = find.byKey(const ValueKey('ai-chat-input-field'));
    await tester.tap(fieldFinder);
    await tester.pump();

    final field = tester.widget<TextField>(fieldFinder);
    expect(field.focusNode?.hasFocus, isTrue);
    expect(
      tester.testTextInput.isVisible,
      isTrue,
      reason: tester.testTextInput.log.map((call) => call.method).join(', '),
    );

    final showCallsAfterTap = tester.testTextInput.log
        .where((call) => call.method == 'TextInput.show')
        .length;
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();

    final settledField = tester.widget<TextField>(fieldFinder);
    expect(settledField.focusNode, same(field.focusNode));
    expect(settledField.focusNode?.hasFocus, isTrue);
    expect(
      tester.testTextInput.isVisible,
      isTrue,
      reason: tester.testTextInput.log.map((call) => call.method).join(', '),
    );
    expect(
      tester.testTextInput.log
          .where((call) => call.method == 'TextInput.show')
          .length,
      showCallsAfterTap,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('AI empty input keeps focus while keyboard inset changes', (
    tester,
  ) async {
    final repo = AppRepository();

    Widget build(double bottomInset) {
      return ChangeNotifierProvider<AppRepository>.value(
        value: repo,
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              viewInsets: EdgeInsets.only(bottom: bottomInset),
            ),
            child: AiChatPanel(onSwitchToManual: () {}),
          ),
        ),
      );
    }

    await tester.pumpWidget(build(0));
    await tester.pump();

    final fieldFinder = find.byKey(const ValueKey('ai-chat-input-field'));
    await tester.tap(fieldFinder);
    await tester.pump();

    final field = tester.widget<TextField>(fieldFinder);
    expect(field.focusNode?.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.pumpWidget(build(340));
    await tester.pump(const Duration(milliseconds: 180));

    final liftedField = tester.widget<TextField>(fieldFinder);
    expect(liftedField.focusNode, same(field.focusNode));
    expect(liftedField.focusNode?.hasFocus, isTrue);
    expect(
      tester.testTextInput.isVisible,
      isTrue,
      reason: tester.testTextInput.log.map((call) => call.method).join(', '),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('AI input respects system keyboard dismissal after startup', (
    tester,
  ) async {
    final repo = AppRepository();

    Widget build(double bottomInset) {
      return ChangeNotifierProvider<AppRepository>.value(
        value: repo,
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              viewInsets: EdgeInsets.only(bottom: bottomInset),
            ),
            child: AiChatPanel(onSwitchToManual: () {}),
          ),
        ),
      );
    }

    await tester.pumpWidget(build(0));
    await tester.pump();

    final fieldFinder = find.byKey(const ValueKey('ai-chat-input-field'));
    await tester.tap(fieldFinder);
    await tester.pump();

    final field = tester.widget<TextField>(fieldFinder);
    final focusNode = field.focusNode!;
    expect(focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.pumpWidget(build(320));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    tester.testTextInput.hide();
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.pumpWidget(build(0));
    await tester.pump(const Duration(milliseconds: 140));
    await tester.pump();

    final dismissedField = tester.widget<TextField>(fieldFinder);
    expect(dismissedField.focusNode, same(focusNode));
    expect(dismissedField.focusNode?.hasFocus, isFalse);
    expect(
      tester.testTextInput.isVisible,
      isFalse,
      reason: tester.testTextInput.log.map((call) => call.method).join(', '),
    );

    await tester.tap(fieldFinder);
    await tester.pump();
    final refocusedField = tester.widget<TextField>(fieldFinder);
    expect(refocusedField.focusNode, same(focusNode));
    expect(refocusedField.focusNode?.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  testWidgets('AI input does not drop focus during prolonged IME startup', (
    tester,
  ) async {
    final repo = AppRepository();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repo,
        child: MaterialApp(
          home: Scaffold(body: AiChatPanel(onSwitchToManual: () {})),
        ),
      ),
    );
    await tester.pump();

    final fieldFinder = find.byKey(const ValueKey('ai-chat-input-field'));
    await tester.tap(fieldFinder);
    await tester.pump();

    final field = tester.widget<TextField>(fieldFinder);
    final focusNode = field.focusNode!;
    var sawFocusLoss = false;
    void listener() {
      if (!focusNode.hasFocus) sawFocusLoss = true;
    }

    focusNode.addListener(listener);
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();
    focusNode.removeListener(listener);

    expect(sawFocusLoss, isFalse);
    expect(focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('AI input keeps keyboard dismissed after a delayed system close',
      (
    tester,
  ) async {
    final repo = AppRepository();

    Widget build(double bottomInset) {
      return ChangeNotifierProvider<AppRepository>.value(
        value: repo,
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              viewInsets: EdgeInsets.only(bottom: bottomInset),
            ),
            child: AiChatPanel(onSwitchToManual: () {}),
          ),
        ),
      );
    }

    await tester.pumpWidget(build(0));
    await tester.pump();

    final fieldFinder = find.byKey(const ValueKey('ai-chat-input-field'));
    await tester.tap(fieldFinder);
    await tester.pump();

    final field = tester.widget<TextField>(fieldFinder);
    final focusNode = field.focusNode!;
    expect(focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.pumpWidget(build(320));
    await tester.pump(const Duration(seconds: 3));
    expect(focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    tester.testTextInput.hide();
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.pumpWidget(build(0));
    await tester.pump(const Duration(milliseconds: 140));
    await tester.pump();

    final dismissedField = tester.widget<TextField>(fieldFinder);
    expect(dismissedField.focusNode, same(focusNode));
    expect(dismissedField.focusNode?.hasFocus, isFalse);
    expect(
      tester.testTextInput.isVisible,
      isFalse,
      reason: tester.testTextInput.log.map((call) => call.method).join(', '),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  testWidgets('AI input keeps focus when Android drops it after tap', (
    tester,
  ) async {
    final repo = AppRepository();
    final otherFocus = FocusNode();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repo,
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(child: AiChatPanel(onSwitchToManual: () {})),
                SizedBox(
                  width: 1,
                  height: 1,
                  child: TextField(focusNode: otherFocus),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final fieldFinder = find.byKey(const ValueKey('ai-chat-input-field'));
    await tester.tap(fieldFinder);
    await tester.pump();

    final field = tester.widget<TextField>(fieldFinder);
    expect(field.focusNode?.hasFocus, isTrue);

    otherFocus.requestFocus();
    tester.testTextInput.hide();

    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump();

    final restoredField = tester.widget<TextField>(fieldFinder);
    expect(restoredField.focusNode, same(field.focusNode));
    expect(restoredField.focusNode?.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    otherFocus.dispose();
  });

  testWidgets('AI entry sheet keeps keyboard visible after auto focus', (
    tester,
  ) async {
    final repo = AppRepository();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repo,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                key: const ValueKey('open-ai-entry-sheet'),
                onPressed: () => showRecordEntrySheet(
                  context,
                  initialMode: RecordEntryMode.ai,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-ai-entry-sheet')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 380));

    final fieldFinder = find.byKey(const ValueKey('ai-chat-input-field'));
    expect(fieldFinder, findsOneWidget);
    final field = tester.widget<TextField>(fieldFinder);
    expect(field.focusNode?.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('AI entry sheet does not swap input blur after focus settles', (
    tester,
  ) async {
    final repo = AppRepository();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repo,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                key: const ValueKey('open-ai-entry-sheet'),
                onPressed: () => showRecordEntrySheet(
                  context,
                  initialMode: RecordEntryMode.ai,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-ai-entry-sheet')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 380));

    final fieldFinder = find.byKey(const ValueKey('ai-chat-input-field'));
    expect(fieldFinder, findsOneWidget);
    final field = tester.widget<TextField>(fieldFinder);
    final inputGlass =
        tester.widgetList<GlassSurface>(find.byType(GlassSurface)).singleWhere(
              (surface) =>
                  surface.radius == 28 &&
                  surface.padding == const EdgeInsets.fromLTRB(14, 12, 10, 10),
            );
    final initialBlur = inputGlass.blur;

    await tester.pump(const Duration(milliseconds: 4200));
    await tester.pump();

    final settledField = tester.widget<TextField>(fieldFinder);
    final settledGlass =
        tester.widgetList<GlassSurface>(find.byType(GlassSurface)).singleWhere(
              (surface) =>
                  surface.radius == 28 &&
                  surface.padding == const EdgeInsets.fromLTRB(14, 12, 10, 10),
            );
    expect(settledGlass.blur, initialBlur);
    expect(settledField.focusNode, same(field.focusNode));
    expect(settledField.focusNode?.hasFocus, isTrue);
    expect(
      tester.testTextInput.isVisible,
      isTrue,
      reason: tester.testTextInput.log.map((call) => call.method).join(', '),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('home record input is hidden while entry sheet is open', (
    tester,
  ) async {
    final repo = AppRepository();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repo,
        child: const MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: RecordInputBar(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('home-record-input-shell')),
      findsOneWidget,
    );

    await tester.tap(find.text('记一记'));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('home-record-input-hidden')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('home-record-input-shell')), findsNothing);

    await tester.pump(const Duration(milliseconds: 380));
    expect(find.byType(ManualAddSheet), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
