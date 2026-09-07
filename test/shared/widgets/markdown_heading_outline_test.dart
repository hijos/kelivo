import '../../support/business_test_harness.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/markdown_heading_outline.dart';
import 'package:Kelivo/shared/widgets/markdown_with_highlight.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  group('extractMarkdownHeadingCandidates', () {
    test('recognizes ATX H1-H6 and keeps duplicate occurrences', () {
      final headings = extractMarkdownHeadingCandidates('''
# First
## Second
### Duplicate
#### Fourth
##### Fifth
###### Sixth
### Duplicate
''');

      expect(headings.map((heading) => heading.level), [1, 2, 3, 4, 5, 6, 3]);
      expect(headings.map((heading) => heading.title), [
        'First',
        'Second',
        'Duplicate',
        'Fourth',
        'Fifth',
        'Sixth',
        'Duplicate',
      ]);
      expect(
        headings.map((heading) => heading.offset).toSet().length,
        headings.length,
      );
    });

    test('matches renderer indentation and spacing rules', () {
      final headings = extractMarkdownHeadingCandidates('''
   # valid
    # four spaces is code
\t# tab is a supported horizontal indent
#missing-space
####### too many
## valid ##
''');

      expect(headings.map((heading) => heading.title), [
        'valid',
        'tab is a supported horizontal indent',
        'valid',
      ]);
      expect(headings.map((heading) => heading.level), [1, 1, 2]);
    });

    test('excludes protected markdown regions', () {
      final headings = extractMarkdownHeadingCandidates(r'''
# Visible one
```dart
# fenced
```
~~~
## tilde fenced
~~~
$$
# display math
$$
> # quoted
<details>
<summary>More</summary>
# hidden details
</details>
## Visible two
''');

      expect(headings.map((heading) => heading.title), [
        'Visible one',
        'Visible two',
      ]);
    });

    test('an unclosed fence protects the rest of the document', () {
      final headings = extractMarkdownHeadingCandidates('''
# Before
```
## Hidden
### Also hidden
''');

      expect(headings.map((heading) => heading.title), ['Before']);
    });

    test('turns inline markdown into readable labels', () {
      final headings = extractMarkdownHeadingCandidates(
        r'# **Bold** [link](https://example.com) `code` ![alt](image.png)',
      );

      expect(headings.single.title, 'Bold link code alt');
      expect(
        markdownHeadingPlainText('1.\u200C Introduction'),
        '1. Introduction',
      );
    });

    test('recognizes headings rendered inside supported list items', () {
      final headings = extractMarkdownHeadingCandidates('''
- ## Bullet heading
1. ### Ordered heading
''');

      expect(headings.map((heading) => heading.title), [
        'Bullet heading',
        'Ordered heading',
      ]);
      expect(headings.map((heading) => heading.level), [2, 3]);
    });
  });

  testWidgets('registry exposes distinct live anchors for rendered headings', (
    tester,
  ) async {
    final registry = MarkdownHeadingRegistry();
    addTearDown(registry.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SettingsProvider(createBusinessTestPreferences()),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MarkdownWithCodeHighlight(
              text: r'''# Repeated

> ## Quoted

```md
# Code
```

<details>
<summary>More</summary>
# Details
</details>

- ### List heading

Body

## Repeated''',
              headingRegistry: registry,
              headingScopeId: 'message:block',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(registry.headings.map((heading) => heading.title), [
      'Repeated',
      'List heading',
      'Repeated',
    ]);
    expect(registry.headings.map((heading) => heading.id).toSet().length, 3);
    expect(
      registry.headings.every(
        (heading) => heading.anchorKey.currentContext != null,
      ),
      isTrue,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(registry.headings, isEmpty);
  });
}
