import 'package:flutter/material.dart';

import 'report.dart';

// 앱 안의 측정 결과 요약: 전체 판정, 구간마다 한 줄, 결과 폴더. 자세한 수치는 폴더의 측정.json에 있다.
class MeasureSummaryView extends StatelessWidget {
  const MeasureSummaryView({super.key, required this.report, required this.folder});
  final Map<String, dynamic> report;
  final String folder;

  @override
  Widget build(BuildContext context) {
    final result = '${report['result']}';
    final color = switch (result) { '합격' => const Color(0xff000000), '미달' => const Color(0xff000000), _ => const Color(0x99000000) };
    final cases = [for (final c in report['cases'] as List) Map<String, dynamic>.from(c as Map)];
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('측정 결과 · $result', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: color)),
          const SizedBox(height: 6),
          Text(
            '화면 ${report['display_hz'] ?? '-'}Hz · 한 장면의 예산은 1000 ÷ 주사율(ms). 합격 = 놓친 장면 1% 이하 · 연달아 놓침 없음 · 50ms 멈춤 없음 · 만들기와 칠하기의 느린 1%가 예산의 80% 이하.',
            style: const TextStyle(fontSize: 12, color: Color(0x99000000), height: 1.6),
          ),
          const SizedBox(height: 14),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final c in cases)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: SelectableText(summaryLine(c), style: const TextStyle(fontSize: 12.5, height: 1.5)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SelectableText('자세한 기록: $folder', style: const TextStyle(fontSize: 12, color: Color(0x99000000))),
          const SizedBox(height: 4),
          const Text('합성 입력으로 잰 값입니다 — 실물 마우스의 지연과 화면이 실제로 빛나는 시각은 들어 있지 않습니다.', style: TextStyle(fontSize: 12, color: Color(0x99000000))),
        ],
      ),
    );
  }
}
