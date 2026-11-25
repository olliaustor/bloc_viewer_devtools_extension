import 'package:flutter/material.dart';

import 'controller.dart';
import 'edit_dialog.dart';
import 'history_dialog.dart';
import 'tree_model.dart';

/// Monospace text style used for keys and values.
const _mono = TextStyle(
  fontFamily: 'RobotoMono',
  fontFamilyFallback: ['Menlo', 'Consolas', 'Courier New', 'monospace'],
  fontSize: 13,
);

/// Highlight colour for each kind of [FlashKind].
Color _flashColor(FlashKind k) => switch (k) {
      FlashKind.changed => const Color(0xB3FFB300), // amber
      FlashKind.added => const Color(0xB343A047), // green
      FlashKind.removed => const Color(0xB3E53935), // red
      FlashKind.descendant => const Color(0x40FFB300), // soft amber
    };

/// Row + children of one node. The row listens to `header`, the children
/// column to `structure`, the background to `flash`; so a value change only
/// rebuilds that single row.
class NodeView extends StatelessWidget {
  /// Creates the view of [node] at nesting level [depth].
  const NodeView({
    super.key,
    required this.node,
    required this.entry,
    required this.controller,
    required this.depth,
  });

  /// The node to display.
  final TreeNodeModel node;
  /// The bloc this node belongs to.
  final BlocEntryModel entry;
  /// Controller used to send edits to the app.
  final BlocViewerController controller;
  /// Nesting level, used for indentation.
  final int depth;

