import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../../core/haptics.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_line_icon.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/pressable_scale.dart';

/// CommonMark/GFM owns parsing; this renderer only defines the chat layout.
class ChatMarkdownBody extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Set<String> sourceUrls;

  /// When true (live SSE streaming), uses lightweight [Text.rich] instead of
  /// [SelectableText.rich] and caches already-settled top-level paragraphs so
  /// 60fps streaming stays jank-free. Switches back to full selectable text
  /// as soon as the stream completes.
  final bool streaming;

  const ChatMarkdownBody({
    super.key,
    required this.text,
    required this.style,
    this.sourceUrls = const {},
    this.streaming = false,
  });

  @override
  State<ChatMarkdownBody> createState() => _ChatMarkdownBodyState();
}

class _ChatMarkdownBodyState extends State<ChatMarkdownBody> {
  static final RegExp _numericPattern = RegExp(r'[+\-￥¥]?\d[\d,]*(?:\.\d+)?%?');
  late List<md.Node> _nodes;
  String _settledPrefix = '';
  List<md.Node> _settledNodes = const [];
  List<Widget>? _cachedSettledWidgets;
  TextStyle? _cachedSettledStyle;
  Brightness? _cachedSettledBrightness;
  TextScaler? _cachedSettledScaler;
  final _links = <String, TapGestureRecognizer>{};
  List<RegExp> _sourceUrlPatterns = const [];

  @override
  void initState() {
    super.initState();
    _compileSourcePatterns();
    _parse();
  }

