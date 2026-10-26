import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../shell/look.dart';
import '../app_bus.dart';
import '../detail_shell.dart';
import 'kin_record.dart';

// ════════════════════════════════════════════════════════════════════════════════════════════
//  계보 창(승계표 · 세계표)의 머리 칩 · 조종 손잡이 — D1 확정 설계 `docs/설계-10건/1-2-계승과-가문-확정.md` 3-2 · 4-2 · 8-4.
//
//  ◆ 머리 칩 [KinHead]
//    승계표: `[● 구분] › [● 민족] › [● 국가 이름] · [꼬리표] …`(정권 기록의 `x_head`)
//    세계표: `[● 구분] › [● 민족] › [● 본관 성씨] › [● 이름] · [꼬리표] …`(가문 기록의 `x_head`)
//    · 칩 한 줄은 내보내기가 웹 `HT.polityHead` · `HT.houseHead`에서 `field`만 빼고 실어 준 `{role, text, title?, uid?, auto?}`.
//      앱은 칩 글을 짓지 않는다 — 실려 온 글 그대로, 차례 그대로.
//    · 연표 · 새 앱에서 칩은 **링크일 뿐**이다(편집은 웹 메이커만 — 확정 설계 0절 원칙 2). `uid`가 있는 칩만 누른다.
//    · 짐작한 칩(`auto`)은 불투명 .7 · 설명 풍선에 `title`('짐작 — 국성으로 삼은 나라에서').
//    · 꼬리표(`role` = `tag` · `tags`)는 `›`가 아니라 `·` 뒤에 늘어선다. 값이 없는 칩은 실려 오지 않는다(빈 칩 · '없음' 없음).
//
//  ◆ 조종 손잡이 [KinDriver] — D1-N4(측정 구간 `승계표` · `세계표`)와 검사가 창을 부리는 이음새(주인 D1-N2).
//    지금 떠 있는 창이 `bus.slot('kinDriver')`(app_glue의 `slotKinDriver`)에 제 손잡이를 싣고, 닫히면 비운다.
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 계보 창 하나를 밖에서 부리는 손잡이(측정 · 검사). 승계표([kind] `succession`)와 세계표(`family`)가 함께 쓴다.
///
/// 모든 값은 화면의 것이다 — 접힘은 보기 설정이라 자료를 바꾸지 않고, 창을 닫으면 손잡이도 사라진다.
abstract class KinDriver {
  /// `succession`(승계표) · `family`(세계표).
  String get kind;

  /// 뼈대 기록을 받아 작업자 isolate에서 풀고 첫 장면을 지을 준비가 되면 끝난다(받지 못했어도 끝난다 — 그때 [ready]는 거짓).
  Future<void> get loaded;

  /// 뼈대를 받아 풀었는가.
  bool get ready;

  /// 모두 펼치기 · 모두 접기(바닥 단추와 같은 일 — 움직임 포함).
  void expandAll();
  void collapseAll();

  /// 지금 보이는 마디의 안정 열쇠 — 승계표는 위 → 아래 줄(지도자 줄은 `c:<정권 uid>|leader:<i>`), 세계표는 세대마다 왼 → 오른.
  List<String> get visible;

  /// 그 마디를 접거나 편다(누른 것과 같다 — 그 줄 · 카드는 0px 움직인다). 그 마디가 없거나 펼 것이 없으면 거짓.
  bool toggle(String key);

  /// 끌어 옮기기와 같다(px — 승계표는 [dy]만 쓴다). 관성은 없다.
  void panBy(double dx, double dy);

  /// 그 사람까지 조상을 펴고 그 줄 · 카드로 데려간다(찾기 · `세계표에서 보기`와 같은 길). 없으면 거짓.
  Future<bool> reveal(String key);

  /// 지금 지은 줄 · 카드 위젯 수(그리는 수 합격선 — 확정 설계 6-2: 승계표 줄 ≤ 50 · 세계표 카드 ≤ 200).
  int get built;

  /// 지금 그린 선 수(세계표 ≤ 300 · 승계표 0).
  int get lines;

  /// 창 몸통(목록 · 나무가 그려지는 곳)의 전역 자리 — 합성 입력을 넣을 곳. 아직 그려지지 않았으면 null.
  Rect? get area;
}

