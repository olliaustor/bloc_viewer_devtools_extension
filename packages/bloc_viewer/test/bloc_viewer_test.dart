import 'dart:convert';
import 'dart:developer' show ServiceExtensionHandler;

import 'package:bloc/bloc.dart';
import 'package:bloc_viewer/src/bloc_viewer.dart';
import 'package:test/test.dart';

class CounterCubit extends Cubit<int> {
  CounterCubit([super.initial = 0]);
  void inc() => emit(state + 1);
}

/// Reports itself as closed while still registered (guards in snapshot/edit).
class ZombieCubit extends CounterCubit {
  bool zombie = false;
  @override
  bool get isClosed => zombie || super.isClosed;
}

class ValueCubit<T> extends Cubit<T> {
  ValueCubit(super.initial);
  void fail(Object e) => addError(e);
}

class NoopObserver extends BlocObserver {
  const NoopObserver();
}

class NullableCubit extends Cubit<Object?> {
  NullableCubit() : super(null);
}

class Settings {
  Settings({
    required this.name,
    required this.volume,
    required this.count,
    required this.tags,
    required this.nested,
  });
  final String name;
  final double volume;
  final int count;
  final List<dynamic> tags;
  final Map<String, dynamic> nested;

  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
        name: j['name'] as String,
        volume: j['volume'] as double,
        count: j['count'] as int,
        tags: j['tags'] as List<dynamic>,
        nested: j['nested'] as Map<String, dynamic>,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'volume': volume,
        'count': count,
        'tags': tags,
        'nested': nested,
      };
}

Settings makeSettings() => Settings(
    name: 'n', volume: 1.5, count: 1, tags: ['a', 'b'], nested: {'on': true});

class SettingsCubit extends Cubit<Settings> {
  SettingsCubit() : super(makeSettings());
}

/// State without toJson/props: display only.
class Opaque {
  @override
  String toString() => 'opaque';
}

class OpaqueCubit extends Cubit<Opaque> {
  OpaqueCubit() : super(Opaque());
}

/// toJson() returns a list, so it cannot be edited as an object.
class ListState {
  List<int> toJson() => [1];
}

class ListStateCubit extends Cubit<ListState> {
  ListStateCubit() : super(ListState());
}

/// Needs an encoder (no toJson).
class Encoded {
  Encoded(this.x);
  final int x;
}

class EncodedCubit extends Cubit<Encoded> {
  EncodedCubit() : super(Encoded(1));
}

class ThrowingIterable extends Iterable<int> {
  @override
  Iterator<int> get iterator => throw StateError('boom');
}

class ThrowingCubit extends Cubit<Iterable<int>> {
  ThrowingCubit() : super(const [1]);
  void poison() => emit(ThrowingIterable());
}

sealed class CEvent {}

class Inc extends CEvent {}

class CounterBloc extends Bloc<CEvent, int> {
  CounterBloc() : super(0) {
    on<Inc>((e, emit) => emit(state + 1));
  }
}

class RecordingObserver extends BlocObserver {
  final calls = <String>[];
  @override
  void onCreate(BlocBase<dynamic> bloc) {
    super.onCreate(bloc);
    calls.add('create');
  }

  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    calls.add('event');
  }

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    calls.add('change');
  }

  @override
  void onTransition(
      Bloc<dynamic, dynamic> bloc, Transition<dynamic, dynamic> transition) {
    super.onTransition(bloc, transition);
    calls.add('transition');
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    calls.add('error');
  }

  @override
  void onClose(BlocBase<dynamic> bloc) {
    super.onClose(bloc);
    calls.add('close');
  }
}

