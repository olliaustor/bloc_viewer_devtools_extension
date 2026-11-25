import 'dart:async';

import 'package:bloc_viewer_devtools_extension/src/backend.dart';
import 'package:flutter/foundation.dart';
import 'package:vm_service/vm_service.dart';

/// Scriptable stand-in for the DevTools connection.
class FakeBackend implements BlocViewerBackend {
  FakeBackend({bool connected = false}) : connectedNotifier = ValueNotifier(connected);

  final ValueNotifier<bool> connectedNotifier;
  final StreamController<Event> events = StreamController<Event>.broadcast(sync: true);

  /// When true, [extensionEvents] reports that there is no VM service.
  bool noService = false;

  /// Every `(method, args)` pair passed to [callExtension].
  final List<(String, Map<String, dynamic>?)> calls = [];

  /// Produces the response for each call; override per test.
  Future<Response> Function(String method, Map<String, dynamic>? args) onCall =
      (m, a) async => respond({'seq': 0, 'blocs': []});

  bool disposed = false;

  @override
  ValueListenable<bool> get connected => connectedNotifier;

  @override
  Future<Stream<Event>?> extensionEvents() async => noService ? null : events.stream;

  @override
  Future<Response> callExtension(String method, {Map<String, dynamic>? args}) {
    calls.add((method, args));
    return onCall(method, args);
  }

  @override
  void dispose() => disposed = true;
}

Response respond(Map<String, dynamic>? json) => Response()..json = json;

Map<String, dynamic> leaf(String kind, Object? value, [String? type]) =>
    {'kind': kind, 'type': type ?? kind, 'value': value};

Map<String, dynamic> container(String kind, String type, Map<String, Map<String, dynamic>> kids) => {
      'kind': kind,
      'type': type,
      'length': kids.length,
      'children': [
        for (final e in kids.entries) {'key': e.key, 'node': e.value},
      ],
    };

Map<String, dynamic> blocJson(
  int id, {
  String name = 'CounterCubit',
  String kind = 'Cubit',
  bool editable = true,
  String? lastEvent,
  Map<String, dynamic>? node,
}) =>
    {
      'id': id,
      'name': name,
      'kind': kind,
      'editable': editable,
      'lastEvent': lastEvent,
      'node': node ?? leaf('int', 0),
    };

Event vmEvent(Map<String, dynamic>? data, {String extensionKind = 'bloc_viewer'}) => Event(
      kind: EventKind.kExtension,
      timestamp: 0,
      extensionKind: extensionKind,
      extensionData: data == null ? null : ExtensionData.parse(data),
    );

Event blocEvent(String type, int seq, {Map<String, dynamic>? bloc}) =>
    vmEvent({'type': type, 'seq': seq, if (bloc != null) 'bloc': bloc});
