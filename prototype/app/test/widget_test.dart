import 'package:archive_prototype/archive_app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('기원전 표시는 0년을 만들지 않는다', () {
    final minute = DateTime.utc(0, 1, 1).millisecondsSinceEpoch / 60000;
    expect(dateLabel(minute).startsWith('기원전 1년'), isTrue);
  });
}
