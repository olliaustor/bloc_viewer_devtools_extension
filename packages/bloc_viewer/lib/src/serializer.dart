import 'dart:convert';

/// Maximum nesting depth that is expanded; deeper values are shown via `toString()`.
const int _maxDepth = 12;
/// Maximum number of children sent per container.
const int _maxChildren = 500;

/// Custom encoders registered by the app, keyed by runtime type.
final Map<Type, Object? Function(Object)> encoders = {};

/// Whether [v] is an int, double, bool or String.
bool isPrimitive(Object? v) => v is int || v is double || v is bool || v is String;

/// Sentinel returned by [_oneLevel] when an object offers neither a registered
/// encoder nor `toJson()`.
const Object _none = Object();

/// Converts [v] one level via a registered encoder or `toJson()`; returns [_none] if neither exists.
Object? _oneLevel(Object v) {
  final enc = encoders[v.runtimeType];
  if (enc != null) return enc(v);
  try {
    return (v as dynamic).toJson();
  } catch (_) {
    return _none;
  }
}

/// Deep conversion into plain JSON-compatible data (`Map<String, dynamic>`,
/// `List<dynamic>`, num, bool, String, null). Used for editing.
Object? toPlain(Object? v, [int depth = 0]) {
  if (v == null || v is bool || v is String) return v;
  if (v is num) return v.isFinite ? v : v.toString();
  if (v is Enum) return v.name;
  if (depth > _maxDepth) return v.toString();
  if (v is Map) {
    return <String, dynamic>{
      for (final e in v.entries) e.key.toString(): toPlain(e.value, depth + 1),
    };
  }
  if (v is Iterable) {
    return <dynamic>[for (final e in v) toPlain(e, depth + 1)];
  }
  final one = _oneLevel(v);
  if (identical(one, _none)) return v.toString();
  return toPlain(one, depth + 1);
}

/// Builds a leaf node of the given [kind], [type] and [value].
Map<String, Object?> _leaf(String kind, String type, Object? value) =>
    {'kind': kind, 'type': type, 'value': value};

/// Builds a container node, encoding up to [_maxChildren] of [entries] and recording the total length.
Map<String, Object?> _container(
    String kind, String type, Iterable<MapEntry<String, Object?>> entries, int depth) {
  final children = <Map<String, Object?>>[];
  var total = 0;
  for (final e in entries) {
    total++;
    if (children.length < _maxChildren) {
      children.add({'key': e.key, 'node': encodeNode(e.value, depth + 1)});
    }
  }
  return {
    'kind': kind,
    'type': type,
    'length': total,
    'children': children,
  };
}

/// Typed tree representation sent to the DevTools extension.
Map<String, Object?> encodeNode(Object? v, [int depth = 0]) {
  if (v == null) return _leaf('null', 'Null', null);
  if (v is int) return _leaf('int', 'int', v);
  if (v is double) {
    return v.isFinite ? _leaf('double', 'double', v) : _leaf('other', 'double', v.toString());
  }
  if (v is bool) return _leaf('bool', 'bool', v);
  if (v is String) return _leaf('String', 'String', v);
  final type = v.runtimeType.toString();
  if (v is Enum) return _leaf('enum', type, v.name);
  if (depth > _maxDepth) return _leaf('other', type, v.toString());
  if (v is Map) {
    return _container('map', type,
        v.entries.map((e) => MapEntry(e.key.toString(), e.value)), depth);
  }
  if (v is Iterable) {
    var i = 0;
    return _container('list', type, v.map((e) => MapEntry('${i++}', e)), depth);
  }
  final one = _oneLevel(v);
  if (one is Map) {
    return _container('object', type,
        one.entries.map((e) => MapEntry(e.key.toString(), e.value)), depth);
  }
  if (one is Iterable && !identical(one, _none)) {
    var i = 0;
    return _container('object', type, one.map((e) => MapEntry('${i++}', e)), depth);
  }
  // Equatable-style fallback: show props (read-only, order only).
  try {
    final props = (v as dynamic).props;
    if (props is List) {
      var i = 0;
      return {
        ..._container(
            'object', type, props.map((e) => MapEntry('props[${i++}]', e)), depth),
        'readOnly': true,
      };
    }
  } catch (_) {}
  return _leaf('other', type, _safeToString(v));
}

/// `toString()` that never throws.
String _safeToString(Object v) {
  try {
    return v.toString();
  } catch (_) {
    return jsonEncode(v.runtimeType.toString());
  }
}
