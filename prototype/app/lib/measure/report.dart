import 'dart:math' as math;

import 'frame_stats.dart';

// 측정 보고서의 모양. 화면과 무관한 순수 계산이라 검사로 못 박아 둔다.
//  · 구간 하나 = caseJson, 전체 = buildReport. scripts/measure.mjs와 앱 안의 결과 화면이 같은 모양을 읽는다.
//  · 전체 판정: 무효 구간이 있으면 '무효'(다시 잰다), 미달 구간이 하나라도 있으면 '미달', 아니면 '합격'.
//    처음 1회(찬 상태 — 보관이 비어 있을 때)는 따로 적고 판정에는 넣지 않는다.

/// 분포의 요약: 개수 · 가운데 · 느린 5% · 느린 1% 경계 · 최대.
Map<String, dynamic> distribution(List<num> values) {
  if (values.isEmpty) return {'n': 0};
  final list = [for (final v in values) v.toDouble()];
  return {'n': list.length, 'p50': percentile(list, .5), 'p95': percentile(list, .95), 'p99': percentile(list, .99), 'max': list.reduce(math.max)};
}

/// 구간 하나의 기록. [series]는 장면마다의 값(분포로 줄여 담는다), [counts]는 그대로 담는 수.
Map<String, dynamic> caseJson({
  required String name,
  required int repeat,
  required int seconds,
  required bool cold,
  required bool valid,
  required List<String> outsideInputs,
  required SectionVerdict verdict,
  Map<String, List<num>> series = const {},
  Map<String, Object?> counts = const {},
  List<Map<String, num>> missedFrames = const [],
}) => {
  'name': name,
  'repeat': repeat,
  'seconds': seconds,
  'cold': cold,
  // 장면이 기대의 절반도 안 찍혔거나(창이 가려졌거나 멈춤) 밖에서 입력이 끼어들었으면 그 구간은 무효다 — 다시 잰다.
  'valid': valid,
  'outside_inputs': outsideInputs.take(10).toList(),
  'verdict': verdict.toJson(),
  'missed_frames': missedFrames.take(60).toList(),
  for (final entry in series.entries) entry.key: distribution(entry.value),
  ...counts,
};

String _label(Map<String, dynamic> c) => '${c['name']}#${c['repeat']}${c['cold'] == true ? '(처음)' : ''}';

/// 전체 보고서. [environment]는 기기 · 화면 · 자료 · 입력 경로의 기록으로, 맨 위에 펼쳐 담는다.
Map<String, dynamic> buildReport({required Map<String, Object?> environment, required List<Map<String, dynamic>> cases}) {
  final judged = [for (final c in cases) if (c['cold'] != true) c];
  final invalid = [for (final c in judged) if (c['valid'] != true) _label(c)];
  final failed = [for (final c in judged) if (c['valid'] == true && (c['verdict'] as Map)['pass'] != true) _label(c)];
  final result = invalid.isNotEmpty ? '무효' : (failed.isNotEmpty || judged.isEmpty ? '미달' : '합격');
  return {
    ...environment,
    'result': result,
    'pass': result == '합격',
    'failed_sections': failed,
    'invalid_sections': invalid,
    'cases': cases,
  };
}

/// 구간 하나를 한 줄로.
String summaryLine(Map<String, dynamic> c) {
  final v = Map<String, dynamic>.from(c['verdict'] as Map);
  String ms(String key, String p) => ((c[key] as Map?)?[p] as num?)?.toStringAsFixed(2) ?? '-';
  final state = c['valid'] != true ? '무효' : (v['pass'] == true ? '합격' : '미달');
  final by = v['missed_by'] as Map?;
  final why = by == null || (v['missed_ratio'] as num) == 0 ? '' : '(만들기 ${by['build']} · 칠하기 ${by['raster']} · 간격 ${by['gap']})';
  return '${_label(c)} $state | 장면 ${v['frames']} · 놓침 ${((v['missed_ratio'] as num) * 100).toStringAsFixed(2)}%$why · 연달아 ${v['max_consecutive_missed']} · 50ms+ ${v['over_50ms']}'
      ' | 만들기 p99 ${ms('build_ms', 'p99')} · 칠하기 p99 ${ms('raster_ms', 'p99')} (한도 ${((v['budget_ms'] as num) * .8).toStringAsFixed(2)})'
      ' | 입력→반응 p95 ${ms('input_to_first_response_ms', 'p95')}ms · 빈 자리 ${c['blank_tiles'] ?? '-'}';
}
