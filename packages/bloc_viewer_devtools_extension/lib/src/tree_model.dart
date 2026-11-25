import 'package:flutter/foundation.dart';

/// Why a row is highlighted.
enum FlashKind { changed, added, removed, descendant }

/// A request to flash a row.
class FlashEvent {
  /// Creates a flash event of [kind].
  FlashEvent(this.kind);
  /// What kind of highlight to show.
  final FlashKind kind;
}

/// How a node differs between two states.
enum ChangeKind { changed, added, removed }

/// One difference found while merging a new state into the tree.
class NodeChange {
  /// Creates a change at [path].
  const NodeChange(this.path, this.kind, {this.oldValue, this.newValue});

  /// Keys from the state root; empty means the state itself.
  final List<String> path;
  /// Whether the node was changed, added or removed.
  final ChangeKind kind;
  /// Display string of the previous value (null when added).
  final String? oldValue;
  /// Display string of the new value (null when removed).
  final String? newValue;

  /// Path as dotted text; "state" for the root.
  String get pathLabel => path.isEmpty ? 'state' : path.join('.');

  @override
  String toString() => '$pathLabel: $kind $oldValue -> $newValue';
}

/// One state change of a bloc, with the diff against the previous state.
class HistoryRecord {
  /// Creates a record.
  HistoryRecord(this.index, this.time, this.event, this.changes);

  /// Running number of the record, unique per bloc.
  final int index;
  /// When the change was received.
  final DateTime time;

  /// Runtime type of the bloc event that led here (null for cubits).
  final String? event;
  /// Differences against the previous state.
  final List<NodeChange> changes;
}

/// A [ChangeNotifier] that can be triggered manually.
class Bump extends ChangeNotifier {
  /// Notifies all listeners.
  void bump() => notifyListeners();
}

/// A persistent tree node. Nodes are merged in place when new data arrives,
/// so widgets keep their identity (expansion state, scroll position) and only
/// the nodes that actually changed notify their listeners.
class TreeNodeModel {
  /// Creates a node with [key], an optional [parent] and [badge].
  TreeNodeModel({required this.key, this.parent, this.badge});

  /// Name of this node within its parent (field name, index or bloc name).
  final String key;
  /// Parent node; null for a bloc root.
  final TreeNodeModel? parent;

  /// Optional badge (used on bloc root nodes, e.g. "Cubit").
  String? badge;

  /// Node kind: int, double, bool, String, null, enum, list, map, object or other.
  String kind = 'null';
  /// Runtime type name reported by the app.
  String type = '';
  /// Value of a leaf node.
  Object? value;
  /// True if the node cannot be edited (e.g. shown from Equatable props).
  bool readOnly = false;
  /// Number of children in the app (may exceed [children] when truncated).
  int? length;
  /// Whether the children are shown.
  bool expanded = false;

  /// Children in display order.
  final List<TreeNodeModel> children = [];
  /// Children by key, for merging.
  final Map<String, TreeNodeModel> _byKey = {};

  /// Fires when this row's own content changes (value, type, expanded arrow).
  final Bump header = Bump();

  /// Fires when the list of children or the expanded flag changes.
  final Bump structure = Bump();

  /// Fires when the row should flash.
  final ValueNotifier<FlashEvent?> flash = ValueNotifier(null);

  /// Whether this node can have children.
  bool get isContainer => kind == 'map' || kind == 'list' || kind == 'object';

  /// Keys from the root (exclusive) to this node.
  List<String> get path {
    final result = <String>[];
    TreeNodeModel? n = this;
    while (n != null && n.parent != null) {
      result.add(n.key);
      n = n.parent;
    }
    return result.reversed.toList();
  }

  /// Expands or collapses this node and updates its row and children.
  void setExpanded(bool value) {
    if (expanded == value) return;
    expanded = value;
    header.bump();
    structure.bump();
  }

  /// Expands or collapses this node and all descendants.
  void setExpandedRecursive(bool value) {
    if (isContainer) {
      expanded = value;
      header.bump();
      structure.bump();
    }
    for (final c in children) {
      c.setExpandedRecursive(value);
    }
  }

  /// Short human readable form of this node's value (used in diffs).
  String describe() {
    if (isContainer) return '$type${length != null ? ' ($length)' : ''}';
    switch (kind) {
      case 'String':
        return '"$value"';
      case 'double':
        final v = (value as num).toDouble();
        return v == v.roundToDouble() && v.abs() < 1e15 ? v.toStringAsFixed(1) : '$v';
      default:
        return '$value';
    }
  }

  /// Makes this row flash with [kind].
  void doFlash(FlashKind kind) => flash.value = FlashEvent(kind);

