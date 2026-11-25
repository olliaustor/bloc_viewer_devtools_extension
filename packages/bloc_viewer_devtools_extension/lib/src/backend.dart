import 'package:flutter/foundation.dart';
import 'package:vm_service/vm_service.dart';

/// Everything the controller needs from the connected app. Keeping this
/// small lets tests replace DevTools' (sealed) `ServiceManager` with a fake.
abstract class BlocViewerBackend {
  /// Whether an app is currently connected.
  ValueListenable<bool> get connected;

  /// Subscribes to the VM `Extension` stream and returns its events, or null
  /// when there is no VM service yet.
  Future<Stream<Event>?> extensionEvents();

  /// Calls a service extension on the main isolate.
  Future<Response> callExtension(String method, {Map<String, dynamic>? args});

  /// Releases listeners held by the backend.
  void dispose();
}
