import 'package:flutter/material.dart';

import 'tree_model.dart';

/// Monospace text style used for values and diffs.
const _mono = TextStyle(
  fontFamily: 'RobotoMono',
  fontFamilyFallback: ['Menlo', 'Consolas', 'Courier New', 'monospace'],
  fontSize: 13,
);

/// Shows the change history of [entry]: newest first, each record with the
/// old -> new diff of every value that changed. Updates live.
Future<void> showHistoryDialog(BuildContext context, BlocEntryModel entry) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('${entry.name} - history'),
      content: SizedBox(
        width: 640,
        height: 420,
        child: ListenableBuilder(
          listenable: entry.historyChanged,
          builder: (context, _) {
            final records = entry.history.reversed.toList();
            if (records.isEmpty) {
              return const Center(child: Text('No state changes recorded yet.'));
            }
            return ListView.builder(
              itemCount: records.length,
              itemBuilder: (context, i) => _RecordTile(
                key: ValueKey<int>(records[i].index),
                record: records[i],
                initiallyExpanded: i == 0,
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: entry.clearHistory, child: const Text('Clear')),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    ),
  );
}

/// Pads [v] to two digits.
String _two(int v) => v.toString().padLeft(2, '0');

String formatTime(DateTime t) =>
    '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';

/// Expandable tile for one [HistoryRecord].
class _RecordTile extends StatelessWidget {
  /// Creates a tile for [record].
  const _RecordTile({super.key, required this.record, required this.initiallyExpanded});

  /// The state change shown by this tile.
  final HistoryRecord record;
  /// Whether the tile starts expanded (used for the newest record).
  final bool initiallyExpanded;

  /// Builds the widget.
  @override
  Widget build(BuildContext context) {
    final n = record.changes.length;
    return ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      dense: true,
      tilePadding: EdgeInsets.zero,
      title: Text(
        '#${record.index}  ${formatTime(record.time)}'
        '${record.event != null ? '  ${record.event}' : ''}'
        '  ($n ${n == 1 ? 'change' : 'changes'})',
        style: _mono,
      ),
      children: [for (final c in record.changes) _DiffLine(change: c)],
    );
  }
}

/// One line of a diff: marker, path and old -> new values.
class _DiffLine extends StatelessWidget {
  /// Creates a line for [change].
  const _DiffLine({required this.change});
  /// The difference shown by this line.
  final NodeChange change;

  /// Builds the widget.
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final red = dark ? const Color(0xFFEF9A9A) : const Color(0xFFC62828);
    final green = dark ? const Color(0xFFA5D6A7) : const Color(0xFF2E7D32);
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);

    final spans = <InlineSpan>[
      TextSpan(
        text: switch (change.kind) {
          ChangeKind.added => '+ ',
          ChangeKind.removed => '- ',
          ChangeKind.changed => '~ ',
        },
        style: _mono.copyWith(color: muted),
      ),
      TextSpan(text: '${change.pathLabel}: ', style: _mono.copyWith(fontWeight: FontWeight.w600)),
      if (change.oldValue != null)
        TextSpan(
          text: change.oldValue,
          style: _mono.copyWith(color: red, decoration: TextDecoration.lineThrough),
        ),
      if (change.oldValue != null && change.newValue != null)
        TextSpan(text: '  ->  ', style: _mono.copyWith(color: muted)),
      if (change.newValue != null)
        TextSpan(text: change.newValue, style: _mono.copyWith(color: green)),
    ];
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 12, bottom: 3),
        child: SelectableText.rich(TextSpan(children: spans)),
      ),
    );
  }
}
