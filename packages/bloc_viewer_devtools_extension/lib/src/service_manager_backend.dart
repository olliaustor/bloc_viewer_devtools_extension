// coverage:ignore-file
// Thin adapter over DevTools' global, sealed `ServiceManager`; it only runs
// inside a real DevTools session, so it is exercised through a fake
// [BlocViewerBackend] in tests instead.
import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/foundation.dart';
import 'package:vm_service/vm_service.dart';

import 'backend.dart';

/// [BlocViewerBackend] backed by DevTools' `serviceManager`.
class ServiceManagerBackend implements BlocViewerBackend {
  /// `serviceManager` is only touched on first use (inside DevTools' globals setup).
  late final ValueNotifier<bool> _connected = _start();
  bool _started = false;

  ValueNotifier<bool> _start() {
    _started = true;
    serviceManager.connectedState.addListener(_sync);
    final notifier = ValueNotifier<bool>(serviceManager.connectedState.value.connected);
    return notifier;
  }

  void _sync() => _connected.value = serviceManager.connectedState.value.connected;

  @override
  ValueListenable<bool> get connected => _connected;

  @override
  Future<Stream<Event>?> extensionEvents() async {
    final service = serviceManager.service;
    if (service == null) return null;
    try {
      await service.streamListen(EventStreams.kExtension);
    } catch (_) {
      // Already subscribed by DevTools.
    }
    return service.onExtensionEvent;
  }

  @override
  Future<Response> callExtension(String method, {Map<String, dynamic>? args}) =>
      serviceManager.callServiceExtensionOnMainIsolate(method, args: args);

  @override
  void dispose() {
    if (!_started) return;
    serviceManager.connectedState.removeListener(_sync);
    _connected.dispose();
  }
}
