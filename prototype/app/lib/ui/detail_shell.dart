import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../scene/color_mix.dart';
import '../scene/fonts.dart';
import '../scene/paint/look.dart' show Look;
import '../motion.dart';
import '../motion_spring.dart';
import '../shell/line_icon.dart';
import '../shell/look.dart';
import '../shell/motion_widgets.dart';
import '../shell/motion_controls.dart';
import '../shell/parts.dart';
import 'app_bus.dart';

export '../shell/line_icon.dart' show LineGlyph, LineIcon;

// ════════════════════════════════════════════════════════════════════════════════════════════
//  상세 창의 뼈대 — 명세 `docs/명세-3단계/06-상세-검색-필터-도구.md` 2-1 · 2-2절
//
//  종류마다의 상세 위젯(칸 · 인물 · 대범위 · 기본 · 조약)은 여기의 부품만 써서 짠다.
//  치수 · 글꼴 · 색은 지금 연표의 css와 기준 덤프(`prototype/results/dom-r6/ui-dump.json`)에서 옮겼다.
//  이 파일은 다른 상세 파일을 하나도 import 하지 않는다 — 갈래는 [DetailHost.register]로 받는다.
//
// ── 부품마다 쓰는 법 ─────────────────────────────────────────────────────────────────────────
//
//  ◆ 창 전체
//    DetailShell(
//      badges: [DetailBadge('유리해안', color: 트랙색, onTap: …), …],   // 머리의 배지 줄(줄바꿈 · 틈 6)
//      body:   [DetailTitle('유리항 패총국'), DetailWhen('…'), …],      // 몸통(세로로 쌓이고 넘치면 스크롤)
//      foot:   [DetailSmallButton('🎯 이 위치로', onTap: …)],           // 아래 단추 줄(없으면 그 칸이 없다)
//      onClose: …,                                                      // 머리 오른쪽 ✕
//    )
//    · 몸통 안의 빈 묶음은 아예 넣지 않는다(명세 2-3: "비어 있으면 그 묶음은 아예 없다").
//    · 창 하나에 날짜 칸이 여럿 있으면 폭이 저절로 하나로 맞는다(css의 `--yw` — [DetailShell]이 [YearColumn]을 두른다).
//    · 창 밖틀(유리 바탕 · 미끄러져 들어오기)은 [DetailHost]가 씌운다. 앱 틀의 `shell/detail_panel.dart` 안에
//      끼워 넣을 때는 `DetailHost(bus: bus, framed: false)`로 두고 그 창이 밖틀을 맡는다.
//
//  ◆ 글 한 줄
//    DetailTitle('이름')                      제목 h2 — 23px/700 · 자간 −.025em · 줄높이 1.35
//    DetailWhen('기원전 960년 ~ 기원전 400년',  날짜 줄 — 14px/500 · --text-3 · 아래 14
//               sub: '음력 4월 13일 · 경진일', //   날 · 시각까지 적은 항목의 곁들임(12px · 숫자 폭 고정)
//               orig: '원문 표기 …')          //   같은 줄에 붙는 옅은 글
//    DetailAka('묘호 … · 시호 …')             다른 이름 줄 — 12px · --text-3
//    DetailRangeNote('시작 미정 — …')          미정 · 연대 폭 안내 — 13px · --warn
//    DetailNote('〈부모 사건〉 안의 사건')        그 밖의 작은 안내 한 줄 — 13px · --text-2
//    DetailDesc(설명)                          설명 — 14px/1.75 · 줄바꿈 그대로 · 비면 "설명이 없습니다."
//
//  ◆ 묶음 · 딱지
//    DetailBox(title: '소속', small: '3곳', action: …, children: [ … ])   .sub-box — 둥근 14 · 위 여백 16
//    DetailTags(['태그', …])                                             태그 줄 — 위 여백 14
//    DetailChip('이름', onTap: …, muted: true)                            칩(관련 인물 · 하위 문서 · 가문)
//    DetailChipRow([…])                                                   칩을 줄바꿈으로 늘어놓는 줄
//    DetailDefs([DetailDef('제공', Text('…')), …])                        dl — 맨 아래 정의 목록(위 선 1px)
//
//  ◆ 목록(모두 한 줄이 단추 하나 · 올리면 --accent-soft)
//    DetailSuccList([DetailSuccRow(badge: '직접', badgeStyle: SuccBadge.direct,
//                                 name: '…', years: '827–901', onTap: …)])   승계 · 소속 · 왕조 · 인물 · 관련 조약
//    DetailCellList([DetailCellTile(year: '827', name: '…', onTap: …)],       지도자 · 내각 · 연호 · 도읍 · 시기 · 지위
//                   leaders: true)                                           (leaders · single이면 한 칸 격자)
//    DetailYearEvents([DetailYearRow(color: …, when: '827년 5월', title: '…',  이 시기의 사건 · 같은 시기 타국 ·
//                                    track: '유리해안', onTap: …)])            관련 사건 · 서명한 조약 · 같은 해 보기
//    DetailKidList([DetailKidRow(year: '827', name: '…', onTap: …)])          포함된 사건 · 지도자 목록
//    DetailAltList([DetailAltRow(when: '827년', why: '…', main: true)])       다른 견해
//
//  ◆ 아래 단추 · 스위치
//    DetailSmallButton('📄 문서', onTap: …)            .btn.btn-sm — 높이 28 · 12.5px · 둥근 8
//    DetailSwitch('같은 시기를 타국에도', value: …, onChanged: …)   창 안의 체크 한 줄
//
//  ◆ 자리 옮기기
//    final key = GlobalKey();  … DetailShell(body: [ … DetailBox(key: key, …) … ])
//    detailScrollTo(key);                              '인물' 묶음으로 스크롤(갈래 figures-of)
//
//  ◆ 갈래 — 어느 창이 열리는가(명세 2-2)
//    DetailHost.register('cell',   (ctx) => CellDetail(ctx));     // detail_cell.dart 가 제 파일 안에서 부른다
//    DetailHost.register('figure', (ctx) => FigureDetail(ctx));   // detail_people.dart
//    DetailHost.register('scope',  (ctx) => ScopeDetail(ctx));    // detail_scope.dart
//    DetailHost.register('group',  (ctx) => GroupDetail(ctx));    // detail_group.dart(제도 'institution'도)
//    … 그러고 나서 앱 틀이 `DetailHost(bus: bus)` 하나만 띄운다.
//    [DetailContext]가 그 창에 필요한 것을 모두 들고 온다: `ctx.uid` · `ctx.kind` · `ctx.cell` ·
//    `ctx.json`(항목 기록을 푼 Map) · `ctx.branch`(갈래의 성질) · `ctx.open(uid)` · `ctx.goTo(lo,hi)` ·
//    `ctx.askEntity(uid)`(목록 줄이 가리키는 다른 항목) · `ctx.close()`.
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 상세 창에만 쓰는 색 · 치수. 앱 틀과 함께 쓰는 값은 [Ui]에 있다.
abstract final class DetailUi {
  /// css의 `--warn` · `--ok`. 미정 · 연대 폭 안내와 지위의 ▲승격 / ▼격하에 쓴다(노랑은 앱 틀의 [Ui.warn]과 같은 색).
  static const warn = Ui.warn, ok = Ui.ink;

  static const headPad = EdgeInsets.fromLTRB(18, 14, 12, 0);
  static const bodyPad = EdgeInsets.fromLTRB(18, 8, 18, 16);
  static const footPad = EdgeInsets.fromLTRB(18, 12, 18, 12);

  /// 바탕 글꼴: 14px · 줄높이 21/14 · 자간 −.01em.
  static TextStyle get body => TextStyle(fontFamily: sceneFamilyNow, fontFamilyFallback: sceneFallbackNow, fontSize: 14, height: 21 / 14, letterSpacing: -.14, color: Ui.text, fontWeight: FontWeight.w400);

  /// 날짜 칸이 아직 재어지지 않았을 때의 폭(css의 `var(--yw, 74px)`).
  static const yearWidth = 74.0;

  /// 목록 줄에 손을 올렸을 때의 바탕.
  static const rowHover = Ui.accentSoft;
}

Color _soft(Color c, double t) => c.withAlpha((c.a * 255 * t).round().clamp(0, 255));

// ────────────────────────────────────────────────────────────────────────────────────────────
//  1. 창 뼈대
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 상세 창의 세 칸(머리 · 몸통 · 아래 단추 줄). 밖틀(유리 바탕)은 [DetailHost]나 앱 틀이 씌운다.
class DetailShell extends StatelessWidget {
  const DetailShell({super.key, this.badges = const [], this.body = const [], this.foot = const [], this.onClose, this.controller, this.content, this.footGap = 8});

  /// 머리의 배지 줄. 넘치면 줄바꿈한다(틈 6).
  final List<Widget> badges;

  /// 몸통. 세로로 쌓고 넘치면 스크롤한다.
  final List<Widget> body;

  /// 아래 단추 줄. 비어 있으면 그 칸을 아예 그리지 않는다.
  final List<Widget> foot;
  final VoidCallback? onClose;
  final ScrollController? controller;

  /// 몸통을 통째로 맡는 위젯(D1 승계표 — 보이는 줄만 짓는 목록이 제 스크롤을 가진다). 주면 [body]는 쓰지 않는다.
  /// 머리 · 아래 단추 줄은 그대로이고, 이 위젯은 남은 높이를 모두 받는다.
  final Widget? content;

  /// 아래 단추 사이 틈. 단추가 많은 창(D1 승계표 — 웹 `.kv-succ-foot` gap 6)만 좁힌다.
  final double footGap;

  @override
  Widget build(BuildContext context) {
    // 갈래가 남의 창 아래 단추 줄에 더하는 단추([DetailHost.registerFoot]) — 맨 끝 단추(닫기) 앞에 선다.
    final extra = _DetailFootScope.of(context);
    final foot = extra.isEmpty ? this.foot : [...this.foot.take(math.max(0, this.foot.length - 1)), ...extra, ...this.foot.skip(math.max(0, this.foot.length - 1))];
    return _frame(foot, _DetailBackScope.of(context));
  }

