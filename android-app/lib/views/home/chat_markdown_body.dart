import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_line_icon.dart';
import '../../widgets/app_toast.dart';

/// CommonMark/GFM owns parsing; this renderer only defines the chat layout.
class ChatMarkdownBody extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Set<String> sourceUrls;

  const ChatMarkdownBody({
    super.key,
    required this.text,
    required this.style,
    this.sourceUrls = const {},
  });

  @override
  State<ChatMarkdownBody> createState() => _ChatMarkdownBodyState();
}

class _ChatMarkdownBodyState extends State<ChatMarkdownBody> {
  late List<md.Node> _nodes;
  final _links = <String, TapGestureRecognizer>{};

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(ChatMarkdownBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _parse();
  }

  void _parse() {
    final document =
        md.Document(extensionSet: md.ExtensionSet.gitHubWeb, encodeHtml: false);
    _nodes = document.parseLines(widget.text.split('\n'));
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
  Widget build(BuildContext context) => _blocks(context, _nodes, widget.style);

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
            style: base);
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
    return SelectableText.rich(TextSpan(style: base, children: spans),
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
    for (final url in widget.sourceUrls) {
      if (url.isEmpty) continue;
      text = text.replaceAll(
          RegExp('${RegExp.escape(url)}(?=\u0024|[\\s，。；：！？、)])'), '');
    }
    return text;
  }

  List<InlineSpan> _inline(
      BuildContext context, List<md.Node> nodes, TextStyle base) {
    final spans = <InlineSpan>[];
    for (final node in nodes) {
      if (node is md.Text) {
        final visibleText = _withoutKnownSources(node.text);
        final pattern = RegExp(r'[+\-￥¥]?\d[\d,]*(?:\.\d+)?%?');
        var offset = 0;
        for (final match in pattern.allMatches(visibleText)) {
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

class _ChatCodeBlock extends StatelessWidget {
  final String code;
  final String language;
  final TextStyle style;

  const _ChatCodeBlock({
    required this.code,
    required this.language,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                    child: Text(language.isEmpty ? '代码' : language,
                        style: style.copyWith(
                            fontSize: 12,
                            color: AppTextColor.secondary(scheme)))),
                Tooltip(
                    message: '复制代码',
                    child: Semantics(
                        button: true,
                        label: '复制代码',
                        child: InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: code));
                              showAppToast(context, '已复制');
                            },
                            child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: AppLineIcon(AppLineIcons.copy,
                                    size: 17,
                                    color: AppTextColor.secondary(scheme)))))),
              ])),
          SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SelectableText.rich(TextSpan(
                  children: _codeSpans(
                      code.trimRight(), style.copyWith(fontSize: 13))))),
        ]));
  }
}

List<InlineSpan> _codeSpans(String text, TextStyle style) {
  final spans = <InlineSpan>[];
  var offset = 0;
  for (final match in RegExp(r'[\x00-\x7f]+').allMatches(text)) {
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