  @override
  void didUpdateWidget(ChatMarkdownBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameUrls(oldWidget.sourceUrls, widget.sourceUrls)) {
      _compileSourcePatterns();
    }
    if (oldWidget.text != widget.text ||
        oldWidget.streaming != widget.streaming) {
      _parse();
    }
  }

  static bool _sameUrls(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  void _compileSourcePatterns() {
    _cachedSettledWidgets = null;
    if (widget.sourceUrls.isEmpty) {
      _sourceUrlPatterns = const [];
      return;
    }
    _sourceUrlPatterns = [
      for (final url in widget.sourceUrls)
        if (url.isNotEmpty) RegExp('${RegExp.escape(url)}(?=\$|[\\s，。；：！？、)])'),
    ];
  }

  /// Find the last safe top-level paragraph boundary (`\n\n`) outside any open
  /// fenced code block (``` / ~~~) so completed paragraphs can be parsed once
  /// and cached during live streaming.
  static int _safeParagraphSplitOffset(String text) {
    var fence = '';
    var lineStart = 0;
    var lastSplit = 0;
    final len = text.length;
    while (lineStart < len) {
      final nl = text.indexOf('\n', lineStart);
      final lineEnd = nl < 0 ? len : nl;
      final line = text.substring(lineStart, lineEnd).trimLeft();
      if (fence.isEmpty) {
        if (line.startsWith('```')) {
          fence = '```';
        } else if (line.startsWith('~~~')) {
          fence = '~~~';
        } else if (line.isEmpty && nl >= 0 && nl + 1 < len) {
          // Blank line outside a fence separates top-level blocks.
          lastSplit = nl + 1;
        }
      } else if (line.startsWith(fence)) {
        fence = '';
      }
      if (nl < 0) break;
      lineStart = nl + 1;
    }
    return lastSplit;
  }

  void _parse() {
    final text = widget.text;
    if (!widget.streaming) {
      _settledPrefix = '';
      _settledNodes = const [];
      _cachedSettledWidgets = null;
      final document = md.Document(
          extensionSet: md.ExtensionSet.gitHubWeb, encodeHtml: false);
      _nodes = document.parseLines(text.split('\n'));
      return;
    }

    final splitAt = _safeParagraphSplitOffset(text);
    if (splitAt <= 0) {
      _settledPrefix = '';
      _settledNodes = const [];
      _cachedSettledWidgets = null;
      final document = md.Document(
          extensionSet: md.ExtensionSet.gitHubWeb, encodeHtml: false);
      _nodes = document.parseLines(text.split('\n'));
      return;
    }

    final nextPrefix = text.substring(0, splitAt);
    if (nextPrefix != _settledPrefix) {
      _cachedSettledWidgets = null;
      if (_settledPrefix.isNotEmpty && nextPrefix.startsWith(_settledPrefix)) {
        final delta = nextPrefix.substring(_settledPrefix.length);
        final doc = md.Document(
            extensionSet: md.ExtensionSet.gitHubWeb, encodeHtml: false);
        _settledNodes = [
          ..._settledNodes,
          ...doc.parseLines(delta.split('\n')),
        ];
      } else {
        final doc = md.Document(
            extensionSet: md.ExtensionSet.gitHubWeb, encodeHtml: false);
        _settledNodes = doc.parseLines(nextPrefix.split('\n'));
      }
      _settledPrefix = nextPrefix;
    }

    final tail = text.substring(splitAt);
    if (tail.isEmpty) {
      _nodes = _settledNodes;
      return;
    }
    final tailDoc =
        md.Document(extensionSet: md.ExtensionSet.gitHubWeb, encodeHtml: false);
    _nodes = [
      ..._settledNodes,
      ...tailDoc.parseLines(tail.split('\n')),
    ];
  }

  Future<void> _openLink(Uri uri) async {
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) showAppToast(context, '无法打开链接');
    } catch (_) {
      if (mounted) showAppToast(context, '无法打开链接');
    }
  }

  @override
  void dispose() {
    for (final link in _links.values) {
      link.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.streaming || _settledNodes.isEmpty) {
      return _blocks(context, _nodes, widget.style);
    }
    // At 120Hz (8.3ms frame budget), avoid rebuilding already-settled top-level
    // paragraph subtrees on every tick: cache their built Widget instances and
    // only rebuild the actively growing tail block(s).
    final brightness = Theme.of(context).brightness;
    final scaler = MediaQuery.textScalerOf(context);
    var settledWidgets = _cachedSettledWidgets;
    if (settledWidgets == null ||
        _cachedSettledStyle != widget.style ||
        _cachedSettledBrightness != brightness ||
        _cachedSettledScaler != scaler) {
      settledWidgets = [
        for (var i = 0; i < _settledNodes.length; i++)
          RepaintBoundary(child: _block(context, _settledNodes[i], widget.style)),
      ];
      _cachedSettledWidgets = settledWidgets;
      _cachedSettledStyle = widget.style;
      _cachedSettledBrightness = brightness;
      _cachedSettledScaler = scaler;
    }
    final tailCount = _nodes.length - _settledNodes.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < settledWidgets.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          settledWidgets[i],
        ],
        for (var j = 0; j < tailCount; j++) ...[
          if (settledWidgets.isNotEmpty || j > 0) const SizedBox(height: 12),
          _block(context, _nodes[_settledNodes.length + j], widget.style),
        ],
      ],
    );
  }

  TextStyle _emphasis(TextStyle base) => base.copyWith(
      fontWeight: FontWeight.w600,
      fontVariations: const [FontVariation('wght', 550)]);

  Widget _blocks(BuildContext context, List<md.Node> nodes, TextStyle base) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < nodes.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _block(context, nodes[i], base),
          ],
        ],
      );

  Widget _block(BuildContext context, md.Node node, TextStyle base) {
    if (node is! md.Element) return _text(context, [node], base);
    final children = node.children ?? const <md.Node>[];
    switch (node.tag) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        return _text(context, children,
            _emphasis(base).copyWith(fontSize: 18, height: 1.4));
      case 'ul':
      case 'ol':
        final start = int.tryParse(node.attributes['start'] ?? '') ?? 1;
        final scaler = MediaQuery.textScalerOf(context);
        final markerWidth = scaler.scale(base.fontSize ?? 15.5) *
            (node.tag == 'ol'
                ? '${start + children.length}.'.length * 0.65
                : 1.2);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 7),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                    width: markerWidth + 6,
                    child: Text(node.tag == 'ol' ? '${start + i}.' : '\u2022',
                        style: base)),
                Expanded(
                    child: _listContent(
                        context,
                        children[i] is md.Element
                            ? (children[i] as md.Element).children ?? []
                            : [children[i]],
                        base)),
              ]),
            ],
          ],
        );
      case 'blockquote':
        final scheme = Theme.of(context).colorScheme;
        return Container(
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
                border: Border(
                    left: BorderSide(
                        color: AppColors.hairline(scheme), width: 2))),
            child: _blocks(context, children,
                base.copyWith(color: AppTextColor.secondary(scheme))));
      case 'pre':
        final code = children.whereType<md.Element>().firstOrNull;
        return _ChatCodeBlock(
            code: node.textContent,
            language:
                (code?.attributes['class'] ?? '').replaceFirst('language-', ''),
            style: base,
            streaming: widget.streaming);
      case 'table':
        final rows = <md.Element>[];
        void collect(md.Element element) {
          if (element.tag == 'tr') {
            rows.add(element);
          } else {
            for (final child in element.children ?? const <md.Node>[]) {
              if (child is md.Element) collect(child);
            }
          }
        }

        collect(node);
        return SingleChildScrollView(
            key: const ValueKey('ai-chat-markdown-table'),
            scrollDirection: Axis.horizontal,
            child: Table(
                defaultColumnWidth: const IntrinsicColumnWidth(),
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                border: TableBorder(
                    horizontalInside: BorderSide(
                        color:
                            AppColors.hairline(Theme.of(context).colorScheme))),
                children: [
                  for (var i = 0; i < rows.length; i++)
                    TableRow(children: [
                      for (final cell
                          in rows[i].children?.whereType<md.Element>() ??
                              const <md.Element>[])
                        Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            child: _text(context, cell.children ?? [],
                                i == 0 ? _emphasis(base) : base,
                                wrap: false,
                                align: switch (cell.attributes['align']) {
                                  'right' => TextAlign.right,
                                  'center' => TextAlign.center,
                                  _ => TextAlign.left,
                                })),
                    ])
                ]));
      case 'hr':
        return Divider(
            height: 1,
            color: AppColors.hairline(Theme.of(context).colorScheme));
      case 'p':
      case 'li':
        return _text(context, children, base);
      default:
        return _text(context, children, base);
    }
  }

  Widget _text(BuildContext context, List<md.Node> nodes, TextStyle base,
      {bool wrap = true, TextAlign align = TextAlign.left}) {
    final spans = _inline(context, nodes, base);
    final rich = TextSpan(style: base, children: spans);
    if (widget.streaming) {
      return Text.rich(
        rich,
        textAlign: align,
        maxLines: wrap ? null : 1,
      );
    }
    return SelectableText.rich(rich,
        textAlign: align,
        // Horizontal table tracks use intrinsic text width; prose still wraps.
        maxLines: wrap ? null : 1);
  }

  Widget _listContent(
      BuildContext context, List<md.Node> nodes, TextStyle base) {
    final blocks = <Widget>[];
    final inline = <md.Node>[];
    void flush() {
      if (inline.isEmpty) return;
      blocks.add(_text(context, List.of(inline), base));
      inline.clear();
    }

    for (final node in nodes) {
      if (node is md.Element &&
          ['p', 'ul', 'ol', 'pre', 'blockquote'].contains(node.tag)) {
        flush();
        blocks.add(_block(context, node, base));
      } else {
        inline.add(node);
      }
    }
    flush();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < blocks.length; i++) ...[
        if (i > 0) const SizedBox(height: 8),
        blocks[i],
      ],
    ]);
  }

  String _withoutKnownSources(String text) {
    if (_sourceUrlPatterns.isEmpty) return text;
    for (final pattern in _sourceUrlPatterns) {
      text = text.replaceAll(pattern, '');
    }
    return text;
  }

  List<InlineSpan> _inline(
      BuildContext context, List<md.Node> nodes, TextStyle base) {
    final spans = <InlineSpan>[];
    for (final node in nodes) {
      if (node is md.Text) {
        final visibleText = _withoutKnownSources(node.text);
        var offset = 0;
        for (final match in _numericPattern.allMatches(visibleText)) {
          spans.add(TextSpan(
              text: visibleText.substring(offset, match.start), style: base));
          spans.add(TextSpan(
              text: match.group(0),
              style: base.copyWith(
                  fontFamily: 'Nunito',
                  fontFeatures: const [FontFeature.tabularFigures()])));
          offset = match.end;
        }
        spans.add(TextSpan(text: visibleText.substring(offset), style: base));
        continue;
      }
      if (node is! md.Element) continue;
      final children = node.children ?? const <md.Node>[];
      switch (node.tag) {
        case 'strong':
          spans.addAll(_inline(context, children, _emphasis(base)));
        case 'em':
          spans.addAll(_inline(
              context, children, base.copyWith(fontStyle: FontStyle.italic)));
        case 'del':
          spans.addAll(_inline(context, children,
              base.copyWith(decoration: TextDecoration.lineThrough)));
        case 'code':
          spans.addAll(_codeSpans(
              node.textContent,
              base.copyWith(
                  backgroundColor:
                      AppColors.inputFill(Theme.of(context).colorScheme))));
        case 'a':
          final href = node.attributes['href'] ?? '';
          final uri = Uri.tryParse(href);
          final rawLabel = node.textContent;
          final cleanedLabel = _withoutKnownSources(rawLabel);
          if (cleanedLabel != rawLabel) {
            spans.add(TextSpan(text: cleanedLabel, style: base));
            continue;
          }
          // Known bare source URLs belong in the source list, not the prose.
          if (rawLabel == href && widget.sourceUrls.contains(href)) continue;
          final label = rawLabel == href && (uri?.host.isNotEmpty ?? false)
              ? uri!.host.replaceFirst('www.', '')
              : rawLabel;
          final valid = uri != null &&
              uri.host.isNotEmpty &&
              ['https', 'http'].contains(uri.scheme);
          spans.add(TextSpan(
              text: label,
              recognizer: valid
                  ? _links.putIfAbsent(
                      href,
                      () =>
                          TapGestureRecognizer()..onTap = () => _openLink(uri))
                  : null,
              style: base.copyWith(
                  color: valid
                      ? Theme.of(context).colorScheme.primary
                      : base.color,
                  decoration: valid ? TextDecoration.underline : null)));
        case 'br':
          spans.add(const TextSpan(text: '\n'));
        case 'img':
          spans.add(TextSpan(text: node.attributes['alt'] ?? '', style: base));
        case 'input':
          spans.add(TextSpan(
              text: node.attributes.containsKey('checked') ? '[x] ' : '[ ] ',
              style: base));
        default:
          spans.addAll(_inline(context, children, base));
      }
    }
    return spans;
  }
}

