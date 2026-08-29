import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels;
import 'package:provider/provider.dart';

import '../../core/ai/chat_session.dart';
import '../../core/haptics.dart';
import '../../data/app_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_line_icon.dart';
import '../../widgets/ios_dialogs.dart';
import '../../widgets/ios_form.dart';
import '../../widgets/ios_menu.dart';
import '../../widgets/mascot.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/app_page_route.dart';
import '../home/ai_chat_panel.dart';

/// Claude iOS 风格的 Chats 入口。
/// 「记一记」是主页唯一的记账会话；普通聊天会话可以独立保存标题、
/// 星标以及模型选择。详情页仍复用现有 AiChatPanel，避免两套聊天输入
/// 和隐私/报告逻辑分叉。
class MeowAssistantView extends StatefulWidget {
  /// Chats 左上角的菜单不是普通返回：它应回到主页并展开根抽屉。
  /// 由 [RootShell] 注入，独立使用该页面时则自然退回上一个页面。
  final VoidCallback? onOpenHomeDrawer;

  const MeowAssistantView({super.key, this.onOpenHomeDrawer});

  @override
  State<MeowAssistantView> createState() => _MeowAssistantViewState();
}

enum _ChatFilter { all, starred }

// 这两个小图标沿用抽屉的 Lucide 线性笔画，避免 Chats 顶栏混入厚重的
// Cupertino 字形；参考 Claude iOS 的菜单和筛选位置。
const _chatFilterIcon = AppLineIconData(
  '<path d="M4 5h16l-6.5 7.5v5l-3 1v-6Z"/>',
);

// Chats 的几何令牌按 Claude iOS 参考图单独维护：卡片不是主页那种满
// 胶囊，列表、浮层和底部搜索也使用不同的水平安全边距。
const _chatListInset = 18.0;
const _chatBottomInset = 24.0;
const _chatCardRadius = 18.0;
const _chatCardMinHeight = 68.0;
const _chatCardIconSize = 34.0;
const _chatCardGap = 8.0;

