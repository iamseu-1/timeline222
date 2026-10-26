import '../color_mix.dart';
import 'look.dart';
import 'paint_pick.dart';

// 그림판 먹 여섯 단계 — 4단계 감독 고름 G5 #8 '먹 가'(2026-10-25 · 고르기 판 `.claude/research/stage4-choose/themes/g-g5-8.js`의 SETS.six ·
// docs/계획-리메이크-4단계.md 과제 9 걸음 2 덧글의 '바꾼 값 표').
//
// 그림판(띠 · 칸 · 사건 · 관계선 · 매단 이름표 · 폴더 · 상자 · 작은 꼬리표 · 열쇠표 · 문화권 머리 단과 그 밑 줄 · 실 · 뿔 · 인물 · 동군연합 ·
// 접힌 줄 막대 · 사건 글자)의 **먹과 종이만 섞은 회색 · 먹 알파**는 모두 이 파일의 길로 낸다:
//   · 85 글(이름 · 사건 · 이름표 글)   · 60 작은 글(수 · 손잡이 · 출처)   · 45 실(구멍 테 · 매다는 실 · 매듭 · 이름 종이 테)
//   · 25 테(상자 · 머리 단 · 칸 금 · 칩 테) · 12 가는 선(안쪽 겹선 · 주기 줄 테) · 4 칠(상자 뚜껑 · 머리 단 · 주기 줄 칠)
// 그대로 두는 것(이 길로 내지 않음): 그림판 바탕 [Look.ground] 6%(감독이 따로 고름) · 세로 눈금([Look.gridLine]) · 날짜 칸(axis.dart — 틀) ·
// 왼쪽 칸의 머리 단 밖(줄 이름 · 트랙 · 폴더 그림 — 틀 먹 B안) · 나라 색 섞임(설계 4-4 — 나라 색 + 먹 · 나라 색 + 종이) ·
// 상태 먹(고른 테 · 고른 실 100 · 검색 강조 · 올린 것) · 도착 고리(overlay.dart).
//
// 쓰는 길은 셋이다 — 모두 **옛 값**을 받아 단계로 바꾼다(스위치 [PaintPick.ink]가 꺼지면 옛 값 그대로 — 찍기 · 증명 전용):
//   · [gray] — `mixSrgb(Look.ink, Look.paper, 옛 짙기)`였던 종이 위 고른 회색.
//   · [alpha] — `withAlpha(Look.ink, 옛 짙기 × 곱)`였던 먹 알파(곱은 흐림 · 고르기의 밝기 — 단계 위에 곱한다).
//   · [of] — 날 색 값(`0xff474747` · [Look.muted] · `withAlpha(Look.line, .6)` 따위 — 먹 · 종이로만 된 색)을 단계로. 회색이 아니면 그대로.
// 단계 값 자체는 상수(알파 [a85] ~ [a4] · 종이 위 고른 색 [k85] ~ [k4])로도 둔다 — 틀의 시트(remake-4-ui)가 '먹 25' 같은 값을 const로 쓴다.
// 옛 값을 붙들어야 하는 자리(글꼴 상수 따위)는 const를 final로 바꿨다(스위치는 앱이 그리기 전에 한 번 정한다 — main.dart).

/// 그림판 먹 여섯 단계(G5 #8 먹 가 — 85 · 60 · 45 · 25 · 12 · 4).
abstract final class CanvasInk {
  /// 단계의 먹 알파(종이 위에 얹는 먹의 짙기 0 ~ 1).
  static const a85 = .85, a60 = .60, a45 = .45, a25 = .25, a12 = .12, a4 = .04;

  /// 단계의 종이 위 고른 색(먹과 흰 종이를 섞은 불투명 회색 — `mixSrgb(Look.ink, Look.paper, 단계)`와 같은 값).
  static const k85 = 0xff262626, k60 = 0xff666666, k45 = 0xff8c8c8c, k25 = 0xffbfbfbf, k12 = 0xffe0e0e0, k4 = 0xfff5f5f5;

  /// 단계(짙은 것부터)와 그 종이 위 고른 색.
  static const steps = <double>[a85, a60, a45, a25, a12, a4];
  static const colors = <int>[k85, k60, k45, k25, k12, k4];

  /// 자르기 표(고르기 판 SETS.six 그대로): 옛 짙기(%)가 이 값 이상이면 그 단계 — 70 → 85 · 52 → 60 · 33 → 45 · 17 → 25 · 7 → 12 · 나머지 4.
  /// 먹이 없는 것(0 이하 — 그리지 않는 투명)만은 0 그대로 둔다(표의 '나머지 4'는 먹이 있는 값).
  static const cut = <(double, double)>[(70, a85), (52, a60), (33, a45), (17, a25), (7, a12), (0, a4)];

  /// 옛 짙기 [old](0 ~ 1)의 단계 — 스위치와 무관한 표 셈(검사 · 문서용).
  static double snap(double old) {
    if (old <= 0) return 0;
    final v = old * 100;
    for (final (lo, to) in cut) {
      if (v >= lo - 1e-6) return to;
    }
    return a4;
  }

  /// 옛 짙기 [old]를 그림판 먹 단계로 — 스위치 `ink`가 꺼지면(`--paint-off=ink`) 옛 값 그대로.
  static double step(double old) => PaintPick.ink ? snap(old) : old;

  /// 종이 위 고른 회색 — 옛 `mixSrgb(Look.ink, Look.paper, old)`.
  static int gray(double old) => mixSrgb(Look.ink, Look.paper, step(old));

  /// 먹 알파 — 옛 `withAlpha(Look.ink, old * times)`. [times]는 흐림 · 고르기의 밝기(단계에 곱한다 — 곱한 값은 단계가 아니다).
  static int alpha(double old, [double times = 1]) => withAlpha(Look.ink, step(old) * times);

  /// 먹 · 종이로만 된 날 색 [argb]를 단계로 — 불투명 회색은 종이 위 고른 회색으로, 먹 알파 · 회색 알파는 먹 알파로(종이 위에서 같은 짙기).
  /// 이미 단계 위(.5% 안)면 그 값 그대로 · 회색이 아니면(나라 색) 그대로 · 스위치 `ink`가 꺼지면 그대로.
  static int of(int argb) {
    if (!PaintPick.ink) return argb;
    final old = inkOf(argb);
    if (old == null || old <= 0) return argb;
    final to = snap(old);
    if ((to - old).abs() < .005) return argb;
    return ((argb >> 24) & 0xff) == 0xff ? mixSrgb(Look.ink, Look.paper, to) : withAlpha(Look.ink, to);
  }

  /// 먹 · 종이로만 된 색(R = G = B)이 흰 종이 위에서 내는 먹 짙기(0 ~ 1 · .5% 단위로 반올림 — 8비트 색에서 옛 설계 값을 되찾는다). 회색이 아니면 null.
  static double? inkOf(int argb) {
    final r = (argb >> 16) & 0xff, g = (argb >> 8) & 0xff, b = argb & 0xff;
    if (r != g || g != b) return null;
    final a = ((argb >> 24) & 0xff) / 255;
    return (a * (1 - r / 255) * 200).round() / 200;
  }
}
