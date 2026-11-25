import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';

import 'serializer.dart';

/// True in product (release) builds, where the viewer is disabled.
const bool _isProduct = bool.fromEnvironment('dart.vm.product');

/// Event kind used on the VM service `Extension` stream.
const String kEventKind = 'bloc_viewer';

/// Registry record for one live bloc/cubit.
class _Entry {
  /// Creates an entry for [bloc] with the given [id].
  _Entry(this.id, this.bloc);
  /// Unique id assigned when the bloc was created.
  final int id;
  /// The tracked bloc or cubit.
  final BlocBase<dynamic> bloc;
  /// Runtime type of the most recent event (null for cubits).
  String? lastEvent;
}

/// Entry point of the app-side API (static members only; cannot be instantiated).
abstract final class BlocViewer {
  /// All currently alive blocs, keyed by id.
  static final Map<int, _Entry> _entries = {};
  /// Maps a bloc instance to its id without holding a strong reference.
  static final Expando<int> _ids = Expando<int>('bloc_viewer_id');
  /// Registered state decoders, keyed by state or bloc runtime type.
  static final Map<Type, Object? Function(Map<String, dynamic>)> _decoders = {};
  /// Next id to hand out.
  static int _nextId = 1;
  /// Sequence number of the last posted event; lets the extension discard events older than its snapshot.
  static int _seq = 0;
  /// Whether the service extensions were already registered.
  static bool _installed = false;

  /// Posts an event to the VM service; replaceable in tests.
  static void Function(String kind, Map<String, Object?> data) _postEvent =
      developer.postEvent;

  /// Registers a VM service extension; replaceable in tests.
  static void Function(String method, developer.ServiceExtensionHandler handler)
      _registerExtension = developer.registerExtension;

  /// Replaces the VM service hooks; pass null to restore the defaults.
  @visibleForTesting
  static void overrideVmHooks({
    void Function(String kind, Map<String, Object?> data)? postEvent,
    void Function(String method, developer.ServiceExtensionHandler handler)?
        registerExtension,
  }) {
    _postEvent = postEvent ?? developer.postEvent;
    _registerExtension = registerExtension ?? developer.registerExtension;
  }

  /// Clears all registries and flags so tests start from a clean slate.
  @visibleForTesting
  static void resetForTesting() {
    _entries.clear();
    _decoders.clear();
    _handlers.clear();
    encoders.clear();
    _nextId = 1;
    _seq = 0;
    _installed = false;
    overrideVmHooks();
  }

  /// Installs the observer and registers the VM service extensions.
  ///
  /// Call once, as early as possible in `main()` (only blocs created after
  /// this call are tracked). If you already have a [BlocObserver], pass it as
  /// [delegate] and all callbacks are forwarded to it.
  ///
  /// This is a no-op in release/profile-product builds.
  static void install({BlocObserver? delegate}) {
    if (_isProduct) return;
    Bloc.observer = BlocViewerObserver(delegate: delegate);
    if (_installed) return;
    _installed = true;
    _register('snapshot', (_) => _snapshot());
    _register('edit', _edit);
    _post('reset', null);
  }

  /// Registers a decoder that makes states editable from the DevTools tree.
  ///
  /// [T] is either the state type (e.g. `SettingsState`) or the bloc/cubit
  /// type (use that for sealed/freezed union states whose runtime type you
  /// cannot name). [fromJson] receives the whole, edited state as plain JSON
  /// (produced via the state's `toJson()`) and must return the new state.
  /// States that are plain `int`/`double`/`bool`/`String` are editable
  /// without a decoder.
  static void registerDecoder<T extends Object>(
      Object? Function(Map<String, dynamic> json) fromJson) {
    _decoders[T] = fromJson;
  }

  /// Registers a custom encoder for [T] if it has no `toJson()`.
  static void registerEncoder<T extends Object>(Object? Function(T value) toJson) {
    encoders[T] = (o) => toJson(o as T);
  }

  // ---------------------------------------------------------------- tracking

  /// Registers a new bloc and announces it once its constructor has finished.
  static void _created(BlocBase<dynamic> bloc) {
    final id = _nextId++;
    _ids[bloc] = id;
    final entry = _Entry(id, bloc);
    _entries[id] = entry;
    // Defer so the (sub)class constructor has finished before we read state.
    scheduleMicrotask(() {
      if (_entries[id] == entry) _post('created', _describe(entry, entry.bloc.state));
    });
  }