  Widget _frame(List<Widget> foot, VoidCallback? onBack) => DefaultTextStyle(
    style: DetailUi.body,
    child: YearColumn(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: DetailUi.headPad,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Wrap(spacing: 6, runSpacing: 6, children: badges),
                  ),
                ),
                const SizedBox(width: 8),
                // 뒤로 — 이 창에서 거쳐 온 항목이 있을 때만 닫기 왼쪽에 선다([DetailHost]가 기록을 쥔다).
                if (onBack != null) ...[
                  ShellButton(
                    width: 32,
                    padding: EdgeInsets.zero,
                    tooltip: '뒤로',
                    onPressed: onBack,
                    child: const LineIcon(LineGlyph.arrowLeft, size: 15),
                  ),
                  const SizedBox(width: 4),
                ],
                if (onClose != null)
                  ShellButton(
                    width: 32,
                    padding: EdgeInsets.zero,
                    tooltip: '닫기',
                    onPressed: onClose,
                    child: const Text('✕', style: TextStyle(fontSize: 13)),
                  )
                else
                  const SizedBox(width: 32, height: 32),
              ],
            ),
          ),
          if (content != null)
            Expanded(child: content!)
          else
            Flexible(
              child: SingleChildScrollView(
                controller: controller,
                padding: DetailUi.bodyPad,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: body),
              ),
            ),
          if (foot.isNotEmpty)
            DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Ui.line)),
              ),
              child: Padding(
                padding: DetailUi.footPad,
                child: Wrap(spacing: footGap, runSpacing: 8, children: foot),
              ),
            ),
        ],
      ),
    ),
  );
}

/// 몸통 안의 어느 묶음으로 미끄러져 간다(갈래 `figures-of`의 '인물' 묶음 따위).
/// 그 묶음 위젯에 `key: 내 GlobalKey`를 달아 두고 창이 뜬 다음 부른다.
Future<void> detailScrollTo(GlobalKey key, {Duration duration = const Duration(milliseconds: Motion.moveMs)}) async {
  final context = key.currentContext;
  if (context == null) return;
  await Scrollable.ensureVisible(context, duration: duration, curve: Ui.spring, alignment: 0.03);
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  2. 날짜 칸 폭 맞춤 — css의 `--yw`(viewer.js alignYearCols)
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 창 안 모든 날짜 칸이 재어 낸 폭 가운데 가장 넓은 값. 한 해 사건과 기간 사건의 제목이 같은 자리에서 시작한다.
class YearWidth extends ChangeNotifier {
  YearWidth([this._value = DetailUi.yearWidth]);
  double _value;
  bool _pending = false;

  double get value => _value;

  /// 날짜 칸 하나가 제 글의 폭을 알린다. 더 넓으면 다음 판에 모두가 그 폭으로 다시 그려진다.
  void offer(double width) {
    if (width <= _value + .01 || _pending) return;
    _value = width;
    _pending = true;
    scheduleMicrotask(() {
      _pending = false;
      notifyListeners();
    });
  }
}

/// [DetailShell]이 자동으로 두른다. 창을 직접 짤 때만 쓴다.
class YearColumn extends StatefulWidget {
  const YearColumn({super.key, required this.child});
  final Widget child;

  static YearWidth? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_YearScope>()?.notifier;

  /// 승계 · 소속 · 왕조 목록([DetailSuccRow])의 오른쪽 기간 칸 폭 — 창 안에서 하나(웹 `--sw`).
  static YearWidth? spanOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_SpanScope>()?.notifier;

  /// 같은 목록들의 앞 배지 폭 — 창 안에서 하나(웹 `--bw`).
  static YearWidth? badgeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_BadgeScope>()?.notifier;

  @override
  State<YearColumn> createState() => _YearColumnState();
}

class _YearColumnState extends State<YearColumn> {
  final _width = YearWidth(), _span = YearWidth(0), _badge = YearWidth(0);

  @override
  void dispose() {
    _width.dispose();
    _span.dispose();
    _badge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _YearScope(
    notifier: _width,
    child: _SpanScope(notifier: _span, child: _BadgeScope(notifier: _badge, child: widget.child)),
  );
}

class _YearScope extends InheritedNotifier<YearWidth> {
  const _YearScope({required super.notifier, required super.child});
}

class _SpanScope extends InheritedNotifier<YearWidth> {
  const _SpanScope({required super.notifier, required super.child});
}

class _BadgeScope extends InheritedNotifier<YearWidth> {
  const _BadgeScope({required super.notifier, required super.child});
}

/// 글 한 줄의 폭을 잰다(목록의 날짜 칸이 제 폭을 알릴 때 쓴다).
double measureText(String text, TextStyle style, {TextScaler scaler = TextScaler.noScaling}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    textScaler: scaler,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  3. 배지
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 머리의 배지. 색은 그 항목의 색(`--c`)이고 바탕은 그 색 26%, 올릴 수 있으면 45%.
class DetailBadge extends StatefulWidget {
  const DetailBadge(this.text, {super.key, this.color, this.onTap, this.dot = true, this.diamond = false, this.italic = false, this.strike = false});

  final String text;

  /// 없으면 `--text-3`.
  final Color? color;
  final VoidCallback? onTap;

  /// 앞의 7px 색 점. 대범위 배지처럼 점이 없는 것은 false.
  final bool dot;

  /// 조약 배지 — 점 대신 45° 돌린 6px 마름모.
  final bool diamond;

  /// 실재성 배지의 전설 · 반전설은 기울임, 부정됨은 취소선.
  final bool italic, strike;

  @override
  State<DetailBadge> createState() => _DetailBadgeState();
}

class _DetailBadgeState extends State<DetailBadge> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.color ?? Ui.text3;
    final link = widget.onTap != null;
    Widget mark = Container(
      width: widget.diamond ? 6 : 7,
      height: widget.diamond ? 6 : 7,
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(widget.diamond ? 1 : 3.5)),
    );
    if (widget.diamond) mark = Transform.rotate(angle: math.pi / 4, child: mark);

    // 배지 = 흰 꼬리표 칩(리메이크 2부 · 목업 서고 detail의 종류 칩): 왼쪽 두 귀 모따기 4 · 종이 칠 · 테 먹 40(누를 수 있는 것은 올리면 먹 8 칠).
    // 색은 앞의 점에만 남는다.
    Widget body = CustomPaint(
      painter: DetailTagPainter(fill: link && _hover ? const Color(0xffebebeb) : const Color(0xff000000 | Look.paper), edge: const Color(0xff999999), cham: 4),
      child: Padding(
      padding: const EdgeInsets.fromLTRB(9, 2, 8, 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.dot) ...[mark, const SizedBox(width: 5)],
          Text(
            widget.text,
            style: TextStyle(
              fontSize: 12,
              height: 18 / 12,
              fontWeight: FontWeight.w400,
              color: Ui.text,
              fontStyle: widget.italic ? FontStyle.italic : FontStyle.normal,
              decoration: widget.strike ? TextDecoration.lineThrough : null,
              decorationThickness: widget.strike ? 1 : null,
            ),
          ),
        ],
      ),
    ),
    );
    if (!link) return body;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Semantics(
        button: true,
        label: widget.text,
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onTap, child: body),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  4. 글 한 줄
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 제목 = 폴더에서 꺼낸 큰 꼬리표 카드(리메이크 2부 · 목업 서고 detail): 왼쪽 두 귀 모따기 8 · 칠 = [color] 24%(없으면 종이) ·
/// 테 = [color] 84% + 먹(없으면 먹 40) · 구멍(지름 8 · 왼쪽 14 · 세로 가운데)에서 위로 매단 실(카드 위 6에 매듭) ·
/// 이름 20/700 · 그 아래 [when] 14/400 먹 60(기간 — 주면 날짜 줄 대신 카드 안에). [small]은 제목 뒤의 `<small>`(제도 창의 `주제 〈나라〉`).
class DetailTitle extends StatelessWidget {
  const DetailTitle(this.text, {super.key, this.small, this.color, this.when});
  final String text;
  final String? small, when;
  final Color? color;

  static const style = TextStyle(fontFamily: Ui.title, fontFamilyFallback: Ui.titleFallback, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -.4, height: 28 / 20, color: Ui.text);
  static const whenStyle = TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w400, color: Color(0xff666666));

  @override
  Widget build(BuildContext context) {
    final c = color;
    final argb = c == null ? 0 : (0xff000000 | (c.toARGB32() & 0xffffff));
    final fill = c == null ? const Color(0xff000000 | Look.paper) : Color(mixSrgb(argb, Look.paper, .24));
    final edge = c == null ? const Color(0xff999999) : Color(mixOklab(argb, Look.ink, .84));
    final title = small == null || small!.isEmpty
        ? Text(text, style: style)
        : Text.rich(
            TextSpan(
              text: text,
              children: [
                TextSpan(
                  text: ' ${small!}',
                  style: const TextStyle(fontSize: 20 / 1.2),
                ),
              ],
            ),
            style: style,
          );
    return Padding(
      // 위 12: 카드 위로 솟은 실 · 매듭(6 + 여유) 자리.
      padding: const EdgeInsets.only(top: 12, bottom: 12),
      child: CustomPaint(
        painter: DetailTagPainter(fill: fill, edge: edge, cham: 8, hole: true),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 8, 12, 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              title,
              if (when != null && when!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 1), child: Text(when!, style: whenStyle)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 꼬리표 꼴의 바탕(상세 창의 제목 카드 · 배지 칩 — 리메이크 2부 · 목업 서고): 왼쪽 두 귀 모따기 [cham] · 오른쪽 직각 · 칠 · 1px 테.
/// [hole]이면 왼쪽 14 · 세로 가운데에 구멍(지름 8 · 종이 · 테 먹 45)과 거기서 카드 위로 매단 실(위 6에 매듭 지름 3.6).
class DetailTagPainter extends CustomPainter {
  const DetailTagPainter({required this.fill, required this.edge, this.cham = 8, this.hole = false});
  final Color fill, edge;
  final double cham;
  final bool hole;

  static const _thread = Color(0xff8c8c8c);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, k = math.min(cham, h / 2);
    Path shape(double i) => Path()
      ..moveTo(k + i, i)
      ..lineTo(w - i, i)
      ..lineTo(w - i, h - i)
      ..lineTo(k + i, h - i)
      ..lineTo(i, h - k - i)
      ..lineTo(i, k + i)
      ..close();
    canvas.drawPath(shape(0), Paint()..color = fill);
    canvas.drawPath(shape(.5), Paint()
      ..color = edge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);
    if (!hole) return;
    const hx = 14.0;
    final hy = h / 2;
    final line = Paint()
      ..color = _thread
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(hx - 3, hy - 3)
        ..lineTo(hx, -1)
        ..moveTo(hx + 3, hy - 3)
        ..lineTo(hx, -1)
        ..lineTo(hx, -6),
      line,
    );
    canvas.drawCircle(const Offset(hx, -6), 1.8, Paint()..color = _thread);
    canvas.drawCircle(Offset(hx, hy), 4, Paint()..color = const Color(0xff000000 | Look.paper));
    canvas.drawCircle(Offset(hx, hy), 3.5, line);
  }

  @override
  bool shouldRepaint(DetailTagPainter old) => old.fill != fill || old.edge != edge || old.cham != cham || old.hole != hole;
}

/// 날짜 줄 — 14px/500 · `--text-3` · 아래 14. [sub]는 음력 · 일진 · 요일, [orig]는 원문 표기.
class DetailWhen extends StatelessWidget {
  const DetailWhen(this.text, {super.key, this.sub, this.orig});
  final String text;
  final String? sub, orig;

  static const style = TextStyle(fontSize: 14, height: 1.5, fontWeight: FontWeight.w500, color: Ui.text3);
  static const subStyle = TextStyle(fontSize: 12, height: 1.5, color: Ui.text3, fontFeatures: [FontFeature.tabularFigures()]);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (text.isNotEmpty) Text.rich(
          TextSpan(
            text: text,
            children: [
              if (orig != null && orig!.isNotEmpty)
                TextSpan(
                  text: '  ${orig!}',
                  style: const TextStyle(fontWeight: FontWeight.w400, color: Ui.text3),
                ),
            ],
          ),
          style: style,
        ),
        if (sub != null && sub!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(sub!, style: subStyle),
          ),
      ],
    ),
  );
}

