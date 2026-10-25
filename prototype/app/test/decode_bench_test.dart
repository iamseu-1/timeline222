import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive_prototype/scene/tile.dart';
import 'package:flutter_test/flutter_test.dart';

// 전달 형식을 바꾼 효과(설계 5.1): 같은 타일을 JSON 글자열로 받아 풀 때와 이진 타일로 받아 배열 보기만 얹을 때의 해독 시간.
// 큰 표본이 있으면 그것으로 잰다(2단계의 decode-sample.bin은 1판이라 쓰지 않는다 — 이름을 새로 둔다):
//   archive-tool tile data/v3-1m/archive.db '{"level":11,"x":-1,"chunk":0,"packs":[1,2,3,4,5,6,7,8]}' results/decode-sample-v3.bin
// 결과는 results/decode-bench-v3.json에 적는다(보고서가 싣는다).

Map<String, dynamic> asJson(Tile t) => {
  'level': t.level, 'x': t.x, 'chunk': t.chunk, 'origin': t.origin, 'span': t.span,
  'bands': [
    for (int i = 0; i < t.bandCount; i++)
      {'x0': t.bandX0[i], 'x1': t.bandX1[i], 'id': t.bandId[i], 'color': t.bandColor[i], 'name': t.text(t.bandName[i]), 'row': t.bandRow[i], 'flags': t.bandFlags[i],
       'look': t.bandLook[i], 'tag': t.text(t.bandTag[i]), 'sub': t.bandSub[i]},
  ],
  'cells': [
    for (int i = 0; i < t.cellCount; i++)
      {'x0': t.cellX0[i], 'x1': t.cellX1[i], 'id': t.cellId[i], 'name': t.text(t.cellName[i]), 'row': t.cellRow[i], 'kind': t.cellKind[i],
       'lane': t.cellLane[i], 'style': t.cellStyle[i], 'color': t.cellColor[i]},
  ],
  'events': [
    for (int i = 0; i < t.eventCount; i++)
      {'x0': t.eventX0[i], 'x1': t.eventX1[i], 'id': t.eventId[i], 'name': t.text(t.eventName[i]), 'row': t.eventRow[i], 'bits': t.eventBits[i],
       'look': t.eventLook[i], 'label': t.text(t.eventLabel[i]), 'rail': t.eventRail[i], 'band': t.eventBand[i]},
  ],
  'pills': [
    for (int i = 0; i < t.pillCount; i++) {'x0': t.pillX0[i], 'x1': t.pillX1[i], 'count': t.pillRest[i], 'row': t.pillRow[i]},
  ],
  'sections': [
    for (final kind in t.sectionKinds)
      if (kind >= Tile.secGeneral)
        {
          'kind': kind,
          'items': [
            for (int i = 0; i < t.section(kind).count; i++)
              {'x0': t.section(kind).f(0)[i], 'x1': t.section(kind).f(1)[i], 'id': t.section(kind).u(2)[i],
               'name': t.text(t.section(kind).u(3)[i]), 'row': t.section(kind).u(4)[i], 'row2': t.section(kind).u(6)[i],
               'ref': t.section(kind).u(7)[i], 'color': t.section(kind).u(8)[i]},
          ],
        },
  ],
};

double medianMicros(void Function() work, {int rounds = 30}) {
  for (int i = 0; i < 5; i++) {
    work(); // 데우기
  }
  final times = <int>[];
  for (int i = 0; i < rounds; i++) {
    final watch = Stopwatch()..start();
    work();
    times.add(watch.elapsedMicroseconds);
  }
  times.sort();
  return times[times.length ~/ 2].toDouble();
}

void main() {
  test('이진 타일은 JSON보다 훨씬 빨리 풀린다(같은 내용 · 같은 타일)', () {
    final big = File('../results/decode-sample-v3.bin');
    final bytes = big.existsSync() ? big.readAsBytesSync() : File('test/fixtures/tile-100k-L9-x0-c0.bin').readAsBytesSync();
    final tile = Tile.decode(bytes);
    final text = jsonEncode(asJson(tile));
    final encoded = Uint8List.fromList(utf8.encode(text));
    int items = 0;
    final binary = medianMicros(() {
      final t = Tile.decode(bytes);
      // 2판의 열은 물을 때 배열 보기를 얹는다 — JSON 쪽과 견주려면 쓸 열을 실제로 짚어야 한다.
      items = t.bandX0.length + t.cellKind.length + t.eventBits.length + t.pillRest.length;
      items += t.bandLook.length + t.cellLane.length + t.eventBand.length;
    });
    final json = medianMicros(() {
      final m = jsonDecode(utf8.decode(encoded)) as Map<String, dynamic>;
      items = (m['bands'] as List).length + (m['cells'] as List).length + (m['events'] as List).length + (m['pills'] as List).length;
    });
    final result = {
      'sample': big.existsSync() ? 'results/decode-sample-v3.bin' : 'test/fixtures/tile-100k-L9-x0-c0.bin',
      'items': items, 'binary_bytes': bytes.length, 'json_bytes': encoded.length,
      'tile_decode_us': binary, 'json_decode_us': json, 'ratio': json / (binary < 1 ? 1 : binary),
      'note': '가운데 값 · 30회. 이진 타일은 받은 바이트 위에 배열 보기만 얹고 글자는 물을 때 푼다. JSON은 값마다 객체를 만든다.',
    };
    final out = Directory('../results');
    if (out.existsSync()) File('../results/decode-bench-v3.json').writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(result)}\n');
    // ignore: avoid_print
    print(result);
    expect(json, greaterThan(binary * 10), reason: '열 배도 차이 나지 않으면 이진 형식을 둘 까닭이 없다');
  });
}