/// 계보 창이 뼈대 기록 글을 푸는 길 — 기본은 작업자 isolate의 [decodeKin](UI isolate에서 JSON을 풀지 않는다 — 8-3).
/// 위젯 검사의 가짜 시계는 다른 isolate를 기다리지 못하므로 검사만 같은 isolate의 풀기로 갈아 끼운다.
Future<KinSkeleton> Function(String json, {String uid}) kinDecode = decodeKin;

/// [kinReveal]과 같은 일(그 사람이 든 덩어리를 차례로 받아 합침)을 [kinDecode]로 — 창이 쓰는 길.
Future<({KinSkeleton skel, int at})> kinRevealIn(KinSkeleton skel, int full, Future<String?> Function(String uid) fetch) async {
  var s = skel;
  for (var guard = 0; guard < 64; guard++) {
    final spot = s.locate(full);
    if (spot.at >= 0 || spot.stub < 0) return (skel: s, at: spot.at);
    final uid = s.stubs[spot.stub]!.key;
    final text = await fetch(uid);
    if (text == null || text.isEmpty) return (skel: s, at: -1);
    final merged = mergeKin(s, await kinDecode(text, uid: uid));
    if (identical(merged, s)) return (skel: s, at: -1);
    s = merged;
  }
  return (skel: s, at: -1);
}

/// 꼬투리 [t]의 덩어리를 받아 합친다(꼬투리 카드를 펼칠 때). 받지 못하면 [skel] 그대로.
Future<KinSkeleton> kinOpenStub(KinSkeleton skel, int t, Future<String?> Function(String uid) fetch) async {
  final stub = skel.stubs[t];
  if (stub == null) return skel;
  final text = await fetch(stub.key);
  if (text == null || text.isEmpty) return skel;
  try {
    return mergeKin(skel, await kinDecode(text, uid: stub.key));
  } catch (_) {
    return skel;
  }
}

/// 머리 칩 한 줄(`x_head`의 한 칸).
@immutable
class KinChip {
  const KinChip({required this.role, required this.text, this.title = '', this.uid = '', this.doc = '', this.auto = false});

  /// `track`(구분) · `people`(민족) · `surname`(본관 성씨) · `name`(국가 · 가문 · 파 이름) · `tag`(꼬리표) — 웹 `HT.polityHead` ·
  /// `HT.houseHead`가 붙인 이름 그대로(D1-E ④). 앱은 꼬리표인지만 가린다([tail]).
  final String role;

  /// [uid]는 항목 기록이 있는 칩(정권 · `house:<id>` · `surname:<id>`), [doc]은 문서 열쇠로 가리키는 칩(구분 · 민족 — 본문이 있을 때만).
  final String text, title, uid, doc;

  /// 짐작한 값(파일에 적지 않은 값) — 옅게.
  final bool auto;

  /// `·` 뒤의 꼬리표인가.
  bool get tail => role == 'tag' || role == 'tags';

  /// 누를 수 있는가(항목 기록이나 문서가 있다).
  bool get link => uid.isNotEmpty || doc.isNotEmpty;

  /// 기록의 칩 목록을 읽는다(깨진 칸 · 빈 글은 건너뛴다).
  static List<KinChip> read(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final one in raw)
        if (one is Map && '${one['text'] ?? ''}'.isNotEmpty)
          KinChip(
            role: '${one['role'] ?? ''}',
            text: '${one['text']}',
            title: '${one['title'] ?? ''}',
            uid: '${one['uid'] ?? ''}',
            doc: '${one['doc'] ?? ''}',
            auto: one['auto'] == 1 || one['auto'] == true,
          ),
    ];
  }

  /// 칩들을 화면 글 한 줄로(`가람 › 누리족 › 물빛 온씨 · 왕실`) — 웹 창 글과 견주는 검사 · 읽어 주기(Semantics)에 쓴다.
  static String line(List<KinChip> chips) {
    final main = [for (final c in chips) if (!c.tail) c.text];
    final tags = [for (final c in chips) if (c.tail) c.text];
    return [main.join(' › '), ...tags].where((s) => s.isNotEmpty).join(' · ');
  }
}

