import 'package:flutter/material.dart';

import '../motion.dart';
import 'look.dart';
import 'motion_widgets.dart';

// 선 아이콘(건의 8의 1번 · 감독 선택 '꼴 A · 기호 가' 2026-10-13): HistoryArchive의 AppIcon과 같은 규격 — Lucide 꼴 · 24칸 격자 ·
// 선 굵기 1.5(격자 단위) · 둥근 끝 · 둥근 꺾임 · 칠 없음. 그쪽은 flutter_svg로 그리지만 이 앱은 그 꾸러미를 들이지 않고
// (검색 칸의 돋보기처럼) 그림판에 직접 긋는다 — 아래의 작은 SVG 길 읽기가 Lucide의 path · circle · rect · line · polyline만 읽는다.
// 선 자료의 출처: `.claude/research/suggest8/pieces.html`의 `<defs>` · HistoryArchive `packages/design_system/lib/src/icons.dart`.

/// 쓰는 아이콘 한 벌. 이름은 Lucide의 이름을 따른다(괄호 안은 쓰는 자리).
enum LineGlyph {
  /// 집합 보기(겹친 판).
  layers('<path d="M12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83z"/>'
      '<path d="M2 12a1 1 0 0 0 .58.91l8.6 3.91a2 2 0 0 0 1.65 0l8.58-3.9A1 1 0 0 0 22 12"/>'
      '<path d="M2 17a1 1 0 0 0 .58.91l8.6 3.91a2 2 0 0 0 1.65 0l8.58-3.9A1 1 0 0 0 22 17"/>'),

  /// 필터(삼선).
  menu('<path d="M4 6h16"/><path d="M4 12h16"/><path d="M4 18h16"/>'),

  /// 렌즈(눈동자).
  eye('<path d="M2.062 12.348a1 1 0 0 1 0-.696 10.75 10.75 0 0 1 19.876 0 1 1 0 0 1 0 .696 10.75 10.75 0 0 1-19.876 0"/><circle cx="12" cy="12" r="3"/>'),

  /// 더 보기(점 셋).
  more('<circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/><circle cx="5" cy="12" r="1"/>'),

  /// 같은 해.
  pin('<path d="M20 10c0 4.993-5.539 10.193-7.399 11.799a1 1 0 0 1-1.202 0C9.539 20.193 4 14.993 4 10a8 8 0 0 1 16 0"/><circle cx="12" cy="10" r="3"/>'),

  /// 기간 재기.
  ruler('<path d="M21.3 15.3a2.4 2.4 0 0 1 0 3.4l-2.6 2.6a2.4 2.4 0 0 1-3.4 0L2.7 8.7a2.41 2.41 0 0 1 0-3.4l2.6-2.6a2.41 2.41 0 0 1 3.4 0Z"/>'
      '<path d="m14.5 12.5 2-2"/><path d="m11.5 9.5 2-2"/><path d="m8.5 6.5 2-2"/><path d="m17.5 15.5 2-2"/>'),

  /// 전체 보기.
  expand('<path d="M15 3h6v6"/><path d="m21 3-7 7"/><path d="m3 21 7-7"/><path d="M9 21H3v-6"/>'),

  /// 조감.
  bird('<path d="m7 20 5-5 5 5"/><path d="m7 4 5 5 5-5"/>'),

  /// 모두 접기 · 펴기.
  fold('<path d="M12 22v-6"/><path d="M12 8V2"/><path d="M4 12H2"/><path d="M10 12H8"/><path d="M16 12h-2"/><path d="M22 12h-2"/>'
      '<path d="m15 19-3-3-3 3"/><path d="m15 5-3 3-3-3"/>'),

  /// 범례.
  help('<circle cx="12" cy="12" r="10"/><path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3"/><path d="M12 17h.01"/>'),

  /// 표.
  table('<path d="M12 3v18"/><rect width="18" height="18" x="3" y="3" rx="2"/><path d="M3 9h18"/><path d="M3 15h18"/>'),

  /// 이미지 · 인쇄.
  image('<rect width="18" height="18" x="3" y="3" rx="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/>'),

  /// DLC 관리.
  package('<path d="M11 21.73a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73z"/>'
      '<path d="M12 22V12"/><path d="m3.3 7 7.703 4.734a2 2 0 0 0 1.994 0L20.7 7"/><path d="m7.5 4.27 9 5.15"/>'),

  /// 집중 모드.
  scan('<path d="M3 7V5a2 2 0 0 1 2-2h2"/><path d="M17 3h2a2 2 0 0 1 2 2v2"/><path d="M21 17v2a2 2 0 0 1-2 2h-2"/><path d="M7 21H5a2 2 0 0 1-2-2v-2"/>'),

