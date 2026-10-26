// 흐림(감독 지적 2026-10-26 "부정, 실재 논란, 불분명 시기 칠하는 방식이 너무 제각각 — 흐림으로" · 고름 다 "흐린 부분은 해당하는 기간만 흐리게 해줘.
// 전체 흐리게 하지말고" — paint/bands.dart BandLayer.toneOf · hazePeriod)의 칠 검사. 띠의 구간 흐림(연대 폭 · 미정 끝)은 bands_paint_test가 그림으로 본다.
import 'package:archive_prototype/scene/color_mix.dart';
import 'package:archive_prototype/scene/paint/bands.dart';
import 'package:archive_prototype/scene/paint/look.dart';
import 'package:archive_prototype/scene/paint/paint_pick.dart';
import 'package:flutter_test/flutter_test.dart';

const _rgb = 0x3a7bd5;
int _look({int cert = BandLook.certAccepted, int hs = BandLook.hsAttested, bool range = false}) =>
    (cert << BandLook.certShift) | (hs << BandLook.hsShift) | (range ? BandLook.hasRange : 0);

/// 종이에서 얼마나 먼가(세 채널 차의 합) — 흐릴수록 작다.
int _ink(int argb) {
  int d(int s) => (((argb >> s) & 0xff) - ((Look.paper >> s) & 0xff)).abs();
  return d(16) + d(8) + d(0);
}

void main() {
  tearDown(PaintPick.reset);

  test('기본(흐림 켬): 띠 전체에 붙은 표시(추정 · 전승 · 반전설 · 전설 · 논쟁 · 부정됨 · 미정)는 띠를 흐리지 않는다 — 보통 띠와 같은 칠 · 테', () {
    expect(PaintPick.haze, isTrue);
    final plain = BandLayer.toneOf(_rgb, _look(), fuzzy: false);
    final looks = [
      _look(cert: BandLook.certEstimated), _look(cert: BandLook.certLegend), _look(hs: BandLook.hsSemi), _look(hs: BandLook.hsLegendary),
      _look(hs: BandLook.hsDisputed), _look(hs: BandLook.hsRefuted, cert: BandLook.certLegend), _look(cert: BandLook.certEstimated, range: true),
    ];
    for (final l in looks) {
      final t = BandLayer.toneOf(_rgb, l, fuzzy: false);
      expect((t.fill, t.edge, t.hatch, t.fog, t.stroke), (plain.fill, plain.edge, false, 0.0, EdgeStroke.solid));
    }
    expect(BandLayer.toneOf(_rgb, _look(), fuzzy: true).fill, plain.fill, reason: '미정 띠도 띠 전체는 옅어지지 않음 — 미정 끝 구간만');
  });

  test('끔(--paint-off=haze)이면 옛 꼴(전설 안개 · 전승 빗금)', () {
    expect(PaintPick.turnOff('haze'), isTrue);
    expect(BandLayer.toneOf(_rgb, _look(hs: BandLook.hsLegendary), fuzzy: false).fog, greaterThan(0));
    expect(BandLayer.toneOf(_rgb, _look(cert: BandLook.certLegend), fuzzy: false).hatch, isTrue);
  });

  test('구간 흐림은 종이와 섞은 불투명 색 · 세기 .4(1배에서 옅은 나라 색에도 보이게)', () {
    expect(BandLayer.hazePeriod, .4);
    final c = 0xff000000 | _rgb;
    expect(_ink(BandLayer.hazed(c, BandLayer.hazePeriod)) < _ink(c), isTrue);
    expect(BandLayer.hazed(c, .5) >>> 24, 0xff);
    expect(BandLayer.hazed(withAlpha(c, .5), 0) >>> 24, 0xff);
  });
}
