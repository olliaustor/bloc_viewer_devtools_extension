import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:vm_service/vm_service.dart';

import 'backend.dart';
import 'tree_model.dart';

/// Event kind of the app's `postEvent` calls; must match the app side.
const _eventKind = 'bloc_viewer';

/// Talks to the app (VM service extensions + Extension stream) and keeps the
/// persistent tree model in sync.
class BlocViewerController extends ChangeNotifier {
  /// Uses [_backend] to reach the app.
  BlocViewerController(this._backend);

  final BlocViewerBackend _backend;
  /// Live blocs in creation order.
  final List<BlocEntryModel> _entries = [];
  /// Live blocs by id.
  final Map<int, BlocEntryModel> _byId = {};

  /// Subscription to the VM service Extension stream.
  StreamSubscription<Event>? _sub;
  /// Events received while a snapshot is loading; null when not buffering.
  List<Event>? _buffer;
  /// Sequence number of the last snapshot; older events are ignored.
  int _snapshotSeq = -1;
  /// Set once [dispose] was called, to suppress late notifications.
  bool _disposed = false;

  /// Last error to show to the user, or null.
  String? error;
  /// Whether DevTools is connected to an app.
  bool connected = false;
  /// Case-insensitive name filter applied to [entries].
  String filter = '';

  /// Entries matching the current filter (creation order).
  List<BlocEntryModel> get entries => filter.isEmpty
      ? List.unmodifiable(_entries)
      : _entries
          .where((e) => e.name.toLowerCase().contains(filter.toLowerCase()))
          .toList();

  /// Number of live blocs regardless of the filter.
  int get totalCount => _entries.length;

  /// Starts listening for connection changes.
  void init() {
    _backend.connected.addListener(_onConnectionChanged);
    _onConnectionChanged();
  }

  /// Connects or disconnects when the app connection changes.
  void _onConnectionChanged() {
    final isConnected = _backend.connected.value;
    if (isConnected == connected) return;
    connected = isConnected;
    if (isConnected) {
      unawaited(_connect());
    } else {
      _sub?.cancel();
      _sub = null;
      _clear();
    }
    notifyListeners();
  }

  /// Subscribes to the Extension stream and loads the first snapshot.
  Future<void> _connect() async {
    final events = await _backend.extensionEvents();
    if (events == null) return;
    await _sub?.cancel();
    _buffer = [];
    _sub = events.listen(_onVmEvent);
    await refresh();
  }

