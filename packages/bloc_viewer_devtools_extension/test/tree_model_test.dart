import 'package:bloc_viewer_devtools_extension/src/tree_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a leaf node payload as sent by the app.
Map<String, Object?> leaf(String kind, Object? value, [String? type]) =>
    {'kind': kind, 'type': type ?? kind, 'value': value};

/// Builds a container node payload with the given children.
Map<String, Object?> container(String kind, String type, Map<String, Map<String, Object?>> kids) => {
      'kind': kind,
      'type': type,
      'length': kids.length,
      'children': [
        for (final e in kids.entries) {'key': e.key, 'node': e.value},
      ],
    };

/// Creates a tree from [data] without animation.
TreeNodeModel build(Map<String, Object?> data) =>
    TreeNodeModel(key: 'Root')..applyUpdate(data.cast<String, dynamic>(), animate: false);

/// Tests for [TreeNodeModel] merging, diffs and bloc history.
void main() {
  group('TreeNodeModel.applyUpdate', () {
    test('builds children in order', () {
      final root = build(container('object', 'S', {'a': leaf('int', 1), 'b': leaf('String', 'x')}));
      expect(root.children.map((c) => c.key), ['a', 'b']);
      expect(root.children[1].value, 'x');
      expect(root.children[1].path, ['b']);
    });

    test('keeps node identity and only notifies changed rows', () {
      final root = build(container('object', 'S', {'a': leaf('int', 1), 'b': leaf('int', 2)}));
      final a = root.children[0], b = root.children[1];
      var aBumps = 0, bBumps = 0;
      a.header.addListener(() => aBumps++);
      b.header.addListener(() => bBumps++);

      final changed = root.applyUpdate(
        container('object', 'S', {'a': leaf('int', 1), 'b': leaf('int', 3)}).cast<String, dynamic>(),
        animate: false,
      );

      expect(changed, isTrue);
      expect(identical(root.children[1], b), isTrue);
      expect(b.value, 3);
      expect(aBumps, 0);
      expect(bBumps, 1);
    });

    test('returns false when nothing changed', () {
      final data = container('object', 'S', {'a': leaf('int', 1)});
      final root = build(data);
      expect(root.applyUpdate(data.cast<String, dynamic>(), animate: false), isFalse);
    });

    test('preserves expanded state across updates', () {
      final root = build(container('object', 'S', {
        'inner': container('map', 'Map', {'x': leaf('int', 1)}),
      }));
      root.children[0].expanded = true;
      root.applyUpdate(
        container('object', 'S', {
          'inner': container('map', 'Map', {'x': leaf('int', 2)}),
        }).cast<String, dynamic>(),
        animate: false,
      );
      expect(root.children[0].expanded, isTrue);
      expect(root.children[0].children[0].value, 2);
    });

    test('adds and removes children', () {
      final root = build(container('list', 'List', {'0': leaf('int', 1), '1': leaf('int', 2)}));
      var structure = 0;
      root.structure.addListener(() => structure++);
      root.applyUpdate(
        container('list', 'List', {'0': leaf('int', 1)}).cast<String, dynamic>(),
        animate: false,
      );
      expect(root.children.length, 1);
      expect(structure, 1);
    });

    test('container turning into a leaf drops its children', () {
      final root = build(container('object', 'S', {'a': leaf('int', 1)}));
      root.applyUpdate(leaf('null', null).cast<String, dynamic>(), animate: false);
      expect(root.children, isEmpty);
      expect(root.isContainer, isFalse);
    });

    test('flashes changed leaf', () {
      final root = build(container('object', 'S', {'a': leaf('int', 1)}));
      root.applyUpdate(container('object', 'S', {'a': leaf('int', 2)}).cast<String, dynamic>(),
          animate: true);
      expect(root.children[0].flash.value?.kind, FlashKind.changed);
      expect(root.flash.value?.kind, FlashKind.descendant);
    });

    test('flashes removal on the parent', () {
      final root = build(container('list', 'List', {'0': leaf('int', 1), '1': leaf('int', 2)}));
      root.applyUpdate(container('list', 'List', {'0': leaf('int', 1)}).cast<String, dynamic>(),
          animate: true);
      expect(root.flash.value?.kind, FlashKind.removed);
    });
  });

  group('diff (changes)', () {
    test('records old -> new for a changed leaf', () {
      final root = build(container('object', 'S', {'count': leaf('int', 1)}));
      final changes = <NodeChange>[];
      root.applyUpdate(container('object', 'S', {'count': leaf('int', 2)}).cast<String, dynamic>(),
          animate: false, changes: changes);
      expect(changes, hasLength(1));
      expect(changes.single.path, ['count']);
      expect(changes.single.kind, ChangeKind.changed);
      expect(changes.single.oldValue, '1');
      expect(changes.single.newValue, '2');
    });

    test('records nested paths, quotes strings, formats doubles', () {
      final root = build(container('object', 'S', {
        'user': container('object', 'User', {
          'name': leaf('String', 'a'),
          'score': leaf('double', 1.0),
        }),
      }));
      final changes = <NodeChange>[];
      root.applyUpdate(
        container('object', 'S', {
          'user': container('object', 'User', {
            'name': leaf('String', 'b'),
            'score': leaf('double', 2.5),
          }),
        }).cast<String, dynamic>(),
        animate: false,
        changes: changes,
      );
      expect(changes.map((c) => c.pathLabel), ['user.name', 'user.score']);
      expect(changes[0].oldValue, '"a"');
      expect(changes[0].newValue, '"b"');
      expect(changes[1].oldValue, '1.0');
      expect(changes[1].newValue, '2.5');
    });

    test('records added and removed items', () {
      final root = build(container('list', 'List', {'0': leaf('int', 1), '1': leaf('int', 2)}));
      final changes = <NodeChange>[];
      root.applyUpdate(
        container('list', 'List', {'0': leaf('int', 1), '2': leaf('int', 9)}).cast<String, dynamic>(),
        animate: false,
        changes: changes,
      );
      expect(changes.where((c) => c.kind == ChangeKind.removed).single.path, ['1']);
      expect(changes.where((c) => c.kind == ChangeKind.removed).single.oldValue, '2');
      expect(changes.where((c) => c.kind == ChangeKind.added).single.path, ['2']);
      expect(changes.where((c) => c.kind == ChangeKind.added).single.newValue, '9');
    });

    test('primitive root state has an empty path', () {
      final root = build(leaf('int', 1));
      final changes = <NodeChange>[];
      root.applyUpdate(leaf('int', 2).cast<String, dynamic>(), animate: false, changes: changes);
      expect(changes.single.path, isEmpty);
      expect(changes.single.pathLabel, 'state');
    });

    test('no changes recorded when nothing differs', () {
      final data = container('object', 'S', {'a': leaf('int', 1)});
      final root = build(data);
      final changes = <NodeChange>[];
      root.applyUpdate(data.cast<String, dynamic>(), animate: false, changes: changes);
      expect(changes, isEmpty);
    });

    test('shape change is one entry, not one per child', () {
      final root = build(leaf('null', null));
      final changes = <NodeChange>[];
      root.applyUpdate(
        container('object', 'S', {'a': leaf('int', 1), 'b': leaf('int', 2)}).cast<String, dynamic>(),
        animate: false,
        changes: changes,
      );
      expect(changes, hasLength(1));
      expect(changes.single.oldValue, 'null');
      expect(changes.single.newValue, 'S (2)');
    });
  });

  group('BlocEntryModel history', () {
    test('records, caps and clears', () {
      final e = BlocEntryModel(id: 1, name: 'C', blocKind: 'Cubit');
      var bumps = 0;
      e.historyChanged.addListener(() => bumps++);
      e.lastEvent = 'Inc';
      for (var i = 0; i < BlocEntryModel.maxHistory + 5; i++) {
        e.recordHistory([const NodeChange([], ChangeKind.changed, oldValue: '0', newValue: '1')]);
      }
      expect(e.history.length, BlocEntryModel.maxHistory);
      expect(e.history.first.index, 6);
      expect(e.history.last.event, 'Inc');
      expect(bumps, BlocEntryModel.maxHistory + 5);
      e.clearHistory();
      expect(e.history, isEmpty);
    });
  });
}