class _MeowAssistantViewState extends State<MeowAssistantView> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  _ChatFilter _filter = _ChatFilter.all;
  String _search = '';
  bool _loading = true;
  String? _actioningSessionId;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _searchFocus.addListener(_onSearchFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    _searchFocus
      ..removeListener(_onSearchFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final value = _searchController.text.trim();
    if (value == _search) return;
    setState(() => _search = value);
  }

  void _onSearchFocusChanged() {
    if (mounted) setState(() {});
  }

  bool get _isSearching =>
      _searchFocus.hasFocus || _searchController.text.trim().isNotEmpty;

  void _closeSearch() {
    _searchController.clear();
    _searchFocus.unfocus();
    FocusScope.of(context).unfocus();
  }

  Future<void> _load() async {
    final repo = context.read<AppRepository>();
    await repo.loadChatSessions();
    if (mounted) setState(() => _loading = false);
  }

  List<ChatSession> _visibleSessions(AppRepository repo) {
    final query = _search.toLowerCase();
    return repo.chatSessions.where((session) {
      if (_filter == _ChatFilter.starred &&
          !session.starred &&
          !session.isRecord) {
        return false;
      }
      if (query.isEmpty) return true;
      return session.title.toLowerCase().contains(query);
    }).toList(growable: false);
  }

  Future<void> _createChat() async {
    // 对齐 Claude：点「新聊天」马上进入空会话，不额外拦一道命名表单。
    // 需要命名时再长按使用「重命名」。
    final repo = context.read<AppRepository>();
    final session = await repo.createChatSession();
    if (!mounted) return;
    await _openSession(session);
  }

  Future<void> _openSession(ChatSession session) async {
    await Navigator.of(context).push<void>(
      AppPageRoute<void>(
        builder: (_) => AiChatPanel(
          fullScreen: true,
          recordOnly: session.isRecord,
          sessionId: session.id,
          onSwitchToManual: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
    // 普通会话发出新消息后会更新 updated_ms；回来时重新读库，确保最新
    // 会话立即排到前面，而不是等下一次进入 Chats 才刷新。
    if (!mounted) return;
    await context.read<AppRepository>().loadChatSessions();
    if (mounted) setState(() {});
  }

  void _openHomeDrawer() {
    final openDrawer = widget.onOpenHomeDrawer;
    Navigator.of(context).maybePop();
    // 页面退场后再启动根抽屉动画，避免抽屉短暂被当前页面遮住。
    WidgetsBinding.instance.addPostFrameCallback((_) => openDrawer?.call());
  }

  Future<void> _showFilter(BuildContext anchor) async {
    await showIosMenu(
        anchor,
        [
          IosMenuItem(
            key: const ValueKey('chat-filter-all'),
            icon: CupertinoIcons.chat_bubble_2,
            label: '全部会话',
            selected: _filter == _ChatFilter.all,
            onTap: () {
              if (mounted) setState(() => _filter = _ChatFilter.all);
            },
          ),
          IosMenuItem(
            key: const ValueKey('chat-filter-starred'),
            icon: CupertinoIcons.star,
            label: '加星',
            selected: _filter == _ChatFilter.starred,
            onTap: () {
              if (mounted) setState(() => _filter = _ChatFilter.starred);
            },
          ),
        ],
        width: 236,
        cardKey: const ValueKey('chat-filter-menu'),
        alignToAnchorTop: true);
  }

  Future<void> _showActions(
    ChatSession session,
    BuildContext anchor,
  ) async {
    if (session.isRecord) return;
    Haptics.medium();
    setState(() => _actioningSessionId = session.id);
    _SessionAction? action;
    await showIosMenu(
        anchor,
        [
          IosMenuItem(
            lineIcon: AppLineIcons.star,
            label: session.starred ? '取消加星' : '加星',
            onTap: () => action = _SessionAction.star,
          ),
          IosMenuItem(
            lineIcon: AppLineIcons.pencil,
            label: '重命名',
            onTap: () => action = _SessionAction.rename,
          ),
          IosMenuItem(
            lineIcon: AppLineIcons.trash,
            label: '删除',
            destructive: true,
            onTap: () => action = _SessionAction.delete,
          ),
        ],
        width: 236,
        alignToAnchorLeft: true,
        cardKey: const ValueKey('chat-session-actions-menu'));
    if (mounted) setState(() => _actioningSessionId = null);
    final selectedAction = action;
    if (!mounted || selectedAction == null) return;
    final repo = context.read<AppRepository>();
    switch (selectedAction) {
      case _SessionAction.star:
        await repo.setChatSessionStarred(session.id, !session.starred);
      case _SessionAction.rename:
        await _renameChat(session);
      case _SessionAction.delete:
        await _deleteChat(session);
    }
    if (mounted) setState(() {});
  }

  Future<void> _renameChat(ChatSession session) async {
    final controller = TextEditingController(text: session.title);
    final confirmed = await showIosFormDialog(
      context,
      title: '重命名',
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 40,
        decoration: iosInputDecoration(context, hint: '会话名称'),
      ),
    );
    final title = controller.text.trim();
    controller.dispose();
    if (!confirmed || title.isEmpty || !mounted) return;
    await context.read<AppRepository>().renameChatSession(session.id, title);
  }

  Future<void> _deleteChat(ChatSession session) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除会话？',
      message: '删除后，这个会话和其中的聊天记录都无法恢复。',
      confirmText: '删除',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await context.read<AppRepository>().deleteChatSession(session.id);
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final scheme = Theme.of(context).colorScheme;
    final sessions = _visibleSessions(repo);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    _chatListInset,
                    8,
                    _chatListInset,
                    12,
                  ),
                  child: Row(
                    children: [
                      Semantics(
                        button: true,
                        label: '打开抽屉',
                        child: Tooltip(
                          message: '打开抽屉',
                          child: AppDrawerButton(onPressed: _openHomeDrawer),
                        ),
                      ),
                      const Expanded(
                        child: Center(
                          child: Text(
                            'Chats',
                            style: TextStyle(
                              fontFamily: 'Nunito',
                              fontFamilyFallback: const ['NotoSansSC'],
                              fontSize: 19,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: '筛选会话',
                        child: Tooltip(
                          message: '筛选会话',
                          child: Builder(
                              builder: (anchor) => AppCircleButton.custom(
                                    iconWidget: AppLineIcon(
                                      _chatFilterIcon,
                                      size: 20,
                                      color: scheme.onSurface,
                                    ),
                                    size: 38,
                                    expandHitTarget: false,
                                    onPressed: () => _showFilter(anchor),
                                  )),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(
                          child: Mascot(mood: MascotMood.thinking, size: 72),
                        )
                      : sessions.isEmpty
                          ? _emptyState()
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(
                                _chatListInset,
                                4,
                                _chatListInset,
                                156,
                              ),
                              itemCount: sessions.length,
                              itemBuilder: (_, index) => Padding(
                                padding: const EdgeInsets.only(
                                  bottom: _chatCardGap,
                                ),
                                child: _SessionCard(
                                  session: sessions[index],
                                  selected:
                                      _actioningSessionId == sessions[index].id,
                                  onTap: () => _openSession(sessions[index]),
                                  onLongPressStart: (anchor) =>
                                      _showActions(sessions[index], anchor),
                                  scheme: scheme,
                                ),
                              ),
                            ),
                ),
              ],
            ),
            Positioned(
              left: _chatBottomInset,
              right: _chatBottomInset,
              bottom: 18,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!_isSearching) ...[
                    _NewChatButton(onPressed: _createChat),
                    const SizedBox(height: 22),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: _SearchField(
                          controller: _searchController,
                          focusNode: _searchFocus,
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        width: _isSearching ? 12 : 0,
                      ),
                      if (_isSearching)
                        _SearchCloseButton(onPressed: _closeSearch),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() => const Center(
        child: Padding(
          padding: EdgeInsets.only(bottom: 100),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Mascot(mood: MascotMood.idle, size: 84),
            ],
          ),
        ),
      );
}

enum _SessionAction { star, rename, delete }

class _SessionCard extends StatelessWidget {
  final ChatSession session;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<BuildContext> onLongPressStart;
  final ColorScheme scheme;

  const _SessionCard({
    required this.session,
    required this.selected,
    required this.onTap,
    required this.onLongPressStart,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = _relativeDate(session.updatedAt);
    return Builder(
      builder: (cardContext) => PressableScale(
        key: ValueKey('chat-session-card-${session.id}'),
        onPressed: onTap,
        child: GestureDetector(
          onLongPressStart: (_) {
            onLongPressStart(cardContext);
          },
          child: AnimatedScale(
            scale: selected ? 1.025 : 1,
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOutBack,
            child: Container(
              key: ValueKey('chat-session-surface-${session.id}'),
              constraints: const BoxConstraints(minHeight: _chatCardMinHeight),
              padding: const EdgeInsets.fromLTRB(16, 8, 18, 8),
              decoration: BoxDecoration(
                // Chats 叠在主题背景上：使用全局半透明卡片令牌，不能把
                // scheme.surface 当成近白实底，否则暖色背景会被洗掉。
                color: selected
                    ? AppColors.selectedCard(scheme)
                    : AppColors.card(scheme),
                borderRadius: BorderRadius.circular(_chatCardRadius),
                border: Border.all(color: AppColors.hairline(scheme)),
                boxShadow: [
                  BoxShadow(
                    color:
                        Colors.black.withValues(alpha: selected ? 0.07 : 0.045),
                    blurRadius: selected ? 10 : 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: _chatCardIconSize,
                    height: _chatCardIconSize,
                    decoration: BoxDecoration(
                      color: AppColors.iconCircleFill(scheme),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: AppLineIcon(
                        AppLineIcons.chat,
                        size: 22,
                        color: AppTextColor.secondary(scheme),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Nunito',
                            fontFamilyFallback: ['NotoSansSC'],
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.secondary(scheme).copyWith(
                            fontFamily: 'Nunito',
                            fontFamilyFallback: const ['NotoSansSC'],
                            fontSize: 11.5,
                            fontWeight: FontWeight.w300,
                            fontVariations: const [FontVariation('wght', 350)],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (session.starred)
                    const Icon(
                      CupertinoIcons.star_fill,
                      size: 16,
                      color: kCatGold,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _relativeDate(DateTime date) {
    final delta = DateTime.now().difference(date);
    if (delta.inMinutes < 1) return '刚刚';
    if (delta.inHours < 1) return '${delta.inMinutes}分钟前';
    if (delta.inDays < 1) return '${delta.inHours}小时前';
    if (delta.inDays == 1) return '昨天';
    if (delta.inDays < 7) return '${delta.inDays}天前';
    return '${date.month}月${date.day}日';
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  const _SearchField({required this.controller, required this.focusNode});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 搜索栏只有一层表面：外层负责透明卡片和发丝边，TextField 本身
    // 明确关闭所有主题边框，避免出现「大胶囊套小输入框」的双层轮廓。
    return DecoratedBox(
      key: const ValueKey('chat-search-field'),
      decoration: BoxDecoration(
        color: AppColors.card(scheme),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.hairline(scheme)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SizedBox(
        height: 38,
        child: Row(
          children: [
            const SizedBox(width: 14),
            Icon(CupertinoIcons.search,
                size: 20, color: AppTextColor.primary(scheme)),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                key: const ValueKey('chat-search-input'),
                controller: controller,
                focusNode: focusNode,
                onTap: () {
                  // Focus changes swap the bottom row on the first tap. Re-show
                  // the IME after that frame so the first tap behaves normally.
                  focusNode.requestFocus();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (focusNode.hasFocus) {
                      SystemChannels.textInput.invokeMethod<void>(
                        'TextInput.show',
                      );
                    }
                  });
                },
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  hintText: '搜索',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  filled: false,
                  fillColor: Colors.transparent,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.zero,
                  hintStyle: AppType.secondary(scheme).copyWith(
                    fontFamily: 'Nunito',
                    fontFamilyFallback: const ['NotoSansSC'],
                    fontSize: 17,
                    color: AppTextColor.hint(scheme),
                  ),
                ),
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontFamilyFallback: const ['NotoSansSC'],
                  fontSize: 17,
                  color: AppTextColor.primary(scheme),
                ),
              ),
            ),
            if (controller.text.isNotEmpty)
              AppCircleButton(
                icon: CupertinoIcons.clear_circled_solid,
                size: 30,
                iconSize: 18,
                semanticLabel: '清除搜索',
                onPressed: controller.clear,
              ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

class _NewChatButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _NewChatButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressableScale(
      key: const ValueKey('chat-new-button'),
      onPressed: onPressed,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: scheme.onSurface,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: scheme.onSurface.withValues(alpha: 0.8)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.add, color: scheme.surface, size: 18),
            const SizedBox(width: 6),
            Text(
              '新聊天',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontFamilyFallback: const ['NotoSansSC'],
                color: scheme.surface,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchCloseButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _SearchCloseButton({required this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox(
        key: const ValueKey('chat-search-close-button'),
        width: 38,
        height: 38,
        child: Tooltip(
          message: '关闭搜索',
          child: AppCircleButton(
            icon: CupertinoIcons.xmark,
            iconSize: 18,
            size: 38,
            expandHitTarget: false,
            onPressed: onPressed,
          ),
        ),
      );
}

class _FilterRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme scheme;

  const _FilterRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () {
            Haptics.selection();
            onTap();
          },
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: scheme.onSurface.withValues(alpha: 0.06),
          hoverColor: scheme.onSurface.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            child: Row(
              children: [
                SizedBox(
                  key: ValueKey('chat-filter-check-$label'),
                  width: 24,
                  child: selected
                      ? Icon(
                          CupertinoIcons.check_mark,
                          size: 20,
                          color: scheme.onSurface,
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Icon(icon, size: 22, color: scheme.onSurface),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontFamily: 'Nunito',
                      fontFamilyFallback: ['NotoSansSC'],
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool destructive;
  final VoidCallback onTap;
  final ColorScheme scheme;

  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.scheme,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () {
            Haptics.selection();
            onTap();
          },
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: scheme.onSurface.withValues(alpha: 0.06),
          hoverColor: scheme.onSurface.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: destructive ? AppColors.warning : scheme.onSurface,
                ),
                const SizedBox(width: 14),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontFamilyFallback: const ['NotoSansSC'],
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: destructive ? AppColors.warning : scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
