import 'package:bloc_viewer_devtools_extension/src/screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vm_service/vm_service.dart';

import 'fakes.dart';

/// The fixture state: one of every node kind.
Map<String, dynamic> settingsNode({int count = 1}) => container('object', 'Settings', {
      'count': leaf('int', count),
      'whole': leaf('double', 2.0),
      'ratio': leaf('double', 2.5),
      'flag': leaf('bool', true),
      'name': leaf('String', 'hello'),
      'nothing': leaf('null', null, 'Null'),
      'mode': leaf('enum', 'fast', 'Mode'),
      'weird': leaf('other', 'WeirdThing()', 'Weird'),
      'locked': {...leaf('int', 5), 'readOnly': true},
      'tags': container('list', 'List<String>', {'0': leaf('String', 'a')}),
      'inner': container('map', 'Map<String, int>', {'x': leaf('int', 1)}),
    });

Future<FakeBackend> pumpScreen(
  WidgetTester tester, {
  bool connected = true,
  List<Map<String, dynamic>>? blocs,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final backend = FakeBackend(connected: connected)
    ..onCall = (m, a) async => respond({'seq': 0, 'blocs': blocs ?? []});
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: Scaffold(body: BlocViewerScreen(backend: backend)),
  ));
  await tester.pump();
  await tester.pump();
  return backend;
}

void main() {
  testWidgets('shows a waiting message while disconnected, then reacts to connecting',
      (tester) async {
    final backend = await pumpScreen(tester, connected: false);
    expect(find.text('Waiting for a connected app...'), findsOneWidget);
    expect(find.text('0 live'), findsOneWidget);

    backend.connectedNotifier.value = true;
    await tester.pump();
    await tester.pump();
    expect(find.text('No Cubits/Blocs alive yet.'), findsOneWidget);
  });

  testWidgets('shows an error banner', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = FakeBackend(connected: true)
      ..onCall = (m, a) async => throw RPCError(m, -32601, 'nope');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BlocViewerScreen(backend: backend))));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('BlocViewer.install()'), findsOneWidget);
  });

  testWidgets('lists blocs, filters, and keeps rows when others come and go', (tester) async {
    final backend = await pumpScreen(tester, blocs: [
      blocJson(1, name: 'CounterCubit'),
      blocJson(2, name: 'TodoBloc', kind: 'Bloc'),
    ]);
    expect(find.text('2 live'), findsOneWidget);
    expect(find.text('CounterCubit'), findsOneWidget);
    expect(find.text('Bloc'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'todo');
    await tester.pump();
    expect(find.text('CounterCubit'), findsNothing);
    expect(find.text('TodoBloc'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.text('No match for "zzz".'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();

    // Remove the first, add a third: surviving row keeps its identity.
    backend.events.add(blocEvent('closed', 1, bloc: {'id': 1}));
    backend.events.add(blocEvent('created', 2, bloc: blocJson(3, name: 'Third')));
    await tester.pump();
    expect(find.text('CounterCubit'), findsNothing);
    expect(find.text('TodoBloc'), findsOneWidget);
    expect(find.text('Third'), findsOneWidget);
  });

  testWidgets('toolbar: collapse all, expand all, refresh', (tester) async {
    final backend = await pumpScreen(tester, blocs: [blocJson(1, node: settingsNode())]);
    expect(find.text('"hello"'), findsOneWidget); // root is open, nested nodes are not
    expect(find.text('"a"'), findsNothing);

    await tester.tap(find.byTooltip('Expand all'));
    await tester.pump();
    expect(find.text('"a"'), findsOneWidget);

    await tester.tap(find.byTooltip('Collapse all'));
    await tester.pump();
    expect(find.text('"a"'), findsNothing);
    expect(find.text('"hello"'), findsOneWidget); // roots stay expanded

    final calls = backend.calls.length;
    await tester.tap(find.byTooltip('Refresh (re-read all blocs)'));
    await tester.pump();
    expect(backend.calls.length, calls + 1);
  });
}
