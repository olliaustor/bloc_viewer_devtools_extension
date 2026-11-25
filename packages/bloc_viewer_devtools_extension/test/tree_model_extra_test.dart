import 'package:bloc_viewer_devtools_extension/src/tree_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  group('NodeChange', () {
    test('pathLabel and toString', () {
      const root = NodeChange([], ChangeKind.changed, oldValue: '1', newValue: '2');
      expect(root.pathLabel, 'state');
      const nested = NodeChange(['a', 'b'], ChangeKind.added, newValue: '3');
      expect(nested.pathLabel, 'a.b');
      expect(nested.toString(), 'a.b: ChangeKind.added null -> 3');
    });
  });

  group('describe', () {
    TreeNodeModel node(Map<String, dynamic> data) =>
        TreeNodeModel(key: 'k')..applyUpdate(data, animate: false);

    test('containers show type and length', () {
      expect(node(container('list', 'List<int>', {'0': leaf('int', 1)})).describe(),
          'List<int> (1)');
      expect(node({'kind': 'map', 'type': 'Map'}).describe(), 'Map');
    });

    test('leaves', () {
      expect(node(leaf('String', 'a')).describe(), '"a"');
      expect(node(leaf('double', 2.0)).describe(), '2.0');
      expect(node(leaf('double', 2.5)).describe(), '2.5');
      expect(node(leaf('double', 1e20)).describe(), '${1e20}');
      expect(node(leaf('int', 3)).describe(), '3');
      expect(node(leaf('null', null)).describe(), 'null');
    });
  });

  test('a child added while animating flashes as added after a frame', () async {
    final root = TreeNodeModel(key: 'r')
      ..applyUpdate(container('object', 'S', {'a': leaf('int', 1)}), animate: false);
    root.applyUpdate(container('object', 'S', {'a': leaf('int', 1), 'b': leaf('int', 2)}),
        animate: true);
    final added = root.children.last;
    expect(added.flash.value, isNull);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(added.flash.value?.kind, FlashKind.added);
  });

  test('expansion helpers notify only on real changes', () {
    final root = TreeNodeModel(key: 'r')
      ..applyUpdate(container('object', 'S', {'a': container('map', 'M', {})}), animate: false);
    var bumps = 0;
    root.structure.addListener(() => bumps++);
    root.setExpanded(false); // already collapsed
    expect(bumps, 0);
    root.setExpanded(true);
    expect(bumps, 1);
    root.setExpandedRecursive(true);
    expect(root.children.single.expanded, isTrue);
  });

  group('BlocEntryModel history', () {
    test('is capped and can be cleared', () {
      final e = BlocEntryModel(id: 1, name: 'X', blocKind: 'Cubit');
      var notified = 0;
      e.historyChanged.addListener(() => notified++);
      for (var i = 0; i < BlocEntryModel.maxHistory + 5; i++) {
        e.recordHistory([const NodeChange([], ChangeKind.changed, oldValue: 'a', newValue: 'b')]);
      }
      expect(e.history, hasLength(BlocEntryModel.maxHistory));
      expect(e.history.first.index, 6); // the five oldest were dropped
      expect(e.root.badge, 'Cubit');
      e.clearHistory();
      expect(e.history, isEmpty);
      expect(notified, BlocEntryModel.maxHistory + 6);
    });
  });
}