  /// Merges [n] into this node. Returns true if anything in this subtree
  /// changed. When [animate] is true, changed nodes flash. When [changes] is
  /// given, every difference found is appended to it (old -> new).
  bool applyUpdate(Map<String, dynamic> n,
      {required bool animate, List<NodeChange>? changes}) {
    final oldDescription = changes == null ? '' : describe();
    var kindChanged = false;
    var displayChanged = false;
    var selfChanged = false;
    var structureChanged = false;
    var descendantChanged = false;
    var removedSomething = false;

    final newKind = n['kind'] as String;
    final newType = (n['type'] as String?) ?? '';
    final newValue = n['value'];
    final newReadOnly = n['readOnly'] == true;
    final newLength = n['length'] as int?;

    if (kind != newKind) {
      kind = newKind;
      selfChanged = kindChanged = displayChanged = true;
    }
    if (type != newType) {
      type = newType;
      selfChanged = displayChanged = true;
    }
    if (value != newValue) {
      value = newValue;
      selfChanged = displayChanged = true;
    }
    if (length != newLength) {
      length = newLength;
      selfChanged = true;
    }
    readOnly = newReadOnly;

    if (changes != null && displayChanged) {
      changes.add(NodeChange(path, ChangeKind.changed,
          oldValue: oldDescription, newValue: describe()));
    }
    // Children of a node that changed shape are all new/gone: not worth listing.
    final childChanges = kindChanged ? null : changes;

    if (isContainer) {
      final incoming = (n['children'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final incomingKeys = {for (final c in incoming) c['key'] as String};

      for (final k in _byKey.keys.toList()) {
        if (!incomingKeys.contains(k)) {
          childChanges?.add(NodeChange(
              [...path, k], ChangeKind.removed, oldValue: _byKey[k]!.describe()));
          _byKey.remove(k);
          structureChanged = true;
          removedSomething = true;
        }
      }

      final ordered = <TreeNodeModel>[];
      for (final c in incoming) {
        final k = c['key'] as String;
        final data = (c['node'] as Map).cast<String, dynamic>();
        final existing = _byKey[k];
        if (existing == null) {
          final child = TreeNodeModel(key: k, parent: this)
            ..applyUpdate(data, animate: false);
          _byKey[k] = child;
          ordered.add(child);
          childChanges?.add(
              NodeChange(child.path, ChangeKind.added, newValue: child.describe()));
          structureChanged = true;
          descendantChanged = true;
          if (animate) {
            // Flash after the widget has been built.
            WidgetsBindingHelper.afterFrame(() => child.doFlash(FlashKind.added));
          }
        } else {
          if (existing.applyUpdate(data, animate: animate, changes: childChanges)) {
            descendantChanged = true;
          }
          ordered.add(existing);
        }
      }
      if (!listEquals(ordered, children)) {
        structureChanged = true;
        children
          ..clear()
          ..addAll(ordered);
      }
    } else if (children.isNotEmpty) {
      children.clear();
      _byKey.clear();
      structureChanged = true;
    }

    if (selfChanged) header.bump();
    if (structureChanged) structure.bump();

    final anything = selfChanged || structureChanged || descendantChanged;
    if (animate && anything) {
      if (selfChanged && !isContainer) {
        doFlash(FlashKind.changed);
      } else if (removedSomething) {
        doFlash(FlashKind.removed);
      } else if (selfChanged) {
        doFlash(FlashKind.changed);
      } else {
        doFlash(FlashKind.descendant);
      }
    }
    return anything;
  }
}

/// Tiny indirection so the model file stays free of widget imports.
class WidgetsBindingHelper {
  /// Runs [cb] shortly after, giving newly added rows time to be built.
  static void afterFrame(VoidCallback cb) {
    Future<void>.delayed(const Duration(milliseconds: 32), cb);
  }
}

/// One live Cubit/Bloc.
class BlocEntryModel {
  /// Creates an entry whose root node is named [name] and badged [blocKind].
  BlocEntryModel({required this.id, required String name, required String blocKind})
      : root = TreeNodeModel(key: name, badge: blocKind);

  /// Id assigned by the app.
  final int id;
  /// Root of the state tree.
  final TreeNodeModel root;
  /// Whether the app can apply edits to this bloc's state.
  bool editable = false;
  /// Runtime type of the last bloc event (null for cubits).
  String? lastEvent;

  /// Maximum number of history records kept.
  static const maxHistory = 200;

  /// State changes, oldest first; capped at [maxHistory].
  final List<HistoryRecord> history = [];
  /// Fires when [history] changes.
  final Bump historyChanged = Bump();
  /// Last used record index.
  int _historyCounter = 0;

  /// Appends a record for [changes], dropping the oldest above [maxHistory].
  void recordHistory(List<NodeChange> changes) {
    history.add(HistoryRecord(++_historyCounter, DateTime.now(), lastEvent, changes));
    if (history.length > maxHistory) history.removeAt(0);
    historyChanged.bump();
  }

  /// Deletes all history records.
  void clearHistory() {
    history.clear();
    historyChanged.bump();
  }
  /// Display name (the bloc's type name).
  String get name => root.key;
}