/// 다른 이름 줄 — 12px · `--text-3` · 위 −2 아래 8.
class DetailAka extends StatelessWidget {
  const DetailAka(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(fontSize: 12, height: 1.5, color: Ui.text3)),
  );
}

/// 미정 · 연대 폭 안내 — 13px · `--warn` · 위 −8 아래 12.
class DetailRangeNote extends StatelessWidget {
  const DetailRangeNote(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(text, style: const TextStyle(fontSize: 13, height: 1.5, color: DetailUi.warn)),
  );
}

/// 그 밖의 작은 안내 한 줄(빵부스러기 · 공동 사건 · 민족 한마디) — 13px · `--text-2`.
class DetailNote extends StatelessWidget {
  const DetailNote(this.text, {super.key, this.onTap});
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: const TextStyle(fontSize: 13, height: 1.5, color: Ui.text2)),
    );
    if (onTap == null) return body;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: body),
    );
  }
}

/// 설명 — 읽는 글이라 명조 15px · 줄 높이 24 · 줄바꿈 그대로. 비어 있으면 기울임으로 "설명이 없습니다.".
class DetailDesc extends StatelessWidget {
  const DetailDesc(this.text, {super.key, this.small = false});
  final String? text;

  /// 상자 안의 설명은 13px/1.7.
  final bool small;

  @override
  Widget build(BuildContext context) {
    final t = (text ?? '').trim();
    if (t.isEmpty) {
      return const Text(
        '설명이 없습니다.',
        style: TextStyle(fontSize: 14, height: 1.75, color: Ui.text3, fontStyle: FontStyle.italic),
      );
    }
    if (small) return Text(t, style: const TextStyle(fontSize: 13, height: 1.7, color: Ui.text));
    return Text(
      t,
      style: const TextStyle(fontFamily: Ui.serif, fontFamilyFallback: Ui.serifFallback, fontSize: 15, height: 24 / 15, color: Ui.text),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  5. 상자 · 태그 · 칩 · 정의 목록 · 단추
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 상세 창 묶음의 접힘 기억 — 머리글(제목) 글 → 접힘(감독 건의 2026-10-14 3번: "다른 이름 · 실재성 · 소속 등 접기 펴기").
/// 한 번 접은 묶음은 다른 띠를 눌러 연 창에서도 접혀 있다(같은 제목이면). 앱 기억(`ui-state.json`의 `parts['detailFold']`)에 실려
/// 다음 실행에도 같다 — [AppGlue.attachMemory]가 [load]하고 [onChanged]로 적는다. 측정 모드에서는 기억을 붙이지 않으므로 늘 펼침이다.
class DetailFolds extends ChangeNotifier {
  DetailFolds._();
  static final instance = DetailFolds._();

  final _folded = <String>{};

  /// 접힘이 바뀌면(사람이 눌렀을 때만 — [load]는 부르지 않는다) 기억에 적는 길.
  VoidCallback? onChanged;

  bool isFolded(String title) => _folded.contains(title);

  void toggle(String title) {
    if (!_folded.remove(title)) _folded.add(title);
    notifyListeners();
    onChanged?.call();
  }

  /// 기억의 꼴: `{'folded': [제목, …]}`(가나다 차례).
  Map<String, dynamic> toJson() => {'folded': _folded.toList()..sort()};

  void load(Map<String, dynamic>? json) {
    final list = json?['folded'];
    _folded
      ..clear()
      ..addAll([if (list is List) for (final t in list) if (t is String && t.isNotEmpty) t]);
    notifyListeners();
  }
}

/// `.sub-box` — 둥근 14 · 안쪽 12/14 · 바탕 `--surface-2` 70% · 위 여백 16.
/// [title]은 12.5px/650, [small]은 그 옆의 옅은 글, [action]은 오른쪽 끝의 작은 단추.
/// 제목과 내용이 있는 묶음은 머리글을 눌러 접고 편다([foldable] — 머리글 오른쪽 끝의 ▾ · ▸). 접힘은 제목마다 [DetailFolds]가 기억한다.
class DetailBox extends StatelessWidget {
  const DetailBox({super.key, this.title, this.small, this.action, this.children = const [], this.warn = false, this.footnote, this.foldable = true});
  final String? title, small, footnote;
  final Widget? action;
  final List<Widget> children;

  /// 대범위의 '확인할 것'처럼 노란 상자.
  final bool warn;

  /// 머리글을 눌러 접고 펼 수 있는가(제목과 내용이 있을 때만 실제로 접힌다).
  final bool foldable;

  bool get _canFold => foldable && title != null && title!.isNotEmpty && (children.isNotEmpty || (footnote ?? '').isNotEmpty);

  @override
  Widget build(BuildContext context) {
    if (!_canFold) return _box(context, false, false);
    return ListenableBuilder(listenable: DetailFolds.instance, builder: (context, _) => _box(context, true, DetailFolds.instance.isFolded(title!)));
  }

  Widget _box(BuildContext context, bool canFold, bool folded) {
    Widget head = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              text: title,
              children: [
                if (small != null && small!.isNotEmpty)
                  TextSpan(
                    text: ' ${small!}',
                    style: const TextStyle(fontWeight: FontWeight.w400, color: Ui.text3),
                  ),
              ],
            ),
            style: const TextStyle(fontFamily: Ui.title, fontFamilyFallback: Ui.titleFallback, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w700, color: Ui.text),
          ),
        ),
        if (canFold)
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 3),
            // 선 아이콘(Lucide chevron-down · 흑백) — 접히면 −90°(오른쪽). 도는 것은 같은 장의 snap 한 값.
            child: MotionValue(
              target: folded ? 1 : 0,
              enter: MotionToken.snap,
              exit: MotionToken.snap,
              maxOvershoot: 0,
              child: const LineIcon(LineGlyph.chevronDown, size: 14, color: Ui.text3),
              builder: (context, t, child) => Transform.rotate(angle: -math.pi / 2 * t.clamp(0.0, 1.0), child: child),
            ),
          ),
        if (action != null) Padding(padding: const EdgeInsets.only(left: 8), child: action),
      ],
    );
    if (canFold) {
      head = Semantics(
        button: true,
        expanded: !folded,
        label: '$title ${folded ? '펼치기' : '접기'}',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => DetailFolds.instance.toggle(title!), child: head),
        ),
      );
    }
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ...children,
        if (footnote != null && footnote!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(footnote!, style: const TextStyle(fontSize: 12, height: 1.5, color: Ui.text3)),
          ),
      ],
    );
    return Container(
      // 묶음은 상자가 아니라 위의 선 하나와 머리글로 나눈다('확인할 것'만 옅은 ink8 바탕을 남긴다).
      margin: const EdgeInsets.only(top: 20),
      padding: warn ? const EdgeInsets.fromLTRB(12, 12, 12, 10) : const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: warn ? Ui.ink8 : null,
        border: const Border(top: BorderSide(color: Ui.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 접히는 묶음은 머리글 아래 8px도 내용과 함께 접힌다(다 접히면 머리글만 남는다).
          if (title != null) Padding(padding: EdgeInsets.only(bottom: canFold ? 0 : 8), child: head),
          if (!canFold)
            body
          else
            // 접고 펴기: 높이와 짙기를 한 값이 맡는다(펼 때 pop · 접을 때 snap · 넘침 없음 — 움직임 원칙). 다 접히면 내용을 짓지 않는다.
            MotionValue(
              target: folded ? 0 : 1,
              enter: MotionToken.pop,
              exit: MotionToken.snap,
              maxOvershoot: 0,
              child: Padding(padding: const EdgeInsets.only(top: 8), child: body),
              builder: (context, t, child) {
                final k = t.clamp(0.0, 1.0);
                if (folded && k <= .001) return const SizedBox(width: double.infinity);
                if (k >= .999) return child!;
                return ClipRect(child: Align(alignment: Alignment.topCenter, heightFactor: k, child: Opacity(opacity: k, child: child)));
              },
            ),
        ],
      ),
    );
  }
}

/// 태그 줄 — 12px · 둥근 4 · 채움 없이 1px 선 · 위 여백 14.
class DetailTags extends StatelessWidget {
  const DetailTags(this.tags, {super.key});
  final List<String> tags;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final t in tags)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Ui.innerRadius),
              border: Border.all(color: Ui.line),
            ),
            child: Text(t, style: const TextStyle(fontSize: 12, height: 1.5, color: Ui.text2)),
          ),
      ],
    ),
  );
}