class _ChatCodeBlock extends StatefulWidget {
  final String code;
  final String language;
  final TextStyle style;
  final bool streaming;

  const _ChatCodeBlock({
    required this.code,
    required this.language,
    required this.style,
    this.streaming = false,
  });

  @override
  State<_ChatCodeBlock> createState() => _ChatCodeBlockState();
}

class _ChatCodeBlockState extends State<_ChatCodeBlock> {
  bool _copied = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  void _copyCode() {
    Haptics.selection();
    Clipboard.setData(ClipboardData(text: widget.code));
    showAppToast(context, '已复制');
    _resetTimer?.cancel();
    setState(() => _copied = true);
    _resetTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final codeSpan = TextSpan(
      children: _codeSpans(
        widget.code.trimRight(),
        widget.style.copyWith(fontSize: 13),
      ),
    );
    return Container(
        key: const ValueKey('ai-chat-code-block'),
        decoration: BoxDecoration(
            color: AppColors.inputFill(scheme),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.hairline(scheme))),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
              padding: const EdgeInsets.only(left: 12, right: 4),
              child: Row(children: [
                Expanded(
                    child: Text(widget.language.isEmpty ? '代码' : widget.language,
                        style: widget.style.copyWith(
                            fontSize: 12,
                            color: AppTextColor.secondary(scheme)))),
                Tooltip(
                    message: '复制代码',
                    child: Semantics(
                        button: true,
                        label: '复制代码',
                        child: PressableScale(
                            onPressed: _copyCode,
                            child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: _copied
                                    ? Icon(Icons.check_rounded,
                                        size: 17, color: scheme.primary)
                                    : AppLineIcon(AppLineIcons.copy,
                                        size: 17,
                                        color: AppTextColor.secondary(
                                            scheme)))))),
              ])),
          SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: widget.streaming
                  ? Text.rich(codeSpan)
                  : SelectableText.rich(codeSpan)),
        ]));
  }
}

final RegExp _asciiCodePattern = RegExp(r'[\x00-\x7f]+');

List<InlineSpan> _codeSpans(String text, TextStyle style) {
  final spans = <InlineSpan>[];
  var offset = 0;
  for (final match in _asciiCodePattern.allMatches(text)) {
    spans.add(TextSpan(
        text: text.substring(offset, match.start),
        style: style
            .copyWith(fontFamily: 'NotoSansSC', fontVariations: const [])));
    spans.add(TextSpan(
        text: match.group(0),
        style:
            style.copyWith(fontFamily: 'monospace', fontVariations: const [])));
    offset = match.end;
  }
  spans.add(TextSpan(
      text: text.substring(offset),
      style:
          style.copyWith(fontFamily: 'NotoSansSC', fontVariations: const [])));
  return spans;
}