/// 칩을 누르면: 문서 열쇠가 있으면 문서 창(`slot('doc')`), 아니면 그 항목의 창(나라 상세 · 가문 창 · 성씨 창).
void kinChipOpen(AppBus bus, KinChip c) {
  if (c.doc.isNotEmpty) {
    bus.slot('doc').value = c.doc;
  } else if (c.uid.isNotEmpty) {
    bus.select(c.uid, kind: c.uid.startsWith('house:') ? 'house' : (c.uid.startsWith('surname:') ? 'surname' : ''));
  }
}

/// 머리 칩 줄 — 상세 창 머리 배지([DetailBadge])와 같은 꼴, 사이 기호 `›`는 가문 창 본가 길과 같은 것.
class KinHead extends StatelessWidget {
  const KinHead(this.chips, {super.key, this.onOpen, this.colorOf});

  final List<KinChip> chips;

  /// 칩을 눌렀을 때(그 칩의 `uid` · `doc`) — 없으면 칩은 누르지 않는 글이다. 보통 [kinChipOpen].
  final void Function(KinChip chip)? onOpen;

  /// 칩의 점 색(구분 = 트랙 색 · 국가 = 나라 색 …). 없으면 `--text-3`.
  final Color? Function(KinChip chip)? colorOf;

  static const _sep = TextStyle(fontSize: 13, height: 18 / 13, color: Ui.text3);

  @override
  Widget build(BuildContext context) {
    final main = [for (final c in chips) if (!c.tail) c];
    final tags = [for (final c in chips) if (c.tail) c];
    final out = <Widget>[];
    for (int i = 0; i < main.length; i++) {
      if (i > 0) out.add(const Padding(padding: EdgeInsets.only(top: 2), child: Text('›', style: _sep)));
      out.add(_chip(main[i]));
    }
    for (int i = 0; i < tags.length; i++) {
      if (out.isNotEmpty && i == 0) out.add(const Padding(padding: EdgeInsets.only(top: 2), child: Text('·', style: _sep)));
      out.add(_chip(tags[i]));
    }
    return Semantics(
      label: KinChip.line(chips),
      child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: out),
    );
  }

  Widget _chip(KinChip c) {
    final open = onOpen;
    Widget chip = DetailBadge(
      c.text,
      color: colorOf?.call(c),
      dot: !c.tail,
      onTap: open != null && c.link ? () => open(c) : null,
    );
    if (c.auto) chip = Opacity(opacity: .7, child: chip);
    if (c.title.isNotEmpty) chip = Tooltip(message: c.title, waitDuration: const Duration(milliseconds: 400), child: chip);
    return chip;
  }
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  두 창이 함께 쓰는 색 · 선 무늬 · 글 — 목업 판(`.claude/research/10건/D1/d1-ui.mjs`의 D1_CSS)의 값 그대로.
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 계보 창의 색 · 치수.
abstract final class KinUi {
  /// 카드 · 선 위 글의 종이빛(`--paper`)과 글자색(`--paper-ink`).
  static const paper = Ui.paper;

  /// 선 · 무늬의 색 — `color-mix(in srgb, 나라색 40%, --text-2)`.
  static Color ink(Color c) => Color.lerp(const Color(0xff666666), c, .40)!; // --text-2(ink60)를 흰 바탕에 얹은 불투명한 값과 섞는다 — 투명한 색끼리는 섞은 값이 css와 어긋난다

  /// 세계표 선 — `color-mix(in srgb, --text-2 70%, transparent)`.
  static final treeInk = Ui.text2.withValues(alpha: Ui.text2.a * .70);

  /// `color-mix(in srgb, c p, --surface)`.
  static Color tint(Color c, double p, [Color base = Ui.surface]) => Color.lerp(base, c, p)!;

  /// `color-mix(in srgb, c p, transparent)`.
  static Color fade(Color c, double p) => c.withValues(alpha: c.a * p);

  /// 선 굵기 2px · 양자 파선(5 · 3.5) · 여러 대 건너뜀 긴 파선(12 · 5) · 미상 점선(둥근 점 · 4.2 간격).
  static const stroke = 2.0;
  static const adoptDash = [5.0, 3.5], skipDash = [12.0, 5.0];
  static const dotGap = 4.2;
}

/// 해 글 — 카드 · 막대 축의 짧은 꼴(`1368` · `기원전 57`). 목업 `yr()`과 같다.
String kinYear(int year) => year < 0 ? '기원전 ${-year}' : '$year';

