// 한 구간이 합격선을 지켰는지 판정하는 산수. 화면과 무관한 순수 계산이라 검사로 못 박아 둔다.
// 합격선은 docs/설계-아카이브-2단계-규모와-병목-검증.md 3절: 한 장면의 예산 T = 1000 ÷ 주사율.

/// 한 장면의 기록(ms). vsyncGapMs는 앞 장면의 vsync 시작과의 간격이고 첫 장면은 0.
class FrameSample {
  const FrameSample({
    required this.buildMs,
    required this.rasterMs,
    required this.vsyncGapMs,
  });
  final double buildMs, rasterMs, vsyncGapMs;
}

class SectionVerdict {
  const SectionVerdict({
    required this.frames,
    required this.budgetMs,
    required this.missedRatio,
    required this.maxConsecutiveMissed,
    required this.over50,
    required this.buildP99,
    required this.rasterP99,
    required this.pass,
    this.missedByBuild = 0,
    this.missedByRaster = 0,
    this.missedByGap = 0,
  });
  final int frames, maxConsecutiveMissed, over50;
  final double budgetMs, missedRatio, buildP99, rasterP99;
  final bool pass;

  /// 놓친 장면을 까닭별로: 만들기가 예산을 넘음 · 칠하기가 예산을 넘음 · 앞 장면과의 간격이 1.5T를 넘음(한 장면이 여러 까닭에 들 수 있다).
  /// 간격만 넘은 장면은 일이 무거워서가 아니라 장면이 늦게 시작된 것이다(다른 프로그램 · 화면 합성기의 흔들림).
  final int missedByBuild, missedByRaster, missedByGap;

  Map<String, dynamic> toJson() => {
    'pass': pass,
    'frames': frames,
    'budget_ms': budgetMs,
    'missed_ratio': missedRatio,
    'max_consecutive_missed': maxConsecutiveMissed,
    'over_50ms': over50,
    'build_p99_ms': buildP99,
    'raster_p99_ms': rasterP99,
    'missed_by': {'build': missedByBuild, 'raster': missedByRaster, 'gap': missedByGap},
  };
}

/// 느린 쪽 경계(백분위). 1단계 측정과 같은 올림 규칙.
double percentile(List<double> values, double p) {
  if (values.isEmpty) return 0;
  final sorted = values.toList()..sort();
  return sorted[(sorted.length * p).ceil().clamp(1, sorted.length) - 1];
}

/// 놓친 장면 = 화면 만들기나 칠하기가 예산 T를 넘었거나, 앞 장면과의 간격이 1.5T를 넘은 장면.
/// 합격 = 놓친 비율 1% 이하 · 2장 이상 연달아 놓침 없음 · 50ms 이상 멈춤 없음 · 만들기와 칠하기의 느린 1% 경계가 각각 0.8T 이하.
SectionVerdict judge(List<FrameSample> frames, double hz) {
  final budget = 1000 / hz;
  int missed = 0, run = 0, longestRun = 0, over50 = 0, byBuild = 0, byRaster = 0, byGap = 0;
  for (final f in frames) {
    final slowBuild = f.buildMs > budget, slowRaster = f.rasterMs > budget, late = f.vsyncGapMs > budget * 1.5;
    if (slowBuild) byBuild++;
    if (slowRaster) byRaster++;
    if (late) byGap++;
    if (slowBuild || slowRaster || late) {
      missed++;
      run++;
      if (run > longestRun) longestRun = run;
    } else {
      run = 0;
    }
    if (f.vsyncGapMs >= 50) over50++;
  }
  final ratio = frames.isEmpty ? 0.0 : missed / frames.length;
  final buildP99 = percentile([for (final f in frames) f.buildMs], .99);
  final rasterP99 = percentile([for (final f in frames) f.rasterMs], .99);
  return SectionVerdict(
    frames: frames.length,
    budgetMs: budget,
    missedRatio: ratio,
    maxConsecutiveMissed: longestRun,
    over50: over50,
    buildP99: buildP99,
    rasterP99: rasterP99,
    missedByBuild: byBuild,
    missedByRaster: byRaster,
    missedByGap: byGap,
    pass:
        frames.isNotEmpty &&
        ratio <= .01 + 1e-12 &&
        longestRun < 2 &&
        over50 == 0 &&
        buildP99 <= budget * .8 &&
        rasterP99 <= budget * .8,
  );
}
