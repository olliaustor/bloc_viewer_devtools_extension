// ignore_for_file: invalid_use_of_protected_member
import 'package:bloc_viewer_devtools_extension/src/tree_model.dart';
import 'package:bloc_viewer_devtools_extension/src/tree_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'screen_test.dart' show pumpScreen, settingsNode;

/// Finds the tappable row whose key label is [key].
Finder row(String key) =>
    find.ancestor(of: find.text(key), matching: find.byType(InkWell)).first;

Future<void> doubleTap(WidgetTester tester, String key) async {
  tester.widget<InkWell>(row(key)).onDoubleTap!();
  await tester.pumpAndSettle();
}

Finder dialogField() =>
    find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));

void main() {
  group('rendering', () {
    for (final dark in [false, true]) {
      testWidgets('every node kind (${dark ? 'dark' : 'light'})', (tester) async {
        await pumpScreen(tester,
            blocs: [blocJson(1, node: settingsNode())],
            theme: dark ? ThemeData.dark() : ThemeData.light());
        expect(find.text('1'), findsWidgets);
        expect(find.text('2.0'), findsOneWidget);
        expect(find.text('2.5'), findsOneWidget);
        expect(find.text('true'), findsOneWidget);
        expect(find.text('"hello"'), findsOneWidget);
        expect(find.text('null'), findsOneWidget);
        expect(find.text('fast'), findsOneWidget);
        expect(find.text('Mode'), findsOneWidget);
        expect(find.text('WeirdThing()'), findsOneWidget);
        expect(find.text('Weird'), findsOneWidget);
        expect(find.text('Settings (11)'), findsOneWidget);
        expect(find.text('List<String> (1)'), findsOneWidget);
        expect(find.text('Cubit'), findsOneWidget);
        expect(find.byTooltip('Change history (0)'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a container without type or length shows just its key', (tester) async {
      await pumpScreen(tester, blocs: [
        blocJson(1, node: {'kind': 'map', 'type': '', 'children': <Object>[]}),
      ]);
      expect(find.text('CounterCubit'), findsOneWidget);
    });

    testWidgets('tapping a container toggles it', (tester) async {
      await pumpScreen(tester, blocs: [blocJson(1, node: settingsNode())]);
      expect(find.text('"a"'), findsNothing);
      await tester.tap(row('tags'));
      await tester.pump();
      expect(find.text('"a"'), findsOneWidget);
      await tester.tap(row('tags'));
      await tester.pump();
      expect(find.text('"a"'), findsNothing);
    });

    testWidgets('history button opens the history dialog', (tester) async {
      final backend = await pumpScreen(tester, blocs: [blocJson(1, node: settingsNode())]);
      backend.events.add(blocEvent('changed', 1,
          bloc: blocJson(1, node: settingsNode(count: 2), lastEvent: 'Inc')));
      await tester.pump();
      await tester.tap(find.byTooltip('Change history (1)'));
      await tester.pumpAndSettle();
      expect(find.text('CounterCubit - history'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    });
  });

  group('live updates', () {
    testWidgets('changed values flash and then fade; structure changes flash too',
        (tester) async {
      final backend = await pumpScreen(tester, blocs: [blocJson(1, node: settingsNode())]);
      await tester.tap(row('tags'));
      await tester.pump();

      backend.events.add(blocEvent('changed', 1,
          bloc: blocJson(1, node: settingsNode(count: 2))));
      await tester.pump();
      expect(find.text('2'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
    });

    testWidgets('every flash colour renders', (tester) async {
      await pumpScreen(tester, blocs: [blocJson(1, node: settingsNode())]);
      final nodes = tester
          .widgetList<FlashBackground>(find.byType(FlashBackground))
          .map((f) => f.flash)
          .toList();
      for (final kind in FlashKind.values) {
        nodes.first.value = FlashEvent(kind);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
      }
      nodes.first.value = null; // clearing must not flash
      await tester.pumpAndSettle();
    });

    testWidgets('FlashBackground follows a replaced notifier', (tester) async {
      final a = ValueNotifier<FlashEvent?>(null);
      final b = ValueNotifier<FlashEvent?>(null);
      Widget host(ValueNotifier<FlashEvent?> n) =>
          MaterialApp(home: FlashBackground(flash: n, child: const SizedBox(width: 10, height: 10)));
      await tester.pumpWidget(host(a));
      await tester.pumpWidget(host(b));
      expect(a.hasListeners, isFalse);
      expect(b.hasListeners, isTrue);
      b.value = FlashEvent(FlashKind.added);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      expect(b.hasListeners, isFalse);
    });
  });

  group('editing', () {
    Future<FakeBackend> setup(WidgetTester tester, {bool editable = true}) async {
      final backend = await pumpScreen(tester,
          blocs: [blocJson(1, editable: editable, node: settingsNode())]);
      backend.onCall = (m, a) async => respond({'ok': true});
      return backend;
    }

    Map<String, dynamic>? lastArgs(FakeBackend b) => b.calls.last.$2;

    testWidgets('not editable shows a hint', (tester) async {
      final backend = await setup(tester, editable: false);
      final before = backend.calls.length;
      await doubleTap(tester, 'count');
      expect(find.textContaining('Not editable'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(backend.calls.length, before);
    });

    testWidgets('read-only and non-leaf values show a hint', (tester) async {
      await setup(tester);
      await doubleTap(tester, 'locked');
      expect(find.textContaining('Only int, double, bool, String and null'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      await doubleTap(tester, 'weird');
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('int: validates, then sends the number', (tester) async {
      final backend = await setup(tester);
      await doubleTap(tester, 'count');
      expect(find.text('Edit count'), findsOneWidget);
      await tester.enterText(dialogField(), 'abc');
      await tester.tap(find.text('Apply'));
      await tester.pump();
      expect(find.text('Not a valid integer'), findsOneWidget);
      await tester.enterText(dialogField(), ' 42 ');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(lastArgs(backend), {'id': '1', 'path': '["count"]', 'value': '42'});
    });

    testWidgets('double: validates, then sends the number', (tester) async {
      final backend = await setup(tester);
      await doubleTap(tester, 'ratio');
      await tester.enterText(dialogField(), 'x');
      await tester.tap(find.text('Apply'));
      await tester.pump();
      expect(find.text('Not a valid number'), findsOneWidget);
      await tester.enterText(dialogField(), '3.5');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(lastArgs(backend)!['value'], '3.5');
    });

    testWidgets('String: sent verbatim, also via the keyboard action', (tester) async {
      final backend = await setup(tester);
      await doubleTap(tester, 'name');
      expect(find.widgetWithText(TextField, 'hello'), findsOneWidget);
      await tester.enterText(dialogField(), 'new "text"');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(lastArgs(backend)!['value'], '"new \\"text\\""');
    });

    testWidgets('bool: toggled with a switch', (tester) async {
      final backend = await setup(tester);
      await doubleTap(tester, 'flag');
      expect(find.text('true'), findsWidgets);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(find.text('false'), findsWidgets);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(lastArgs(backend)!['value'], 'false');
    });

    testWidgets('null: accepts any JSON value', (tester) async {
      final backend = await setup(tester);
      await doubleTap(tester, 'nothing');
      expect(find.widgetWithText(TextField, 'null'), findsOneWidget);
      await tester.enterText(dialogField(), '{oops');
      await tester.tap(find.text('Apply'));
      await tester.pump();
      expect(find.textContaining('Enter valid JSON'), findsOneWidget);
      await tester.enterText(dialogField(), '[1, "a"]');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(lastArgs(backend)!['value'], '[1,"a"]');
    });

    testWidgets('nested paths are sent as lists', (tester) async {
      final backend = await setup(tester);
      await tester.tap(row('inner'));
      await tester.pump();
      await doubleTap(tester, 'x');
      await tester.enterText(dialogField(), '7');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(lastArgs(backend)!['path'], '["inner","x"]');
    });

    testWidgets('cancel sends nothing', (tester) async {
      final backend = await setup(tester);
      final before = backend.calls.length;
      await doubleTap(tester, 'count');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(backend.calls.length, before);
    });

    testWidgets('app-side failure is reported', (tester) async {
      final backend = await setup(tester);
      backend.onCall = (m, a) async => respond({'ok': false, 'error': 'nope'});
      await doubleTap(tester, 'count');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(find.text('Edit failed: nope'), findsOneWidget);
    });
  });
}