/// 칩 — 높이 32 · 둥근 6 · ink20 선 · 13px/400(올리면 ink8). [muted]는 찾지 못한 이름(옅은 글자).
class DetailChip extends StatefulWidget {
  const DetailChip(this.text, {super.key, this.onTap, this.muted = false, this.color});
  final String text;
  final VoidCallback? onTap;
  final bool muted;
  final Color? color;

  @override
  State<DetailChip> createState() => _DetailChipState();
}

class _DetailChipState extends State<DetailChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final body = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Ui.ease,
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: widget.onTap != null && _hover ? Ui.ink8 : widget.color, borderRadius: BorderRadius.circular(Ui.controlRadius)),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Ui.controlRadius),
        border: Border.all(color: Ui.ink20),
      ),
      // 폭은 제 글만큼만(Container의 alignment는 주어진 폭을 다 써서 Wrap 안의 칩이 한 줄에 하나씩 서게 된다) — 세로로만 가운데.
      child: Center(
        widthFactor: 1,
        child: Text(
          widget.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, height: 1.5, fontWeight: FontWeight.w400, color: widget.muted ? Ui.ink40 : Ui.text),
        ),
      ),
    );
    if (widget.onTap == null) return body;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Semantics(
        button: true,
        label: widget.text,
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onTap, child: body),
      ),
    );
  }
}

/// 칩을 줄바꿈으로 늘어놓는 줄.
class DetailChipRow extends StatelessWidget {
  const DetailChipRow(this.children, {super.key, this.top = 8});
  final List<Widget> children;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: top),
    child: Wrap(spacing: 6, runSpacing: 6, children: children),
  );
}

/// dl 한 줄.
@immutable
class DetailDef {
  const DetailDef(this.term, this.child);
  final String term;
  final Widget child;
}

/// 맨 아래 정의 목록 — 13px · 위 선 1px · 위 여백 18 · 위 패딩 14 · 틈 4×12.
class DetailDefs extends StatelessWidget {
  const DetailDefs(this.defs, {super.key});
  final List<DetailDef> defs;

  @override
  Widget build(BuildContext context) {
    if (defs.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.only(top: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Ui.line)),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(fontSize: 13, height: 1.5, color: Ui.text),
        child: Table(
          columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
          defaultVerticalAlignment: TableCellVerticalAlignment.top,
          children: [
            for (int i = 0; i < defs.length; i++)
              TableRow(
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : 4, right: 12),
                    child: Text(defs[i].term, style: const TextStyle(fontSize: 13, height: 1.5, color: Ui.text3)),
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : 4),
                    child: defs[i].child,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// 아래 단추 줄의 작은 단추 — 높이 32 · 좌우 12 · 13px/600 · 둥근 6 · 채움 없이 ink20 선(올리면 ink8).
class DetailSmallButton extends StatefulWidget {
  const DetailSmallButton(this.text, {super.key, this.onTap, this.enabled = true, this.pad = 12, this.icon});
  final String text;

  /// 글 앞의 선 아이콘(14 · 먹 60% — 예전의 그림 글자 📄 🎯 …를 갈음, 건의 8의 1번).
  final LineGlyph? icon;
  final VoidCallback? onTap;
  final bool enabled;

  /// 좌우 안쪽 여백. 단추가 많은 줄(D1 승계표 — 웹 `.kv-succ-foot .btn-sm` 9px)만 좁힌다.
  final double pad;

  @override
  State<DetailSmallButton> createState() => _DetailSmallButtonState();
}

class _DetailSmallButtonState extends State<DetailSmallButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.enabled && widget.onTap != null;
    // 폭은 글만큼(웹 `.btn-sm`과 같음) — `alignment`만 주면 Container가 받은 폭을 다 채워, 아래 단추 줄(Wrap)에서
    // 단추가 한 줄에 하나씩 창 폭으로 늘어났다. 세로 가운데만 맞추고 가로는 글 폭(widthFactor 1)으로 둔다.
    final body = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Ui.ease,
      height: 32,
      padding: EdgeInsets.symmetric(horizontal: widget.pad),
      decoration: BoxDecoration(color: on && _hover ? Ui.ink8 : null, borderRadius: BorderRadius.circular(Ui.controlRadius)),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Ui.controlRadius),
        border: Border.all(color: Ui.ink20),
      ),
      child: Center(
        widthFactor: 1,
        child: Opacity(
          opacity: on ? 1 : .45,
          child: widget.icon == null
              ? Text(widget.text, style: const TextStyle(fontSize: 13, height: 1.5, fontWeight: FontWeight.w600, color: Ui.text))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LineIcon(widget.icon!, size: 14, color: Ui.ink60),
                    const SizedBox(width: 6),
                    Text(widget.text, style: const TextStyle(fontSize: 13, height: 1.5, fontWeight: FontWeight.w600, color: Ui.text)),
                  ],
                ),
        ),
      ),
    );
    if (!on) return body;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Semantics(
        button: true,
        label: widget.text,
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onTap, child: body),
      ),
    );
  }
}

/// 창 안의 체크 한 줄(같은 시기를 타국에도 · 모아 보기 …) — 13px · `--text-2`.
class DetailSwitch extends StatelessWidget {
  const DetailSwitch(this.label, {super.key, required this.value, required this.onChanged, this.top = 12});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final double top;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: top),
    child: MotionToggle(value: value, onChanged: onChanged, label: label),
  );
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  6. 목록 줄
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 목록 한 줄의 바탕 — 올리면 `--accent-soft`. 목록 부품을 새로 만들 때 이것으로 감싼다.
class DetailPressable extends StatefulWidget {
  const DetailPressable({
    super.key,
    required this.child,
    this.onTap,
    this.radius = 7,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    this.background,
    this.semantics,
  });
  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final EdgeInsets padding;
  final Color? background;
  final String? semantics;

  @override
  State<DetailPressable> createState() => _DetailPressableState();
}

class _DetailPressableState extends State<DetailPressable> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.onTap != null;
    final body = Container(
      width: double.infinity,
      padding: widget.padding,
      decoration: BoxDecoration(color: on && _hover ? DetailUi.rowHover : (widget.background ?? Colors.transparent), borderRadius: BorderRadius.circular(widget.radius)),
      child: widget.child,
    );
    if (!on) return body;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Semantics(
        button: true,
        label: widget.semantics,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: MotionPress(child: body),
        ),
      ),
    );
  }
}

/// 승계 목록 배지의 테두리 모양 — 직접은 실선 · 간접은 파선 · 부흥은 점선 · 소속 관계도 파선.
enum SuccBadge { direct, indirect, revival, partial, relation, plain }

/// `.succ-list` — 승계 · 소속 · 왕조 · 인물 · 대범위 구성 정권 · 관련 조약.
/// 앞 구분 칸의 폭은 이 목록 안에서 가장 넓은 칸에 맞춘다(감독 건의 2026-10-16 "구분 칸은 최대한 좁게, 명칭이 넓은 자리를" — 창 하나에서 맞추면
/// 다른 묶음의 긴 이름표 하나('부흥 운동' 따위)가 모든 줄의 구분 칸을 넓혀 이름이 두 줄로 꺾였다). 줄이 아닌 것이 섞이면 창 하나의 폭을 따른다.
class DetailSuccList extends StatelessWidget {
  const DetailSuccList(this.children, {super.key});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final column = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children);
    if (children.isEmpty || children.any((c) => c is! DetailSuccRow)) return column;
    final scaler = MediaQuery.textScalerOf(context);
    var width = 0.0;
    for (final row in children.cast<DetailSuccRow>()) {
      if (row.badge != null) width = math.max(width, _SuccBadge.widthOf(row.badge!, scaler));
    }
    return _ListBadge(width: width, child: column);
  }
}

class _ListBadge extends InheritedWidget {
  const _ListBadge({required this.width, required super.child});
  final double width;

  @override
  bool updateShouldNotify(_ListBadge oldWidget) => oldWidget.width != width;
}

/// `[배지][이름][오른쪽 끝 연도]` 한 줄 — 패딩 4/6 · 둥근 6 · 배지 뒤 틈 6 · 연도 앞 틈 8.
class DetailSuccRow extends StatelessWidget {
  const DetailSuccRow({super.key, this.badge, this.badgeHint, this.badgeStyle = SuccBadge.plain, required this.name, this.years, this.trailing, this.onTap});

  /// 배지 글(`직접` · `간접` · `부흥` · `부분` · `조공` …). 없으면 배지를 그리지 않는다.
  final String? badge;

  /// 배지에 올리면 뜨는 긴 이름 — 종류를 짧은 이름(`세력`)으로 적을 때 원래 이름(`부흥·저항 세력`).
  final String? badgeHint;
  final SuccBadge badgeStyle;
  final String name;

  /// 오른쪽 끝의 옅은 연도 글.
  final String? years;

  /// 이름 뒤에 붙는 옅은 글(`정도 중 · 지배층` · `3년 합류` 따위).
  final String? trailing;
  final VoidCallback? onTap;

  static const yearsStyle = TextStyle(fontSize: 11, height: 1.5, color: Ui.text3, fontFeatures: [FontFeature.tabularFigures()]);