/// 승계표 이음매 · 범례의 선 갈래(웹 `HT.accessionLine` — 확정 설계 3-3).
/// 0 비움(옅은 1px · 글 없음) · 1 찬탈 · 정변(끊긴 선 + 빗금) · 2 관계 · 방식 미상(점선) · 3 선양(겹선) · 4 복위(실선 + 고리) · 5 세습 · 추대 …(실선).
abstract final class SeamLine {
  static const blank = 0, usurp = 1, unknown = 2, abdicate = 3, restore = 4, solid = 5;

  /// 기록에 `line`이 없을 때(옛 기록) 관계 · 방식에서 셈한다 — 웹과 같은 차례(첫째로 맞는 것).
  static int of(Map<String, dynamic>? a) {
    if (a == null) return blank;
    final line = a['line'];
    if (line is num && line >= 0 && line <= 5) return line.toInt();
    bool on(String k) => a[k] == 1 || a[k] == true;
    final how = '${a['howId'] ?? ''}';
    if (const {'usurpation', 'coup', 'conquest'}.contains(how)) return usurp;
    if (on('kinUnknown') || on('howUnknown')) return unknown;
    if (how == 'abdication') return abdicate;
    if (how == 'restoration') return restore;
    final kin = '${a['kin'] ?? ''}', h = '${a['how'] ?? ''}';
    return kin.isEmpty && h.isEmpty && how.isEmpty ? blank : solid;
  }
}

/// 이음매 선 한 토막을 그린다 — 세로([vertical]) 또는 가로(범례). [c]는 가로세로 가운데, [a] · [b]는 길이 방향 처음 · 끝.
void paintSeamLine(Canvas canvas, int kind, Color ink, {required double c, required double a, required double b, bool vertical = true}) {
  final p = Paint()
    ..color = ink
    ..strokeWidth = KinUi.stroke
    ..style = PaintingStyle.stroke;
  Offset at(double along, double across) => vertical ? Offset(across, along) : Offset(along, across);
  void seg(double s, double e, [Paint? q]) => canvas.drawLine(at(s, c), at(e, c), q ?? p);
  final len = b - a;
  switch (kind) {
    case SeamLine.blank:
      seg(a, b, Paint()
        ..color = KinUi.fade(ink, .45)
        ..strokeWidth = 1);
    case SeamLine.usurp:
      final g = math.max(5.0, (len * .26).roundToDouble()), m = a + len / 2;
      seg(a, m - g / 2);
      seg(m + g / 2, b);
      // 빗금: 아래 왼쪽 → 위 오른쪽(목업 `M c−4 m+3 → c+4 m−3`).
      canvas.drawLine(vertical ? Offset(c - 4, m + 3) : Offset(m - 3, c + 4), vertical ? Offset(c + 4, m - 3) : Offset(m + 3, c - 4), p);
    case SeamLine.unknown:
      final dot = Paint()
        ..color = ink
        ..style = PaintingStyle.fill;
      for (var t = a + 1.5; t <= b - 1 + .01; t += KinUi.dotGap) {
        canvas.drawCircle(at(t, c), 1, dot);
      }
    case SeamLine.abdicate:
      canvas.drawLine(at(a, c - 2.5), at(b, c - 2.5), p);
      canvas.drawLine(at(a, c + 2.5), at(b, c + 2.5), p);
    default:
      seg(a, b);
  }
}

/// 파선을 긋는다(`stroke-dasharray`) — [path]를 [dash] 무늬로 잘라 그린다.
void paintDashed(Canvas canvas, Path path, Paint paint, List<double> dash) {
  for (final metric in path.computeMetrics()) {
    var d = 0.0, on = true, k = 0;
    while (d < metric.length) {
      final step = dash[k % dash.length];
      final e = math.min(d + step, metric.length);
      if (on) canvas.drawPath(metric.extractPath(d, e), paint);
      d = e;
      on = !on;
      k++;
    }
  }
}

/// 범례 한 칸의 그림(22 × 10) — 승계표 · 세계표가 함께 쓴다.
class KinLegendIcon extends StatelessWidget {
  const KinLegendIcon(this.kind, {super.key, required this.ink, this.width = 22});

