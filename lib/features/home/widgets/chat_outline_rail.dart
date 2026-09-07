import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';

enum ChatOutlineSide { left, right }

@immutable
class ChatOutlineRailEntry {
  const ChatOutlineRailEntry({
    required this.id,
    required this.label,
    this.depth = 0,
    this.tooltip,
  });

  final String id;
  final String label;
  final int depth;
  final String? tooltip;
}

class ChatOutlineRail extends StatefulWidget {
  const ChatOutlineRail({
    super.key,
    required this.side,
    required this.entries,
    required this.onTap,
    this.activeId,
    this.expandedWidth = 300,
    this.maxHeight = double.infinity,
    this.showNestedEntriesToggle = false,
    this.expandNestedEntriesTooltip,
    this.collapseNestedEntriesTooltip,
  });

  final ChatOutlineSide side;
  final List<ChatOutlineRailEntry> entries;
  final String? activeId;
  final ValueChanged<ChatOutlineRailEntry> onTap;
  final double expandedWidth;
  final double maxHeight;
  final bool showNestedEntriesToggle;
  final String? expandNestedEntriesTooltip;
  final String? collapseNestedEntriesTooltip;

  @override
  State<ChatOutlineRail> createState() => _ChatOutlineRailState();
}

class _ChatOutlineRailState extends State<ChatOutlineRail> {
  static const _animationDuration = Duration(milliseconds: 220);
  static const _collapseDelay = Duration(milliseconds: 200);
  static const double _collapsedWidth = 28;
  static const double _itemExtent = 31;
  static const double _verticalPadding = 10;

  Timer? _collapseTimer;
  final ScrollController _scrollController = ScrollController();
  bool _expanded = false;
  bool _nestedEntriesExpanded = false;
  int _activeScrollRequest = 0;

  @override
  void initState() {
    super.initState();
    _scheduleActiveEntryReveal(animate: false);
  }