  @override
  Widget build(BuildContext context) {
    // 줄을 표처럼(감독 건의 2026-10-14 6번 — "이어간 나라의 연도 표기 정렬"): 예전에는 이름(Flexible)과 연도(Expanded)가 남은 폭을 반씩 나눠
    // 연도가 줄마다 다른 자리(창 가운데쯤)에 섰다. 이제 [배지 — 목록 안 가장 넓은 배지 폭][이름 — 나머지][기간 — 창 안 가장 넓은 기간 폭 · 왼쪽 맞춤 · 오른쪽 끝]
    // — 기간 폭은 [YearColumn]이 창 하나에서 모아 맞춘다(웹 `--sw`). 기간 칸은 줄 폭의 45%까지(넘으면 그 안에서 줄을 바꾼다).
    // 배지 폭은 [DetailSuccList]가 목록 안에서 잰 값이 먼저다(없으면 창 하나의 값).
    final scaler = MediaQuery.textScalerOf(context);
    final listBadge = context.dependOnInheritedWidgetOfExactType<_ListBadge>()?.width;
    final badgeW = listBadge == null ? YearColumn.badgeOf(context) : null, spanW = YearColumn.spanOf(context);
    final hasYears = years != null && years!.isNotEmpty;
    if (badge != null && badgeW != null) badgeW.offer(_SuccBadge.widthOf(badge!, scaler));
    Widget? chip;
    if (badge != null) {
      chip = _SuccBadge(text: badge!, style: badgeStyle);
      if (badgeHint != null && badgeHint!.isNotEmpty && badgeHint != badge) chip = Tooltip(message: badgeHint!, child: chip);
    }
    if (hasYears && spanW != null) spanW.offer(measureText(years!, yearsStyle, scaler: scaler) + 1);
    return DetailPressable(
      onTap: onTap,
      radius: 6,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      semantics: name,
      child: LayoutBuilder(
        builder: (context, box) {
          final cap = box.maxWidth.isFinite ? box.maxWidth * .45 : double.infinity;
          final yw = math.min(spanW?.value ?? 0, cap);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              if (chip != null) ...[
                ConstrainedBox(constraints: BoxConstraints(minWidth: listBadge ?? badgeW?.value ?? 0), child: chip),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: name,
                    children: [
                      if (trailing != null && trailing!.isNotEmpty)
                        TextSpan(
                          text: ' ${trailing!}',
                          style: const TextStyle(fontSize: 11, color: Ui.text3),
                        ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 14, height: 1.5, color: Ui.text),
                ),
              ),
              if (hasYears) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(minWidth: yw, maxWidth: math.max(yw, cap)),
                  child: Text(years!, style: yearsStyle),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SuccBadge extends StatelessWidget {
  const _SuccBadge({required this.text, required this.style});
  final String text;
  final SuccBadge style;

  static const textStyle = TextStyle(fontSize: 11, height: 1.6, color: Ui.text2);

  /// 배지 하나의 바깥 폭(글 + 왼쪽 안쪽 5(모따기 몫 포함) + 오른쪽 4 — 테는 그 안에 그린다).
  /// 감독 건의 2026-10-16 "구분 칸은 최대한 좁게": 예전 7 · 6에서 줄임(글과 테 사이는 가운데 높이에서 4px 남짓).
  static double widthOf(String text, TextScaler scaler) => measureText(text, textStyle, scaler: scaler) + 9 + .5;

  @override
  Widget build(BuildContext context) {
    // 파선 · 점선 테두리는 Flutter의 Border가 그리지 못한다 — 같은 뜻을 전하려고 옅기로 구분한다
    // (직접 1 · 간접 .62 · 부흥 .38 · 부분은 연표의 선처럼 실선 1 — 정도는 이름 뒤의 글로).
    const alpha = {SuccBadge.direct: 1.0, SuccBadge.indirect: .62, SuccBadge.revival: .38, SuccBadge.partial: 1.0, SuccBadge.relation: .62, SuccBadge.plain: 1.0};
    // 리메이크 2부(목업 서고): 흰 꼬리표 칩 — 왼쪽 두 귀 모따기 3 · 종이 칠 · 테는 승계 갈래의 옅기대로.
    return CustomPaint(
      painter: DetailTagPainter(fill: const Color(0xff000000 | Look.paper), edge: _soft(Ui.lineStrong, alpha[style]!), cham: 3),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(5, 0, 4, 0),
        child: Text(text, style: textStyle, textAlign: TextAlign.center),
      ),
    );
  }
}

/// `.cell-list` — 지도자 · 내각 · 연호 · 도읍 · 시기 · 지위.
/// 격자 `repeat(auto-fill, minmax(140px, 1fr))` · 틈 2×8 · 최대 높이 `min(50vh, 420)`.
class DetailCellList extends StatelessWidget {
  const DetailCellList(this.tiles, {super.key, this.leaders = false, this.single = false});
  final List<Widget> tiles;

  /// 지도자 목록(한 칸 격자 · 연도 칸 104px 고정).
  final bool leaders;

  /// 지위 목록처럼 한 칸으로 두는 것.
  final bool single;

  @override
  Widget build(BuildContext context) {
    final maxHeight = math.min(420.0, MediaQuery.sizeOf(context).height * .5);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: LayoutBuilder(
        builder: (context, box) {
          final columns = leaders || single ? 1 : math.max(1, ((box.maxWidth + 8) / 148).floor());
          final rows = <Widget>[];
          for (int i = 0; i < tiles.length; i += columns) {
            rows.add(
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 2),
                child: Row(
                  // 세로로 늘리지 않는다 — 이 목록은 속이 스크롤되는 통 안에 있어 높이가 열려 있다.
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (int c = 0; c < columns; c++) ...[if (c > 0) const SizedBox(width: 8), Expanded(child: i + c < tiles.length ? tiles[i + c] : const SizedBox.shrink())],
                  ],
                ),
              ),
            );
          }
          return SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: rows),
          );
        },
      ),
    );
  }
}

/// 칸 목록의 한 칸 — `[연도 11px][이름 13px]` 세로 쌓기, 오른쪽 위에 겹쳐 뜨는 `📄`.
class DetailCellTile extends StatefulWidget {
  const DetailCellTile({
    super.key,
    required this.year,
    required this.name,
    this.sub,
    this.mark,
    this.markColor,
    this.current = false,
    this.leaders = false,
    this.hasDoc = false,
    this.onDoc,
    this.onTap,
    this.swatch,
  });

  /// 왼쪽(또는 위)의 연도 글.
  final String year;
  final String name;

  /// 이름 아래(지도자면 둘째 줄)의 옅은 글.
  final String? sub;

  /// 이름 뒤의 작은 글(`▲승격` · `▼격하`).
  final String? mark;
  final Color? markColor;

  /// 지금 보고 있는 칸 — 바탕 `--accent-soft` · 이름 굵게.
  final bool current;
  final bool leaders;
  final bool hasDoc;
  final VoidCallback? onDoc, onTap;

  /// 지위 목록의 짙기 견본(12×12 색 네모).
  final Color? swatch;

  @override
  State<DetailCellTile> createState() => _DetailCellTileState();
}

class _DetailCellTileState extends State<DetailCellTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    const yearStyle = TextStyle(fontSize: 11, height: 1.5, color: Ui.text3, fontFeatures: [FontFeature.tabularFigures()]);
    final nameStyle = TextStyle(fontSize: 13, height: 1.5, color: Ui.text, fontWeight: widget.current ? FontWeight.w700 : FontWeight.w400);
    final name = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        if (widget.swatch != null) ...[
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: widget.swatch, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(widget.name, style: nameStyle, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        if (widget.mark != null) ...[const SizedBox(width: 4), Text(widget.mark!, style: TextStyle(fontSize: 10.5, height: 1.5, color: widget.markColor ?? Ui.text3))],
      ],
    );
    final sub = widget.sub == null || widget.sub!.isEmpty
        ? null
        : Text(
            widget.sub!,
            style: const TextStyle(fontSize: 11, height: 1.5, color: Ui.text3),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );

    Widget inner;
    if (widget.leaders) {
      inner = Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(width: 104, child: Text(widget.year, style: yearStyle)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [name, ?sub]),
          ),
        ],
      );
    } else {
      inner = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.year, style: yearStyle),
          name,
          ?sub,
        ],
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Stack(
        children: [
          DetailPressable(
            onTap: widget.onTap,
            radius: 6,
            padding: const EdgeInsets.fromLTRB(6, 4, 28, 4),
            background: widget.current ? Ui.accentSoft : null,
            semantics: widget.name,
            child: inner,
          ),
          // 문서 단추는 자리를 차지하지 않고 오른쪽 위에 겹쳐 뜬다. 문서가 있으면 늘 보이고(.7), 없으면 올렸을 때만.
          if (widget.onDoc != null && (widget.hasDoc || _hover))
            Positioned(
              top: 3,
              right: 3,
              child: Opacity(
                opacity: widget.hasDoc && !_hover ? .7 : 1,
                child: DetailPressable(
                  onTap: widget.onDoc,
                  radius: 6,
                  padding: EdgeInsets.zero,
                  semantics: '문서',
                  child: const SizedBox(
                    width: 22,
                    height: 22,
                    child: Center(child: LineIcon(LineGlyph.file, size: 12, color: Ui.ink60)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// `.year-events` — 이 시기의 사건 · 같은 시기 타국 · 관련 사건 · 서명한 조약 · 같은 해 보기.
class DetailYearEvents extends StatelessWidget {
  const DetailYearEvents(this.children, {super.key});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children);
}

/// `[색 점 9px][날짜][제목][트랙]` 한 줄. 날짜 칸의 폭은 창 안에서 하나로 맞는다(`--yw`).
class DetailYearRow extends StatelessWidget {
  const DetailYearRow({super.key, this.color, this.when = '', required this.title, this.track, this.tail, this.diamond = false, this.hollow = false, this.onTap});
  final Color? color;

  /// 왼쪽의 날짜 글.
  final String when;
  final String title;

  /// 오른쪽의 트랙 이름.
  final String? track;

  /// 제목 뒤의 꼬리표(`소속 · 〈이름〉` · `포함 3`).
  final String? tail;

  /// 조약은 마름모, 공동 사건의 다른 자리는 속 빈 점.
  final bool diamond, hollow;
  final VoidCallback? onTap;

  static const whenStyle = TextStyle(fontSize: 12, height: 1.5, color: Ui.text3, fontFeatures: [FontFeature.tabularFigures()]);

  @override
  Widget build(BuildContext context) {
    final shared = YearColumn.maybeOf(context);
    if (shared != null && when.isNotEmpty) shared.offer(measureText(when, whenStyle, scaler: MediaQuery.textScalerOf(context)) + 1);
    final yw = shared?.value ?? DetailUi.yearWidth;

    Widget dot = Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: hollow ? Colors.transparent : (color ?? Ui.text3),
        border: hollow ? Border.all(color: color ?? Ui.text3, width: 2) : null,
        borderRadius: BorderRadius.circular(diamond ? 1 : 4.5),
      ),
    );
    if (diamond) dot = Transform.rotate(angle: math.pi / 4, child: dot);

    return LayoutBuilder(
      builder: (context, box) {
        final cap = box.maxWidth.isFinite ? box.maxWidth * .45 : yw;
        final width = math.min(yw, cap);
        return DetailPressable(
          onTap: onTap,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          semantics: title,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Padding(padding: const EdgeInsets.only(top: 2), child: dot),
              const SizedBox(width: 8),
              if (when.isNotEmpty) ...[
                ConstrainedBox(
                  constraints: BoxConstraints(minWidth: width, maxWidth: math.max(width, cap)),
                  child: Text(when, style: whenStyle),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: title,
                    children: [
                      if (tail != null && tail!.isNotEmpty)
                        TextSpan(
                          text: ' ${tail!}',
                          style: const TextStyle(fontSize: 12, color: Ui.text3),
                        ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 14, height: 1.5, color: Ui.text),
                ),
              ),
              if (track != null && track!.isNotEmpty) ...[const SizedBox(width: 8), Text(track!, style: const TextStyle(fontSize: 12, height: 1.5, color: Ui.text3))],
            ],
          ),
        );
      },
    );
  }
}

/// `.kid-list` — 포함된 사건 · 지도자 목록. `[연도 60px 고정][이름 13px]`.
class DetailKidList extends StatelessWidget {
  const DetailKidList(this.children, {super.key});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children);
}

class DetailKidRow extends StatelessWidget {
  const DetailKidRow({super.key, required this.year, required this.name, this.onTap});
  final String year, name;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => DetailPressable(
    onTap: onTap,
    semantics: name,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        SizedBox(
          width: 60,
          child: Text(
            year,
            style: const TextStyle(fontSize: 12, height: 1.5, color: Ui.text3, fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(name, style: const TextStyle(fontSize: 13, height: 1.5, color: Ui.text)),
        ),
      ],
    ),
  );
}

/// `.alt-list` — 다른 견해. 첫 줄(이 연표가 쓰는 연대)은 `--accent` 10% 바탕.
class DetailAltList extends StatelessWidget {
  const DetailAltList(this.children, {super.key});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children);
}

/// `[연대(굵게)][근거 12px]` 한 줄. [note]는 그 아래 작은 메모, [onTap]이 없으면 누르지 않는 줄.
class DetailAltRow extends StatelessWidget {
  const DetailAltRow({super.key, required this.when, this.why, this.note, this.main = false, this.onTap});
  final String when;
  final String? why, note;

  /// 첫 줄 — 이 연표가 쓰는 연대.
  final bool main;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: DetailPressable(
      onTap: onTap,
      background: main ? _soft(Ui.accent, .10) : null,
      semantics: when,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 1,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Text(
                when.isEmpty ? '—' : when,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  fontWeight: FontWeight.w700,
                  color: onTap == null && when.isEmpty ? Ui.text3 : Ui.text,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (why != null && why!.isNotEmpty) Text(why!, style: const TextStyle(fontSize: 12, height: 1.6, color: Ui.text2)),
            ],
          ),
          if (note != null && note!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(note!, style: const TextStyle(fontSize: 11.5, height: 1.5, color: Ui.text3)),
            ),
        ],
      ),
    ),
  );
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  7. 갈래 — 어느 창이 열리는가 (명세 2-2)
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 갈래 하나의 성질. `lane`은 제 줄이 있어 세로 닻을 거는가, `pick`은 연표를 흐리게 하며 고르는가,
/// `spot`은 칸 조명을 거는가(조명끼리는 끄지 않고 곧바로 옮겨 간다), `always`는 그 강조를 사건 배치에도 쓰는가.
@immutable
class DetailKind {
  const DetailKind(this.id, {this.lane = true, this.pick = true, this.spot = false, this.always = false});
  final String id;
  final bool lane, pick, spot, always;
}

