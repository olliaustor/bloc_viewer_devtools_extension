import 'package:bloc_viewer_devtools_extension/src/history_dialog.dart';
import 'package:bloc_viewer_devtools_extension/src/tree_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget test for the history dialog.
void main() {
  testWidgets('history dialog renders records and updates live', (tester) async {
    final entry = BlocEntryModel(id: 1, name: 'CounterCubit', blocKind: 'Cubit');
    entry.lastEvent = 'Inc';
    entry.recordHistory([
      const NodeChange(['a', 'b'], ChangeKind.changed, oldValue: '1', newValue: '2'),
      const NodeChange(['c'], ChangeKind.added, newValue: '"x"'),
      const NodeChange(['d'], ChangeKind.removed, oldValue: '3'),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showHistoryDialog(context, entry),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('#1'), findsOneWidget);

    entry.recordHistory([
      const NodeChange([], ChangeKind.changed, oldValue: '2', newValue: '3'),
    ]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('#2'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('No state changes recorded yet.'), findsOneWidget);
  });
}
