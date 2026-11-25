import 'package:flutter/material.dart';

import 'backend.dart';
import 'controller.dart';
import 'tree_view.dart';

/// Main screen: toolbar plus the list of live blocs.
class BlocViewerScreen extends StatefulWidget {
  const BlocViewerScreen({super.key, required this.backend});

  /// Connection to the inspected app.
  final BlocViewerBackend backend;

  /// Creates the state object.
  @override
  State<BlocViewerScreen> createState() => _BlocViewerScreenState();
}

/// State of [BlocViewerScreen]; owns the [BlocViewerController].
class _BlocViewerScreenState extends State<BlocViewerScreen> {
  /// Syncs with the app and holds the tree models.
  late final controller = BlocViewerController(widget.backend);

  /// Initialises state and subscribes to listeners.
  @override
  void initState() {
    super.initState();
    controller.init();
  }

  /// Releases listeners and controllers.
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  /// Builds the widget.
  @override
  Widget build(BuildContext context) {
    return Material(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final entries = controller.entries;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Toolbar(controller: controller),
              const Divider(height: 1),
              if (controller.error != null)
                Container(
                  color: Theme.of(context).colorScheme.errorContainer,
                  padding: const EdgeInsets.all(8),
                  child: Text(controller.error!),
                ),
              Expanded(
                child: !controller.connected
                    ? const Center(child: Text('Waiting for a connected app...'))
                    : entries.isEmpty
                        ? Center(
                            child: Text(controller.totalCount == 0
                                ? 'No Cubits/Blocs alive yet.'
                                : 'No match for "${controller.filter}".'))
                        : ListView.builder(
                            // Keyed by bloc id so scroll offset and expansion
                            // survive additions/removals above/below.
                            itemCount: entries.length,
                            findChildIndexCallback: (key) {
                              final id = (key as ValueKey<int>).value;
                              final i = entries.indexWhere((e) => e.id == id);
                              return i < 0 ? null : i;
                            },
                            itemBuilder: (context, i) {
                              final e = entries[i];
                              return NodeView(
                                key: ValueKey<int>(e.id),
                                node: e.root,
                                entry: e,
                                controller: controller,
                                depth: 0,
                              );
                            },
                          ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Top bar with live count, name filter and expand/collapse/refresh buttons.
class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.controller});
  /// Controller the toolbar reads from and sends commands to.
  final BlocViewerController controller;

  /// Builds the widget.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Text('${controller.totalCount} live', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(width: 16),
          SizedBox(
            width: 240,
            height: 34,
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Filter by name',
                prefixIcon: Icon(Icons.search, size: 18),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: controller.setFilter,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Expand all',
            icon: const Icon(Icons.unfold_more),
            onPressed: () => controller.expandAll(true),
          ),
          IconButton(
            tooltip: 'Collapse all',
            icon: const Icon(Icons.unfold_less),
            onPressed: () => controller.expandAll(false),
          ),
          IconButton(
            tooltip: 'Refresh (re-read all blocs)',
            icon: const Icon(Icons.refresh),
            onPressed: controller.refresh,
          ),
        ],
      ),
    );
  }
}