  /// 검색.
  search('<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>'),

  /// 움직임 계측.
  activity('<path d="M22 12h-2.48a2 2 0 0 0-1.93 1.46l-2.35 8.36a.25.25 0 0 1-.48 0L9.24 2.18a.25.25 0 0 0-.48 0l-2.35 8.36A2 2 0 0 1 4.49 12H2"/>'),

  /// 문서 대문(서가).
  library('<path d="m16 6 4 14"/><path d="M12 6v14"/><path d="M8 8v12"/><path d="M4 4v16"/>'),

  /// 문서를 연표 옆에 나란히(오른쪽 칸).
  panelRight('<rect width="18" height="18" x="3" y="3" rx="2"/><path d="M15 3v18"/>'),

  /// 문서.
  file('<path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/><path d="M10 9H8"/><path d="M16 13H8"/><path d="M16 17H8"/>'),

  /// 여기로 확대.
  zoomIn('<circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/><path d="M11 8v6"/><path d="M8 11h6"/>'),

  /// 지도.
  map('<path d="M14.106 5.553a2 2 0 0 0 1.788 0l3.659-1.83A1 1 0 0 1 21 4.619v12.764a1 1 0 0 1-.553.894l-4.553 2.277a2 2 0 0 1-1.788 0l-4.212-2.106'
      'a2 2 0 0 0-1.788 0l-3.659 1.83A1 1 0 0 1 3 19.381V6.618a1 1 0 0 1 .553-.894l4.553-2.277a2 2 0 0 1 1.788 0z"/><path d="M15 5.764v15"/><path d="M9 3.236v15"/>'),

  /// 노선도(도읍).
  route('<circle cx="6" cy="19" r="3"/><path d="M9 19h8.5a3.5 3.5 0 0 0 0-7h-11a3.5 3.5 0 0 1 0-7H15"/><circle cx="18" cy="5" r="3"/>'),

  /// 이 시기로 · 이 위치로 · 연표에서(과녁).
  locate('<line x1="2" x2="5" y1="12" y2="12"/><line x1="19" x2="22" y1="12" y2="12"/><line x1="12" x2="12" y1="2" y2="5"/>'
      '<line x1="12" x2="12" y1="19" y2="22"/><circle cx="12" cy="12" r="7"/><circle cx="12" cy="12" r="3"/>'),

  /// 꽂아 두기(노선도 카드).
  pushPin('<path d="M12 17v5"/><path d="M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-.76'
      'a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 1 0 0 1 1 1z"/>'),

  /// 확대 · 축소(확대 단추 묶음).
  plus('<path d="M5 12h14"/><path d="M12 5v14"/>'),
  minus('<path d="M5 12h14"/>'),

  /// 파일에서 더하기.
  folder('<path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"/>'),

  /// 인쇄.
  printer('<path d="M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2"/><path d="M6 9V3a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v6"/>'
      '<rect x="6" y="14" width="12" height="8" rx="1"/>'),

  /// 내보내기(CSV).
  download('<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="m7 10 5 5 5-5"/><path d="M12 15V3"/>'),

  /// 체크(켠 줄).
  check('<path d="M20 6 9 17l-5-5"/>'),

  /// 접고 펴기(상세 창 묶음의 머리글 — 펼침이면 아래, 접힘이면 오른쪽으로 돌려 그린다).
  chevronDown('<path d="m6 9 6 6 6-6"/>'),

  /// 뒤로(상세 창 — 거쳐 온 항목으로).
  arrowLeft('<path d="m12 19-7-7 7-7"/><path d="M19 12H5"/>'),

  /// 닫기.
  x('<path d="M18 6 6 18"/><path d="m6 6 12 12"/>');

  const LineGlyph(this.svg);

  /// 24칸 격자의 SVG 조각(Lucide 그대로).
  final String svg;

  /// 읽어 둔 길(24칸 격자). 처음 쓸 때 한 번만 읽는다.
  Path get path => _paths[this] ??= svgPath(svg);
  static final _paths = <LineGlyph, Path>{};
}

/// 선 아이콘 하나. [size]는 그리는 크기(px) — 선 굵기는 격자 단위로 1.5라 크기를 따라 준다(HistoryArchive의 Glyph와 같다).
class LineIcon extends StatelessWidget {
  const LineIcon(this.glyph, {super.key, this.size = 18, this.color = Ui.ink, this.stroke = 1.5});
  final LineGlyph glyph;
  final double size, stroke;
  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(size: Size.square(size), painter: LinePainter(glyph, color, stroke)),
  );
}

