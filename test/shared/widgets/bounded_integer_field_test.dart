import 'package:Kelivo/shared/widgets/bounded_integer_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('clamps submitted values to the configured bounds', (
    tester,
  ) async {
    int? changedValue;
    await tester.pumpWidget(
      _testApp(value: 60, onChanged: (value) => changedValue = value),
    );

    final field = _textFieldFinder();
    await tester.enterText(field, '999');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(changedValue, 120);
    expect(tester.widget<TextField>(field).controller?.text, '120');

    await tester.enterText(field, '0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(changedValue, 1);
    expect(tester.widget<TextField>(field).controller?.text, '1');
  });

  testWidgets('restores the current value when empty input loses focus', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(value: 60, onChanged: (_) {}));

    final field = _textFieldFinder();
    await tester.enterText(field, '');
    await tester.tap(find.text('Outside'));
    await tester.pump();

    expect(tester.widget<TextField>(field).controller?.text, '60');
  });

  testWidgets('syncs the field when the external value changes', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(value: 60, onChanged: (_) {}));
    expect(tester.widget<TextField>(_textFieldFinder()).controller?.text, '60');

    await tester.pumpWidget(_testApp(value: 75, onChanged: (_) {}));
    await tester.pump();

    expect(tester.widget<TextField>(_textFieldFinder()).controller?.text, '75');
  });
}

Finder _textFieldFinder() => find.descendant(
  of: find.byKey(const ValueKey('bounded_integer_field')),
  matching: find.byType(TextField),
);

Widget _testApp({required int value, required ValueChanged<int> onChanged}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Column(
          children: [
            BoundedIntegerField(
              key: const ValueKey('bounded_integer_field'),
              value: value,
              minValue: 1,
              maxValue: 120,
              onChanged: onChanged,
            ),
            TextButton(
              onPressed: () => FocusScope.of(context).unfocus(),
              child: const Text('Outside'),
            ),
          ],
        ),
      ),
    ),
  );
}
