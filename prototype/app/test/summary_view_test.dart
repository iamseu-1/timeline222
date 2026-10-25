import 'package:archive_prototype/measure/frame_stats.dart';
import 'package:archive_prototype/measure/report.dart';
import 'package:archive_prototype/measure/summary_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> section(String name, {required bool pass}) => caseJson(
  name: name, repeat: 1, seconds: 10, cold: false, valid: true, outsideInputs: const [],
  verdict: judge([for (int i = 0; i < 600; i++) FrameSample(buildMs: 1, rasterMs: pass ? 2 : 9, vsyncGapMs: 6.94)], 144),
  series: {'build_ms': [1, 2], 'raster_ms': [pass ? 2 : 9], 'input_to_first_response_ms': [5]},
  counts: {'blank_tiles': 0},
);

void main() {
  testWidgets('결과 요약 화면: 전체 판정과 구간마다 한 줄, 결과 폴더', (tester) async {
    final report = buildReport(environment: const {'display_hz': 144.0}, cases: [section('끌기', pass: true), section('돋보기', pass: false)]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MeasureSummaryView(report: report, folder: r'C:\별여울\측정-결과\20260921-153000'))));
    expect(find.text('측정 결과 · 미달'), findsOneWidget);
    expect(find.textContaining('끌기#1 합격'), findsOneWidget);
    expect(find.textContaining('돋보기#1 미달'), findsOneWidget);
    expect(find.textContaining(r'C:\별여울\측정-결과\20260921-153000'), findsOneWidget);
    expect(find.textContaining('합성 입력'), findsOneWidget, reason: '무엇을 잰 것인지 밝힌다');
  });

  testWidgets('모두 합격이면 합격이라고 보인다', (tester) async {
    final report = buildReport(environment: const {}, cases: [section('끌기', pass: true)]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MeasureSummaryView(report: report, folder: 'x'))));
    expect(find.text('측정 결과 · 합격'), findsOneWidget);
  });
}