/// 명세 2-2의 표 그대로 — **앞에서부터 처음 맞는 갈래**가 창을 그린다.
const detailKinds = <DetailKind>[
  DetailKind('epoch', lane: false),
  DetailKind('scope', lane: false),
  DetailKind('phase', spot: true, always: true),
  DetailKind('rank', spot: true, always: true),
  DetailKind('cell', spot: true, always: true),
  DetailKind('dynasty'),
  // 승계표(D1 결정 1 A — 확정 설계 3-1): 나라 상세와 같은 자리에서 그 나라의 지도자 차례를 보인다. 고른 것은 그 나라 그대로라
  // 나라 상세와 같이 세로 닻을 걸고 흐리게 고른다(칸 참조 'succession'은 칸이 아니라 조명 · 칸 강조에 걸리지 않는다).
  DetailKind('succession'),
  // 계보 전용 인물(확정 설계 2-1 · 9-2 W2 5번): 띠에 제 막대가 없어 고르지도 흐리게 하지도 않고 세로 닻도 걸지 않는다.
  DetailKind('lineage', lane: false, pick: false),
  DetailKind('figure'),
  DetailKind('figures-of'),
  // 성씨 창(결정 7 A 덧붙임 — 확정 설계 5-3): 가문 창처럼 연표를 흐리게 하지 않고 그 성의 가문들만 조명한다.
  // (차례는 가문 바로 앞 — 가문 다음 · 기본 앞의 단체 · 제도 자리는 웹이 정한 그대로 둔다.)
  DetailKind('surname', lane: false, pick: false),
  DetailKind('house', lane: false, pick: false),
  // 단체 · 제도(형식 버전 3): 제 줄이 없어 가문 창처럼 고르지 않고 세로 닻도 걸지 않는다(웹 DETAIL_KINDS의 group · institution —
  // '기본' 바로 앞). 그림 · 조명은 없고 창의 글만 선다(띠 안의 집권 단 · 렌즈 띠는 A3).
  DetailKind('group', lane: false, pick: false),
  DetailKind('institution', lane: false, pick: false),
  DetailKind('item'),
];

/// 칸 참조의 앞머리(`CELL_KINDS`) — 이것이면 칸 창이 열린다.
const detailCellPrefixes = <String>['leader:', 'cabinet:', 'era:', 'capital:'];

/// 나라를 이 칸 참조로 고르면 승계표가 열린다(웹 `DETAIL_KINDS`의 `succession` — `opts.cell === 'succession'`).
const successionCell = 'succession';

/// 종류 · 칸 참조 · 항목 기록을 보고 갈래를 고른다(명세 2-2의 차례 그대로).
DetailKind pickDetailKind({required String kind, String? cell, Map<String, dynamic> json = const {}}) {
  DetailKind of(String id) => detailKinds.firstWhere((k) => k.id == id);
  if (kind == 'epoch') return of('epoch');
  if (kind == 'scope') return of('scope');
  if (cell != null) {
    if (cell.startsWith('phase:')) return of('phase');
    if (cell.startsWith('rank:')) return of('rank');
    if (detailCellPrefixes.any(cell.startsWith)) return of('cell');
    if (cell == 'figures') return of('figures-of');
    if (cell == successionCell) return of('succession');
  }
  if (kind == 'dynasty' && _hasRuled(json)) return of('dynasty');
  // 계보 전용 인물은 기록 본문에 `lineageOnly: true`가 그대로 실려 온다(내보내기 8-1 — 활동 칸을 뺀 본문).
  if (kind == 'figure') return json['lineageOnly'] == true ? of('lineage') : of('figure');
  if (kind == 'house' || json['itemKind'] == 'house') return of('house');
  if (kind == 'surname' || json['itemKind'] == 'surname') return of('surname');
  if (kind == 'group' || json['itemKind'] == 'group') return of('group');
  if (kind == 'institution' || json['itemKind'] == 'institution') return of('institution');
  return of('item');
}

/// 왕조가 다스린 구간이 있는가 — 없으면 기본 상세로 간다(명세 2-2의 6번 조건).
bool _hasRuled(Map<String, dynamic> json) {
  for (final key in const ['x_ruled', 'ruled', 'polities']) {
    final v = json[key];
    if (v is List && v.isNotEmpty) return true;
  }
  return false;
}

/// 상세 위젯 하나가 받는 것.
@immutable
class DetailContext {
  const DetailContext({
    required this.bus,
    required this.uid,
    required this.kind,
    required this.cell,
    required this.json,
    required this.branch,
    required this.fresh,
    required this.close,
    required this.askEntity,
  });

  final AppBus bus;

  /// 항목 기록의 열쇠.
  final String uid;

  /// 항목의 종류(`period` · `event` · `treaty` · `figure` · `epoch` · `scope` · `organ` · `culture` · `dynasty` ·
  /// `house` · `group` · `institution`).
  final String kind;

  /// 칸 참조(`leader:3` · `era:2` · `phase:0:1` · `figures` …). 항목 전체를 고른 것이면 null.
  final String? cell;

  /// 항목 기록의 JSON을 푼 것(계약 6-9절). 뿌리가 아닌 곳의 항목은 `{"$ref": uid, "name": 이름}`이다.
  final Map<String, dynamic> json;
  final DetailKind branch;

  /// 앞 창과 다른 항목을 새로 골랐는가 — 참일 때만 세로 닻이 그 줄을 데려온다(`reveal`).
  final bool fresh;
  final VoidCallback close;

  /// 목록 줄이 가리키는 다른 항목의 기록을 받아 온다. 없으면 null.
  final Future<Map<String, dynamic>?> Function(String uid) askEntity;

  /// 그 항목의 창으로 옮겨 간다.
  void open(String uid, {String kind = '', String? cell}) => bus.select(uid, kind: kind, cell: cell);

  /// 그 기간으로 데려간다(🎯 이 위치로 · 이 시기로 · 다른 견해의 해).
  void goTo(double lo, double hi, {int? row, bool fly = true, String? ring}) => bus.goTo(lo, hi, row: row, fly: fly, ring: ring);

  /// 부품끼리 알릴 것(메아리 스위치 · 모아 보기 …).
  ValueNotifier<Object?> slot(String name) => bus.slot(name);

  /// 항목의 이름(관점을 고르지 않았을 때의 기본 이름).
  String get name => detailString(json, 'name');
}

/// 상세 창이 연표에 알리는 것 — `bus.slot('detail')`에 실린다. 앱 틀이 이것을 듣고
/// 흐림(`pick`) · 세로 닻(`lane`) · 칸 조명(`spot`) · 가린 폭(`inset`)을 건다.
@immutable
class DetailState {
  const DetailState({required this.uid, required this.kind, required this.branch, required this.fresh, required this.inset});
  const DetailState.closed() : uid = '', kind = '', branch = null, fresh = false, inset = 0;