  @override
  void didUpdateWidget(ChatOutlineRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    final entriesChanged = !_sameEntryIds(oldWidget.entries, widget.entries);
    if (entriesChanged && widget.showNestedEntriesToggle) {
      _nestedEntriesExpanded = false;
    }
    if (oldWidget.activeId != widget.activeId || entriesChanged) {
      _scheduleActiveEntryReveal(animate: oldWidget.activeId != null);
    }
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleEnter() {
    _collapseTimer?.cancel();
    if (!_expanded) {
      setState(() => _expanded = true);
      _scheduleActiveEntryReveal(animate: true);
    }
  }

  void _handleExit() {
    _collapseTimer?.cancel();
    _collapseTimer = Timer(_collapseDelay, () {
      if (mounted && _expanded) {
        setState(() => _expanded = false);
        _scheduleActiveEntryReveal(animate: false);
      }
    });
  }

  List<ChatOutlineRailEntry> get _visibleEntries {
    if (!widget.showNestedEntriesToggle) return widget.entries;
    final maxDepth = _nestedEntriesExpanded ? 2 : 0;
    return [
      for (final entry in widget.entries)
        if (entry.depth <= maxDepth) entry,
    ];
  }

  String? _visibleActiveId(List<ChatOutlineRailEntry> visibleEntries) {
    final activeId = widget.activeId;
    if (activeId == null || !widget.showNestedEntriesToggle) return activeId;
    final activeIndex = widget.entries.indexWhere(
      (entry) => entry.id == activeId,
    );
    if (activeIndex < 0) return activeId;
    final visibleIds = {for (final entry in visibleEntries) entry.id};
    if (visibleIds.contains(activeId)) return activeId;
    for (var index = activeIndex - 1; index >= 0; index--) {
      final candidate = widget.entries[index];
      if (visibleIds.contains(candidate.id)) return candidate.id;
    }
    return null;
  }

  void _setNestedEntriesExpanded(bool expanded) {
    if (_nestedEntriesExpanded == expanded) return;
    setState(() => _nestedEntriesExpanded = expanded);
    _scheduleActiveEntryReveal(animate: true);
  }

  bool _sameEntryIds(
    List<ChatOutlineRailEntry> previous,
    List<ChatOutlineRailEntry> current,
  ) {
    if (previous.length != current.length) return false;
    for (var index = 0; index < previous.length; index++) {
      if (previous[index].id != current[index].id) return false;
    }
    return true;
  }

  void _scheduleActiveEntryReveal({required bool animate}) {
    final request = ++_activeScrollRequest;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || request != _activeScrollRequest) return;
      _revealActiveEntry(animate: animate);
    });
  }

  void _revealActiveEntry({required bool animate}) {
    if (!_scrollController.hasClients) return;
    final entries = _visibleEntries;
    final activeId = _visibleActiveId(entries);
    if (activeId == null) return;
    final activeIndex = entries.indexWhere((entry) => entry.id == activeId);
    if (activeIndex < 0) return;

    final position = _scrollController.position;
    final itemTop = _verticalPadding + activeIndex * _itemExtent;
    final itemBottom = itemTop + _itemExtent;
    final visibleTop = position.pixels;
    final visibleBottom = visibleTop + position.viewportDimension;
    if (itemTop >= visibleTop && itemBottom <= visibleBottom) return;

    final target = (itemTop - (position.viewportDimension - _itemExtent) / 2)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (animate) {
      unawaited(
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
        ),
      );
    } else {
      _scrollController.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final borderRadius = BorderRadius.circular(16);
    final width = _expanded ? widget.expandedWidth : _collapsedWidth;
    final visibleEntries = _visibleEntries;
    final showToggle = _expanded && widget.showNestedEntriesToggle;
    final naturalHeight =
        math.max(1, visibleEntries.length) * _itemExtent + _verticalPadding * 2;
    final height = math.min(naturalHeight, widget.maxHeight);
    if (height <= 0) return const SizedBox.shrink();

    return MouseRegion(
      key: ValueKey('chat-outline-${widget.side.name}-hover-region'),
      cursor: _expanded ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => _handleEnter(),
      onExit: (_) => _handleExit(),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: width),
        duration: _animationDuration,
        curve: Curves.easeOutCubic,
        builder: (context, animatedWidth, child) {
          return SizedBox(
            width: animatedWidth,
            height: height,
            child: ClipRRect(
              borderRadius: borderRadius,
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: _expanded ? 18 : 0,
                  sigmaY: _expanded ? 18 : 0,
                ),
                child: AnimatedContainer(
                  key: ValueKey('chat-outline-${widget.side.name}-surface'),
                  duration: _animationDuration,
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: _expanded
                        ? cs.surface.withValues(alpha: isDark ? 0.90 : 0.94)
                        : Colors.transparent,
                    borderRadius: borderRadius,
                    border: _expanded
                        ? Border.all(
                            color: cs.outlineVariant.withValues(alpha: 0.28),
                            width: 0.8,
                          )
                        : null,
                    boxShadow: _expanded
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: isDark ? 0.26 : 0.10,
                              ),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ]
                        : const <BoxShadow>[],
                  ),
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: widget.side == ChatOutlineSide.left
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      minWidth: widget.expandedWidth,
                      maxWidth: widget.expandedWidth,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Padding(
                            padding: EdgeInsets.only(
                              right: showToggle ? 30 : 0,
                            ),
                            child: _OutlineList(
                              side: widget.side,
                              entries: visibleEntries,
                              activeId: _visibleActiveId(visibleEntries),
                              expanded: _expanded,
                              controller: _scrollController,
                              itemExtent: _itemExtent,
                              topPadding: _verticalPadding,
                              bottomPadding: _verticalPadding,
                              onTap: widget.onTap,
                            ),
                          ),
                          if (!_expanded && visibleEntries.isEmpty)
                            Align(
                              alignment: widget.side == ChatOutlineSide.left
                                  ? Alignment.centerLeft
                                  : Alignment.centerRight,
                              child: SizedBox(
                                width: _collapsedWidth,
                                child: Center(
                                  child: Container(
                                    width: 13,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: cs.onSurfaceVariant.withValues(
                                        alpha: 0.18,
                                      ),
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (showToggle)
                            Positioned(
                              top: math.min(_verticalPadding, height / 4),
                              right: 6,
                              width: 28,
                              height: math.min(_itemExtent, height / 2),
                              child: IconButton(
                                key: const ValueKey(
                                  'chat-outline-nested-toggle',
                                ),
                                tooltip: _nestedEntriesExpanded
                                    ? widget.collapseNestedEntriesTooltip
                                    : widget.expandNestedEntriesTooltip,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                iconSize: 15,
                                style: IconButton.styleFrom(
                                  foregroundColor: _nestedEntriesExpanded
                                      ? cs.primary.withValues(alpha: 0.8)
                                      : cs.onSurfaceVariant.withValues(
                                          alpha: 0.5,
                                        ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                ),
                                onPressed: () => _setNestedEntriesExpanded(
                                  !_nestedEntriesExpanded,
                                ),
                                icon: Icon(
                                  _nestedEntriesExpanded
                                      ? Lucide.ChevronsDownUp
                                      : Lucide.ChevronsUpDown,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OutlineList extends StatelessWidget {
  const _OutlineList({
    required this.side,
    required this.entries,
    required this.activeId,
    required this.expanded,
    required this.controller,
    required this.itemExtent,
    required this.topPadding,
    required this.bottomPadding,
    required this.onTap,
  });

  final ChatOutlineSide side;
  final List<ChatOutlineRailEntry> entries;
  final String? activeId;
  final bool expanded;
  final ScrollController controller;
  final double itemExtent;
  final double topPadding;
  final double bottomPadding;
  final ValueChanged<ChatOutlineRailEntry> onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scrollbar(
      controller: controller,
      thumbVisibility: false,
      child: ListView.builder(
        key: ValueKey('chat-outline-${side.name}-list'),
        controller: controller,
        primary: false,
        padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
        itemExtent: itemExtent,
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          final active = entry.id == activeId;
          if (!expanded) {
            return Align(
              alignment: side == ChatOutlineSide.left
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: SizedBox(
                width: 28,
                child: Center(
                  child: AnimatedContainer(
                    key: ValueKey('chat-outline-dash-${entry.id}'),
                    duration: const Duration(milliseconds: 140),
                    width: active ? 17 : 13,
                    height: 5,
                    decoration: BoxDecoration(
                      color: active
                          ? cs.primary.withValues(alpha: 0.78)
                          : cs.onSurfaceVariant.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ),
            );
          }
          return Tooltip(
            message: entry.tooltip ?? entry.label,
            waitDuration: const Duration(milliseconds: 450),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: InkWell(
                key: ValueKey('chat-outline-entry-${entry.id}'),
                borderRadius: BorderRadius.circular(9),
                onTap: () => onTap(entry),
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: 8 + entry.depth.clamp(0, 5) * 12,
                    end: 8,
                  ),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        width: active ? 16 : 12,
                        height: 4,
                        decoration: BoxDecoration(
                          color: active
                              ? cs.primary.withValues(alpha: 0.72)
                              : cs.onSurfaceVariant.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          entry.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.25,
                            fontWeight: active
                                ? AppFontWeights.semibold
                                : AppFontWeights.regular,
                            color: active
                                ? cs.primary
                                : cs.onSurface.withValues(alpha: 0.66),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
