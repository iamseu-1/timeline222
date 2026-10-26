import 'package:flutter/material.dart';

import '../scene/color_mix.dart';
import '../scene/fonts.dart';
import '../scene/paint/look.dart';
import '../scene/paint/scopes.dart' show FlagEntry, FlagKind, FlagLook, FlagSpot;
import '../shell/line_icon.dart';

// 플래그 창(리메이크 2부 · 목업 slice4 s4-플래그 · 감독 2026-10-15 "접었다 폈다 하는 기능은 포스트잇 플래그처럼 위에 살짝 놓고
// 누르면 해당 창을 띄우는 느낌" → "플래그 하나로 모으고, 빗금 말고 그냥 칠하자"): 꼬리표 윗변의 플래그를 누르면 같은 플래그가
// 위로 늘어나 창이 된다. 창은 그 꼬리표의 접고 펴는 것(소속 · 속국 · 단체 · 할거와 대범위)을 칸마다 하나씩 — 이름 · 수 · 선 아이콘(펼침 +, 접힘 −).
// 단체 칸은 그 아래에 단체의 색 점과 이름을 적는다. 창의 아랫단은 플래그 칠이 그대로 남아 어디서 나온 창인지 보인다.
//
// 창은 그림판 위에 올린 위젯이다(날짜 칸 도움말과 같은 자리 — 배치 px × 돋보기 배율). 화면을 움직이거나 다른 곳을 누르면 닫히고,
// 칸을 누르면 그 일을 하고 닫힌다(부르는 쪽 — archive_app).

/// 플래그 창의 값(배치 px — 그리는 쪽이 배율을 곱한다).
abstract final class FlagWindowLook {
  static const minWidth = 112.0, padX = 8.0, padTop = 6.0, padBottom = 5.0, rowH = 20.0, nameH = 17.0;
  static const labelSize = 11.0, countSize = 10.5, nameSize = 10.5, icon = 12.0, dot = 7.0;
}

class FlagWindow extends StatelessWidget {
  const FlagWindow({super.key, required this.spot, required this.onPick});

  final FlagSpot spot;

  /// 칸을 눌렀다 — 부르는 쪽이 그 갈래의 접기 · 펴기를 한다.
  final void Function(FlagEntry entry) onPick;

  @override
  Widget build(BuildContext context) {
    final color = 0xff000000 | spot.color;
    final edge = Color(mixOklab(color, Look.ink, .84));
    final fill = Color(mixSrgb(color, Look.paper, FlagLook.fillPct));
    const ink85 = Color(0xff262626), ink50 = Color(0xff808080), ink60 = Color(0xff666666);
    TextStyle style(double size, FontWeight weight, Color c) =>
        TextStyle(fontFamily: sceneFontFamily, fontFamilyFallback: sceneFontFallback, fontSize: size, fontWeight: weight, color: c, height: 1.2);
    final rows = <Widget>[];
    for (final e in spot.entries) {
      rows.add(MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onPick(e),
          child: SizedBox(
            height: FlagWindowLook.rowH,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(e.label, style: style(FlagWindowLook.labelSize, FontWeight.w700, ink85)),
                const SizedBox(width: 5),
                Text('${e.count}', style: style(FlagWindowLook.countSize, FontWeight.w400, ink50)),
                const SizedBox(width: 14),
                const Spacer(),
                LineIcon(e.on ? LineGlyph.minus : LineGlyph.plus, size: FlagWindowLook.icon, color: ink60),
              ],
            ),
          ),
        ),
      ));
      if (e.kind == FlagKind.groups) {
        for (final (name, c) in e.names) {
          rows.add(SizedBox(
            height: FlagWindowLook.nameH,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: FlagWindowLook.dot,
                  height: FlagWindowLook.dot,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(mixSrgb(0xff000000 | c, Look.paper, .24)),
                    border: Border.all(color: Color(mixOklab(0xff000000 | c, Look.ink, .84))),
                  ),
                ),
                const SizedBox(width: 6),
                Text(name, style: style(FlagWindowLook.nameSize, FontWeight.w400, ink85)),
              ],
            ),
          ));
        }
      }
    }
    return IntrinsicWidth(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: FlagWindowLook.minWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xff000000 | Look.paper),
                border: Border(top: BorderSide(color: edge), left: BorderSide(color: edge), right: BorderSide(color: edge)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(FlagWindowLook.padX, FlagWindowLook.padTop, FlagWindowLook.padX, FlagWindowLook.padBottom),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
              ),
            ),
            // 아랫단: 플래그 칠이 창 폭으로 늘어난 것(위 테는 창의 몸과 가른다).
            Container(
              height: FlagLook.h,
              decoration: BoxDecoration(
                color: fill,
                border: Border(top: BorderSide(color: edge), left: BorderSide(color: edge), right: BorderSide(color: edge)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