  /// Re-reads the full list of blocs from the app.
  Future<void> refresh() async {
    if (!connected) return;
    _buffer ??= [];
    try {
      final response =
          await _backend.callExtension('ext.bloc_viewer.snapshot');
      final json = response.json ?? const {};
      error = null;
      _snapshotSeq = (json['seq'] as int?) ?? 0;
      final blocs = (json['blocs'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      _applySnapshot(blocs);
    } on RPCError catch (e) {
      error = e.code == -32601 || e.message.toLowerCase().contains('method not found')
          ? 'The app does not expose Bloc Viewer yet. Call BlocViewer.install() '
              'in main() and restart the app.'
          : 'Error reading blocs: ${e.message}';
      _clear();
    } catch (e) {
      error = 'Error reading blocs: $e';
    }
    final buffered = _buffer ?? const <Event>[];
    _buffer = null;
    for (final e in buffered) {
      _onVmEvent(e);
    }
    _lastSignature = -1;
    _notify();
    if (error != null) notifyListeners();
  }

  /// Merges a full list of blocs into the model and drops blocs that no longer exist.
  void _applySnapshot(List<Map<String, dynamic>> blocs) {
    final seen = <int>{};
    for (final b in blocs) {
      final id = b['id'] as int;
      seen.add(id);
      _upsert(b, animate: _byId.containsKey(id));
    }
    for (final id in _byId.keys.toList()) {
      if (!seen.contains(id)) _remove(id);
    }
  }

  /// Handles one VM Extension event (reset/created/changed/closed), buffering it while a snapshot loads.
  void _onVmEvent(Event event) {
    if (event.extensionKind != _eventKind) return;
    if (_buffer != null) {
      _buffer!.add(event);
      return;
    }
    final data = event.extensionData?.data;
    if (data == null) return;
    final seq = data['seq'] as int? ?? 0;
    final type = data['type'] as String?;
    final bloc = (data['bloc'] as Map?)?.cast<String, dynamic>();

    switch (type) {
      case 'reset':
        // App (re)started: its previous blocs are gone.
        _clear();
        _notify();
        unawaited(refresh());
      case 'created':
        if (seq <= _snapshotSeq) return;
        if (bloc != null) _upsert(bloc, animate: false);
        _notify();
      case 'changed':
        if (seq <= _snapshotSeq) return;
        if (bloc != null) _upsert(bloc, animate: true);
        _notify();
      case 'closed':
        if (seq <= _snapshotSeq) return;
        final id = bloc?['id'] as int?;
        if (id != null) _remove(id);
        _notify();
    }
  }

  /// Creates or updates the entry for payload [b]; records a history entry for changes.
  void _upsert(Map<String, dynamic> b, {required bool animate}) {
    final id = b['id'] as int;
    var entry = _byId[id];
    final isNew = entry == null;
    if (entry == null) {
      entry = BlocEntryModel(
        id: id,
        name: b['name'] as String,
        blocKind: b['kind'] as String,
      );
      entry.root.expanded = true;
      _byId[id] = entry;
      _entries.add(entry);
    }
    entry.editable = b['editable'] == true;
    entry.lastEvent = b['lastEvent'] as String?;
    final changes = isNew ? null : <NodeChange>[];
    entry.root.applyUpdate(
      (b['node'] as Map).cast<String, dynamic>(),
      animate: animate && !isNew,
      changes: changes,
    );
    if (changes != null && changes.isNotEmpty) entry.recordHistory(changes);
  }

  /// Removes the entry with the given [id].
  void _remove(int id) {
    final e = _byId.remove(id);
    if (e != null) _entries.remove(e);
  }

  /// Removes all entries.
  void _clear() {
    _byId.clear();
    _entries.clear();
  }

  /// Hash of the entry ids at the last notification.
  int _lastSignature = -1;
  /// Rebuilds the top-level list only when the set of entries changed.
  /// Value changes inside a bloc never go through here; they are delivered to
  /// the individual tree nodes.
  void _notify() {
    if (_disposed) return;
    final sig = Object.hashAll(_entries.map((e) => e.id));
    if (sig != _lastSignature) {
      _lastSignature = sig;
      notifyListeners();
    }
  }

  /// Sets the name filter and rebuilds the list.
  void setFilter(String value) {
    filter = value;
    notifyListeners();
  }

  /// Expands ([expand] true) or collapses all trees; roots always stay open.
  void expandAll(bool expand) {
    for (final e in _entries) {
      e.root.setExpandedRecursive(expand);
      if (!expand) e.root.setExpanded(true);
    }
  }

  /// Asks the app to replace the value at [path] of the given bloc state.
  /// Returns an error message or null on success.
  Future<String?> edit(BlocEntryModel entry, List<String> path, Object? value) async {
    try {
      final response = await _backend.callExtension(
        'ext.bloc_viewer.edit',
        args: {
          'id': '${entry.id}',
          'path': jsonEncode(path),
          'value': jsonEncode(value),
        },
      );
      final json = response.json ?? const {};
      if (json['ok'] == true) return null;
      return (json['error'] as String?) ?? 'Unknown error';
    } catch (e) {
      return e.toString();
    }
  }

  /// Releases listeners and controllers.
  @override
  void dispose() {
    _disposed = true;
    _backend.connected.removeListener(_onConnectionChanged);
    _backend.dispose();
    _sub?.cancel();
    super.dispose();
  }
}