  /// `seam:<0~5>` · `res`(복위 견본) · `adopt`(양자 파선) · `skip`(긴 파선) · `ring`(빈 고리) · `ruler:<색>` · `paper`.
  final String kind;
  final Color ink;
  final double width;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size(width, 12), painter: _LegendPainter(kind, ink));
}

class _LegendPainter extends CustomPainter {
  _LegendPainter(this.kind, this.ink);
  final String kind;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.height / 2;
    final p = Paint()
      ..color = ink
      ..strokeWidth = KinUi.stroke
      ..style = PaintingStyle.stroke;
    if (kind.startsWith('seam:')) {
      paintSeamLine(canvas, int.tryParse(kind.substring(5)) ?? 5, ink, c: c, a: 0, b: size.width, vertical: false);
    } else if (kind == 'res') {
      final w = size.width;
      final path = Path()
        ..moveTo(2, c + 4)
        ..lineTo(2, c - 1)
        ..quadraticBezierTo(2, c - 4, 5, c - 4)
        ..lineTo(w - 5, c - 4)
        ..quadraticBezierTo(w - 2, c - 4, w - 2, c - 1)
        ..lineTo(w - 2, c + 4);
      canvas.drawPath(path, p);
      // 화살촉은 내려가는 끝(다시 오른 쪽)에 — 승계표의 복위 고리와 같은 쪽(건의 8의 5번 A).
      canvas.drawPath(
        Path()
          ..moveTo(w - 5, c + 1)
          ..lineTo(w - 2, c + 4)
          ..lineTo(w + 1, c + 1),
        p,
      );
    } else if (kind == 'adopt' || kind == 'skip') {
      paintDashed(canvas, Path()
        ..moveTo(0, c)
        ..lineTo(size.width, c), p, kind == 'adopt' ? KinUi.adoptDash : KinUi.skipDash);
    } else if (kind == 'ring') {
      // 이름 미상 = 세계표와 같은 원(종이빛 채움 · 테 2px = 선과 같은 빛 — 건의 8의 4-다).
      canvas.drawCircle(Offset(5.5, c), 5.5, Paint()..color = Ui.surface);
      canvas.drawCircle(Offset(5.5, c), 4.5, p);
    } else if (kind.startsWith('ruler:') || kind == 'paper') {
      final col = kind == 'paper' ? null : detailColor(kind.substring(6));
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, 18, 12), const Radius.circular(4));
      canvas.drawRRect(r, Paint()..color = col == null ? KinUi.paper : KinUi.tint(col, .34));
      canvas.drawRRect(r.deflate(.5), Paint()
        ..color = col == null ? Ui.lineStrong : KinUi.fade(col, .60)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1);
    }
  }

  @override
  bool shouldRepaint(_LegendPainter old) => old.kind != kind || old.ink != ink;
}

/// 범례 줄(`.d1-legend`) — 둥근 12 · 안쪽 7/12 · `--surface-2` 70% · 12px `--text-2` · 틈 4 × 14.
class KinLegend extends StatelessWidget {
  const KinLegend(this.items, {super.key, required this.ink});

  /// (그림 갈래, 글) — 그림이 빈 글이면 글만.
  final List<(String, String)> items;
  final Color ink;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(color: KinUi.fade(Ui.surface2, .70), borderRadius: BorderRadius.circular(12)),
    child: Wrap(
      spacing: 14,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (kind, text) in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (kind.isNotEmpty) ...[KinLegendIcon(kind, ink: ink, width: kind == 'skip' ? 30 : (kind == 'ring' ? 11 : (kind.startsWith('ruler') || kind == 'paper' ? 18 : 22))), const SizedBox(width: 6)],
              Text(text, style: const TextStyle(fontSize: 12, height: 1.5, color: Ui.text2)),
            ],
          ),
      ],
    ),
  );
}

/// 안정 열쇠 → 그 사람의 창을 여는 자리 — `f:<인물 uid>`는 인물 창, `c:<정권 uid>|leader:3`은 그 칸 창. 이름뿐인 사람(`n:`)은 null.
({String uid, String? cell})? kinPersonTarget(String key) {
  if (key.startsWith('f:')) return (uid: key.substring(2), cell: null);
  if (key.startsWith('c:')) {
    final bar = key.lastIndexOf('|');
    if (bar > 2) return (uid: key.substring(2, bar), cell: key.substring(bar + 1));
  }
  return null;
}