  /// Announces a state change of a tracked bloc.
  static void _changed(BlocBase<dynamic> bloc, Change<dynamic> change) {
    final entry = _lookup(bloc);
    if (entry == null) return;
    _post('changed', _describe(entry, change.nextState));
  }

  /// Remembers the type of the latest event for [bloc].
  static void _event(BlocBase<dynamic> bloc, Object? event) {
    _lookup(bloc)?.lastEvent = event.runtimeType.toString();
  }

  /// Removes a closed bloc from the registry and announces it.
  static void _closed(BlocBase<dynamic> bloc) {
    final id = _ids[bloc];
    if (id == null) return;
    final entry = _entries.remove(id);
    if (entry != null) _post('closed', {'id': id});
  }

  /// Returns the registry entry for [bloc], or null if it is not tracked.
  static _Entry? _lookup(BlocBase<dynamic> bloc) {
    final id = _ids[bloc];
    return id == null ? null : _entries[id];
  }

  // --------------------------------------------------------------- payloads

  /// Builds the JSON payload describing entry [e] with state [s].
  static Map<String, Object?> _describe(_Entry e, Object? s) {
    return {
      'id': e.id,
      'name': e.bloc.runtimeType.toString(),
      'kind': e.bloc is Bloc ? 'Bloc' : 'Cubit',
      'editable': _isEditable(e.bloc, s),
      'lastEvent': e.lastEvent,
      'node': encodeNode(s),
    };
  }

  /// Whether the state of [bloc] can be edited (primitive or has a decoder).
  static bool _isEditable(BlocBase<dynamic> bloc, Object? state) =>
      isPrimitive(state) || _decoderFor(bloc, state) != null;

  /// Finds the decoder for the state type, falling back to the bloc type.
  static Object? Function(Map<String, dynamic>)? _decoderFor(
          BlocBase<dynamic> bloc, Object? state) =>
      (state == null ? null : _decoders[state.runtimeType]) ?? _decoders[bloc.runtimeType];

  /// Posts an event of the given [type] on the VM service Extension stream.
  static void _post(String type, Object? payload) {
    try {
      _postEvent(kEventKind, {
        'type': type,
        'seq': ++_seq,
        if (payload is Map<String, Object?>) 'bloc': payload,
      });
    } catch (e) {
      developer.log('bloc_viewer: postEvent failed: $e', name: 'bloc_viewer');
    }
  }

  // ------------------------------------------------------ service extensions

  /// Registered extension handlers, keyed by short name (`snapshot`, `edit`).
  static final Map<String, FutureOr<Object?> Function(Map<String, String>)>
      _handlers = {};

  /// Runs [handler] and JSON-encodes its result; errors become `{ok: false, error}`.
  static Future<String> _run(
      FutureOr<Object?> Function(Map<String, String> params) handler,
      Map<String, String> params) async {
    try {
      return jsonEncode(await handler(params));
    } catch (e) {
      return jsonEncode({'ok': false, 'error': e.toString()});
    }
  }

  /// Invokes the handler registered as [name] and returns its decoded JSON result.
  @visibleForTesting
  static Future<Object?> invokeForTesting(String name, Map<String, String> params) async =>
      jsonDecode(await _run(_handlers[name]!, params));

  /// Registers the service extension `ext.bloc_viewer.<name>`; errors become `{ok: false, error}` results.
  static void _register(
      String name, FutureOr<Object?> Function(Map<String, String> params) handler) {
    _handlers[name] = handler;
    try {
      _registerExtension('ext.bloc_viewer.$name', (method, params) async =>
          developer.ServiceExtensionResponse.result(await _run(handler, params)));
    } catch (_) {
      // Already registered (e.g. install() called twice).
    }
  }

  /// Handler for `snapshot`: the current sequence number and all live blocs.
  static Object? _snapshot() => {
        'seq': _seq,
        'blocs': [
          for (final e in _entries.values)
            if (!e.bloc.isClosed) _describe(e, e.bloc.state),
        ],
      };