/// [LineIcon]의 그리개 — 다른 그리개 안에서 아이콘을 찍을 때도 쓴다.
class LinePainter extends CustomPainter {
  const LinePainter(this.glyph, this.color, [this.stroke = 1.5]);
  final LineGlyph glyph;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawPath(
      glyph.path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true
        ..color = color,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(LinePainter old) => old.glyph != glyph || old.color != color || old.stroke != stroke;
}

/// 맨 위 줄의 기호 단추(꼴 A — 테 없음): 36×36 · 아이콘 18 · 평소 먹 60% · 올리면 바탕 먹 8% + 아이콘 먹 100% ·
/// 켜짐([on] — 연 것이 열려 있거나 상태가 켜짐) = 반전 채움(먹 바탕 · 종이빛 아이콘 · 둥근 6). [dot]을 주면 오른쪽 위에 그 색 점
/// (지름 7 · 종이빛 1.5px 테 — 렌즈를 켠 동안 주제 색). 이름은 풍선([tooltip] — `필터 (F)` 꼴)으로만, 스크린 리더 이름은 [semantics].
class DockIconButton extends StatefulWidget {
  const DockIconButton({super.key, required this.glyph, this.onPressed, this.tooltip, this.semantics, this.on = false, this.dot});
  final LineGlyph glyph;
  final VoidCallback? onPressed;
  final String? tooltip, semantics;
  final bool on;
  final Color? dot;

  @override
  State<DockIconButton> createState() => _DockIconButtonState();
}

class _DockIconButtonState extends State<DockIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.on;
    final ink = on ? Ui.paper : (_hover ? Ui.ink : Ui.ink60);
    Widget body = AnimatedContainer(
      duration: const Duration(milliseconds: Motion.microMs),
      curve: Ui.ease,
      width: Ui.buttonHeight,
      height: Ui.buttonHeight,
      decoration: BoxDecoration(
        color: on ? Ui.ink : (_hover ? Ui.ink8 : const Color(0x00000000)),
        borderRadius: BorderRadius.circular(Ui.buttonRadius),
      ),
      alignment: Alignment.center,
      child: LineIcon(widget.glyph, size: Ui.dockIcon, color: ink),
    );
    final dot = widget.dot;
    if (dot != null) {
      body = Stack(
        clipBehavior: Clip.none,
        children: [
          body,
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              width: Ui.dockDot,
              height: Ui.dockDot,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle, border: Border.all(color: Ui.paper, width: 1.5)),
            ),
          ),
        ],
      );
    }
    if (widget.tooltip != null) body = Tooltip(message: widget.tooltip!, child: body);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Semantics(
        button: true,
        label: widget.semantics ?? widget.tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: MotionPress(enabled: widget.onPressed != null, child: body),
        ),
      ),
    );
  }
}

// ─────────────────────────── 작은 SVG 길 읽기 ───────────────────────────

/// Lucide 조각(`<path d>` · `<circle>` · `<rect>` · `<line>` · `<polyline>`)을 하나의 길로. 모르는 것은 건너뛴다.
Path svgPath(String svg) {
  final out = Path();
  final attr = RegExp(r'([a-z0-9-]+)="([^"]*)"');
  for (final element in RegExp(r'<(path|circle|rect|line|polyline)\s([^>]*?)/?>').allMatches(svg)) {
    final a = {for (final m in attr.allMatches(element.group(2)!)) m.group(1)!: m.group(2)!};
    double n(String key, [double fallback = 0]) => double.tryParse(a[key] ?? '') ?? fallback;
    switch (element.group(1)) {
      case 'path':
        _readPath(out, a['d'] ?? '');
      case 'circle':
        out.addOval(Rect.fromCircle(center: Offset(n('cx'), n('cy')), radius: n('r')));
      case 'rect':
        final rect = Rect.fromLTWH(n('x'), n('y'), n('width'), n('height'));
        final rx = n('rx', n('ry')), ry = n('ry', rx);
        out.addRRect(RRect.fromRectXY(rect, rx, ry));
      case 'line':
        out
          ..moveTo(n('x1'), n('y1'))
          ..lineTo(n('x2'), n('y2'));
      case 'polyline':
        final v = _numbers(a['points'] ?? '');
        for (int i = 0; i + 1 < v.length; i += 2) {
          i == 0 ? out.moveTo(v[i], v[i + 1]) : out.lineTo(v[i], v[i + 1]);
        }
    }
  }
  return out;
}

final _number = RegExp(r'[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?');
List<double> _numbers(String text) => [for (final m in _number.allMatches(text)) double.parse(m.group(0)!)];

