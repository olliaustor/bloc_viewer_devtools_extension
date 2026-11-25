import 'package:bloc_viewer/src/serializer.dart';
import 'package:test/test.dart';

/// Sample enum for encoding tests.
enum Color { red, green }

/// Sample object with `toJson()`.
class WithJson {
  /// Creates the sample with [a] and [b].
  WithJson(this.a, this.b);
  /// Integer field.
  final int a;
  /// String field.
  final String b;
  /// Serializes to a JSON map.
  Map<String, dynamic> toJson() => {'a': a, 'b': b};
}

/// Sample Equatable-style object exposing `props`.
class WithProps {
  /// Values shown read-only by the serializer.
  List<Object?> get props => [1, 'x'];
}

/// Sample object with only a `toString()`.
class Plain {
  @override
  String toString() => 'plain!';
}

/// Sample object whose `toString()` throws.
class Throwing {
  @override
  String toString() => throw StateError('boom');
}

/// Tests for the serializer.
void main() {
  tearDown(encoders.clear);

  group('encodeNode', () {
    test('primitives carry an explicit kind', () {
      expect(encodeNode(1), {'kind': 'int', 'type': 'int', 'value': 1});
      expect(encodeNode(1.5), {'kind': 'double', 'type': 'double', 'value': 1.5});
      expect(encodeNode(true), {'kind': 'bool', 'type': 'bool', 'value': true});
      expect(encodeNode('s'), {'kind': 'String', 'type': 'String', 'value': 's'});
      expect(encodeNode(null), {'kind': 'null', 'type': 'Null', 'value': null});
    });

    test('whole double stays a double', () {
      expect(encodeNode(2.0)['kind'], 'double');
    });

    test('non-finite doubles become strings', () {
      final n = encodeNode(double.nan);
      expect(n['kind'], 'other');
      expect(n['value'], 'NaN');
      expect(encodeNode(double.infinity)['value'], 'Infinity');
    });

    test('enum', () {
      expect(encodeNode(Color.green), {'kind': 'enum', 'type': 'Color', 'value': 'green'});
    });

    test('list', () {
      final n = encodeNode([1, 'a']);
      expect(n['kind'], 'list');
      expect(n['length'], 2);
      final kids = n['children'] as List;
      expect(kids.map((c) => (c as Map)['key']), ['0', '1']);
      expect(((kids[1] as Map)['node'] as Map)['value'], 'a');
    });

    test('map keys are stringified', () {
      final n = encodeNode({1: 'x', 'k': true});
      expect(n['kind'], 'map');
      final kids = n['children'] as List;
      expect(kids.map((c) => (c as Map)['key']), ['1', 'k']);
    });

    test('object via toJson', () {
      final n = encodeNode(WithJson(3, 'z'));
      expect(n['kind'], 'object');
      expect(n['type'], 'WithJson');
      expect(n.containsKey('readOnly'), isFalse);
      final kids = n['children'] as List;
      expect(kids.map((c) => (c as Map)['key']), ['a', 'b']);
    });

    test('registered encoder wins and is used for nested values', () {
      encoders[Plain] = (o) => {'custom': 1};
      final n = encodeNode([Plain()]);
      final inner = ((n['children'] as List).first as Map)['node'] as Map;
      expect(inner['kind'], 'object');
      expect((inner['children'] as List).single['key'], 'custom');
    });

    test('props fallback is read-only', () {
      final n = encodeNode(WithProps());
      expect(n['kind'], 'object');
      expect(n['readOnly'], isTrue);
      expect((n['children'] as List).map((c) => (c as Map)['key']), ['props[0]', 'props[1]']);
    });

    test('unknown object falls back to toString', () {
      final n = encodeNode(Plain());
      expect(n['kind'], 'other');
      expect(n['value'], 'plain!');
    });

    test('throwing toString does not crash', () {
      expect(encodeNode(Throwing())['kind'], 'other');
    });

    test('children are capped but length is the real total', () {
      final n = encodeNode(List.generate(600, (i) => i));
      expect(n['length'], 600);
      expect((n['children'] as List).length, 500);
    });

    test('depth limit stops recursion', () {
      Object? nested = 1;
      for (var i = 0; i < 30; i++) {
        nested = [nested];
      }
      var node = encodeNode(nested);
      var depth = 0;
      while (node['kind'] == 'list') {
        node = (node['children'] as List).single['node'] as Map<String, Object?>;
        depth++;
      }
      expect(node['kind'], 'other');
      expect(depth, lessThan(30));
    });
  });

  group('toPlain', () {
    test('primitives and null pass through', () {
      expect(toPlain(1), 1);
      expect(toPlain('s'), 's');
      expect(toPlain(null), isNull);
      expect(toPlain(false), false);
    });

    test('non-finite numbers become strings', () {
      expect(toPlain(double.nan), 'NaN');
    });

    test('enum becomes its name', () {
      expect(toPlain(Color.red), 'red');
    });

    test('nested structures', () {
      expect(
        toPlain({'list': [WithJson(1, 'a'), Color.green], 2: null}),
        {
          'list': [
            {'a': 1, 'b': 'a'},
            'green'
          ],
          '2': null,
        },
      );
    });

    test('unknown object becomes toString', () {
      expect(toPlain(Plain()), 'plain!');
    });
  });

  test('isPrimitive', () {
    expect(isPrimitive(1), isTrue);
    expect(isPrimitive(1.0), isTrue);
    expect(isPrimitive('a'), isTrue);
    expect(isPrimitive(true), isTrue);
    expect(isPrimitive(null), isFalse);
    expect(isPrimitive([1]), isFalse);
  });
}