  /// Handler for `edit`: replaces the value at `path` in the state of bloc `id` and emits the new state.
  static Object? _edit(Map<String, String> params) {
    final id = int.parse(params['id']!);
    final path = (jsonDecode(params['path']!) as List).cast<String>();
    final value = jsonDecode(params['value']!);
    final entry = _entries[id];
    if (entry == null) throw 'Bloc #$id no longer exists';
    final bloc = entry.bloc;
    if (bloc.isClosed) throw 'Bloc #$id is closed';
    final Object? current = bloc.state;

    Object? next;
    if (isPrimitive(current)) {
      if (path.isNotEmpty) throw 'Invalid path for a primitive state';
      next = _coerce(current, value);
    } else {
      final decoder = _decoderFor(bloc, current);
      if (decoder == null) {
        throw 'No decoder registered. Call BlocViewer.registerDecoder<'
            '${current.runtimeType}>(...) to make this state editable.';
      }
      final plain = toPlain(current);
      if (plain is! Map<String, dynamic>) {
        throw 'State does not serialize to a JSON object (missing toJson()?)';
      }
      _setPath(plain, path, value);
      next = decoder(plain);
    }
    // emit() is @protected, but a dynamic call works fine for debugging.
    (bloc as dynamic).emit(next);
    return {'ok': true};
  }

  /// Converts [value] to the primitive type of [old], or throws if incompatible.
  static Object? _coerce(Object? old, Object? value) {
    if (old is int && value is num) return value.toInt();
    if (old is double && value is num) return value.toDouble();
    if (old is bool && value is bool) return value;
    if (old is String && value is String) return value;
    throw 'Cannot assign ${value.runtimeType} to ${old.runtimeType}';
  }

  /// Sets [value] at [path] inside the plain JSON tree [root], keeping int/double types consistent.
  static void _setPath(Object root, List<String> path, Object? value) {
    if (path.isEmpty) throw 'Empty path';
    Object? node = root;
    for (var i = 0; i < path.length - 1; i++) {
      node = _child(node, path[i]);
    }
    final last = path.last;
    final old = _child(node, last);
    Object? v = value;
    if (old is double && v is num) v = v.toDouble();
    if (old is int && v is double && v == v.truncateToDouble()) v = v.toInt();
    // _child above already rejected anything that is neither Map nor List.
    if (node is Map) {
      node[last] = v;
    } else {
      (node as List)[int.parse(last)] = v;
    }
  }

  /// Returns the child of a map/list [node] at [key].
  static Object? _child(Object? node, String key) {
    if (node is Map) return node[key];
    if (node is List) return node[int.parse(key)];
    throw 'Invalid path segment "$key"';
  }
}

/// [BlocObserver] feeding [BlocViewer]; forwards to an optional [delegate].
class BlocViewerObserver extends BlocObserver {
  /// Creates the observer; callbacks are forwarded to [delegate] if given.
  BlocViewerObserver({this.delegate});

  /// Observer that also receives every callback.
  final BlocObserver? delegate;

  /// Runs [f], logging instead of throwing so the viewer never breaks the app.
  T? _safe<T>(T Function() f) {
    try {
      return f();
    } catch (e) {
      developer.log('bloc_viewer: $e', name: 'bloc_viewer');
      return null;
    }
  }

  /// Registers the new bloc with the viewer.
  @override
  void onCreate(BlocBase<dynamic> bloc) {
    super.onCreate(bloc);
    delegate?.onCreate(bloc);
    _safe(() => BlocViewer._created(bloc));
  }

  /// Records the event type.
  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    delegate?.onEvent(bloc, event);
    _safe(() => BlocViewer._event(bloc, event));
  }

  /// Publishes the state change.
  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    delegate?.onChange(bloc, change);
    _safe(() => BlocViewer._changed(bloc, change));
  }

  /// Forwards to the delegate only.
  @override
  void onTransition(
      Bloc<dynamic, dynamic> bloc, Transition<dynamic, dynamic> transition) {
    super.onTransition(bloc, transition);
    delegate?.onTransition(bloc, transition);
  }

  /// Forwards to the delegate only.
  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    delegate?.onError(bloc, error, stackTrace);
  }

  /// Removes the bloc from the viewer.
  @override
  void onClose(BlocBase<dynamic> bloc) {
    super.onClose(bloc);
    delegate?.onClose(bloc);
    _safe(() => BlocViewer._closed(bloc));
  }
}
