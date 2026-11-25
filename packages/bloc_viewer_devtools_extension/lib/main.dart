// coverage:ignore-file
// Entry point; DevToolsExtension only runs inside DevTools (web), so the UI it
// hosts is covered by widget tests of BlocViewerScreen instead.
import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';

import 'src/screen.dart';
import 'src/service_manager_backend.dart';

void main() {
  runApp(const BlocViewerExtension());
}

class BlocViewerExtension extends StatelessWidget {
  const BlocViewerExtension({super.key});

  @override
  Widget build(BuildContext context) {
    return DevToolsExtension(child: BlocViewerScreen(backend: ServiceManagerBackend()));
  }
}