  /// Builds the widget.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        FlashBackground(
          flash: node.flash,
          child: ListenableBuilder(
            listenable: node.header,
            builder: (context, _) => _NodeRow(
              node: node,
              entry: entry,
              controller: controller,
              depth: depth,
            ),
          ),
        ),
        ListenableBuilder(
          listenable: node.structure,
          builder: (context, _) {
            if (!node.isContainer || !node.expanded) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final c in node.children)
                  NodeView(
                    key: ObjectKey(c),
                    node: c,
                    entry: entry,
                    controller: controller,
                    depth: depth + 1,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// One row: expand arrow, badge, key, value/type and (on roots) the history button.
class _NodeRow extends StatelessWidget {
  const _NodeRow({
    required this.node,
    required this.entry,
    required this.controller,
    required this.depth,
  });

  /// The node shown in this row.
  final TreeNodeModel node;
  /// The bloc this row belongs to.
  final BlocEntryModel entry;
  /// Controller used to send edits to the app.
  final BlocViewerController controller;
  /// Nesting level, used for indentation.
  final int depth;

  /// Whether this row is the root (the bloc itself).
  bool get _isRoot => node.parent == null;

  /// Whether the value can be edited: app supports it, node is not read-only and is a leaf of a primitive/null kind.
  bool get _canEdit {
    if (!entry.editable || node.readOnly) return false;
    return switch (node.kind) {
      'int' || 'double' || 'bool' || 'String' || 'null' => true,
      _ => false,
    };
  }

  /// Opens the edit dialog and sends the result to the app; shows a snack bar if editing is impossible or fails.
  Future<void> _edit(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!_canEdit) {
      messenger?.showSnackBar(SnackBar(
        content: Text(
          !entry.editable
              ? 'Not editable. Register a decoder with BlocViewer.registerDecoder<...>() in the app.'
              : 'Only int, double, bool, String and null values can be edited.',
        ),
      ));
      return;
    }
    final result = await showEditDialog(context, node);
    if (result == null) return;
    final err = await controller.edit(entry, node.path, result.value);
    if (err != null) {
      messenger?.showSnackBar(SnackBar(content: Text('Edit failed: $err')));
    }
  }

  /// Builds the widget.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.55);
    final container = node.isContainer;

    return InkWell(
      onTap: container ? () => node.setExpanded(!node.expanded) : null,
      onDoubleTap: container ? null : () => _edit(context),
      child: Padding(
        padding: EdgeInsets.fromLTRB(8 + depth * 18.0, 3, 8, 3),
        child: Row(
          children: [
            // Left content takes all remaining width so the history button is
            // always pinned to the right edge (a Spacer would share free space
            // with the Flexible value text and end up mid-row).
            Expanded(
              child: Row(
                children: [
                SizedBox(
                  width: 20,
                  child: container
                      ? Icon(node.expanded ? Icons.expand_more : Icons.chevron_right, size: 18)
                      : null,
                ),
                if (node.badge != null) ...[
                  _Badge(text: node.badge!, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                ],
                Text(
                  node.key,
                  style: _mono.copyWith(
                    fontWeight: _isRoot ? FontWeight.bold : FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (!container || node.length != null || node.type.isNotEmpty) const SizedBox(width: 6),
                if (container)
                  Text(
                    '${node.type}${node.length != null ? ' (${node.length})' : ''}',
                    style: _mono.copyWith(color: muted),
                  )
                else ...[
                  Text(':', style: _mono.copyWith(color: muted)),
                  const SizedBox(width: 6),
                  Flexible(child: _ValueText(node: node)),
                  if (node.kind == 'enum' || node.kind == 'other') ...[
                    const SizedBox(width: 8),
                    Text(node.type, style: _mono.copyWith(color: muted)),
                  ],
                ],
              ],
              ),
            ),
            if (_isRoot)
              ListenableBuilder(
                listenable: entry.historyChanged,
                builder: (context, _) => IconButton(
                  tooltip: 'Change history (${entry.history.length})',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                  icon: Icon(Icons.history,
                      color: entry.history.isEmpty ? muted : theme.colorScheme.primary),
                  onPressed: () => showHistoryDialog(context, entry),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Value of a leaf, coloured by kind.
class _ValueText extends StatelessWidget {
  /// Creates the text for [node].
  const _ValueText({required this.node});
  /// The leaf node whose value is shown.
  final TreeNodeModel node;

  /// Builds the widget.
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    Color c;
    String text;
    switch (node.kind) {
      case 'int':
        c = dark ? const Color(0xFF64B5F6) : const Color(0xFF1565C0);
        text = '${node.value}';
      case 'double':
        c = dark ? const Color(0xFF64B5F6) : const Color(0xFF1565C0);
        final v = (node.value as num).toDouble();
        text = v == v.roundToDouble() && v.abs() < 1e15 ? v.toStringAsFixed(1) : '$v';
      case 'bool':
        c = dark ? const Color(0xFFBA68C8) : const Color(0xFF7B1FA2);
        text = '${node.value}';
      case 'String':
        c = dark ? const Color(0xFF81C784) : const Color(0xFF2E7D32);
        text = '"${node.value}"';
      case 'enum':
        c = dark ? const Color(0xFFFFB74D) : const Color(0xFFE65100);
        text = '${node.value}';
      case 'null':
        c = Theme.of(context).disabledColor;
        text = 'null';
      default:
        c = Theme.of(context).colorScheme.onSurface;
        text = '${node.value}';
    }
    return Text(text, style: _mono.copyWith(color: c), overflow: TextOverflow.ellipsis, maxLines: 2);
  }
}

/// Small coloured label, e.g. "Cubit" or "Bloc".
class _Badge extends StatelessWidget {
  /// Creates a badge with [text] in [color].
  const _Badge({required this.text, required this.color});
  /// Label text.
  final String text;
  /// Accent colour of the label.
  final Color color;

  /// Builds the widget.
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      );
}

/// Paints a colour that fades out each time [flash] fires. Only this widget
/// repaints during the animation; [child] is never rebuilt.
class FlashBackground extends StatefulWidget {
  /// Creates a flash background around [child], triggered by [flash].
  const FlashBackground({super.key, required this.flash, required this.child});

  /// Notifier that triggers the highlight.
  final ValueNotifier<FlashEvent?> flash;
  /// Content drawn on top of the highlight.
  final Widget child;

  /// Creates the state object.
  @override
  State<FlashBackground> createState() => _FlashBackgroundState();
}

/// State of [FlashBackground]; drives the fade animation.
class _FlashBackgroundState extends State<FlashBackground> with SingleTickerProviderStateMixin {
  /// Runs the 2.2 s fade.
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));
  /// Fade progress, holding full colour for the first part.
  late final Animation<double> _fade =
      CurvedAnimation(parent: _controller, curve: const Interval(0.25, 1.0, curve: Curves.easeOut));
  /// Colour of the current flash.
  Color _color = Colors.transparent;

  /// Initialises state and subscribes to listeners.
  @override
  void initState() {
    super.initState();
    widget.flash.addListener(_onFlash);
  }

  /// Re-subscribes if the listened notifier changed.
  @override
  void didUpdateWidget(FlashBackground old) {
    super.didUpdateWidget(old);
    if (old.flash != widget.flash) {
      old.flash.removeListener(_onFlash);
      widget.flash.addListener(_onFlash);
    }
  }

  /// Starts the animation with the colour for the new flash.
  void _onFlash() {
    final e = widget.flash.value;
    if (e == null || !mounted) return;
    _color = _flashColor(e.kind);
    _controller.forward(from: 0);
  }

  /// Releases listeners and controllers.
  @override
  void dispose() {
    widget.flash.removeListener(_onFlash);
    _controller.dispose();
    super.dispose();
  }

  /// Builds the widget.
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _fade,
      child: widget.child,
      builder: (context, child) => ColoredBox(
        color: Color.lerp(_color, Colors.transparent, _fade.value)!,
        child: child,
      ),
    );
  }
}
