import 'package:flutter/widgets.dart';

import 'markdown_line_lexer.dart';

/// The ATX heading syntax used by both the renderer and the chat outline.
const String markdownAtxHeadingLinePattern =
    r'[ \t]{0,3}(#{1,6})[ \t]+([^\r\n\u2028\u2029]+?)(?:[ \t]+#+[ \t]*)?';

final RegExp _markdownAtxHeadingLine = RegExp(
  '^$markdownAtxHeadingLinePattern\$',
);

// gpt_markdown recursively parses a list item's body, so a heading directly
// inside a supported list item is rendered by the same ATX component too.
final RegExp _listItemMarkdownAtxHeadingLine = RegExp(
  r'^[ \t]{0,3}(?:[-*]|[0-9]+\.)[ \t]+'
  '$markdownAtxHeadingLinePattern\$',
);

final RegExp _blockquoteLine = RegExp(r'^[ \t]{0,3}>');

@immutable
class MarkdownHeadingCandidate {
  const MarkdownHeadingCandidate({
    required this.offset,
    required this.level,
    required this.title,
  });

  final int offset;
  final int level;
  final String title;
}

/// Extracts document-level ATX headings using the same syntax as the renderer.
///
/// Headings inside fenced code, display math, blockquotes, and details blocks
/// are intentionally excluded from chat navigation.
List<MarkdownHeadingCandidate> extractMarkdownHeadingCandidates(String source) {
  if (source.isEmpty || !source.contains('#')) {
    return const <MarkdownHeadingCandidate>[];
  }
  final lexer = MarkdownLineLexer();
  final math = markdownScanDisplayMath(source);
  final headings = <MarkdownHeadingCandidate>[];
  var lineStart = 0;
  while (lineStart <= source.length) {
    final newline = source.indexOf('\n', lineStart);
    final lineEnd = newline < 0 ? source.length : newline;
    final line = source
        .substring(lineStart, lineEnd)
        .replaceFirst(RegExp(r'\r$'), '');
    final protected = lexer.protected || math.covers(lineStart);
    if (!protected && !_blockquoteLine.hasMatch(line)) {
      final match =
          _markdownAtxHeadingLine.firstMatch(line) ??
          _listItemMarkdownAtxHeadingLine.firstMatch(line);
      if (match != null) {
        final raw = (match.group(2) ?? '').trim();
        final title = markdownHeadingPlainText(raw);
        if (title.isNotEmpty) {
          headings.add(
            MarkdownHeadingCandidate(
              offset: lineStart,
              level: (match.group(1) ?? '#').length,
              title: title,
            ),
          );
        }
      }
    }
    lexer.consumePhysicalLine(line);
    if (newline < 0) break;
    lineStart = newline + 1;
  }
  return headings;
}

/// Produces a compact readable label for a Markdown heading.
String markdownHeadingPlainText(String source) {
  var text = source.replaceAll('\u200C', '');
  text = text.replaceAllMapped(
    RegExp(r'!\[([^\]]*)\]\([^)]*\)'),
    (match) => match.group(1) ?? '',
  );
  text = text.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^)]*\)'),
    (match) => match.group(1) ?? '',
  );
  text = text.replaceAll(RegExp(r'<[^>]+>'), '');
  text = text.replaceAllMapped(
    RegExp(r'(`+)(.*?)\1'),
    (match) => match.group(2) ?? '',
  );
  text = text.replaceAll(RegExp(r'[*_~]+'), '');
  text = text.replaceAllMapped(
    RegExp(r'\\([\\`*_{}\[\]()#+\-.!>])'),
    (match) => match.group(1) ?? '',
  );
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

@immutable
class MarkdownHeadingSpec {
  const MarkdownHeadingSpec({
    required this.id,
    required this.level,
    required this.title,
  });

  final String id;
  final int level;
  final String title;
}

class MarkdownHeadingAnchor {
  const MarkdownHeadingAnchor({
    required this.id,
    required this.level,
    required this.title,
    required this.anchorKey,
  });

  final String id;
  final int level;
  final String title;
  final GlobalKey anchorKey;
}

class _HeadingScope {
  const _HeadingScope({required this.order, required this.headings});

  final int order;
  final List<MarkdownHeadingAnchor> headings;
}

/// Keeps heading metadata and live render anchors for one assistant message.
class MarkdownHeadingRegistry extends ChangeNotifier {
  final Map<String, _HeadingScope> _scopes = <String, _HeadingScope>{};
  bool _notificationScheduled = false;
  bool _disposed = false;

  List<MarkdownHeadingAnchor> get headings {
    final scopes = _scopes.entries.toList()
      ..sort((a, b) {
        final byOrder = a.value.order.compareTo(b.value.order);
        return byOrder != 0 ? byOrder : a.key.compareTo(b.key);
      });
    return List<MarkdownHeadingAnchor>.unmodifiable([
      for (final scope in scopes) ...scope.value.headings,
    ]);
  }

  List<MarkdownHeadingAnchor> replaceScope(
    String scopeId,
    int order,
    List<MarkdownHeadingSpec> specs,
  ) {
    final previous = _scopes[scopeId];
    final previousById = <String, MarkdownHeadingAnchor>{
      for (final heading
          in previous?.headings ?? const <MarkdownHeadingAnchor>[])
        heading.id: heading,
    };
    final next = <MarkdownHeadingAnchor>[
      for (final spec in specs)
        MarkdownHeadingAnchor(
          id: spec.id,
          level: spec.level,
          title: spec.title,
          anchorKey:
              previousById[spec.id]?.anchorKey ??
              GlobalKey(debugLabel: 'markdown-heading:${spec.id}'),
        ),
    ];
    if (_sameScope(previous, order, next)) return previous!.headings;
    _scopes[scopeId] = _HeadingScope(order: order, headings: next);
    _scheduleNotification();
    return next;
  }

  void removeScope(String scopeId) {
    if (_scopes.remove(scopeId) != null) _scheduleNotification();
  }

  bool _sameScope(
    _HeadingScope? previous,
    int order,
    List<MarkdownHeadingAnchor> next,
  ) {
    if (previous == null || previous.order != order) return false;
    if (previous.headings.length != next.length) return false;
    for (var i = 0; i < next.length; i++) {
      final left = previous.headings[i];
      final right = next[i];
      if (left.id != right.id ||
          left.level != right.level ||
          left.title != right.title) {
        return false;
      }
    }
    return true;
  }

  void _scheduleNotification() {
    if (_notificationScheduled || _disposed) return;
    _notificationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notificationScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _scopes.clear();
    super.dispose();
  }
}
