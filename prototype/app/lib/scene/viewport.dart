// 보기: 분 ↔ 배치 px ↔ 화면 px. 배치는 늘 100% 배율의 px로 하고, 돋보기는 그림만 키운다(묶음 2의 13번 결정).
// 그래서 돋보기 배율이 바뀌어도 해마다의 폭(ppm)과 확대 단계는 그대로이고, 같은 창에 보이는 배치 px만 달라진다.
class SceneView {
  /// 왼쪽 줄 이름 칸의 폭과 맨 위 날짜 칸의 높이(배치 px). 왼쪽 칸은 목업 GUT 240(리메이크 2부), 날짜 칸은 연도 30 + 시대 24 + 간지 20.
  static const gutter = 240.0, rulerHeight = 74.0;

  /// 휴대폰의 왼쪽 칸 폭(배치 px). 1100px 창을 통째로 줄여 그리는 배율(`shell/phone_scale.dart`)은 그대로 두고 왼쪽 칸만 좁힌다(감독 2026-10-16 — 180을 견준 뒤 "160으로 더 좁혀줘").
  /// 값은 160 하나 — 검사 손잡이 `--phone=<폭>`만 바꿔 끼운다(후보를 나란히 뜨려고).
  static double phoneGutter = 160.0;

  /// 휴대폰 배치(줄여 그림)인지 — `PhoneScale`이 줄여 그릴 때 켠다(검사 손잡이 `--phone=yes` · `--phone=<폭>`은 컴퓨터에서도 켠다).
  static bool phone = false;

  /// 지금 쓰는 왼쪽 칸 폭 — 배치(`Layout.gutterWidth`)와 맨 위 줄의 보는 시기 글이 함께 따른다.
  static double get gutterNow => phone ? phoneGutter : gutter;

  /// 이 보기의 왼쪽 칸 폭과 날짜 칸 높이(배치 px). 민족 단계가 깊으면 왼쪽 칸이 22px씩 넓어지고, 날짜 칸은 열린 줄에 따라 달라진다.
  /// 정하지 않으면 2단계의 값(196 · 74).
  double left = gutterNow, head = rulerHeight;

  /// 그림 영역 왼쪽 끝의 시각(분).
  double lo = 0;

  /// 1분의 폭(배치 px).
  double ppm = 1;

  /// 몸통의 세로 자리(배치 px).
  double top = 0;

  /// 돋보기 배율 0.5 ~ 3.
  double mag = 1;

  double _width = 1, _height = 1;
  double get width => _width;
  double get height => _height;
  void setSize(double width, double height) {
    _width = width;
    _height = height;
  }

  /// 그림 영역의 폭과 몸통의 높이(배치 px).
  double get plotWidth => (_width / mag - left).clamp(1.0, double.infinity);
  double get bodyHeight => (_height / mag - head).clamp(1.0, double.infinity);

  /// 그림 영역에 보이는 기간(분).
  double get span => plotWidth / ppm;
  double get hi => lo + span;

  /// 분 → 배치 x, 배치 x → 분.
  double xOf(num minute) => left + (minute - lo) * ppm;
  double minuteAt(double layoutX) => lo + (layoutX - left) / ppm;

  /// 몸통 안의 세로 자리(배치 px, 줄 자리 기준) → 배치 y.
  double yOf(double bodyY) => head + bodyY - top;
  double bodyYAt(double layoutY) => layoutY - head + top;

  /// 화면 px → 배치 px.
  (double, double) layoutOf((double, double) screen) => (screen.$1 / mag, screen.$2 / mag);
}
