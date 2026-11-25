import 'dart:async';

import 'package:bloc_viewer_devtools_extension/src/controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vm_service/vm_service.dart';

import 'fakes.dart';

void main() {
  late FakeBackend backend;
  late BlocViewerController c;
  late int notifications;

  Future<void> connect({List<Map<String, dynamic>> blocs = const [], int seq = 0}) async {
    backend.onCall = (m, a) async => respond({'seq': seq, 'blocs': blocs});
    backend.connectedNotifier.value = true;
    await pumpEventQueue();
  }

  setUp(() {
    backend = FakeBackend();
    c = BlocViewerController(backend)..init();
    notifications = 0;
    c.addListener(() => notifications++);
  });

  tearDown(() {
    c.dispose();
  });

  test('starts disconnected and empty', () {
    expect(c.connected, isFalse);
    expect(c.entries, isEmpty);
    expect(c.totalCount, 0);
    expect(backend.calls, isEmpty);
  });

  test('connecting reads a snapshot', () async {
    await connect(blocs: [blocJson(1), blocJson(2, name: 'Other')]);
    expect(c.connected, isTrue);
    expect(c.totalCount, 2);
    expect(c.entries.map((e) => e.name), ['CounterCubit', 'Other']);
    expect(c.entries.first.editable, isTrue);
    expect(c.entries.first.root.expanded, isTrue);
    expect(backend.calls.single.$1, 'ext.bloc_viewer.snapshot');
    expect(notifications, greaterThan(0));
  });

  test('a no-op connection change is ignored', () async {
    backend.connectedNotifier.value = false;
    expect(notifications, 0);
  });

  test('missing VM service leaves the controller idle', () async {
    backend.noService = true;
    await connect();
    expect(c.connected, isTrue);
    expect(backend.calls, isEmpty);
  });

  test('disconnecting clears entries and stops listening', () async {
    await connect(blocs: [blocJson(1)]);
    backend.connectedNotifier.value = false;
    await pumpEventQueue();
    expect(c.connected, isFalse);
    expect(c.entries, isEmpty);
    backend.events.add(blocEvent('created', 9, bloc: blocJson(9)));
    expect(c.entries, isEmpty);
  });

  test('reconnecting replaces the previous subscription', () async {
    await connect(blocs: [blocJson(1)]);
    backend.connectedNotifier.value = false;
    await pumpEventQueue();
    await connect(blocs: [blocJson(2)]);
    expect(c.entries.single.id, 2);
    backend.events.add(blocEvent('created', 1, bloc: blocJson(3)));
    expect(c.totalCount, 2); // delivered exactly once
  });

  group('events', () {
    setUp(() => connect(blocs: [blocJson(1, node: leaf('int', 1))], seq: 10));

    test('created adds an entry', () {
      backend.events.add(blocEvent('created', 11, bloc: blocJson(2)));
      expect(c.entries.map((e) => e.id), [1, 2]);
    });

    test('changed updates the value, records history and flashes', () {
      backend.events.add(blocEvent('changed', 11,
          bloc: blocJson(1, node: leaf('int', 2), lastEvent: 'Inc')));
      final e = c.entries.single;
      expect(e.root.value, 2);
      expect(e.lastEvent, 'Inc');
      expect(e.history, hasLength(1));
      expect(e.history.single.event, 'Inc');
      expect(e.root.flash.value, isNotNull);
    });

    test('changed for an unknown id upserts it', () {
      backend.events.add(blocEvent('changed', 11, bloc: blocJson(5)));
      expect(c.entries.map((e) => e.id), [1, 5]);
      expect(c.entries.last.history, isEmpty);
    });

    test('an unchanged state records no history', () {
      backend.events.add(blocEvent('changed', 11, bloc: blocJson(1, node: leaf('int', 1))));
      expect(c.entries.single.history, isEmpty);
    });

    test('closed removes the entry', () {
      backend.events.add(blocEvent('closed', 11, bloc: {'id': 1}));
      expect(c.entries, isEmpty);
    });

    test('events at or below the snapshot seq are stale', () {
      backend.events.add(blocEvent('created', 10, bloc: blocJson(2)));
      backend.events.add(blocEvent('changed', 9, bloc: blocJson(1, node: leaf('int', 99))));
      backend.events.add(blocEvent('closed', 8, bloc: {'id': 1}));
      expect(c.entries.map((e) => e.id), [1]);
      expect(c.entries.single.root.value, 1);
    });

    test('events without payload are tolerated', () {
      backend.events.add(blocEvent('created', 11));
      backend.events.add(blocEvent('changed', 12));
      backend.events.add(blocEvent('closed', 13));
      backend.events.add(blocEvent('closed', 14, bloc: {}));
      backend.events.add(vmEvent({'seq': 15})); // no type
      backend.events.add(vmEvent({'type': 'mystery', 'seq': 16}));
      backend.events.add(vmEvent({'type': 'created'})); // no seq
      backend.events.add(vmEvent(null));
      backend.events.add(vmEvent({'type': 'created', 'seq': 99}, extensionKind: 'other'));
      expect(c.entries.map((e) => e.id), [1]);
    });

    test('reset clears and reloads from a fresh snapshot', () async {
      backend.onCall = (m, a) async => respond({'seq': 0, 'blocs': [blocJson(7)]});
      backend.events.add(blocEvent('reset', 1));
      expect(c.entries, isEmpty);
      await pumpEventQueue();
      expect(c.entries.map((e) => e.id), [7]);
    });
  });

  test('events arriving during the snapshot are buffered and replayed', () async {
    final gate = Completer<Response>();
    backend.onCall = (m, a) => gate.future;
    backend.connectedNotifier.value = true;
    await pumpEventQueue();
    backend.events.add(blocEvent('changed', 5, bloc: blocJson(1, node: leaf('int', 5))));
    backend.events.add(blocEvent('changed', 2, bloc: blocJson(1, node: leaf('int', 2))));
    expect(c.entries, isEmpty);
    gate.complete(respond({
      'seq': 3,
      'blocs': [blocJson(1, node: leaf('int', 3))],
    }));
    await pumpEventQueue();
    expect(c.entries.single.root.value, 5); // seq 5 replayed, seq 2 dropped
  });

  group('refresh', () {
    test('does nothing while disconnected', () async {
      await c.refresh();
      expect(backend.calls, isEmpty);
    });

    test('removes blocs that disappeared and keeps the rest', () async {
      await connect(blocs: [blocJson(1), blocJson(2)]);
      backend.onCall = (m, a) async => respond({'seq': 1, 'blocs': [blocJson(2)]});
      await c.refresh();
      expect(c.entries.map((e) => e.id), [2]);
    });

    test('refreshing animates changes of known blocs', () async {
      await connect(blocs: [blocJson(1, node: leaf('int', 1))]);
      backend.onCall = (m, a) async =>
          respond({'seq': 1, 'blocs': [blocJson(1, node: leaf('int', 2))]});
      await c.refresh();
      expect(c.entries.single.root.value, 2);
      expect(c.entries.single.root.flash.value, isNotNull);
    });

    test('an empty response is treated as an empty snapshot', () async {
      await connect(blocs: [blocJson(1)]);
      backend.onCall = (m, a) async => respond(null);
      await c.refresh();
      expect(c.entries, isEmpty);
      expect(c.error, isNull);
    });

    test('a response without seq or blocs', () async {
      backend.onCall = (m, a) async => respond({});
      backend.connectedNotifier.value = true;
      await pumpEventQueue();
      expect(c.entries, isEmpty);
    });

    test('method-not-found explains how to install the viewer', () async {
      backend.onCall = (m, a) async => throw RPCError(m, -32601, 'whatever');
      backend.connectedNotifier.value = true;
      await pumpEventQueue();
      expect(c.error, contains('BlocViewer.install()'));
      expect(c.entries, isEmpty);
    });

    test('method-not-found is also recognised by message', () async {
      backend.onCall = (m, a) async => throw RPCError(m, 1, 'Method Not Found');
      backend.connectedNotifier.value = true;
      await pumpEventQueue();
      expect(c.error, contains('BlocViewer.install()'));
    });

    test('other RPC errors are shown', () async {
      backend.onCall = (m, a) async => throw RPCError(m, 5, 'bad thing');
      backend.connectedNotifier.value = true;
      await pumpEventQueue();
      expect(c.error, 'Error reading blocs: bad thing');
    });

    test('unexpected errors are shown and a later success clears them', () async {
      backend.onCall = (m, a) async => throw StateError('kaput');
      backend.connectedNotifier.value = true;
      await pumpEventQueue();
      expect(c.error, contains('kaput'));
      backend.onCall = (m, a) async => respond({'seq': 0, 'blocs': []});
      await c.refresh();
      expect(c.error, isNull);
    });

    test('a refresh finishing after dispose does not notify', () async {
      await connect();
      final gate = Completer<Response>();
      backend.onCall = (m, a) => gate.future;
      final f = c.refresh();
      c.dispose();
      gate.complete(respond({'seq': 0, 'blocs': [blocJson(1)]}));
      await f;
      expect(backend.disposed, isTrue);
      // tearDown disposes a second time; recreate so it stays valid.
      c = BlocViewerController(FakeBackend())..init();
    });
  });

  test('entries are only republished when the set of blocs changes', () async {
    await connect(blocs: [blocJson(1)]);
    final before = notifications;
    backend.events.add(blocEvent('changed', 1, bloc: blocJson(1, node: leaf('int', 4))));
    expect(notifications, before);
    backend.events.add(blocEvent('created', 2, bloc: blocJson(2)));
    expect(notifications, before + 1);
  });

  test('filter narrows entries case-insensitively', () async {
    await connect(blocs: [blocJson(1, name: 'CounterCubit'), blocJson(2, name: 'TodoBloc')]);
    c.setFilter('todo');
    expect(c.filter, 'todo');
    expect(c.entries.map((e) => e.name), ['TodoBloc']);
    expect(c.totalCount, 2);
    c.setFilter('');
    expect(c.entries, hasLength(2));
    expect(() => c.entries.add(c.entries.first), throwsUnsupportedError);
  });

  test('expandAll expands and collapses everything except the roots', () async {
    await connect(blocs: [
      blocJson(1, node: container('object', 'S', {'a': container('map', 'Map', {'b': leaf('int', 1)})})),
    ]);
    final root = c.entries.single.root;
    final a = root.children.single;
    c.expandAll(true);
    expect(root.expanded && a.expanded, isTrue);
    c.expandAll(false);
    expect(root.expanded, isTrue);
    expect(a.expanded, isFalse);
  });

  group('edit', () {
    setUp(() => connect(blocs: [blocJson(1)]));

    test('sends id, path and value as JSON and returns null on success', () async {
      backend.onCall = (m, a) async => respond({'ok': true});
      final err = await c.edit(c.entries.single, ['a', '0'], 'x');
      expect(err, isNull);
      final (method, args) = backend.calls.last;
      expect(method, 'ext.bloc_viewer.edit');
      expect(args, {'id': '1', 'path': '["a","0"]', 'value': '"x"'});
    });

    test('returns the app-side error', () async {
      backend.onCall = (m, a) async => respond({'ok': false, 'error': 'nope'});
      expect(await c.edit(c.entries.single, [], 1), 'nope');
    });

    test('falls back to a generic message', () async {
      backend.onCall = (m, a) async => respond({'ok': false});
      expect(await c.edit(c.entries.single, [], 1), 'Unknown error');
      backend.onCall = (m, a) async => respond(null);
      expect(await c.edit(c.entries.single, [], 1), 'Unknown error');
    });

    test('transport failures are returned as text', () async {
      backend.onCall = (m, a) async => throw StateError('offline');
      expect(await c.edit(c.entries.single, [], 1), contains('offline'));
    });
  });
}