/// SVG의 `d` 글(M L H V C S Q T A Z와 그 소문자).
void _readPath(Path out, String d) {
  var x = 0.0, y = 0.0, startX = 0.0, startY = 0.0;
  // 앞 명령의 둘째 조절점(S · T가 비춰 쓴다).
  var cx = 0.0, cy = 0.0;
  var last = '';
  var i = 0;
  String? command;

  void skip() {
    while (i < d.length && (d[i] == ' ' || d[i] == ',' || d[i] == '\n' || d[i] == '\t')) {
      i++;
    }
  }

  double number() {
    skip();
    final m = _number.matchAsPrefix(d, i);
    if (m == null) throw FormatException('수가 아님', d, i);
    i = m.end;
    return double.parse(m.group(0)!);
  }

  // 호의 깃발은 0 · 1 한 글자(붙여 쓸 수 있다 — "a1 1 0 011 1").
  bool flag() {
    skip();
    final c = d[i];
    i++;
    return c == '1';
  }

  bool moreNumbers() {
    skip();
    return i < d.length && _number.matchAsPrefix(d, i) != null;
  }

  while (true) {
    skip();
    if (i >= d.length) break;
    final c = d[i];
    if (RegExp(r'[MmLlHhVvCcSsQqTtAaZz]').hasMatch(c)) {
      command = c;
      i++;
    } else if (command == null) {
      throw FormatException('명령이 없음', d, i);
    }
    final cmd = command;
    final rel = cmd == cmd.toLowerCase();
    switch (cmd.toUpperCase()) {
      case 'M':
        x = (rel ? x : 0) + number();
        y = (rel ? y : 0) + number();
        out.moveTo(x, y);
        startX = x;
        startY = y;
        // M 뒤의 수 쌍은 L이다.
        command = rel ? 'l' : 'L';
      case 'L':
        x = (rel ? x : 0) + number();
        y = (rel ? y : 0) + number();
        out.lineTo(x, y);
      case 'H':
        x = (rel ? x : 0) + number();
        out.lineTo(x, y);
      case 'V':
        y = (rel ? y : 0) + number();
        out.lineTo(x, y);
      case 'C':
        final x1 = (rel ? x : 0) + number(), y1 = (rel ? y : 0) + number();
        final x2 = (rel ? x : 0) + number(), y2 = (rel ? y : 0) + number();
        final ex = (rel ? x : 0) + number(), ey = (rel ? y : 0) + number();
        out.cubicTo(x1, y1, x2, y2, ex, ey);
        cx = x2;
        cy = y2;
        x = ex;
        y = ey;
      case 'S':
        final reflect = last == 'C' || last == 'S';
        final x1 = reflect ? 2 * x - cx : x, y1 = reflect ? 2 * y - cy : y;
        final x2 = (rel ? x : 0) + number(), y2 = (rel ? y : 0) + number();
        final ex = (rel ? x : 0) + number(), ey = (rel ? y : 0) + number();
        out.cubicTo(x1, y1, x2, y2, ex, ey);
        cx = x2;
        cy = y2;
        x = ex;
        y = ey;
      case 'Q':
        final x1 = (rel ? x : 0) + number(), y1 = (rel ? y : 0) + number();
        final ex = (rel ? x : 0) + number(), ey = (rel ? y : 0) + number();
        out.quadraticBezierTo(x1, y1, ex, ey);
        cx = x1;
        cy = y1;
        x = ex;
        y = ey;
      case 'T':
        final reflect = last == 'Q' || last == 'T';
        final x1 = reflect ? 2 * x - cx : x, y1 = reflect ? 2 * y - cy : y;
        final ex = (rel ? x : 0) + number(), ey = (rel ? y : 0) + number();
        out.quadraticBezierTo(x1, y1, ex, ey);
        cx = x1;
        cy = y1;
        x = ex;
        y = ey;
      case 'A':
        final rx = number(), ry = number(), rotation = number();
        final large = flag(), sweep = flag();
        final ex = (rel ? x : 0) + number(), ey = (rel ? y : 0) + number();
        out.arcToPoint(Offset(ex, ey), radius: Radius.elliptical(rx, ry), rotation: rotation, largeArc: large, clockwise: sweep);
        x = ex;
        y = ey;
      case 'Z':
        out.close();
        x = startX;
        y = startY;
    }
    last = cmd.toUpperCase();
    // 같은 명령이 수만 이어 쓰인 경우(“l2 2 3 3”)는 위의 command를 그대로 다시 쓴다. Z 뒤에는 수가 오지 않는다.
    if (last == 'Z' || !moreNumbers()) command = null;
  }
  // 점 하나짜리(“M12 17h.01”)도 둥근 끝으로 점이 찍힌다 — 따로 할 일 없음.
}
