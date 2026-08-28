import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qingji/core/ai/chat_session.dart';
import 'package:qingji/data/app_repository.dart';
import 'package:qingji/theme/app_colors.dart';
import 'package:qingji/views/assistant/meow_assistant_view.dart';
import 'package:qingji/widgets/app_line_icon.dart';
import 'package:qingji/widgets/ios_menu.dart';

import 'screenshot_font_support.dart';

class _ChatsRepository extends AppRepository {
  _ChatsRepository(this._sessions);

  final List<ChatSession> _sessions;

  @override
  List<ChatSession> get chatSessions => List.unmodifiable(_sessions);

  @override
  Future<List<ChatSession>> loadChatSessions() async => chatSessions;

  @override
  Future<void> setChatSessionStarred(String sessionId, bool starred) async {
    final index = _sessions.indexWhere((session) => session.id == sessionId);
    if (index < 0 || _sessions[index].isRecord) return;
    _sessions[index] = _sessions[index].copyWith(starred: starred);
    notifyListeners();
  }
}

const _now = 1760000000000;

ChatSession _record() => ChatSession(
      id: ChatSession.recordId,
      title: ChatSession.recordTitle,
      createdAt: DateTime.fromMillisecondsSinceEpoch(_now),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(_now),
      isRecord: true,
    );