  final String uid, kind;
  final DetailKind? branch;
  final bool fresh;

  /// 창이 가린 폭(연표 오른쪽 끝 − 창의 왼쪽). 창이 없으면 0.
  final double inset;

  bool get open => branch != null;

  /// 연표를 흐리게 하며 고르는가(가문 창은 거짓).
  bool get pick => branch?.pick ?? false;

  /// 세로 닻을 거는가.
  bool get lane => branch?.lane ?? false;

  /// 칸 조명을 거는가.
  bool get spot => branch?.spot ?? false;

  /// 그 강조를 사건 배치에도 쓰는가(`layout`).
  bool get always => branch?.always ?? false;
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  8. 항목 기록에서 값 꺼내기
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 다른 항목을 가리키는 자리(`{"$ref": uid, "name": 이름}`).
@immutable
class DetailRef {
  const DetailRef(this.uid, this.name);
  final String uid, name;
}

/// 그 자리가 다른 항목을 가리키면 [DetailRef], 아니면 null.
DetailRef? detailRef(Object? value) {
  if (value is! Map) return null;
  final uid = value[r'$ref'] ?? value['uid'];
  if (uid is! String || uid.isEmpty) return null;
  return DetailRef(uid, value['name'] is String ? value['name'] as String : '');
}

/// 글자 값(없거나 글자가 아니면 빈 글).
String detailString(Map<String, dynamic> json, String key) {
  final v = json[key];
  return v is String ? v : (v == null ? '' : '$v');
}

/// 목록 값(없거나 목록이 아니면 빈 목록). 안의 것이 Map인 것만 남긴다.
List<Map<String, dynamic>> detailList(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is! List) return const [];
  return [
    for (final item in v)
      if (item is Map) item.cast<String, dynamic>(),
  ];
}

/// 글자 목록(태그 따위).
List<String> detailStrings(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is! List) return const [];
  return [
    for (final item in v)
      if (item != null) '$item',
  ];
}

/// 수 값(없으면 null).
num? detailNum(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is num) return v;
  if (v is String) return num.tryParse(v);
  return null;
}

/// 0xRRGGBB 정수를 색으로. 없으면 [fallback].
Color detailColor(Object? value, [Color fallback = Ui.text3]) {
  if (value is num) return Color(0xff000000 | (value.toInt() & 0xffffff));
  if (value is String && value.startsWith('#')) {
    final n = int.tryParse(value.substring(1), radix: 16);
    if (n != null) return Color(0xff000000 | (n & 0xffffff));
  }
  return fallback;
}

