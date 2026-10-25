import 'dart:convert';

import 'package:archive_prototype/measure/frame_stats.dart';
import 'package:archive_prototype/measure/report.dart';
import 'package:flutter_test/flutter_test.dart';

SectionVerdict verdict({required bool pass}) => judge([
  for (int i = 0; i < 600; i++) FrameSample(buildMs: 1, rasterMs: pass ? 2 : 9, vsyncGapMs: 6.94),
], 144);

Map<String, dynamic> section(String name, {bool pass = true, bool valid = true, bool cold = false}) => caseJson(
  name: name, repeat: 1, seconds: 30, cold: cold, valid: valid, outsideInputs: const [], verdict: verdict(pass: pass),
  series: {'build_ms': [1, 1.5, 2], 'raster_ms': [2, 2.5], 'total_ms': [4, 5], 'input_to_first_response_ms': [5, 6]},
  counts: {'blank_tiles': 0, 'cover_tiles': 3},
);

void main() {
  test('구간 기록의 모양: 판정 · 분포(p50 · p95 · p99 · 최대) · 개수', () {
    final json = section('끌기');
    expect(json['name'], '끌기');
    expect(json['cold'], isFalse);
    expect(json['valid'], isTrue);
    expect((json['verdict'] as Map)['pass'], isTrue);
    expect((json['build_ms'] as Map).keys, containsAll(['n', 'p50', 'p95', 'p99', 'max']));
    expect((json['build_ms'] as Map)['max'], 2);
    expect(json['blank_tiles'], 0);
    expect(json['cover_tiles'], 3);
    expect(() => jsonEncode(json), returnsNormally);
  });

  test('미달 구간이 하나라도 있으면 전체가 미달이다', () {
    final report = buildReport(environment: const {'display_hz': 144}, cases: [section('끌기'), section('확대', pass: false), section('돋보기')]);
    expect(report['result'], '미달');
    expect(report['pass'], isFalse);
    expect(report['failed_sections'], ['확대#1']);
  });

  test('무효 구간(장면 부족 · 끼어든 입력)이 있으면 합격이라 하지 않고 다시 재라고 한다', () {
    final report = buildReport(environment: const {}, cases: [section('끌기'), section('확대', valid: false)]);
    expect(report['result'], '무효');
    expect(report['pass'], isFalse);
    expect(report['invalid_sections'], ['확대#1']);
  });

  test('모두 합격이면 합격. 처음 1회(찬 상태)는 따로 적고 판정에는 넣지 않는다', () {
    final report = buildReport(environment: const {'display_hz': 144}, cases: [section('끌기', cold: true, pass: false), section('끌기'), section('확대')]);
    expect(report['result'], '합격');
    expect(report['pass'], isTrue);
    expect((report['cases'] as List).length, 3);
    expect(report['display_hz'], 144, reason: '환경 기록은 맨 위에 펼쳐 담는다');
  });

  test('한 줄 요약', () {
    final line = summaryLine(section('끌기'));
    expect(line, contains('끌기#1'));
    expect(line, contains('합격'));
    expect(line, contains('놓침 0.00%'));
  });
}