ChatSession _chat(String id, String title, {bool starred = false}) =>
    ChatSession(
      id: id,
      title: title,
      createdAt: DateTime.fromMillisecondsSinceEpoch(_now),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(_now),
      starred: starred,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadScreenshotFonts);

  Future<void> pumpChats(
    WidgetTester tester,
    _ChatsRepository repository,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider<AppRepository>.value(
        value: repository,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: DecoratedBox(
            key: const ValueKey('chats-test-root'),
            decoration: AppColors.pageBackground(Brightness.light),
            child: const MeowAssistantView(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('Chats 固定置顶记一记，并保留 Claude 式底部新聊天和搜索', (tester) async {
    final repository = _ChatsRepository([
      _record(),
      _chat('alpha', 'Claude 模型咨询'),
      _chat('beta', '预算怎么设置'),
    ]);
    await pumpChats(tester, repository);

    if (Platform.environment['UPDATE_CHATS_SCREENSHOTS'] == '1') {
      await expectLater(
        find.byKey(const ValueKey('chats-test-root')),
        matchesGoldenFile('../outputs/chats/chats_current.png'),
      );
    }

    expect(find.text('Chats'), findsOneWidget);
    final chatsTitle = tester.widget<Text>(find.text('Chats'));
    expect(chatsTitle.style?.fontSize, 19);
    expect(chatsTitle.style?.fontWeight, FontWeight.w400);
    expect(find.byKey(const ValueKey('chat-session-card-record')), findsOne);
    expect(find.byKey(const ValueKey('chat-session-card-alpha')), findsOne);
    expect(find.byKey(const ValueKey('chat-new-button')), findsOne);
    expect(find.byKey(const ValueKey('chat-search-field')), findsOne);

    final recordRect = tester.getRect(
      find.byKey(const ValueKey('chat-session-card-record')),
    );
    final alphaRect = tester.getRect(
      find.byKey(const ValueKey('chat-session-card-alpha')),
    );
    expect(recordRect.top, lessThan(alphaRect.top));
    final sessionTitle = tester.widget<Text>(find.text('Claude 模型咨询'));
    expect(sessionTitle.style?.fontSize, 14);
    expect(sessionTitle.style?.fontWeight, FontWeight.w400);

    final newChatRect = tester.getRect(
      find.byKey(const ValueKey('chat-new-button')),
    );
    final searchRect = tester.getRect(
      find.byKey(const ValueKey('chat-search-field')),
    );
    expect(newChatRect.bottom, lessThan(searchRect.top));
    expect(searchRect.height, 38);
    expect(searchRect.width, closeTo(342, 0.1));
  });

  testWidgets('搜索按标题筛选，加星视图仍保留记一记', (tester) async {
    final repository = _ChatsRepository([
      _record(),
      _chat('alpha', 'Claude 模型咨询'),
      _chat('beta', '预算怎么设置'),
    ]);
    await pumpChats(tester, repository);

    await tester.enterText(
      find.byKey(const ValueKey('chat-search-input')),
      'Claude',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('chat-session-card-alpha')), findsOne);
    expect(find.byKey(const ValueKey('chat-session-card-beta')), findsNothing);
    expect(
        find.byKey(const ValueKey('chat-session-card-record')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('chat-search-input')),
      '',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('筛选会话'));
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text('全部会话'), findsOneWidget);
    expect(find.text('加星'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('全部会话')).style?.fontWeight,
      FontWeight.w400,
    );
    final menuRect = tester.getRect(
      find.byKey(const ValueKey('chat-filter-menu')),
    );
    final filterButtonRect = tester.getRect(
      find.byTooltip('筛选会话'),
    );
    expect(menuRect.top, closeTo(filterButtonRect.top, 2));
    final checkRect = tester.getRect(
      find.byKey(const ValueKey('chat-filter-check-全部会话')),
    );
    final iconRect = tester.getRect(find.byIcon(CupertinoIcons.chat_bubble_2));
    expect(checkRect.left, lessThan(iconRect.left));
    await tester.tap(find.text('加星'));
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.byKey(const ValueKey('chat-session-card-record')), findsOne);
    expect(find.byKey(const ValueKey('chat-session-card-alpha')), findsNothing);
    expect(find.byKey(const ValueKey('chat-session-card-beta')), findsNothing);
  });

  testWidgets('搜索输入态只保留搜索栏和独立关闭按钮', (tester) async {
    final repository = _ChatsRepository([
      _record(),
      _chat('alpha', 'Claude 模型咨询'),
    ]);
    await pumpChats(tester, repository);

    await tester.tap(find.byKey(const ValueKey('chat-search-input')));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    expect(find.byKey(const ValueKey('chat-new-button')), findsNothing);
    expect(find.byKey(const ValueKey('chat-search-close-button')), findsOne);
    expect(
      tester
          .getRect(find.byKey(const ValueKey('chat-search-close-button')))
          .size,
      const Size(38, 38),
    );

    await tester.enterText(
      find.byKey(const ValueKey('chat-search-input')),
      'Claude',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('chat-session-card-alpha')), findsOne);

    await tester.tap(find.byKey(const ValueKey('chat-search-close-button')));
    await tester.pump();
    expect(find.byKey(const ValueKey('chat-new-button')), findsOne);
    expect(
        find.byKey(const ValueKey('chat-search-close-button')), findsNothing);
    expect(find.byKey(const ValueKey('chat-session-card-record')), findsOne);
  });

  testWidgets('长按普通会话高亮并只提供加星、重命名和删除', (tester) async {
    final repository = _ChatsRepository([
      _record(),
      _chat('alpha', 'Claude 模型咨询'),
    ]);
    await pumpChats(tester, repository);

    await tester.longPress(
      find.byKey(const ValueKey('chat-session-card-alpha')),
    );
    await tester.pump(const Duration(milliseconds: 220));

    final cardRect = tester.getRect(
      find.byKey(const ValueKey('chat-session-card-alpha')),
    );
    final menuRect = tester.getRect(
      find.byKey(const ValueKey('unified-ios-menu-card')),
    );
    expect(menuRect.top, greaterThan(cardRect.bottom));
    expect(menuRect.top, closeTo(cardRect.bottom + 4, 3));

    expect(find.text('加星'), findsOneWidget);
    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('重命名')).style?.fontWeight,
      FontWeight.w400,
    );
    expect(find.text('添加到项目'), findsNothing);

    final unifiedMenu = find.byKey(
      const ValueKey('unified-ios-menu-card'),
    );
    expect(find.byType(AppMenuScrim), findsOneWidget);
    expect(
      find.descendant(of: unifiedMenu, matching: find.byType(AppLineIcon)),
      findsNWidgets(3),
    );
    expect(
      find.descendant(of: unifiedMenu, matching: find.byType(Divider)),
      findsNothing,
    );

    final surface = tester.widget<Container>(
      find.byKey(const ValueKey('chat-session-surface-alpha')),
    );
    final decoration = surface.decoration! as BoxDecoration;
    expect(
        decoration.color, AppColors.selectedCard(AppTheme.light().colorScheme));
    final selectedScale = tester.widget<AnimatedScale>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('chat-session-surface-alpha')),
            matching: find.byType(AnimatedScale),
          )
          .first,
    );
    expect(selectedScale.scale, 1.025);

    await tester.tap(find.text('加星'));
    await tester.pump(const Duration(milliseconds: 220));
    expect(
        repository.chatSessions
            .singleWhere((item) => item.id == 'alpha')
            .starred,
        isTrue);

    await tester.longPress(
      find.byKey(const ValueKey('chat-session-card-record')),
    );
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text('重命名'), findsNothing);
    expect(find.text('删除'), findsNothing);
  });
}
