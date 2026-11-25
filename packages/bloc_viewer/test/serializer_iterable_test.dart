import 'package:bloc_viewer/src/serializer.dart';
import 'package:test/test.dart';

class ListJson {
  List<Object?> toJson() => [1, 'two'];
}

void main() {
  test('object whose toJson() returns a list is shown as indexed children', () {
    final n = encodeNode(ListJson());
    expect(n['kind'], 'object');
    expect(n['length'], 2);
    final kids = n['children'] as List;
    expect(kids.map((c) => (c as Map)['key']), ['0', '1']);
  });
}
