import 'dart:convert';

import 'package:flutter/material.dart';

import 'tree_model.dart';

/// Result of the edit dialog: the new value chosen by the user.
class EditResult {
  /// Creates a result holding [value].
  const EditResult(this.value);
  /// The new value (int, double, bool, String or any JSON value for null).
  final Object? value;
}

/// Asks for a new value for a leaf [node]. Returns null when cancelled.
Future<EditResult?> showEditDialog(BuildContext context, TreeNodeModel node) {
  return showDialog<EditResult>(
    context: context,
    builder: (context) => _EditDialog(node: node),
  );
}

/// Dialog widget for editing the value of [node].
class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.node});
  /// The leaf node being edited.
  final TreeNodeModel node;

  /// Creates the state object.
  @override
  State<_EditDialog> createState() => _EditDialogState();
}

/// State of [_EditDialog].
class _EditDialogState extends State<_EditDialog> {
  /// Input for text/number values.
  late final TextEditingController _text;
  /// Current switch position for bool values.
  late bool _bool;
  /// Validation message shown under the text field.
  String? _error;

  /// Kind of the edited node (int, double, bool, String, null).
  String get _kind => widget.node.kind;

  /// Initialises state and subscribes to listeners.
  @override
  void initState() {
    super.initState();
    final v = widget.node.value;
    _bool = v == true;
    _text = TextEditingController(
      text: switch (_kind) {
        'String' => '$v',
        'null' => 'null',
        _ => '${v ?? ''}',
      },
    );
  }

  /// Releases listeners and controllers.
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// Validates the input and closes the dialog with an [EditResult]; shows an error if invalid.
  void _submit() {
    final raw = _text.text;
    Object? value;
    switch (_kind) {
      case 'bool':
        value = _bool;
      case 'int':
        value = int.tryParse(raw.trim());
        if (value == null) return setState(() => _error = 'Not a valid integer');
      case 'double':
        value = double.tryParse(raw.trim());
        if (value == null) return setState(() => _error = 'Not a valid number');
      case 'String':
        value = raw;
      default: // null -> any JSON value
        try {
          value = jsonDecode(raw);
        } catch (_) {
          return setState(() => _error = 'Enter valid JSON, e.g. 42, true, "text"');
        }
    }
    Navigator.of(context).pop(EditResult(value));
  }

  /// Builds the widget.
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${widget.node.key}'),
      content: SizedBox(
        width: 360,
        child: _kind == 'bool'
            ? SwitchListTile(
                title: Text(_bool ? 'true' : 'false'),
                value: _bool,
                onChanged: (v) => setState(() => _bool = v),
              )
            : TextField(
                controller: _text,
                autofocus: true,
                keyboardType: _kind == 'int' || _kind == 'double'
                    ? const TextInputType.numberWithOptions(decimal: true, signed: true)
                    : TextInputType.text,
                decoration: InputDecoration(
                  labelText: _kind == 'null' ? 'JSON value' : _kind,
                  errorText: _error,
                ),
                onSubmitted: (_) => _submit(),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Apply')),
      ],
    );
  }
}