/// 항목 기록 하나를 받아 푼다 — 창 틀 밖의 부품(세계표 떠 있는 창의 머리 칩 · 제목)이 작은 기록(가문 · 인물)을 읽을 때.
/// 기록이 없거나 깨졌으면 null. **계보 뼈대(갈래 `kin`)는 이 길로 받지 않는다** — 작업자 isolate에서 푼다(`kin/kin_record.dart`).
Future<Map<String, dynamic>?> detailEntity(AppBus bus, String uid) async {
  try {
    final answer = await bus.ask({'op': 'entity', 'uid': uid});
    final raw = answer['json'];
    if (raw is Map) return raw.cast<String, dynamic>();
    if (raw is String && raw.isNotEmpty) {
      final v = jsonDecode(raw);
      if (v is Map) return v.cast<String, dynamic>();
    }
  } catch (_) {
    // 없는 항목 · 깨진 기록 — 부른 쪽이 그 줄만 빼고 연다.
  }
  return null;
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  9. DetailHost — 고른 것을 듣고 알맞은 창을 띄운다
// ────────────────────────────────────────────────────────────────────────────────────────────

typedef DetailBuilder = Widget Function(DetailContext ctx);

/// 남의 창 아래 단추 줄에 더할 단추들(없으면 빈 목록).
typedef DetailFootBuilder = List<Widget> Function(DetailContext ctx);

/// 떠 있는 창 하나 — [DetailHost.registerWindow]로 맡긴다. [value]는 그 슬롯의 값(창을 여는 부탁), [close]는 슬롯을 비운다.
typedef DetailWindowBuilder = Widget Function(AppBus bus, Object value, VoidCallback close);

/// [AppBus.selection]을 듣고 `{"op":"entity"}`로 항목 기록을 받아, 갈래(명세 2-2)에 맞는 상세 위젯을 띄운다.
/// 종류마다의 위젯은 그 파일이 제 스스로 [register]로 등록한다 — 이 파일은 그 파일들을 import 하지 않는다.
class DetailHost extends StatefulWidget {
  const DetailHost({super.key, required this.bus, this.framed = true});

  final AppBus bus;

  /// 밖틀(유리 바탕 · 미끄러져 들어오기 · Esc)까지 이 부품이 그리는가.
  /// 앱 틀의 `shell/detail_panel.dart` 안에 끼워 넣을 때는 false.
  final bool framed;

  static final _builders = <String, DetailBuilder>{};
  static final _feet = <String, Map<String, DetailFootBuilder>>{};
  static final _windows = <String, DetailWindowBuilder>{};

  /// 갈래 하나를 맡는다. `id`는 [detailKinds]의 것(`item` · `cell` · `figure` · `house` · `scope` …).
  static void register(String id, DetailBuilder builder) => _builders[id] = builder;

  /// 검사에서 되돌릴 때.
  static void unregister(String id) => _builders.remove(id);

  static bool registered(String id) => _builders.containsKey(id);

  /// 갈래 [id]의 창 아래 단추 줄에 단추를 더한다 — 그 창의 파일을 고치지 않고 다른 갈래가 길을 낸다
  /// (D1 칸 창의 `승계표에서 보기` — 확정 설계 3-1). 단추는 그 창의 맨 끝 단추(닫기) 앞에 선다. [key]가 같으면 갈아 끼운다.
  static void registerFoot(String id, String key, DetailFootBuilder builder) => (_feet[id] ??= {})[key] = builder;

  /// 검사에서 되돌릴 때.
  static void unregisterFoot(String id, String key) => _feet[id]?.remove(key);

  /// 떠 있는 창을 맡는다(D1 세계표 — 확정 설계 4-1). `bus.slot(slot)`에 값을 넣으면 그 창이 연표 위에 뜨고, null이면 닫힌다.
  /// 상세 창이 닫혀도 떠 있는 창은 남는다(제 ✕ · Esc로 닫는다). 앱에 [Overlay]가 없으면(검사의 맨 틀) 띄우지 않는다.
  static void registerWindow(String slot, DetailWindowBuilder builder) => _windows[slot] = builder;

  /// 검사에서 되돌릴 때.
  static void unregisterWindow(String slot) => _windows.remove(slot);

  /// 맡긴 떠 있는 창 가운데 지금 열린 것이 있는가(그림 찍기 — 창은 길잡이의 층에 서므로 앱 틀의 경계 밖이다).
  static bool windowOpen(AppBus bus) => _windows.keys.any((slot) => bus.slot(slot).value != null);

  @override
  State<DetailHost> createState() => _DetailHostState();
}

class _DetailHostState extends State<DetailHost> {
  Selection? _want;
  String _uid = '', _kind = '';
  String? _cell;
  Map<String, dynamic> _json = const {};
  bool _open = false, _fresh = false;
  int _turn = 0;
  Object? _retire;

  /// 이 창이 열려 있는 동안 거쳐 온 고른 것(감독 건의 2026-10-16 "뒤로가기 버튼 — 지금은 끄고 다시 키고 이래야"). 닫히면 비운다.
  final _history = <Selection>[];
  static const _historyMax = 50;

  /// 창에 지금 보이는 고른 것 · 뒤로 단추로 고른 것(그것이 열리면 기록에 쌓지 않는다).
  Selection? _shown, _backTo;

  /// 떠 있는 창마다의 자리(Overlay) 조종 — 슬롯 이름이 열쇠.
  final _portals = <String, OverlayPortalController>{};

  @override
  void initState() {
    super.initState();
    widget.bus.selection.addListener(_onSelection);
    _listenWindows(widget.bus, true);
    _onSelection();
  }

  @override
  void didUpdateWidget(DetailHost old) {
    super.didUpdateWidget(old);
    if (old.bus != widget.bus) {
      old.bus.selection.removeListener(_onSelection);
      _listenWindows(old.bus, false);
      widget.bus.selection.addListener(_onSelection);
      _listenWindows(widget.bus, true);
      _onSelection();
    }
  }

  @override
  void dispose() {
    widget.bus.selection.removeListener(_onSelection);
    MotionStage.instance.cancel(_retire);
    _listenWindows(widget.bus, false);
    super.dispose();
  }

  void _listenWindows(AppBus bus, bool on) {
    for (final slot in DetailHost._windows.keys) {
      if (on) {
        _portals.putIfAbsent(slot, OverlayPortalController.new);
        bus.slot(slot).addListener(_onWindows);
      } else {
        bus.slot(slot).removeListener(_onWindows);
      }
    }
    if (on) _onWindows();
  }

  /// 떠 있는 창의 슬롯이 바뀌었다 — 값이 있으면 띄우고 없으면 거둔다.
  void _onWindows() {
    if (!mounted) return;
    for (final entry in _portals.entries) {
      final want = widget.bus.slot(entry.key).value != null;
      if (want == entry.value.isShowing) continue;
      // 지금 장면을 짓는 중일 수 있다(다른 위젯의 build 안에서 슬롯을 바꾼 때) — 다음 틈에 연다.
      scheduleMicrotask(() {
        if (!mounted) return;
        final now = widget.bus.slot(entry.key).value != null;
        if (now && !entry.value.isShowing) entry.value.show();
        if (!now && entry.value.isShowing) entry.value.hide();
      });
    }
  }

  /// 떠 있는 창들을 [child] 둘레에 건다. 앱에 [Overlay]가 없으면 그대로 둔다.
  Widget _withWindows(Widget child) {
    if (_portals.isEmpty || Overlay.maybeOf(context) == null) return child;
    var out = child;
    for (final entry in _portals.entries) {
      final build = DetailHost._windows[entry.key];
      if (build == null) continue;
      out = OverlayPortal(
        controller: entry.value,
        overlayChildBuilder: (context) {
          final value = widget.bus.slot(entry.key).value;
          if (value == null) return const SizedBox.shrink();
          return build(widget.bus, value, () => widget.bus.slot(entry.key).value = null);
        },
        child: out,
      );
    }
    return out;
  }

  Future<void> _onSelection() async {
    final pick = widget.bus.selection.value;
    if (pick == _want) return;
    _want = pick;
    final turn = ++_turn;
    if (pick == null) {
      _close(quiet: true);
      return;
    }

    Map<String, dynamic>? answer;
    try {
      answer = await widget.bus.ask({'op': 'entity', 'uid': pick.uid});
    } catch (_) {
      answer = null;
    }
    if (!mounted || turn != _turn) return;

    final kind = answer?['kind'] is String ? answer!['kind'] as String : pick.kind;
    final json = _decode(answer?['json']);
    // 기록이 없으면 창을 닫는다(명세 2-1의 창 열기 1번) — 다만 가문은 제 기록 없이도 열린다.
    if (answer == null && !pick.uid.startsWith('house:')) {
      _close(quiet: true);
      return;
    }

    setState(() {
      // 열린 창에서 다른 것으로 넘어가면 앞의 것을 쌓는다(뒤로 단추로 온 때는 쌓지 않는다).
      final shown = _shown, back = _backTo;
      _backTo = null;
      if (back != pick && _open && shown != null && shown != pick) {
        _history.add(shown);
        if (_history.length > _historyMax) _history.removeAt(0);
      }
      _shown = pick;
      _fresh = !_open || pick.uid != _uid;
      _uid = pick.uid;
      _kind = kind.isEmpty && pick.uid.startsWith('house:') ? 'house' : kind;
      _cell = pick.cell;
      _json = json;
      _open = true;
    });
    MotionStage.instance.cancel(_retire);
    _retire = null;
    // 같은 해 보기가 열려 있었으면 끈다(명세 2-1의 창 열기 4번). 그 창의 슬롯 이름은 `yearPanel`이다(tools_year.dart의 [yearSlot]).
    widget.bus.slot('yearPanel').value = null;
    _tell();
  }

  Map<String, dynamic> _decode(Object? raw) {
    if (raw is Map) return raw.cast<String, dynamic>();
    if (raw is String && raw.isNotEmpty) {
      try {
        final v = jsonDecode(raw);
        if (v is Map) return v.cast<String, dynamic>();
      } catch (_) {
        // 기록이 깨졌으면 빈 항목으로 연다 — 창은 제목만 보이고 닫을 수 있다.
      }
    }
    return const {};
  }

  /// 뒤로 — 거쳐 온 것 가운데 마지막을 다시 고른다(연표는 옮기지 않는다 — 앞으로 갈 때의 [DetailContext.open]과 같다).
  void _back() {
    if (_history.isEmpty) return;
    final prev = _history.removeLast();
    _backTo = prev;
    widget.bus.select(prev.uid, kind: prev.kind, cell: prev.cell, eventId: prev.eventId);
  }

  void _close({bool quiet = false}) {
    if (!quiet) widget.bus.clearSelection();
    _history.clear();
    _shown = _backTo = null;
    if (!_open) return;
    setState(() {
      // 물러나는 동안 마지막 내용을 유지한다. 다음 선택은 같은 위치에서 이어진다.
      _open = false;
    });
    _tell();
    if (!widget.framed) {
      // 바깥 상세 칸이 물러날 동안만 내용을 둔다. 같은 장의 시간 배율을 따른다.
      MotionStage.instance.cancel(_retire);
      _retire = MotionStage.instance.schedule(Motion.outMs * 2, _dismissed);
    }
  }

  void _dismissed() {
    if (!mounted || _open) return;
    MotionStage.instance.cancel(_retire);
    _retire = null;
    setState(() {
      _uid = '';
      _kind = '';
      _cell = null;
      _json = const {};
    });
  }

  /// 흐림 · 세로 닻 · 조명 · 가린 폭을 앱 틀에 알린다.
  void _tell() {
    if (!_open) {
      widget.bus.slot('detail').value = const DetailState.closed();
      return;
    }
    final branch = pickDetailKind(kind: _kind, cell: _cell, json: _json);
    widget.bus.slot('detail').value = DetailState(uid: _uid, kind: _kind, branch: branch, fresh: _fresh, inset: Ui.detailCover);
  }

  Future<Map<String, dynamic>?> _askEntity(String uid) async {
    try {
      final answer = await widget.bus.ask({'op': 'entity', 'uid': uid});
      return _decode(answer['json']);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_uid.isEmpty) return _withWindows(const SizedBox.shrink());
    final branch = pickDetailKind(kind: _kind, cell: _cell, json: _json);
    final ctx = DetailContext(bus: widget.bus, uid: _uid, kind: _kind, cell: _cell, json: _json, branch: branch, fresh: _fresh, close: _close, askEntity: _askEntity);
    final build = DetailHost._builders[branch.id] ?? DetailHost._builders['item'];
    final extra = <Widget>[for (final foot in (DetailHost._feet[branch.id]?.values ?? const <DetailFootBuilder>[])) ...foot(ctx)];
    // 같은 uid가 아니면 창 안의 상태(관점 탭 · 스위치)를 비운다 — 열쇠를 갈면 그 안이 새로 선다.
    // 칸 참조가 바뀌어도(같은 나라의 나라 상세 ↔ 승계표) 갈래가 바뀌면 새로 선다.
    final child = KeyedSubtree(
      key: ValueKey('$_uid|${branch.id}'),
      child: _DetailFootScope(
        extra: extra,
        child: _DetailBackScope(onBack: _history.isEmpty ? null : _back, child: build != null ? build(ctx) : _placeholder(ctx)),
      ),
    );
    if (!widget.framed) return _withWindows(child);
    return _DetailFrame(open: _open, onClose: _close, onDismissed: _dismissed, wrap: _withWindows, child: child);
  }

  /// 그 갈래를 맡은 위젯이 아직 등록되지 않았을 때 — 창은 서고, 무엇이 없는지 적는다.
  Widget _placeholder(DetailContext ctx) => DetailShell(
    onClose: ctx.close,
    badges: [DetailBadge(ctx.branch.id)],
    body: [DetailTitle(ctx.name.isEmpty ? ctx.uid : ctx.name), DetailNote('이 갈래의 상세 창이 아직 등록되지 않았습니다 — DetailHost.register(\'${ctx.branch.id}\', …)')],
    foot: [DetailSmallButton('닫기', onTap: ctx.close)],
  );
}

/// 창의 밖틀: 오른쪽 위 12 · 아래 16 · 폭 380 · 둥근 20 · `surface` 93% 유리 · 260ms에 오른쪽에서 미끄러져 들어온다.
class _DetailFrame extends StatefulWidget {
  const _DetailFrame({required this.child, required this.onClose, required this.onDismissed, this.wrap, required this.open});
  final bool open;
  final Widget child;
  final VoidCallback onClose, onDismissed;

  /// 밖틀 안쪽을 한 번 더 두르는 것(떠 있는 창의 자리 — [Positioned] 바로 밑이라 Stack의 자리 정보를 깨지 않는다).
  final Widget Function(Widget child)? wrap;

  @override
  State<_DetailFrame> createState() => _DetailFrameState();
}

class _DetailFrameState extends State<_DetailFrame> {
  @override
  void didUpdateWidget(_DetailFrame old) {
    super.didUpdateWidget(old);
    if (old.open == widget.open) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _enter.value = widget.open ? 1 : 0;
      if (!widget.open) _finished(AnimationStatus.dismissed);
    } else if (widget.open) {
      _enter.forward();
    } else {
      _enter.reverse();
    }
  }

  late final SurfaceMotion _enter = SurfaceMotion();
  Animation<double> get _curve => _enter;

  @override
  void initState() {
    super.initState();
    _enter.addStatusListener(_finished);
    if (widget.open) _enter.forward();
  }

  void _finished(AnimationStatus status) {
    if (status != AnimationStatus.dismissed || widget.open) return;
    // 줄이기 변경은 부모 build 중에도 도착한다. 자식 해제는 그 판이 끝난 뒤에 한다.
    scheduleMicrotask(() {
      if (mounted && !widget.open && _enter.isDismissed) widget.onDismissed();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _enter.value = widget.open ? 1 : 0;
      if (!widget.open) _finished(AnimationStatus.dismissed);
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Positioned(
    top: Ui.detailInset,
    right: Ui.detailInset,
    bottom: Ui.detailBottom,
    width: Ui.detailWidth,
    child: (widget.wrap ?? (w) => w)(
      IgnorePointer(
        ignoring: !widget.open,
        child: ExcludeSemantics(
          excluding: !widget.open,
          child: ExcludeFocus(
            excluding: !widget.open,
            child: Shortcuts(
              shortcuts: const {SingleActivator(LogicalKeyboardKey.escape): DismissIntent()},
              child: Actions(
                actions: {DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) => widget.onClose())},
                child: Focus(
                  autofocus: true,
                  child: AnimatedBuilder(
                    animation: _curve,
                    builder: (context, child) => Opacity(
                      opacity: _enter.opacity,
                      child: Transform.translate(offset: Offset(Ui.detailSlide * (1 - _curve.value), 0), child: child),
                    ),
                    // 오른쪽에 붙은 칸: paper 바탕 · 왼쪽 1px 선 하나.
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: Ui.detailGlass,
                        border: Border(left: BorderSide(color: Ui.line)),
                      ),
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// 갈래가 남의 창 아래 단추 줄에 더한 단추들([DetailHost.registerFoot]) — [DetailShell]이 읽어 닫기 앞에 세운다.
/// 머리의 뒤로 단추가 부를 것 — 거쳐 온 항목이 없으면 null(단추를 그리지 않는다).
class _DetailBackScope extends InheritedWidget {
  const _DetailBackScope({required this.onBack, required super.child});
  final VoidCallback? onBack;

  static VoidCallback? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_DetailBackScope>()?.onBack;

  @override
  bool updateShouldNotify(_DetailBackScope old) => old.onBack != onBack;
}

class _DetailFootScope extends InheritedWidget {
  const _DetailFootScope({required this.extra, required super.child});
  final List<Widget> extra;

  static List<Widget> of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_DetailFootScope>()?.extra ?? const [];

  @override
  bool updateShouldNotify(_DetailFootScope old) => old.extra.length != extra.length || !identical(old.extra, extra);
}
