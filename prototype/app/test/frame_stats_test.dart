import 'package:archive_prototype/measure/frame_stats.dart';
import 'package:flutter_test/flutter_test.dart';

/// 144Hz에서 한 장면의 예산은 6.94ms. 기본 표본은 넉넉히 합격하는 장면이다.
List<FrameSample> steady(int n, {double build = 2, double raster = 3, double gap = 6.94}) => [
  for (int i = 0; i < n; i++)
    FrameSample(buildMs: build, rasterMs: raster, vsyncGapMs: gap),
];

void main() {
  test('고르게 빠른 구간은 합격한다', () {
    final v = judge(steady(1000), 144);
    expect(v.pass, isTrue);
    expect(v.frames, 1000);
    expect(v.missedRatio, 0);
    expect(v.maxConsecutiveMissed, 0);
    expect(v.over50, 0);
    expect(v.buildP99, 2);
    expect(v.rasterP99, 3);
    expect(v.budgetMs, closeTo(6.944, .001));
  });

  test('놓친 장면이 1%를 넘으면 미달이다', () {
    final frames = steady(1000);
    for (int i = 0; i < 11; i++) {
      frames[i * 50] = const FrameSample(
        buildMs: 2,
        rasterMs: 7.5,
        vsyncGapMs: 6.94,
      );
    }
    final v = judge(frames, 144);
    expect(v.missedRatio, closeTo(.011, 1e-9));
    expect(v.maxConsecutiveMissed, 1);
    expect(v.pass, isFalse);
    // 꼭 10장(1%)이면 놓친 비율로는 합격선 안이다.
    frames[0] = const FrameSample(buildMs: 2, rasterMs: 3, vsyncGapMs: 6.94);
    expect(judge(frames, 144).missedRatio, closeTo(.01, 1e-9));
  });

  test('두 장을 연달아 놓치면 비율이 낮아도 미달이다', () {
    final frames = steady(1000);
    frames[400] = const FrameSample(buildMs: 7.2, rasterMs: 3, vsyncGapMs: 6.94);
    frames[401] = const FrameSample(
      buildMs: 2,
      rasterMs: 3,
      vsyncGapMs: 13.9,
    );
    final v = judge(frames, 144);
    expect(v.missedRatio, closeTo(.002, 1e-9));
    expect(v.maxConsecutiveMissed, 2);
    expect(v.pass, isFalse);
  });

  test('50ms 이상 멈춤은 한 번이어도 미달이다', () {
    final frames = steady(1000);
    frames[10] = const FrameSample(buildMs: 2, rasterMs: 3, vsyncGapMs: 51);
    final v = judge(frames, 144);
    expect(v.over50, 1);
    expect(v.pass, isFalse);
  });

  test('화면 만들기의 느린 1% 경계가 예산의 80%를 넘으면 미달이다', () {
    final frames = steady(1000);
    for (int i = 0; i < 11; i++) {
      frames[i * 50] = const FrameSample(
        buildMs: 5.6,
        rasterMs: 3,
        vsyncGapMs: 6.94,
      );
    }
    final v = judge(frames, 144);
    expect(v.missedRatio, 0, reason: '5.6ms는 예산 6.94ms 안이라 놓친 장면은 아니다');
    expect(v.buildP99, 5.6);
    expect(v.pass, isFalse);
  });

  test('잰 장면이 없으면 미달이다', () {
    expect(judge(const [], 144).pass, isFalse);
  });

  test('주사율이 낮으면 같은 표본이 합격한다', () {
    final frames = steady(1000, build: 6, raster: 9, gap: 16.67);
    expect(judge(frames, 144).pass, isFalse);
    expect(judge(frames, 60).pass, isTrue);
  });

  test('놓친 장면을 까닭별로 센다: 만들기 · 칠하기 · 간격(하나의 장면이 여러 까닭에 들 수 있다)', () {
    final frames = [
      ...steady(100),
      const FrameSample(buildMs: 8, rasterMs: 2, vsyncGapMs: 6.94), // 만들기
      const FrameSample(buildMs: 1, rasterMs: 9, vsyncGapMs: 14), // 칠하기 + 간격
      const FrameSample(buildMs: 1, rasterMs: 2, vsyncGapMs: 11), // 간격만: 일은 가벼웠는데 장면이 늦게 시작됐다
    ];
    final v = judge(frames, 144);
    expect((v.missedByBuild, v.missedByRaster, v.missedByGap), (1, 1, 2));
    expect(v.toJson()['missed_by'], {'build': 1, 'raster': 1, 'gap': 2});
  });

  test('결과는 보고서에 실을 수 있는 값으로 바뀐다', () {
    final json = judge(steady(10), 144).toJson();
    expect(json['pass'], isTrue);
    expect(json.keys, containsAll(['frames', 'missed_ratio', 'max_consecutive_missed', 'over_50ms', 'build_p99_ms', 'raster_p99_ms', 'budget_ms']));
  });
}