void main() {
  late List<Map<String, Object?>> posted;
  late Map<String, ServiceExtensionHandler> registered;

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  Map<String, Object?> lastBloc() => posted.last['bloc'] as Map<String, Object?>;

  Future<Map<String, dynamic>> edit(int id, List<String> path, Object? value) async {
    final r = await BlocViewer.invokeForTesting('edit', {
      'id': '$id',
      'path': jsonEncode(path),
      'value': jsonEncode(value),
    });
    return (r as Map).cast<String, dynamic>();
  }

  setUp(() {
    BlocViewer.resetForTesting();
    posted = [];
    registered = {};
    BlocViewer.overrideVmHooks(
      postEvent: (kind, data) {
        expect(kind, kEventKind);
        posted.add(data);
      },
      registerExtension: (m, h) => registered[m] = h,
    );
  });

  tearDown(() {
    Bloc.observer = NoopObserver();
    BlocViewer.resetForTesting();
  });

  group('install', () {
    test('sets observer, registers extensions once and posts reset', () {
      BlocViewer.install();
      expect(Bloc.observer, isA<BlocViewerObserver>());
      expect(registered.keys,
          unorderedEquals(['ext.bloc_viewer.snapshot', 'ext.bloc_viewer.edit']));
      expect(posted.map((e) => e['type']), ['reset']);
      expect(posted.single.containsKey('bloc'), isFalse);

      final first = Bloc.observer;
      BlocViewer.install();
      expect(Bloc.observer, isNot(same(first)));
      expect(posted, hasLength(1));
    });

    test('works with the real dart:developer hooks, even when called twice', () {
      BlocViewer.resetForTesting();
      BlocViewer.install();
      BlocViewer.resetForTesting(); // forget the flag; registering again must not throw
      BlocViewer.install();
      expect(Bloc.observer, isA<BlocViewerObserver>());
    });

    test('registered extension handlers return a service response', () async {
      BlocViewer.install();
      final c = CounterCubit(4);
      await flush();
      final snap = await registered['ext.bloc_viewer.snapshot']!(
          'ext.bloc_viewer.snapshot', {});
      expect(snap.isError(), isFalse);
      final bad = await registered['ext.bloc_viewer.edit']!('ext.bloc_viewer.edit', {});
      expect(bad.isError(), isFalse); // errors are reported in the payload
      await c.close();
    });

    test('failing postEvent is logged, not thrown', () {
      BlocViewer.overrideVmHooks(
        postEvent: (_, __) => throw StateError('no vm'),
        registerExtension: (m, h) {},
      );
      expect(BlocViewer.install, returnsNormally);
    });

    test('registerExtension failure is swallowed', () {
      BlocViewer.overrideVmHooks(
        postEvent: (_, __) {},
        registerExtension: (m, h) => throw ArgumentError('dup'),
      );
      expect(BlocViewer.install, returnsNormally);
    });
  });

  group('tracking', () {
    setUp(BlocViewer.install);

    test('cubit lifecycle: created, changed, closed', () async {
      posted.clear();
      final c = CounterCubit(1);
      expect(posted, isEmpty); // deferred until the constructor finished
      await flush();
      expect(posted.single['type'], 'created');
      final b = lastBloc();
      expect(b['name'], 'CounterCubit');
      expect(b['kind'], 'Cubit');
      expect(b['editable'], isTrue);
      expect(b['lastEvent'], isNull);
      expect((b['node'] as Map)['value'], 1);
      final id = b['id'];

      c.inc();
      expect(posted.last['type'], 'changed');
      expect((lastBloc()['node'] as Map)['value'], 2);
      expect(lastBloc()['id'], id);
      expect(posted.last['seq'], greaterThan(posted.first['seq'] as int));

      await c.close();
      expect(posted.last['type'], 'closed');
      expect(lastBloc(), {'id': id});
    });

    test('closed before the microtask runs is never announced', () async {
      posted.clear();
      final c = CounterCubit();
      await c.close();
      await flush();
      expect(posted.map((e) => e['type']), ['closed']);
    });

    test('bloc records last event and reports kind Bloc', () async {
      final b = CounterBloc();
      await flush();
      expect(lastBloc()['kind'], 'Bloc');
      b.add(Inc());
      await flush();
      expect(posted.last['type'], 'changed');
      expect(lastBloc()['lastEvent'], 'Inc');
      await b.close();
    });

    test('untracked blocs are ignored', () async {
      final c = CounterCubit();
      await flush();
      final n = posted.length;
      BlocViewer.resetForTesting();
      BlocViewer.overrideVmHooks(
          postEvent: (k, d) => posted.add(d), registerExtension: (m, h) {});
      c.inc(); // observer still installed, but registry was cleared
      expect(posted.length, n);
      await c.close();
      expect(posted.length, n);
    });

    test('delegate observer receives every callback', () async {
      final d = RecordingObserver();
      BlocViewer.install(delegate: d);
      final b = CounterBloc()..add(Inc());
      await flush();
      final v = ValueCubit<int>(0)..fail(StateError('x'));
      await b.close();
      await v.close();
      expect(d.calls,
          containsAll(['create', 'event', 'change', 'transition', 'error', 'close']));
    });

    test('a failing encoder never breaks the app', () async {
      final c = ThrowingCubit();
      await flush();
      final n = posted.length;
      expect(c.poison, returnsNormally);
      expect(posted.length, n);
      await c.close();
    });

    test('failing postEvent does not break the app', () async {
      final c = CounterCubit();
      BlocViewer.overrideVmHooks(
          postEvent: (_, __) => throw StateError('no vm'),
          registerExtension: (m, h) {});
      await flush();
      expect(c.inc, returnsNormally);
      await c.close();
    });

    test('null state is not editable without a decoder', () async {
      NullableCubit();
      await flush();
      expect(lastBloc()['editable'], isFalse);
    });

    test('decoder makes object state editable (by state type and bloc type)', () async {
      SettingsCubit();
      OpaqueCubit();
      await flush();
      expect(posted[posted.length - 2]['bloc'], containsPair('editable', false));
      BlocViewer.registerDecoder<Settings>(Settings.fromJson);
      SettingsCubit();
      await flush();
      expect(lastBloc()['editable'], isTrue);
      BlocViewer.registerDecoder<OpaqueCubit>((j) => Opaque());
      OpaqueCubit();
      await flush();
      expect(lastBloc()['editable'], isTrue);
    });

    test('registerEncoder renders objects without toJson', () async {
      BlocViewer.registerEncoder<Encoded>((v) => {'x': v.x});
      EncodedCubit();
      await flush();
      final node = lastBloc()['node'] as Map;
      expect(node['kind'], 'object');
      expect(((node['children'] as List).single as Map)['key'], 'x');
    });
  });

  group('snapshot', () {
    setUp(BlocViewer.install);

    test('lists live blocs with the current seq and skips closed ones', () async {
      final a = CounterCubit(7);
      ZombieCubit().zombie = true;
      await flush();
      final r = await BlocViewer.invokeForTesting('snapshot', {}) as Map;
      expect(r['seq'], posted.last['seq']);
      final blocs = (r['blocs'] as List).cast<Map>();
      expect(blocs, hasLength(1));
      expect((blocs.single['node'] as Map)['value'], 7);
      await a.close();
    });

    test('empty registry', () async {
      final r = await BlocViewer.invokeForTesting('snapshot', {}) as Map;
      expect(r['blocs'], isEmpty);
    });
  });

  group('edit', () {
    setUp(BlocViewer.install);

    Future<int> idOf(Future<void> Function() create) async {
      await create();
      await flush();
      return lastBloc()['id'] as int;
    }

    test('primitive states are coerced and emitted', () async {
      final i = CounterCubit(1);
      final iid = await idOf(() async {});
      expect(await edit(iid, [], 5.0), {'ok': true});
      expect(i.state, 5);
      expect(posted.last['type'], 'changed');

      final d = ValueCubit<double>(1.0);
      await flush();
      expect(await edit(lastBloc()['id'] as int, [], 3), {'ok': true});
      expect(d.state, 3.0);
      expect(d.state, isA<double>());

      final b = ValueCubit<bool>(false);
      await flush();
      expect(await edit(lastBloc()['id'] as int, [], true), {'ok': true});
      expect(b.state, isTrue);

      final s = ValueCubit<String>('a');
      await flush();
      expect(await edit(lastBloc()['id'] as int, [], 'z'), {'ok': true});
      expect(s.state, 'z');
    });

    test('primitive state rejects wrong types and paths', () async {
      CounterCubit();
      await flush();
      final id = lastBloc()['id'] as int;
      final wrong = await edit(id, [], 'text');
      expect(wrong['ok'], isFalse);
      expect(wrong['error'], contains('Cannot assign String to int'));
      final path = await edit(id, ['x'], 1);
      expect(path['error'], contains('Invalid path for a primitive state'));
    });

    test('unknown and closed blocs', () async {
      expect((await edit(999, [], 1))['error'], contains('no longer exists'));
      final c = ZombieCubit();
      await flush();
      final id = lastBloc()['id'] as int;
      c.zombie = true;
      expect((await edit(id, [], 1))['error'], contains('is closed'));
    });

    test('malformed request is reported, not thrown', () async {
      final r = (await BlocViewer.invokeForTesting('edit', {})) as Map;
      expect(r['ok'], isFalse);
    });

    test('object state needs a decoder and a JSON object', () async {
      OpaqueCubit();
      await flush();
      final r = await edit(lastBloc()['id'] as int, ['a'], 1);
      expect(r['error'], contains('No decoder registered'));

      BlocViewer.registerDecoder<ListState>((j) => ListState());
      ListStateCubit();
      await flush();
      final r2 = await edit(lastBloc()['id'] as int, ['a'], 1);
      expect(r2['error'], contains('does not serialize to a JSON object'));

      NullableCubit();
      await flush();
      final r3 = await edit(lastBloc()['id'] as int, ['a'], 1);
      expect(r3['error'], contains('No decoder registered'));
    });

    test('decoder path: nested map/list edits keep numeric types', () async {
      BlocViewer.registerDecoder<Settings>(Settings.fromJson);
      final c = SettingsCubit();
      await flush();
      final id = lastBloc()['id'] as int;

      expect(await edit(id, ['nested', 'on'], false), {'ok': true});
      expect(c.state.nested['on'], isFalse);
      expect(await edit(id, ['tags', '1'], 'z'), {'ok': true});
      expect(c.state.tags, ['a', 'z']);
      expect(await edit(id, ['volume'], 3), {'ok': true}); // int -> double field
      expect(c.state.volume, 3.0);
      expect(await edit(id, ['count'], 2.0), {'ok': true}); // whole double -> int field
      expect(c.state.count, 2);
      expect(await edit(id, ['name'], 'new'), {'ok': true});
      expect(c.state.name, 'new');
      expect(posted.last['type'], 'changed');
    });

    test('decoder path errors', () async {
      BlocViewer.registerDecoder<Settings>(Settings.fromJson);
      SettingsCubit();
      await flush();
      final id = lastBloc()['id'] as int;
      expect((await edit(id, [], 1))['error'], 'Empty path');
      expect((await edit(id, ['name', 'x'], 1))['error'],
          contains('Invalid path segment "x"'));
      expect((await edit(id, ['count'], 'text'))['ok'], isFalse); // decoder cast fails
    });
  });
}

