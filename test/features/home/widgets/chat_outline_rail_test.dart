import 'package:Kelivo/features/home/widgets/chat_outline_rail.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpRail(
    WidgetTester tester, {
    required ValueChanged<ChatOutlineRailEntry> onTap,
    List<ChatOutlineRailEntry> entries = const [
      ChatOutlineRailEntry(id: 'first', label: 'First'),
      ChatOutlineRailEntry(id: 'second', label: 'Second', depth: 2),
    ],
    String? activeId = 'second',
    double maxHeight = 104,
    bool showNestedEntriesToggle = false,
    double expandedWidth = 300,
    ThemeData? theme,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: SizedBox(
            height: 260,
            child: Align(
              alignment: Alignment.centerLeft,
              child: ChatOutlineRail(
                side: ChatOutlineSide.left,
                activeId: activeId,
                entries: entries,
                maxHeight: maxHeight,
                expandedWidth: expandedWidth,
                showNestedEntriesToggle: showNestedEntriesToggle,
                onTap: onTap,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('hover region only covers the outline content height', (
    tester,
  ) async {
    await pumpRail(tester, onTap: (_) {});

    final hoverRegion = find.byKey(
      const ValueKey('chat-outline-left-hover-region'),
    );
    expect(tester.getSize(hoverRegion).height, 82);
    expect(tester.getSize(hoverRegion).height, lessThan(260));
  });

  testWidgets('long outlines are capped and remain independently scrollable', (
    tester,
  ) async {
    final entries = List.generate(
      30,
      (index) =>
          ChatOutlineRailEntry(id: 'entry-$index', label: 'Entry $index'),
    );
    await pumpRail(
      tester,
      entries: entries,
      activeId: 'entry-29',
      maxHeight: 104,
      onTap: (_) {},
    );

    final hoverRegion = find.byKey(
      const ValueKey('chat-outline-left-hover-region'),
    );
    expect(tester.getSize(hoverRegion).height, 104);
    final list = tester.widget<ListView>(
      find.byKey(const ValueKey('chat-outline-left-list')),
    );
    expect(list.controller!.position.maxScrollExtent, greaterThan(0));
    expect(list.controller!.offset, greaterThan(0));
  });

  testWidgets('active entry changes scroll back into the outline viewport', (
    tester,
  ) async {
    final entries = List.generate(
      30,
      (index) =>
          ChatOutlineRailEntry(id: 'entry-$index', label: 'Entry $index'),
    );
    await pumpRail(
      tester,
      entries: entries,
      activeId: 'entry-29',
      onTap: (_) {},
    );
    final listFinder = find.byKey(const ValueKey('chat-outline-left-list'));
    final initialList = tester.widget<ListView>(listFinder);
    expect(initialList.controller!.offset, greaterThan(0));

    await pumpRail(
      tester,
      entries: entries,
      activeId: 'entry-0',
      onTap: (_) {},
    );
    final updatedList = tester.widget<ListView>(listFinder);
    expect(updatedList.controller!.offset, 0);
  });

  testWidgets('nested heading toggle defaults to H1 and only reveals H2-H3', (
    tester,
  ) async {
    await pumpRail(
      tester,
      entries: const [
        ChatOutlineRailEntry(id: 'h1', label: 'H1'),
        ChatOutlineRailEntry(id: 'h2', label: 'H2', depth: 1),
        ChatOutlineRailEntry(id: 'h3', label: 'H3', depth: 2),
        ChatOutlineRailEntry(id: 'h4', label: 'H4', depth: 3),
      ],
      activeId: 'h3',
      maxHeight: 240,
      showNestedEntriesToggle: true,
      onTap: (_) {},
    );

    final toggle = find.byKey(const ValueKey('chat-outline-nested-toggle'));
    final region = find.byKey(const ValueKey('chat-outline-left-hover-region'));
    expect(toggle, findsNothing);
    expect(tester.getSize(region).height, 51);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(
        find.byKey(const ValueKey('chat-outline-left-hover-region')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat-outline-entry-h1')), findsOne);
    expect(find.byKey(const ValueKey('chat-outline-entry-h2')), findsNothing);
    expect(find.byKey(const ValueKey('chat-outline-entry-h3')), findsNothing);
    expect(find.byKey(const ValueKey('chat-outline-entry-h4')), findsNothing);

    final firstEntry = find.byKey(const ValueKey('chat-outline-entry-h1'));
    expect(
      tester.getRect(firstEntry).right,
      lessThan(tester.getRect(toggle).left),
    );
    expect(
      (tester.getCenter(firstEntry).dy - tester.getCenter(toggle).dy).abs(),
      lessThan(5),
    );

    await tester.tap(find.byKey(const ValueKey('chat-outline-nested-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-outline-entry-h1')), findsOne);
    expect(find.byKey(const ValueKey('chat-outline-entry-h2')), findsOne);
    expect(find.byKey(const ValueKey('chat-outline-entry-h3')), findsOne);
    expect(find.byKey(const ValueKey('chat-outline-entry-h4')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('chat-outline-nested-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-outline-entry-h2')), findsNothing);
    expect(find.byKey(const ValueKey('chat-outline-entry-h3')), findsNothing);
  });

  testWidgets('expands on hover and collapses after the delay', (tester) async {
    await pumpRail(tester, onTap: (_) {});
    final surface = find.byKey(const ValueKey('chat-outline-left-surface'));
    expect(tester.getSize(surface).width, 28);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(
        find.byKey(const ValueKey('chat-outline-left-hover-region')),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(surface).width, 300);
    expect(find.byKey(const ValueKey('chat-outline-entry-second')), findsOne);

    await mouse.moveTo(const Offset(700, 500));
    await tester.pump(const Duration(milliseconds: 199));
    expect(tester.getSize(surface).width, 300);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(tester.getSize(surface).width, 28);
  });

  testWidgets('custom width affects the expanded panel only', (tester) async {
    await pumpRail(tester, expandedWidth: 460, onTap: (_) {});
    final surface = find.byKey(const ValueKey('chat-outline-left-surface'));
    expect(tester.getSize(surface).width, 28);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(surface));
    await tester.pumpAndSettle();
    expect(tester.getSize(surface).width, 460);
    await pumpRail(tester, expandedWidth: 380, onTap: (_) {});
    expect(tester.getSize(surface).width, 380);
    await mouse.moveTo(const Offset(700, 500));
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    expect(tester.getSize(surface).width, 28);
  });

  testWidgets('outline without H1 retains an accessible expansion control', (
    tester,
  ) async {
    await pumpRail(
      tester,
      onTap: (_) {},
      showNestedEntriesToggle: true,
      entries: const [ChatOutlineRailEntry(id: 'h2', label: 'H2', depth: 1)],
    );
    final region = find.byKey(const ValueKey('chat-outline-left-hover-region'));
    expect(tester.getSize(region).height, 51);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(region));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-outline-nested-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-outline-entry-h2')), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact icon layout handles dark theme and enlarged text', (
    tester,
  ) async {
    await pumpRail(
      tester,
      onTap: (_) {},
      expandedWidth: 180,
      maxHeight: 55,
      theme: ThemeData.dark(),
      textScale: 2,
      showNestedEntriesToggle: true,
    );
    final region = find.byKey(const ValueKey('chat-outline-left-hover-region'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(region));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-outline-nested-toggle')));
    await tester.pumpAndSettle();
    expect(tester.getSize(region).width, 180);
    expect(tester.getSize(region).height, 55);
    expect(tester.takeException(), isNull);
  });

  testWidgets('marks the active dash and invokes the selected entry', (
    tester,
  ) async {
    ChatOutlineRailEntry? selected;
    await pumpRail(tester, onTap: (entry) => selected = entry);

    expect(
      tester
          .getSize(find.byKey(const ValueKey('chat-outline-dash-second')))
          .width,
      17,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('chat-outline-dash-first')))
          .width,
      13,
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(
        find.byKey(const ValueKey('chat-outline-left-hover-region')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-outline-entry-second')));
    expect(selected?.id, 'second');
  });
}
