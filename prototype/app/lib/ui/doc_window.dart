import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../motion.dart';
import '../shell/line_icon.dart' show DockIconButton;
import '../shell/look.dart';
import '../shell/motion_widgets.dart';
import '../shell/parts.dart';
import 'app_bus.dart';
import 'detail_shell.dart';
import 'shell_keys.dart';

// ════════════════════════════════════════════════════════════════════════════════════════════
//  문서(위키) 창과 하위 문서 칩 — 지금 연표의 `js/viewer.js` 2691~3009 · `css/viewer.css` 264~292 · 407~423
//
//  연표 위를 통째로 덮는 창 하나다(가장자리 12 · 아래 16 · 둥근 22 · `--surface` 바탕).
//  혼자 서는 부품이라 [AppBus]만 받는다:
//    bus.slot('doc')       = 문서 열쇠(글) — 이것이 실리면 열리고, null이면 닫힌다.
//                            열쇠는 항목 uid · `track:<id>` · `people:<id>` · `category:<id>` · `house:<id>` ·
//                            `cell:<정권uid>:<목록>:<이름>@<시작>`, 그리고 그 뒤에 `//하위 문서`가 이어진다.
//    bus.slot('command')   = [Cmd.wiki](고른 항목의 문서 · `W`) · [Cmd.trackWiki](트랙 문서) · [Cmd.close](Esc)
//    bus.slot('notice')    ← 문서를 찾지 못했을 때의 안내 한 줄
//    bus.slot('tracks')    = 트랙 표 — [Cmd.trackWiki]의 번호를 글자 id로 되돌릴 때만 본다.
//    bus.ask({'op':'entity','uid':'doc:<열쇠>'}) — 문서 기록(계약 6-9 나)
//    bus.select · bus.goTo — `🎯 연표에서`
//
//  ── 앱에 끼우는 법 ───────────────────────────────────────────────────────────────────────────
//    Stack(children: [ …앱 틀…, DocWindow(bus: bus, padding: EdgeInsets.fromLTRB(12, Ui.top + 12, 12, 16)) ])
//    닫혀 있으면 아무 자리도 차지하지 않는다(`SizedBox.shrink`). 열려 있으면 `Positioned.fill`로 그 Stack을 덮는다.
//    `bus.slot('docSide')`가 참이면(나란히 — 앱 틀이 기억에서 채움) 덮지 않고 [DocWindow.top] 아래 오른쪽에 붙은 칸(폭 760)으로 서서
//    왼쪽 연표가 그대로 눌린다. 열쇠 [docFrontKey]로 열면 본문 대신 문서 대문(갈래별 카드 · `{"op":"doc_list"}`)이다.
//
//  ── 상세 창에 다는 하위 문서 칩 ───────────────────────────────────────────────────────────────
//    DetailBox 하나로 서는 부품이다. 상세 위젯의 몸통 맨 아래(명세 06의 2-3절 ㈎ 23번)에 넣는다:
//      DocChips(bus: ctx.bus, uid: ctx.uid, json: ctx.json)
//    항목 기록의 `x_docs`(내보내기가 미리 푼 값)를 읽는다. 새 내보내기로 만든 기록에서는 `x_docs`가 없는 것이
//    곧 '하위 문서 없음'이라 되묻지 않고, 옛 기록일 때만 `doc:<uid>`의 `subs`를 하나짜리 `entities`로 묻는다.
//    하위 문서가 없으면 아무것도 그리지 않는다.
//
//  ── 본문 문법 ────────────────────────────────────────────────────────────────────────────────
//    [parseDocBody]가 나무위키 문법(`js/wiki.js`의 `HT.namu.render`)을 풀어 [DocBody]로 준다. 옮긴 것:
//    제목 `== … ==`(2~6단계 · 목차 번호) · 문단 · 목록(`*` · `1.` · 들여쓰기) · 인용 `>` · 가로줄 `----` ·
//    표 `|| … ||`(`<-n>` · `<bgcolor=…>` · `<(> <:> <)>`) · 접기 `{{{#!folding}}}` · 상자 `{{{#!wiki}}}` ·
//    여러 줄 코드 · `'''굵게'''` · `''기울임''` · `~~취소~~` · `__밑줄__` · `^^위^^` · `,,아래,,` ·
//    `{{{+n 크게}}}` · `{{{-n 작게}}}` · `{{{#색 글자}}}` · `{{{코드}}}` · `[* 각주]` · `[목차]` · `[각주]` ·
//    `[br]` · `[[안쪽 고리]]` · `[[분류:…]]` · `[[https://…|바깥 고리]]`.
//    안쪽 고리의 목적지는 **내보내기가 미리 푼다**(기록의 `links`) — 새 엔진은 모델을 올리지 않아
//    창이 이름으로 항목을 찾아 나설 수 없다. 표에 없는 이름은 '연표에 없는 항목'(붉은 파선)이다.
//
//  ── 문서 그림(형식 3 images — 10건 D3 결정 9 B · 지금 연표 js/wiki.js `namu.figureHTML` · css/viewer.css `.wk-fig`) ──
//    `[[파일:이름]]` · `|align=center` · `|align=left` · `|width=N(px · %)` → [DocFigure]. 그림의 열쇠 · 크기 · 설명은 내보내기가
//    미리 푼다(기록의 `images[이름]` — docs.mjs), 바이트는 열 때 자료 처리부에서 읽는다([docBlob] · 없으면 `{"op":"blob"}`).
//    그림 고리가 든 줄은 그 앞에서 문단을 끊고 그림을 놓은 뒤 나머지 글을 이어 쓴다(지금 연표와 같다).
//    기본은 **오른쪽에 띄우고**(폭 340 · 원본이 작으면 원본 · 글에 280 남김) 문단 · 목록의 글이 왼쪽으로 흐르다가
//    그림 아래로 내려간 줄부터 본문 폭으로 넓어진다 — 줄마다 폭을 따로 셈한다([DocArticleState]의 띄운 자리: 먼저 그림 옆 폭으로
//    그리고, 그린 뒤 줄 자리를 재어 그림 아래로 내려간 첫 줄에서 글을 나눠 다시 그린다). 제목 · 가로줄 · 표 · 인용 · 상자 · 접기 ·
//    코드 · 목차 · 각주는 그림 아래에서 시작한다. 본문이 600보다 좁거나 상자 · 인용 · 접기 안이면 띄우지 않고 본문 폭 가운데(결정 9 A).
//    그림을 누르면 화면 전체로 크게 본다(따스한 어두운 막 · Esc는 크게 보기만 닫는다).
// ════════════════════════════════════════════════════════════════════════════════════════════

/// [AppBus.slot]에 쓰는 이름 — 문서 열쇠 하나가 실린다(`app_glue.dart`의 `slotDoc`과 같은 이름).
const docSlot = 'doc';

/// [AppBus.slot]에 쓰는 이름 — 문서 창을 연표 옆 칸으로 세우는가(참 = 나란히: 연표 오른쪽 · 상세 칸 자리에 붙은 칸 ·
/// 그 밖 = 넓게: 연표를 덮는 창). 앱 틀이 기억(`parts['doc']`)에서 채우고, 창 머리의 기호 단추가 뒤집는다.
/// (2026-10-16 감독 "문서 기능과 함께 볼 수 있는 기능 부활" → 갈래 '가 · 상세 칸 자리에')
const docSideSlot = 'docSide';

/// 문서 대문의 열쇠 — 어느 문서 열쇠와도 겹치지 않는다(문서 열쇠는 `@`로 시작하지 않는다). 이 열쇠로 열면 문서 창이
/// 본문 대신 서재의 문서를 갈래별 카드로 한 번에 늘어놓는다(2026-10-16 감독 "문서 한번에 나란히 볼 수 있게 하는 대문").
const docFrontKey = '@대문';

/// 바깥 고리를 여는 길 — 앱 틀이 한 번 채워 두면 문서 창이 그것으로 연다(열었으면 참).
/// 이 시제품의 `pubspec.yaml`에는 바깥 주소를 여는 패키지(`url_launcher`)가 없어 비워 두었고,
/// 비어 있으면 창이 주소를 복사해 안내 한 줄로 알린다.
/// ```dart
/// docOpenUrl = (url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
/// ```
Future<bool> Function(String url)? docOpenUrl;

/// 문서 그림 바이트를 읽는 길 — 앱 틀이 채워 두면(`docBlob = engine.blob;`) 자료 처리부의 `archive_blob`으로 바이트 그대로 받는다.
/// 비어 있으면 창이 `bus.ask({'op':'blob','key':…})`의 base64 답을 푼다(JSON에 그림이 실려 조금 느릴 뿐 답은 같다).
Future<Uint8List?> Function(String key)? docBlob;

/// 문서 창에만 쓰는 색 · 치수. 앱 틀과 함께 쓰는 값은 [Ui]에 있다.
abstract final class DocUi {
  /// css의 `--danger`(연표에 없는 항목) · `--ok`(바깥 고리).
  static const danger = Ui.ink, ok = Ui.ink;

  /// 창: 가장자리 12 · 아래 16 · 둥근 12 · `--surface` 바탕 · ink20 선(`.wiki-pane`).
  static const pane = EdgeInsets.fromLTRB(12, 12, 12, 16), radius = Ui.menuRadius;

  /// 머리 10/14 → 14/18(`.wiki-head`) · 하위 문서 줄 10/18 · 몸통 22/28 · 목차와 본문 사이 28.
  static const headPad = EdgeInsets.symmetric(horizontal: 18, vertical: 14);
  static const subsPad = EdgeInsets.symmetric(horizontal: 18, vertical: 10);
  static const bodyPad = EdgeInsets.symmetric(horizontal: 28, vertical: 22), bodyGap = 28.0;

  /// 목차 칸 200 · 본문 780까지 · 이보다 좁으면 목차가 본문 위로(css의 860px 문턱).
  static const tocWidth = 200.0, articleWidth = 780.0, narrow = 860.0;

  /// 본문 — 읽는 글이라 명조 15px · 줄 높이 24(`.wiki-article` · `.wk`).
  static const font = 15.0, lineHeight = 24 / 15;

  /// 하위 문서 줄의 바탕 — css의 `color-mix(in srgb, var(--surface-2) 50%, var(--surface))`.
  static const subsBack = Ui.paper;

  /// 인용의 왼쪽 선 · 고리의 밑줄 — `color-mix(in srgb, var(--accent) 45%|35%, transparent)`.
  static const quoteBar = Color(0x73000000), linkLine = Color(0x59000000);

  /// 아직 문서가 없는 곳을 가리키는 고리 — `color-mix(in srgb, var(--accent) 70%, var(--text-3))`.
  static const linkEmpty = Color(0xe0000000);

  /// 나란히 볼 때: 문서 칸의 폭 760(목차는 본문 위로) · 그 왼쪽에 연표가 적어도 480은 남아야 한다(모자라면 넓게 — 덮는다).
  static const sideWidth = 760.0, sideMinTimeline = 480.0;

  /// 대문의 카드: 적어도 폭 300(그 수만큼 한 줄에 — 나란히 칸이면 둘) · 높이 144로 고르게 · 카드 사이 12 · 갈래 사이 28.
  static const frontCardMin = 300.0, frontCardHeight = 144.0, frontGap = 12.0, frontSectionGap = 28.0;

  /// 창이 뜨는 움직임(`docs/움직임-원칙.md`의 `--t-in` 200ms) — 오른쪽에서 12px 미끄러지며 떠오른다.
  static const enter = Duration(milliseconds: 200), slide = 12.0;

  /// 문서 그림(css `.wk-fig`): 오른쪽에 띄울 때 폭 340 · 글과의 틈 24 · 글에 남기는 폭 280 · 본문이 600보다 좁으면 띄우지 않음.
  static const figureWidth = 340.0, figureGap = 24.0, figureMinText = 280.0, figureNarrow = 600.0;

  /// 띄운 그림의 위 · 아래 바깥 여백(6 · 12) · 띄우지 않은 그림의 위 · 아래(8 · 16) · 설명과의 틈 6 · 설명 12.5px/1.5 · 둥근 12.
  static const figureTop = 6.0, figureBottom = 12.0, blockTop = 8.0, blockBottom = 16.0, captionGap = 6.0, captionSize = 12.5, figureRadius = 12.0;

  /// 크게 보기의 막과 설명 글 — css `.wk-zoom`과 같은 B 모양의 paper · ink60.
  static const zoomBack = Ui.paper, zoomText = Ui.ink60;

  /// 크게 보기가 나타나고(`--t-in` 200ms) 사라지는(`--t-out` 160ms) 시간.
  static const zoomIn = Duration(milliseconds: 200), zoomOut = Duration(milliseconds: 160);
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  1. 값 — 문서 기록 하나(계약 6-9 나)
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 본문 안의 `[[고리]]` 하나. [key]가 비어 있으면 연표에 없는 이름이다(붉은 파선).
@immutable
class DocLink {
  const DocLink(this.name, {this.key = '', this.title = '', this.empty = false, this.url = ''});

  /// 본문에 적힌 이름(`은륜 제국` · `/생활` · `인물:은결 베루`).
  final String name;

  /// 목적지 문서 열쇠.
  final String key, title;

  /// 항목은 있으나 아직 문서가 없다(점선 고리).
  final bool empty;

  /// 바깥 고리면 그 주소(그 자리에서는 [key]가 비어 있다).
  final String url;

  bool get missing => key.isEmpty && url.isEmpty;
}

/// 문서 기록의 그림 한 장 — 내보내기(docs.mjs)가 본문의 `[[파일:이름]]`을 그림 사전에서 미리 푼 값(`images[이름]`).
@immutable
class DocImageRef {
  const DocImageRef({required this.key, this.mime = '', this.width = 0, this.height = 0, this.caption = '', this.alt = '', this.credit = '', this.bytes = 0});

  /// 자료 처리부의 그림 열쇠(`img:<DLC id>/<그림 id>`) · 종류(image/webp …) · 설명 · 대체 글 · 출처.
  final String key, mime, caption, alt, credit;

  /// 원본 그림의 픽셀 크기(모르면 0 — 그때는 16:9로 자리를 잡는다) · 바이트 수.
  final int width, height, bytes;

  /// 그림 아래 한 줄 — 설명 · 출처(지금 연표의 `figcaption`).
  String get captionLine => [caption, credit].where((s) => s.isNotEmpty).join(' · ');

  /// 높이 ÷ 폭.
  double get ratio => width > 0 && height > 0 ? height / width : 9 / 16;

  static Map<String, DocImageRef> parse(Object? v) {
    if (v is! Map) return const {};
    final out = <String, DocImageRef>{};
    v.forEach((name, one) {
      if (one is! Map || _str(one['key']).isEmpty) return;
      int n(Object? x) => x is num ? x.toInt() : 0;
      out['$name'] = DocImageRef(
        key: _str(one['key']),
        mime: _str(one['mime']),
        width: n(one['w']),
        height: n(one['h']),
        caption: _str(one['caption']),
        alt: _str(one['alt']),
        credit: _str(one['credit']),
        bytes: n(one['bytes']),
      );
    });
    return out;
  }
}

/// 빵 부스러기 한 칸 · 하위 문서 칩 하나.
@immutable
class DocCrumb {
  const DocCrumb(this.key, this.label);
  final String key, label;
}

/// 문서 기록. `{"op":"entity","uid":"doc:<열쇠>"}`의 답을 푼 것이다.
@immutable
class DocRecord {
  const DocRecord({
    required this.key,
    required this.title,
    this.meta = '',
    this.base = '',
    this.sub = '',
    this.body = '',
    this.pack = '',
    this.desc = '',
    this.uid = '',
    this.ref = '',
    this.span,
    this.subs = const [],
    this.crumbs = const [],
    this.last = '',
    this.links = const {},
    this.back = const [],
    this.images = const {},
  });

  final String key, title, meta, base, sub, body, pack, desc;

  /// 연표에서 고를 항목(`🎯 연표에서`). 칸 문서면 그 정권의 uid이고 [ref]가 칸 참조다.
  final String uid, ref;

  /// 그 항목이 차지하는 기간(분). 없으면 연표를 옮기지 않는다(가문 · 민족 · 트랙 · 분류).
  final List<double>? span;

  final List<DocCrumb> subs, crumbs;

  /// 빵 부스러기 끝에 굵게 적는 지금 문서의 이름.
  final String last;

  final Map<String, DocLink> links;
  final List<DocCrumb> back;

  /// 본문의 그림 이름 → 그림(문서 그림 — 형식 3). 표에 없는 이름은 '그림 없음' 자리다.
  final Map<String, DocImageRef> images;

  bool get empty => body.trim().isEmpty;

  /// 답 `{uid, kind, json}`을 푼다. 문서 기록이 아니면 null.
  static DocRecord? fromAnswer(Map<String, dynamic> answer) {
    final raw = answer['json'];
    Map<String, dynamic> j;
    if (raw is Map) {
      j = raw.cast<String, dynamic>();
    } else if (raw is String && raw.isNotEmpty) {
      try {
        final v = jsonDecode(raw);
        if (v is! Map) return null;
        j = v.cast<String, dynamic>();
      } catch (_) {
        return null;
      }
    } else {
      return null;
    }
    final key = _str(j['key']);
    if (key.isEmpty) return null;
    return DocRecord(
      key: key,
      title: _str(j['title']),
      meta: _str(j['meta']),
      base: _str(j['base']),
      sub: _str(j['sub']),
      body: _str(j['body']),
      pack: _str(j['pack']),
      desc: _str(j['desc']),
      uid: _str(j['uid']),
      ref: _str(j['ref']),
      span: _span(j['span']),
      subs: _crumbs(j['subs'], 'key', 'sub'),
      crumbs: _crumbs(j['crumbs'], 'key', 'label'),
      last: _str(j['last']),
      links: _links(j['links']),
      back: _crumbs(j['back'], 'key', 'title'),
      images: DocImageRef.parse(j['images']),
    );
  }

  static List<double>? _span(Object? v) {
    if (v is! List || v.length < 2) return null;
    final lo = v[0], hi = v[1];
    if (lo is! num || hi is! num) return null;
    return [lo.toDouble(), hi.toDouble()];
  }

  static List<DocCrumb> _crumbs(Object? v, String a, String b) {
    if (v is! List) return const [];
    return [
      for (final one in v)
        if (one is Map && _str(one[a]).isNotEmpty) DocCrumb(_str(one[a]), _str(one[b])),
    ];
  }

  static Map<String, DocLink> _links(Object? v) {
    if (v is! Map) return const {};
    final out = <String, DocLink>{};
    v.forEach((name, one) {
      if (one is! Map) return;
      out['$name'] = DocLink('$name', key: _str(one['key']), title: _str(one['title']), empty: one['empty'] == 1 || one['empty'] == true);
    });
    return out;
  }
}

String _str(Object? v) => v == null ? '' : '$v';

// ────────────────────────────────────────────────────────────────────────────────────────────
//  2. 문법 풀기 — 나무위키 문법(js/wiki.js)의 자주 쓰는 부분
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 글 한 조각과 그 꾸밈.
@immutable
class DocSpan {
  const DocSpan(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.strike = false,
    this.underline = false,
    this.code = false,
    this.sup = false,
    this.low = false,
    this.scale = 1,
    this.color,
    this.link,
    this.footnote = 0,
    this.lineBreak = false,
  });

  final String text;
  final bool bold, italic, strike, underline, code, sup, low, lineBreak;

  /// `{{{+2 …}}}` · `{{{-1 …}}}`의 글자 크기 배수.
  final double scale;
  final Color? color;
  final DocLink? link;

  /// 각주 번호(0이면 각주가 아니다).
  final int footnote;

  DocSpan _with(String text) =>
      DocSpan(text, bold: bold, italic: italic, strike: strike, underline: underline, code: code, sup: sup, low: low, scale: scale, color: color, link: link);
}

/// 본문의 블록 하나.
abstract class DocNode {
  const DocNode();
}

class DocHeading extends DocNode {
  DocHeading(this.level, this.spans, this.id, this.plain);
  final int level;
  final List<DocSpan> spans;
  final String id, plain;

  /// 목차 번호(`1.2`)와 목차에서의 깊이(1부터) — [parseDocBody]가 끝에 매긴다.
  String number = '';
  int depth = 1;
}

class DocParagraph extends DocNode {
  const DocParagraph(this.spans);
  final List<DocSpan> spans;
}

class DocListItem {
  const DocListItem(this.depth, this.marker, this.spans);

  /// 0부터의 깊이.
  final int depth;

  /// 앞에 찍는 글(`•` · `1.` · `가.`).
  final String marker;
  final List<DocSpan> spans;
}

class DocList extends DocNode {
  const DocList(this.items);
  final List<DocListItem> items;
}

class DocQuote extends DocNode {
  const DocQuote(this.body);
  final List<DocNode> body;
}

class DocRule extends DocNode {
  const DocRule();
}

class DocCell {
  const DocCell(this.spans, {this.colspan = 1, this.rowspan = 1, this.background, this.align});
  final List<DocSpan> spans;
  final int colspan, rowspan;
  final Color? background;
  final TextAlign? align;
}

/// 격자에 자리를 잡은 칸 하나 — 몇째 줄 · 몇째 칸에서 가로 [colspan] · 세로 [rowspan]만큼을 차지한다.
@immutable
class DocPlacedCell {
  const DocPlacedCell(this.cell, this.row, this.column, this.colspan, this.rowspan);
  final DocCell cell;
  final int row, column, colspan, rowspan;

  /// 오른쪽 · 아래 테두리를 그리는가(표의 바깥 테두리는 표 전체가 두르므로 안쪽만 긋는다).
  bool rightEdge(int columns) => column + colspan >= columns;
  bool bottomEdge(int rows) => row + rowspan >= rows;
}

/// 표 하나를 칸 합치기(`<-n>`) · 세로 칸 합치기(`<|n>`)까지 풀어 놓은 격자.
@immutable
class DocGrid {
  const DocGrid(this.cells, this.columns, this.rows);
  final List<DocPlacedCell> cells;
  final int columns, rows;
}

class DocTable extends DocNode {
  DocTable(this.rows);
  final List<List<DocCell>> rows;

  /// 칸 합치기가 없고 줄마다 칸 수가 같으면 글에 맞춰 칸 폭을 잡을 수 있다.
  bool get plain {
    if (rows.isEmpty) return false;
    final n = rows.first.length;
    for (final row in rows) {
      if (row.length != n) return false;
      for (final cell in row) {
        if (cell.colspan != 1 || cell.rowspan != 1) return false;
      }
    }
    return true;
  }

  DocGrid? _grid;

  /// 격자 — 브라우저의 표 자리 잡기와 같다: 줄마다 왼쪽부터 채우되, 위에서 내려온 세로 합친 칸이 잡아 둔 자리는 건너뛴다.
  DocGrid get grid => _grid ??= _makeGrid();

  DocGrid _makeGrid() {
    final taken = <(int, int)>{}; // 이미 잡힌 (줄, 칸)
    final out = <DocPlacedCell>[];
    int columns = 0, lines = rows.length;
    for (int r = 0; r < rows.length; r++) {
      int c = 0;
      for (final cell in rows[r]) {
        while (taken.contains((r, c))) {
          c++;
        }
        final colspan = cell.colspan.clamp(1, 64), rowspan = cell.rowspan.clamp(1, 64);
        for (int i = 0; i < rowspan; i++) {
          for (int j = 0; j < colspan; j++) {
            taken.add((r + i, c + j));
          }
        }
        out.add(DocPlacedCell(cell, r, c, colspan, rowspan));
        columns = math.max(columns, c + colspan);
        lines = math.max(lines, r + rowspan);
        c += colspan;
      }
    }
    // 마지막 줄에서 아래로 뻗은 세로 합치기는 표 밖으로 나가지 않게 줄인다.
    if (lines > rows.length) {
      lines = rows.length;
      for (int i = 0; i < out.length; i++) {
        final p = out[i];
        if (p.row + p.rowspan > lines) out[i] = DocPlacedCell(p.cell, p.row, p.column, p.colspan, math.max(1, lines - p.row));
      }
    }
    return DocGrid(out, math.max(columns, 1), math.max(lines, 1));
  }
}

class DocFold extends DocNode {
  const DocFold(this.summary, this.body);
  final List<DocSpan> summary;
  final List<DocNode> body;
}

/// `{{{#!wiki}}}` 상자와 `{{{+2 …}}}` 여러 줄 묶음.
class DocGroup extends DocNode {
  const DocGroup(this.body, {this.boxed = false, this.scale = 1});
  final List<DocNode> body;
  final bool boxed;
  final double scale;
}

class DocPre extends DocNode {
  const DocPre(this.text);
  final String text;
}

/// 문서 그림 하나(`[[파일:이름|width=…|align=…]]`). [image]가 없으면 '그림 없음' 자리다.
class DocFigure extends DocNode {
  const DocFigure(this.name, {this.image, this.align = '', this.widthPx = 0, this.widthPct = 0});

  /// 본문에 적힌 이름(id여도 된다).
  final String name;
  final DocImageRef? image;

  /// `left` · `center` · `right` · 빈 글(= right — 오른쪽에 띄움).
  final String align;

  /// `width=240` → 240 · `width=60%` → 60(본문 폭의 백분율). 없으면 0.
  final double widthPx, widthPct;

  /// 오른쪽에 띄우는 그림인가(본문이 넓을 때).
  bool get floats => image != null && (align.isEmpty || align == 'right');
}

/// `[목차]`가 놓인 자리.
class DocTocMark extends DocNode {
  const DocTocMark();
}

/// `[각주]`가 놓인 자리.
class DocFootMark extends DocNode {
  const DocFootMark();
}

/// 각주 하나.
class DocFootnote {
  DocFootnote(this.id, this.label, this.spans);
  final int id;
  final String label;
  final List<DocSpan> spans;
}

/// 풀어 놓은 본문.
class DocBody {
  DocBody(this.nodes, this.toc, this.footnotes, this.categories, this.footMarked);
  final List<DocNode> nodes;
  final List<DocHeading> toc;
  final List<DocFootnote> footnotes;
  final List<String> categories;

  /// 본문에 `[각주]`를 적어 두었는가(없으면 각주 목록을 맨 끝에 붙인다).
  final bool footMarked;
}

/// 본문 글을 블록으로 푼다. [links]는 내보내기가 미리 푼 고리 표(이름 → 목적지)다. [images]는 그림 표(이름 → 그림).
DocBody parseDocBody(String source, {Map<String, DocLink> links = const {}, Map<String, DocImageRef> images = const {}}) {
  final parser = _Parser(links, images);
  final nodes = parser.blocks(source.replaceAll('\r\n', '\n').replaceAll('\r', '\n'));
  // 목차 번호는 그 문서에서 가장 큰 제목 단계를 1로 잡는다(js/wiki.js의 `counters`).
  if (parser.toc.isNotEmpty) {
    final min = parser.toc.map((h) => h.level).reduce(math.min);
    final counters = <int>[];
    for (final h in parser.toc) {
      final depth = h.level - min + 1;
      h.depth = depth;
      while (counters.length > depth) {
        counters.removeLast();
      }
      while (counters.length < depth) {
        counters.add(0);
      }
      counters[depth - 1] = counters[depth - 1] + 1;
      for (int k = 0; k < depth - 1; k++) {
        if (counters[k] == 0) counters[k] = 1;
      }
      h.number = counters.sublist(0, depth).join('.');
    }
  }
  return DocBody(nodes, parser.toc, parser.footnotes, parser.categories, parser.footMarked);
}

/// 여는 글자로 시작하는 자리에서 짝이 맞는 닫는 글자 뒤의 자리를 찾는다(js/wiki.js의 `matchEnd`).
int _matchEnd(String text, int from, String open, String close) {
  int depth = 0;
  for (int i = from; i < text.length; i++) {
    if (text.startsWith(open, i)) {
      depth++;
      i += open.length - 1;
    } else if (text.startsWith(close, i)) {
      depth--;
      i += close.length - 1;
      if (depth == 0) return i + 1;
    }
  }
  return -1;
}

final _reHeading = RegExp(r'^(={1,6})(#?) (.+?) \2\1\s*$');
final _reRule = RegExp(r'^-{4,9}\s*$');
final _reTable = RegExp(r'^\s*\|\|');
final _reList = RegExp(r'^( +)(\*|1\.(?:#\d+)?|a\.|A\.|i\.|I\.)\s?(.*)$');
final _reHold = RegExp('^\\s*(\\d+)\\s*\$');
final _reToc = RegExp(r'^\s*\[(목차|tableofcontents)\]\s*$', caseSensitive: false);
final _reFoot = RegExp(r'^\s*\[(각주|footnote)\]\s*$', caseSensitive: false);
final _reBrace = RegExp(r'^#!(folding|wiki|syntax|html)\b([^\n]*)\n?([\s\S]*)$');
final _reSize = RegExp(r'^([+-])(\d)\s([\s\S]*)$');
final _reColor = RegExp(r'^#([0-9a-fA-F]{3,8}|[a-zA-Z]{3,20})(?:,#[0-9a-fA-F]{3,8})?\s([\s\S]*)$');
final _reCategory = RegExp(r'^(분류|category):', caseSensitive: false);
final _reFile = RegExp(r'^(파일|이미지|file):', caseSensitive: false);
final _reExternal = RegExp(r'^(https?://|//)', caseSensitive: false);
final _reFigure = RegExp(r'^인물\s*:\s*');
final _reFootLabel = RegExp(r'^(\S*)\s?([\s\S]*)$');
final _reFileLink = RegExp(r'\[\[((?:파일|이미지|file)\s*:[^\]]*?)\]\]', caseSensitive: false);
final _reFilePrefix = RegExp(r'^(파일|이미지|file)\s*:\s*', caseSensitive: false);

/// 글자 꾸밈 짝 — `'''`가 `''`보다 앞이어야 한다.
const _pairs = <List<String>>[
  ["'''", "'''", 'b'],
  ["''", "''", 'i'],
  ['~~', '~~', 's'],
  ['__', '__', 'u'],
  ['^^', '^^', 'sup'],
  [',,', ',,', 'sub'],
];

class _Parser {
  _Parser(this.links, [this.images = const {}]);

  final Map<String, DocLink> links;
  final Map<String, DocImageRef> images;
  final toc = <DocHeading>[];
  final footnotes = <DocFootnote>[];
  final categories = <String>[];
  bool footMarked = false;

  final _held = <DocNode>[];

  /// 줄 단위 블록. `{{{ … }}}`를 먼저 걷어 내고(자리표시자) 줄을 훑는다.
  List<DocNode> blocks(String text) {
    final lines = _extractBraces(text).split('\n');
    final out = <DocNode>[];
    final para = <String>[];
    void flush() {
      if (para.isEmpty) return;
      final spans = <DocSpan>[];
      for (int i = 0; i < para.length; i++) {
        if (i > 0) spans.add(const DocSpan('\n', lineBreak: true));
        spans.addAll(inline(para[i]));
      }
      para.clear();
      out.add(DocParagraph(spans));
    }

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) {
        flush();
        continue;
      }
      final hold = _reHold.firstMatch(line);
      if (hold != null) {
        flush();
        final n = int.parse(hold.group(1)!);
        if (n < _held.length) out.add(_held[n]);
        continue;
      }
      if (_reFoot.hasMatch(line)) {
        flush();
        footMarked = true;
        out.add(const DocFootMark());
        continue;
      }
      if (_reToc.hasMatch(line)) {
        flush();
        out.add(const DocTocMark());
        continue;
      }
      final head = _reHeading.firstMatch(line);
      if (head != null) {
        flush();
        final level = head.group(1)!.length;
        final text = head.group(3)!;
        final node = DocHeading(level, inline(text), 'wk-h${toc.length + 1}', _plainOf(text));
        toc.add(node);
        out.add(node);
        continue;
      }
      if (_reRule.hasMatch(line)) {
        flush();
        out.add(const DocRule());
        continue;
      }
      if (_reTable.hasMatch(line)) {
        flush();
        final rows = <String>[];
        while (i < lines.length && (_reTable.hasMatch(lines[i]) || (rows.isNotEmpty && !rows.last.trimRight().endsWith('||')))) {
          rows.add(lines[i++]);
        }
        i--;
        out.add(_table(rows));
        continue;
      }
      if (line.startsWith('>')) {
        flush();
        final quoted = <String>[];
        while (i < lines.length && lines[i].startsWith('>')) {
          quoted.add(lines[i++].replaceFirst(RegExp(r'^>\s?'), ''));
        }
        i--;
        out.add(DocQuote(blocks(quoted.join('\n'))));
        continue;
      }
      if (_reList.hasMatch(line)) {
        flush();
        final raw = <List<String>>[]; // [들여쓰기, 표시, 글]
        while (i < lines.length) {
          final m = _reList.firstMatch(lines[i]);
          if (m == null) break;
          raw.add([m.group(1)!, m.group(2)!, m.group(3)!]);
          i++;
          // 들여쓴 이어지는 줄은 같은 항목의 계속이다.
          while (i < lines.length && RegExp(r'^ {2,}\S').hasMatch(lines[i]) && !_reList.hasMatch(lines[i])) {
            raw.last[2] = '${raw.last[2]}\n${lines[i++].trim()}';
          }
        }
        i--;
        out.add(_list(raw));
        continue;
      }
      if (_reFileLink.hasMatch(line)) {
        // 문서 그림: 그 줄 앞에서 문단을 끊고 그림을 놓은 뒤, 그림 고리를 뺀 나머지 글을 새 문단으로 이어 쓴다(js/wiki.js와 같다).
        flush();
        final rest = line.replaceAllMapped(_reFileLink, (m) {
          out.add(_figure(m.group(1)!));
          return '';
        });
        if (rest.trim().isNotEmpty) para.add(rest);
        continue;
      }
      para.add(line);
    }
    flush();
    return out;
  }

  /// `{{{ … }}}` 블록을 걷어 내고 그 자리에 자리표시자를 남긴다(js/wiki.js의 `extractBlocks`).
  String _extractBraces(String text) {
    final out = StringBuffer();
    int i = 0;
    while (i < text.length) {
      final at = text.indexOf('{{{', i);
      if (at < 0) {
        out.write(text.substring(i));
        break;
      }
      final end = _matchEnd(text, at, '{{{', '}}}');
      if (end < 0) {
        out.write(text.substring(i));
        break;
      }
      final body = text.substring(at + 3, end - 3);
      final head = _reBrace.firstMatch(body);
      DocNode? node;
      if (head != null) {
        final kind = head.group(1)!, arg = head.group(2)!.trim(), inner = head.group(3) ?? '';
        if (kind == 'folding') {
          node = DocFold(inline(arg.isEmpty ? '펼치기' : arg), blocks(inner));
        } else if (kind == 'wiki') {
          node = DocGroup(blocks(inner), boxed: true);
        } else {
          node = DocPre(inner); // `#!syntax` · `#!html`은 그대로 보인다(안전).
        }
      } else if (body.contains('\n')) {
        final m = _reSize.firstMatch(body);
        node = m == null ? DocPre(body) : DocGroup(blocks(m.group(3)!), scale: _scaleOf(m.group(1)!, m.group(2)!));
      }
      if (node == null) {
        out.write(text.substring(i, end)); // 한 줄짜리 `{{{ }}}`는 [inline]이 맡는다
      } else {
        out.write(text.substring(i, at));
        out.write('${_held.length}');
        _held.add(node);
      }
      i = end;
    }
    return out.toString();
  }

  /// 표 한 덩이(js/wiki.js의 `table`).
  DocTable _table(List<String> lines) {
    // 칸이 여러 줄이면 `||`로 끝나지 않은 줄을 다음 줄과 잇는다.
    final rows = <String>[];
    var cur = '';
    for (final l in lines) {
      cur = cur.isEmpty ? l : '$cur\n$l';
      if (cur.trimRight().endsWith('||')) {
        rows.add(cur);
        cur = '';
      }
    }
    if (cur.isNotEmpty) rows.add(cur);
    final out = <List<DocCell>>[];
    for (final r in rows) {
      final body = r.trim();
      if (body.length < 4) continue;
      final cells = body.substring(2, body.length - 2).split('||');
      final line = <DocCell>[];
      for (var cell in cells) {
        int colspan = 1, rowspan = 1;
        Color? background;
        TextAlign? align;
        while (true) {
          final m = RegExp(r'^<([^<>\n]*)>').firstMatch(cell);
          if (m == null) break;
          final opt = m.group(1)!.trim();
          final rest = cell.substring(m.group(0)!.length);
          final span = RegExp(r'^-(\d+)$').firstMatch(opt);
          final down = RegExp(r'^(?:\||\^\||v\|)(\d+)$').firstMatch(opt);
          final bg = RegExp(r'^bgcolor=(.+)$', caseSensitive: false).firstMatch(opt);
          if (span != null) {
            colspan = int.parse(span.group(1)!);
          } else if (down != null) {
            rowspan = int.parse(down.group(1)!);
          } else if (opt == '(') {
            align = TextAlign.left;
          } else if (opt == ':') {
            align = TextAlign.center;
          } else if (opt == ')') {
            align = TextAlign.right;
          } else if (bg != null) {
            background = _cssColor(bg.group(1)!.trim());
          } else if (RegExp(r'^(nopad|table|color=|width=|height=|row)', caseSensitive: false).hasMatch(opt)) {
            // 아직 옮기지 않은 옵션은 건너뛴다.
          } else {
            break; // 옵션이 아니면 글자로 되돌린다
          }
          cell = rest;
        }
        if (align == null) {
          final left = RegExp(r'^\s').hasMatch(cell), right = RegExp(r'\s$').hasMatch(cell);
          align = left && right ? TextAlign.center : (left ? TextAlign.right : null);
        }
        line.add(DocCell(inline(cell.trim()), colspan: colspan, rowspan: rowspan, background: background, align: align));
      }
      if (line.isNotEmpty) out.add(line);
    }
    return DocTable(out);
  }

  /// 목록 한 덩이 — 들여쓰기를 깊이로 바꾸고 번호를 매긴다.
  DocList _list(List<List<String>> raw) {
    final items = <DocListItem>[];
    final indents = <int>[];
    final counters = <int>[];
    final kinds = <String>[];
    for (final one in raw) {
      final indent = one[0].length;
      final marker = one[1];
      while (indents.isNotEmpty && indents.last > indent) {
        indents.removeLast();
        counters.removeLast();
        kinds.removeLast();
      }
      final kind = marker == '*' ? '*' : marker[0];
      if (indents.isEmpty || indents.last < indent) {
        indents.add(indent);
        counters.add(0);
        kinds.add(kind);
      } else if (kinds.last != kind) {
        counters[counters.length - 1] = 0;
        kinds[kinds.length - 1] = kind;
      }
      final start = RegExp(r'#(\d+)').firstMatch(marker);
      if (start != null) counters[counters.length - 1] = int.parse(start.group(1)!) - 1;
      counters[counters.length - 1] = counters.last + 1;
      final n = counters.last;
      final label = switch (kind) {
        '*' => '•',
        'a' => '${String.fromCharCode('a'.codeUnitAt(0) + (n - 1) % 26)}.',
        'A' => '${String.fromCharCode('A'.codeUnitAt(0) + (n - 1) % 26)}.',
        'i' => '$n)',
        'I' => '$n)',
        _ => '$n.',
      };
      items.add(DocListItem(indents.length - 1, label, inline(one[2])));
    }
    return DocList(items);
  }

  /// 글 한 줄을 조각으로. 각주 · 고리 · 꾸밈이 섞인다.
  List<DocSpan> inline(String raw) => _spans(raw, const DocSpan(''));

  List<DocSpan> _spans(String s, DocSpan style) {
    final out = <DocSpan>[];
    final buf = StringBuffer();
    void push() {
      if (buf.isEmpty) return;
      out.add(style._with(buf.toString()));
      buf.clear();
    }

    int i = 0;
    while (i < s.length) {
      if (s.codeUnitAt(i) == 1) {
        // 블록 자리표시자가 글 한복판에 남았으면 지운다.
        final e = s.indexOf('', i + 1);
        if (e > 0) {
          i = e + 1;
          continue;
        }
      }
      if (s.startsWith('[[', i)) {
        final end = s.indexOf(']]', i + 2);
        if (end > 0) {
          push();
          final made = _link(s.substring(i + 2, end), style);
          if (made != null) out.add(made);
          i = end + 2;
          continue;
        }
      }
      if (s.startsWith('[*', i)) {
        final end = _matchEnd(s, i, '[', ']');
        if (end > 0) {
          push();
          out.add(_footnote(s.substring(i + 2, end - 1)));
          i = end;
          continue;
        }
      }
      if (s.startsWith('[br]', i) || s.startsWith('[BR]', i)) {
        push();
        out.add(const DocSpan('\n', lineBreak: true));
        i += 4;
        continue;
      }
      if (s.startsWith('{{{', i)) {
        final end = _matchEnd(s, i, '{{{', '}}}');
        if (end > 0) {
          push();
          out.addAll(_brace(s.substring(i + 3, end - 3), style));
          i = end;
          continue;
        }
      }
      var matched = false;
      for (final pair in _pairs) {
        if (!s.startsWith(pair[0], i)) continue;
        final from = i + pair[0].length;
        final end = s.indexOf(pair[1], from);
        if (end < 0 || end == from) continue;
        push();
        out.addAll(_spans(s.substring(from, end), _mark(style, pair[2])));
        i = end + pair[1].length;
        matched = true;
        break;
      }
      if (matched) continue;
      buf.write(s[i]);
      i++;
    }
    push();
    return out;
  }

  DocSpan _mark(DocSpan style, String kind) => DocSpan(
    '',
    bold: style.bold || kind == 'b',
    italic: style.italic || kind == 'i',
    strike: style.strike || kind == 's',
    underline: style.underline || kind == 'u',
    code: style.code,
    sup: style.sup || kind == 'sup',
    low: style.low || kind == 'sub',
    scale: style.scale,
    color: style.color,
    link: style.link,
  );

  /// `[[파일:이름|width=…|align=…]]`의 속 → 그림(js/wiki.js의 `namu.fileSpec`과 같은 읽기 — 크기와 자리만).
  DocFigure _figure(String inner) {
    final parts = inner.split('|');
    final name = parts.first.replaceFirst(_reFilePrefix, '').trim();
    var align = '';
    double px = 0, pct = 0;
    for (final p in parts.skip(1)) {
      final m = RegExp(r'^(width|align)\s*=\s*(.+)$', caseSensitive: false).firstMatch(p.trim());
      if (m == null) continue;
      final v = m.group(2)!.trim().toLowerCase();
      if (m.group(1)!.toLowerCase() == 'width') {
        final w = RegExp(r'^(\d{1,4})(px|%)?$').firstMatch(v);
        final n = w == null ? 0 : int.parse(w.group(1)!);
        if (n > 0) {
          if (w!.group(2) == '%') {
            pct = math.min(100, n).toDouble();
            px = 0;
          } else {
            px = n.toDouble();
            pct = 0;
          }
        }
      } else if (const {'left', 'center', 'right'}.contains(v)) {
        align = v;
      }
    }
    return DocFigure(name, image: name.isEmpty ? null : images[name], align: align, widthPx: px, widthPct: pct);
  }

  /// `[[…]]` 하나 — 분류 · 파일은 글에서 사라지고, 바깥 주소는 바깥 고리다.
  DocSpan? _link(String inner, DocSpan style) {
    final bar = inner.indexOf('|');
    final target = (bar < 0 ? inner : inner.substring(0, bar)).trim();
    final label = bar < 0 ? null : inner.substring(bar + 1).trim();
    if (_reCategory.hasMatch(target)) {
      final name = target.split(':').skip(1).join(':').trim();
      if (name.isNotEmpty && !categories.contains(name)) categories.add(name);
      return null;
    }
    if (_reFile.hasMatch(target)) return null;
    var text = label != null && label.isNotEmpty ? label : target.replaceFirst(_reFigure, '');
    if (text.isEmpty) text = target;
    if (_reExternal.hasMatch(target)) {
      return DocSpan(
        text,
        link: DocLink(target, url: target),
        scale: style.scale,
      );
    }
    final name = target.split('#').first.trim();
    final found = links[name];
    return DocSpan(text, bold: style.bold, italic: style.italic, scale: style.scale, link: found ?? DocLink(name));
  }

  DocSpan _footnote(String inner) {
    final m = _reFootLabel.firstMatch(inner);
    final named = m == null ? '' : m.group(1)!;
    final body = m == null ? inner : m.group(2) ?? '';
    if (named.isNotEmpty) {
      for (final f in footnotes) {
        if (f.label == named) return DocSpan('[${f.label}]', footnote: f.id);
      }
    }
    final id = footnotes.length + 1;
    final label = named.isNotEmpty ? named : '$id';
    footnotes.add(DocFootnote(id, label, _spans(body, const DocSpan(''))));
    return DocSpan('[$label]', footnote: id);
  }

  /// 한 줄짜리 `{{{ … }}}` — 크기 · 색 · 코드.
  List<DocSpan> _brace(String body, DocSpan style) {
    final size = _reSize.firstMatch(body);
    if (size != null) {
      return _spans(size.group(3)!, DocSpan('', bold: style.bold, italic: style.italic, scale: style.scale * _scaleOf(size.group(1)!, size.group(2)!), color: style.color));
    }
    final color = _reColor.firstMatch(body);
    if (color != null) {
      final made = _cssColor(RegExp(r'^[0-9a-fA-F]{3,8}$').hasMatch(color.group(1)!) ? '#${color.group(1)!}' : color.group(1)!);
      if (made != null) {
        return _spans(color.group(2)!, DocSpan('', bold: style.bold, italic: style.italic, scale: style.scale, color: made));
      }
    }
    return [DocSpan(body, code: true, scale: style.scale)];
  }

  String _plainOf(String text) => text.replaceAllMapped(RegExp(r'\[\[([^\]|]+?)(?:\|([^\]]*?))?\]\]'), (m) => m.group(2) ?? m.group(1)!).replaceAll(RegExp("'{2,3}"), '');
}

double _scaleOf(String sign, String digit) {
  const up = [1.1, 1.25, 1.4, 1.6, 1.85], down = [.9, .8, .7, .6, .6];
  final n = (int.tryParse(digit) ?? 1).clamp(1, 5);
  return sign == '+' ? up[n - 1] : down[n - 1];
}

/// css의 색 글(`#a0bcc5` · 이름 몇 개)을 색으로. 모르면 null.
Color? _cssColor(String raw) {
  var text = raw.trim();
  if (text.startsWith('#')) {
    var hex = text.substring(1);
    if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
    if (hex.length == 6 || hex.length == 8) {
      final n = int.tryParse(hex.length == 6 ? 'ff$hex' : hex, radix: 16);
      if (n != null) return Color(n);
    }
    return null;
  }
  const named = {
    'red': 0xffff0000,
    'blue': 0xff0000ff,
    'green': 0xff008000,
    'black': 0xff000000,
    'white': 0xffffffff,
    'gray': 0xff808080,
    'grey': 0xff808080,
    'orange': 0xffffa500,
    'purple': 0xff800080,
    'brown': 0xffa52a2a,
    'yellow': 0xffffff00,
    'pink': 0xffffc0cb,
    'navy': 0xff000080,
    'teal': 0xff008080,
    'silver': 0xffc0c0c0,
  };
  final n = named[text.toLowerCase()];
  return n == null ? null : Color(n);
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  3. 본문 그리기
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 풀어 놓은 본문을 그린다. 고리를 누르면 [onLink], 목차 · 각주를 누르면 그 자리로 미끄러진다.
/// 문서 그림의 바이트는 [loadImage]로 읽고(없으면 빈 자리만), 그림을 누르면 [onZoom](크게 보기)을 부른다.
class DocArticle extends StatefulWidget {
  const DocArticle({super.key, required this.body, this.onLink, this.width = DocUi.articleWidth, this.loadImage, this.onZoom});

  final DocBody body;
  final void Function(DocLink link)? onLink;
  final double width;
  final Future<Uint8List?> Function(String key)? loadImage;
  final void Function(DocFigure figure)? onZoom;

  @override
  State<DocArticle> createState() => DocArticleState();
}

class DocArticleState extends State<DocArticle> {
  final _taps = <TapGestureRecognizer>[];
  final _anchors = <String, GlobalKey>{};

  /// 이번 그리기에서 되돌아올 자리를 이미 단 각주의 번호.
  /// 이름을 붙인 각주를 되풀이 쓰면(`[*ㄱ 주석]` … `[*ㄱ]`) 파서가 **같은 번호**를 돌려주어
  /// 본문에 그 표가 둘 이상이 된다(js/wiki.js:59~61). 자리표(GlobalKey)는 한 위젯에만 붙을 수 있으므로
  /// **첫 표에만** 단다 — 브라우저도 같은 id가 둘이면 첫 자리로 간다.
  final _rfnSeen = <int>{};

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  void _clear() {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
    _rfnSeen.clear();
    _regions = 0;
    _pending.clear();
  }

  // ── 띄운 그림의 자리(결정 9 B) ── 그림 하나와 그 뒤의 문단 · 목록 항목(흐르는 글 조각)이 한 자리다.
  //  ① 처음에는 조각을 모두 그림 옆 폭(본문 − 그림 − 틈)으로 그린다(그림 옆에서 시작하므로 그 자리의 첫 줄은 늘 맞다).
  //  ② 그린 뒤 조각마다 줄의 윗변을 재어(`RenderParagraph.getBoxesForSelection`) 그림의 바깥 아랫변 아래로 내려간 첫 줄을 찾는다.
  //  ③ 그 줄이 든 조각을 그 줄의 첫 글자에서 나눠(앞은 그림 옆 폭 · 뒤는 본문 폭) 다시 그리고, 그 뒤 조각은 모두 본문 폭이다.
  //  줄을 앞에서부터 채우는 줄 나눔은 앞부분이 같으면 같은 자리에서 끊기므로 ③의 앞 조각은 ②에서 잰 줄 그대로다 — 한 번 재면 끝난다.
  //  본문 폭 · 본문이 바뀌면 다시 잰다. 지금 연표(css float)의 '그림 바깥 아랫변보다 위에서 시작하는 줄은 좁은 줄'과 같은 규칙이다.

  /// 이번 그리기의 띄운 자리 번호(본문 안 차례).
  int _regions = 0;

  /// 아직 재지 않은 자리 → 그 그림의 바깥 아랫변(자리 위에서부터).
  final _pending = <int, double>{};

  /// 잰 결과: 자리 번호 → (나눌 조각, 나눌 글자 자리). 조각이 −1이면 모든 조각이 그림 옆에서 끝난다.
  final _splits = <int, (int, int)>{};
  final _regionKeys = <int, GlobalKey>{};
  final _unitKeys = <String, GlobalKey>{};
  String _floatSig = '';
  bool _measureQueued = false;

  GlobalKey _anchor(String id) => _anchors[id] ??= GlobalKey();

  /// 목차 · 각주가 부르는 자리 옮기기.
  Future<void> jumpTo(String id) async {
    final target = _anchors[id]?.currentContext;
    if (target == null) return;
    await Scrollable.ensureVisible(target, duration: DocUi.enter, curve: Ui.spring, alignment: .02);
  }

  TextStyle get _base =>
      const TextStyle(fontFamily: Ui.serif, fontFamilyFallback: Ui.serifFallback, fontSize: DocUi.font, height: DocUi.lineHeight, color: Ui.text, fontWeight: FontWeight.w400);

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.width),
      // 본문 폭을 알아야 그림을 띄울지(600 넘음) · 그림 옆 폭을 정한다. 다시 그릴 때마다 고리 · 각주 자리표를 새로(_clear).
      child: LayoutBuilder(
        builder: (context, box) {
          _clear();
          final width = box.maxWidth;
          final sig = '${identityHashCode(widget.body)}/${width.toStringAsFixed(2)}';
          if (sig != _floatSig) {
            _floatSig = sig;
            _splits.clear();
          }
          final children = [
            ..._blocks(widget.body.nodes, _base, width),
            // 본문에 `[각주]`를 적지 않았으면 각주 목록을 맨 끝에 붙인다(js/wiki.js의 `hasFootTag`).
            if (!widget.body.footMarked && widget.body.footnotes.isNotEmpty) _footnotes(_base),
          ];
          if (_pending.isNotEmpty && !_measureQueued) {
            _measureQueued = true;
            WidgetsBinding.instance.addPostFrameCallback((_) => _measureFloats());
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children);
        },
      ),
    );
  }

  /// 본문의 블록들 — 오른쪽에 띄우는 그림은 그 뒤의 문단 · 목록과 한 자리로 묶는다(본문이 600보다 넓을 때만).
  List<Widget> _blocks(List<DocNode> nodes, TextStyle style, double width) {
    final out = <Widget>[];
    final floats = width >= DocUi.figureNarrow;
    for (int i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      if (floats && node is DocFigure && node.floats) {
        var j = i + 1;
        while (j < nodes.length && (nodes[j] is DocParagraph || nodes[j] is DocList)) {
          j++;
        }
        out.add(_floatRegion(_regions++, node, nodes.sublist(i + 1, j), style, width, j < nodes.length ? _topGap(nodes[j], style) : 0));
        i = j - 1;
        continue;
      }
      out.add(_node(node, style));
    }
    return out;
  }

  /// 그 블록의 위 바깥 여백 — 그림 아래에서 시작하는 블록(css `clear`)은 그 위 테두리가 그림의 바깥 아랫변에 맞도록 자리 높이에서 이만큼 뺀다.
  double _topGap(DocNode node, TextStyle style) {
    final fs = style.fontSize!;
    if (node is DocHeading) return fs * (const {1: 1.45, 2: 1.25, 3: 1.1}[node.level] ?? 1.0) * 1.1;
    if (node is DocRule) return fs;
    if (node is DocTable || node is DocQuote || node is DocPre) return fs * .6;
    if (node is DocFold) return 8;
    if (node is DocGroup) return node.boxed ? fs * .5 : 4;
    if (node is DocFootMark) return fs * .9 * 1.2;
    if (node is DocFigure) return node.floats ? 0 : DocUi.blockTop;
    return 0;
  }

  TextStyle get _captionStyle => const TextStyle(fontSize: DocUi.captionSize, height: 1.5, color: Ui.text3, fontWeight: FontWeight.w400);

  /// 그림 아래 설명 한 줄의 높이(폭 [width]에서 — 그림 상자와 같은 글자 설정).
  double _captionHeight(String text, double width) {
    if (text.isEmpty) return 0;
    final painter = TextPainter(
      text: TextSpan(text: text, style: DefaultTextStyle.of(context).style.merge(_captionStyle)),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: width);
    final h = painter.height;
    painter.dispose();
    return h;
  }

  /// 그림 상자 — 둥근 12 · 1px 선 · 누르면 크게 · 아래 설명(css `.wk-fig-img` · `figcaption`).
  Widget _figureBox(DocFigure fig, DocImageRef image, double width, TextAlign captionAlign) {
    final boxH = (width - 2) * image.ratio + 2;
    final label = image.alt.isNotEmpty ? image.alt : (image.caption.isNotEmpty ? image.caption : fig.name);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          image: true,
          button: true,
          label: '$label — 누르면 크게',
          child: MouseRegion(
            cursor: SystemMouseCursors.zoomIn,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onZoom?.call(fig),
              child: Container(
                height: boxH,
                decoration: BoxDecoration(color: Ui.surface2, borderRadius: BorderRadius.circular(DocUi.figureRadius), border: Border.all(color: Ui.line)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(DocUi.figureRadius - 1),
                  child: DocImage(image: image, loader: widget.loadImage),
                ),
              ),
            ),
          ),
        ),
        if (image.captionLine.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: DocUi.captionGap),
            child: Text(image.captionLine, style: _captionStyle, textAlign: captionAlign),
          ),
      ],
    );
  }

  /// 띄우지 않는 그림(결정 9 A — 가운데 · 왼쪽 · 좁은 본문 · 상자 안) · 사전에 없는 그림.
  Widget _blockFigure(DocFigure fig) {
    final image = fig.image;
    if (image == null) {
      return Padding(
        padding: const EdgeInsets.only(top: DocUi.blockTop, bottom: DocUi.blockBottom),
        child: CustomPaint(
          painter: const _DashedBox(color: DocUi.danger, radius: DocUi.figureRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text('그림 없음 — ${fig.name}', style: const TextStyle(fontSize: 13, height: 1.5, color: DocUi.danger)),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final natural = image.width > 0 ? image.width.toDouble() : width;
        final spec = fig.widthPx > 0 ? fig.widthPx : (fig.widthPct > 0 ? width * fig.widthPct / 100 : natural);
        final w = math.min(spec, width);
        final left = fig.align == 'left';
        return Padding(
          padding: const EdgeInsets.only(top: DocUi.blockTop, bottom: DocUi.blockBottom),
          child: Align(
            alignment: left ? Alignment.centerLeft : Alignment.topCenter,
            child: SizedBox(width: w, child: _figureBox(fig, image, w, left ? TextAlign.left : TextAlign.center)),
          ),
        );
      },
    );
  }

  /// 띄운 그림의 자리 하나 — 그림(오른쪽 위) + 흐르는 글 조각(문단 · 목록 항목).
  Widget _floatRegion(int index, DocFigure fig, List<DocNode> flow, TextStyle style, double width, double clearGap) {
    final image = fig.image!;
    final spec = fig.widthPx > 0 ? fig.widthPx : (fig.widthPct > 0 ? width * fig.widthPct / 100 : DocUi.figureWidth);
    final natural = image.width > 0 ? image.width.toDouble() : DocUi.figureWidth;
    final figW = math.max(1.0, [spec, natural, width - DocUi.figureMinText - DocUi.figureGap].reduce(math.min));
    final capH = _captionHeight(image.captionLine, figW);
    final floatH = DocUi.figureTop + (figW - 2) * image.ratio + 2 + (capH > 0 ? DocUi.captionGap + capH : 0) + DocUi.figureBottom;
    final units = <_FlowUnit>[];
    for (final node in flow) {
      if (node is DocParagraph) units.add(_FlowUnit(node.spans));
      if (node is DocList) {
        for (int k = 0; k < node.items.length; k++) {
          final it = node.items[k];
          units.add(_FlowUnit(it.spans, item: it, first: k == 0, last: k == node.items.length - 1));
        }
      }
    }
    final split = _splits[index];
    if (split == null) _pending[index] = floatH;
    final fs = style.fontSize!;
    final narrow = EdgeInsets.only(right: figW + DocUi.figureGap);
    final children = <Widget>[];
    for (int k = 0; k < units.length; k++) {
      final u = units[k];
      // 그림 옆(좁게) · 나눔(앞은 좁게 · 뒤는 넓게) · 본문 폭(넓게)
      final whole = split == null || split.$1 < 0 || k < split.$1 ? 0 : (k == split.$1 && split.$2 > 0 ? 1 : 2);
      final key = split == null ? (_unitKeys['$index/$k'] ??= GlobalKey()) : null;
      final item = u.item;
      if (item == null) {
        if (whole == 1) {
          final (head, tail) = _splitSpans(u.spans, split!.$2);
          children.add(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(padding: narrow, child: _rich(head, style)),
              Padding(padding: EdgeInsets.only(bottom: fs * .7), child: _rich(tail, style)),
            ],
          ));
        } else {
          children.add(Padding(
            padding: EdgeInsets.only(bottom: fs * .7, right: whole == 0 ? narrow.right : 0),
            child: _rich(u.spans, style, key: key),
          ));
        }
        continue;
      }
      // 목록 항목 — `_list`와 같은 자리(글은 1.5em × 깊이에서 시작 · 앞의 표시는 그 안쪽)
      final indent = fs * 1.5, markW = fs * 1.2;
      final left = math.max(0.0, indent * (item.depth + 1) - markW);
      final pad = EdgeInsets.only(top: (u.first ? fs * .3 : 0) + fs * .15, bottom: fs * .15 + (u.last ? fs * .6 : 0));
      Widget row(List<DocSpan> spans, {Key? key}) => Padding(
        padding: EdgeInsets.only(left: left),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: markW, child: Text(item.marker, style: style.copyWith(color: Ui.text2))),
            Expanded(child: _rich(spans, style, key: key)),
          ],
        ),
      );
      if (whole == 1) {
        final (head, tail) = _splitSpans(u.spans, split!.$2);
        children.add(Padding(
          padding: pad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(padding: narrow, child: row(head)),
              Padding(padding: EdgeInsets.only(left: left + markW), child: _rich(tail, style)),
            ],
          ),
        ));
      } else {
        children.add(Padding(padding: pad, child: Padding(padding: whole == 0 ? narrow : EdgeInsets.zero, child: row(u.spans, key: key))));
      }
    }
    return Stack(
      key: _regionKeys[index] ??= GlobalKey(),
      clipBehavior: Clip.none,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(minWidth: width, minHeight: math.max(0, floatH - clearGap)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children),
        ),
        Positioned(
          top: DocUi.figureTop,
          right: 0,
          width: figW,
          child: _figureBox(fig, image, figW, TextAlign.left),
        ),
      ],
    );
  }

  /// 그린 뒤 — 아직 재지 않은 띄운 자리마다 그림 아래로 내려간 첫 줄을 찾아 나눌 자리를 정하고 다시 그린다.
  /// 장면을 다 그린 뒤에 불리므로 그사이 폭이 바뀌어 다시 그렸어도 지금 그려진 것(지금의 [_pending])을 잰다.
  void _measureFloats() {
    _measureQueued = false;
    if (!mounted || _pending.isEmpty) return;
    final found = <int, (int, int)>{};
    for (final entry in _pending.entries) {
      final index = entry.key, floatH = entry.value;
      final region = _regionKeys[index]?.currentContext?.findRenderObject();
      var result = (-1, 0);
      if (region is RenderBox && region.hasSize) {
        for (int k = 0;; k++) {
          final key = _unitKeys['$index/$k'];
          final rp = key?.currentContext?.findRenderObject();
          if (key == null || rp is! RenderParagraph) break;
          if (!rp.hasSize) continue;
          final top = rp.localToGlobal(Offset.zero, ancestor: region).dy;
          int line = 0;
          (int, int)? hit;
          for (final lineTop in _lineTops(rp)) {
            if (top + lineTop >= floatH - .5) {
              hit = (k, line == 0 ? 0 : rp.getPositionForOffset(Offset(0, lineTop + 2)).offset);
              break;
            }
            line++;
          }
          if (hit != null) {
            result = hit;
            break;
          }
        }
      }
      found[index] = result;
    }
    setState(() => _splits.addAll(found));
  }

  /// 글 한 덩이의 줄마다 윗변(위에서부터 · 오름차순) — 한 줄의 글 조각 상자들은 하나로 셈한다.
  static List<double> _lineTops(RenderParagraph rp) {
    final length = rp.text.toPlainText(includeSemanticsLabels: false).length;
    final tops = rp.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: length)).map((b) => b.top).toList()..sort();
    final out = <double>[];
    for (final t in tops) {
      if (out.isEmpty || t - out.last > 6) out.add(t);
    }
    return out;
  }

  /// 조각 하나가 그려진 글에서 차지하는 글자 수 — [_span]이 만드는 것과 같게(각주 · 코드 · 위아래 첨자는 자리 하나 · 바깥 고리는 ↗ 하나 더).
  static int _spanLength(DocSpan s) {
    if (s.lineBreak || s.footnote > 0 || s.code || s.sup || s.low) return 1;
    final link = s.link;
    return s.text.length + (link != null && link.url.isNotEmpty ? 1 : 0);
  }

  /// 조각들을 그려진 글의 글자 자리 [offset]에서 둘로 — 앞 끝의 줄바꿈은 뺀다(빈 줄이 생기지 않게).
  static (List<DocSpan>, List<DocSpan>) _splitSpans(List<DocSpan> spans, int offset) {
    final head = <DocSpan>[], tail = <DocSpan>[];
    var at = 0;
    for (final s in spans) {
      final n = _spanLength(s);
      if (at + n <= offset) {
        head.add(s);
      } else if (at >= offset) {
        tail.add(s);
      } else {
        final cut = math.min(offset - at, s.text.length);
        head.add(s._with(s.text.substring(0, cut)));
        tail.add(s._with(s.text.substring(cut)));
      }
      at += n;
    }
    while (head.isNotEmpty && head.last.lineBreak) {
      head.removeLast();
    }
    while (tail.isNotEmpty && tail.first.lineBreak) {
      tail.removeAt(0);
    }
    return (head, tail);
  }

  // ── 블록 ──────────────────────────────────────────────────────────────────────────────────

  Widget _node(DocNode node, TextStyle style) {
    if (node is DocHeading) return _heading(node, style);
    if (node is DocParagraph) {
      return Padding(
        padding: EdgeInsets.only(bottom: style.fontSize! * .7),
        child: _rich(node.spans, style),
      );
    }
    if (node is DocList) return _list(node, style);
    if (node is DocQuote) {
      return Container(
        margin: EdgeInsets.symmetric(vertical: style.fontSize! * .6),
        padding: EdgeInsets.fromLTRB(style.fontSize! * .9, style.fontSize! * .4, style.fontSize! * .9, style.fontSize! * .4),
        decoration: const BoxDecoration(
          color: Ui.surface2,
          border: Border(left: BorderSide(color: DocUi.quoteBar, width: 4)),
          borderRadius: BorderRadius.only(topRight: Radius.circular(12), bottomRight: Radius.circular(12)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [for (final one in node.body) _node(one, style)]),
      );
    }
    if (node is DocRule) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: style.fontSize!),
        child: const SizedBox(height: 1, child: ColoredBox(color: Ui.lineStrong)),
      );
    }
    if (node is DocTable) return _table(node, style);
    if (node is DocFold) {
      return _DocFoldBox(
        summary: _rich(node.summary, style.copyWith(fontWeight: FontWeight.w600)),
        body: [for (final one in node.body) _node(one, style)],
      );
    }
    if (node is DocGroup) {
      final inner = style.copyWith(fontSize: style.fontSize! * node.scale);
      final body = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [for (final one in node.body) _node(one, inner)]);
      if (!node.boxed) return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: body);
      return Container(
        margin: EdgeInsets.symmetric(vertical: style.fontSize! * .5),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Ui.surface2, borderRadius: BorderRadius.circular(8)),
        child: body,
      );
    }
    if (node is DocPre) {
      return Container(
        width: double.infinity,
        margin: EdgeInsets.symmetric(vertical: style.fontSize! * .6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Ui.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Ui.line),
        ),
        child: Text(node.text, style: _mono(12.5)),
      );
    }
    if (node is DocTocMark) return _inlineToc(style);
    if (node is DocFootMark) return _footnotes(style);
    if (node is DocFigure) return _blockFigure(node); // 상자 · 인용 · 접기 안이나 좁은 본문 — 띄우지 않음
    return const SizedBox.shrink();
  }

  Widget _heading(DocHeading node, TextStyle style) {
    // `== … ==`(단계 2)는 `<h3>`으로 그려진다 — 단계 n이 곧 `h(n+1)`이다(js/wiki.js). 크기는 그 태그의 css 값이고
    // 위아래 여백은 **제 글자 크기**를 기준으로 한다(기준 덤프 `results/dom-doc9/wiki-dump.json`).
    const ems = {1: 1.45, 2: 1.25, 3: 1.1};
    final size = style.fontSize! * (ems[node.level] ?? 1.0);
    final head = style.copyWith(fontFamily: Ui.title, fontFamilyFallback: Ui.titleFallback, fontSize: size, fontWeight: FontWeight.w700, height: 1.3, letterSpacing: -size * .02);
    return Container(
      key: _anchor(node.id),
      width: double.infinity,
      margin: EdgeInsets.only(top: size * 1.1, bottom: size * .4),
      padding: EdgeInsets.only(bottom: size * .2),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Ui.line)),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            if (node.number.isNotEmpty)
              TextSpan(
                text: '${node.number}. ',
                style: head.copyWith(color: Ui.accent, fontWeight: FontWeight.w600),
              ),
            for (final s in node.spans) _span(s, head),
          ],
        ),
      ),
    );
  }

  Widget _list(DocList node, TextStyle style) {
    // 글은 `1.5em × 깊이`에서 시작하고 앞의 표시는 그 안쪽(css의 `list-style: outside`)에 선다.
    final indent = style.fontSize! * 1.5, marker = style.fontSize! * 1.2;
    return Padding(
      padding: EdgeInsets.only(top: style.fontSize! * .3, bottom: style.fontSize! * .6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in node.items)
            Padding(
              padding: EdgeInsets.only(left: math.max(0, indent * (item.depth + 1) - marker), top: style.fontSize! * .15, bottom: style.fontSize! * .15),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: marker,
                    child: Text(item.marker, style: style.copyWith(color: Ui.text2)),
                  ),
                  Expanded(child: _rich(item.spans, style)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 표 — 칸 합치기(`<-n>`)와 세로 칸 합치기(`<|n>`)를 격자로 풀어 그린다.
  /// 칸 폭은 합친 칸이 있어도 **글에 맞춰** 잡고(css의 `display: inline-table`), 넘칠 때만 줄인다.
  Widget _table(DocTable node, TextStyle style) {
    final cell = style.copyWith(fontSize: style.fontSize! * .95);
    final grid = node.grid;
    Widget box(DocPlacedCell p) => Container(
      decoration: BoxDecoration(
        color: p.cell.background,
        border: Border(
          right: p.rightEdge(grid.columns) ? BorderSide.none : const BorderSide(color: Ui.lineStrong),
          bottom: p.bottomEdge(grid.rows) ? BorderSide.none : const BorderSide(color: Ui.lineStrong),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      // 세로 가운데로(지금 연표의 `vertical-align: middle`) — 세로로 합친 칸의 글이 가운데에 선다.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_rich(p.cell.spans, cell, align: p.cell.align)],
      ),
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: style.fontSize! * .6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border.all(color: Ui.lineStrong, width: 2)),
          child: DocTableGrid(grid: grid, children: [for (final p in grid.cells) box(p)]),
        ),
      ),
    );
  }

  /// `[목차]` 자리의 작은 목차 상자.
  Widget _inlineToc(TextStyle style) {
    if (widget.body.toc.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: style.fontSize!),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
          decoration: BoxDecoration(
            color: Ui.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Ui.line),
          ),
          child: DocToc(headings: widget.body.toc, onTap: jumpTo, size: style.fontSize! * .92),
        ),
      ),
    );
  }

  /// 각주 목록.
  Widget _footnotes(TextStyle style) {
    if (widget.body.footnotes.isEmpty) return const SizedBox.shrink();
    final size = style.fontSize! * .9;
    final small = style.copyWith(fontSize: size, color: Ui.text2);
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: size * 1.2),
      padding: EdgeInsets.only(top: size * .6, left: size * 1.4),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Ui.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final f in widget.body.footnotes)
            Padding(
              key: _anchor('wk-fn-${f.id}'),
              padding: const EdgeInsets.only(bottom: 2),
              child: Text.rich(
                TextSpan(
                  children: [
                    // `[번호]`를 누르면 본문의 그 각주 자리로 되돌아간다(js/wiki.js의 `data-wiki-anchor="wk-rfn-<n>"`).
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: _DocJump(
                        onTap: () => jumpTo('wk-rfn-${f.id}'),
                        label: '각주 ${f.label} — 본문으로',
                        child: Text('[${f.label}] ', style: small.copyWith(color: Ui.accent)),
                      ),
                    ),
                    for (final s in f.spans) _span(s, small),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── 글 ────────────────────────────────────────────────────────────────────────────────────

  Widget _rich(List<DocSpan> spans, TextStyle style, {TextAlign? align, Key? key}) =>
      Text.rich(TextSpan(children: [for (final s in spans) _span(s, style)]), textAlign: align, key: key);

  TextStyle _mono(double size) => TextStyle(fontSize: size, height: 1.6, color: Ui.text, fontFamily: 'Consolas', fontFamilyFallback: const ['D2Coding', 'monospace']);

  InlineSpan _span(DocSpan s, TextStyle base) {
    if (s.lineBreak) return const TextSpan(text: '\n');
    if (s.footnote > 0) {
      // 본문의 각주 자리에 표를 남긴다 — 각주 목록의 `[번호]`를 누르면 여기로 되돌아온다(js/wiki.js의 `wk-rfn-<n>`).
      // 같은 각주를 되풀이 쓰면 표가 둘 이상이 되므로 되돌아올 자리는 **첫 표에만** 단다([_rfnSeen]).
      final first = _rfnSeen.add(s.footnote);
      return WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: _DocJump(
          anchor: first ? _anchor('wk-rfn-${s.footnote}') : null,
          onTap: () => jumpTo('wk-fn-${s.footnote}'),
          label: '각주 ${s.text}',
          child: Text(
            s.text,
            style: base.copyWith(fontSize: base.fontSize! * .8, color: Ui.accent),
          ),
        ),
      );
    }
    var style = base.copyWith(fontSize: base.fontSize! * s.scale);
    if (s.bold) style = style.copyWith(fontWeight: FontWeight.w700);
    if (s.italic) style = style.copyWith(fontStyle: FontStyle.italic);
    if (s.color != null) style = style.copyWith(color: s.color);
    if (s.strike || s.underline) {
      style = style.copyWith(
        decoration: TextDecoration.combine([if (s.strike) TextDecoration.lineThrough, if (s.underline) TextDecoration.underline]),
        decorationColor: style.color,
      );
    }
    if (s.code) {
      return WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: Ui.surface2,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Ui.line),
          ),
          child: Text(s.text, style: _mono(base.fontSize! * .92)),
        ),
      );
    }
    if (s.sup || s.low) {
      return WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Transform.translate(
          offset: Offset(0, base.fontSize! * (s.sup ? -.32 : .22)),
          child: Text(s.text, style: style.copyWith(fontSize: base.fontSize! * .83)), // 브라우저의 `font-size: smaller`
        ),
      );
    }
    final link = s.link;
    if (link == null) return TextSpan(text: s.text, style: style);
    // 고리의 밑줄: 있는 문서는 실선, 아직 없는 문서는 점선, 연표에 없는 이름은 붉은 파선(css의 border-bottom).
    final color = link.missing ? DocUi.danger : (link.url.isNotEmpty ? DocUi.ok : (link.empty ? DocUi.linkEmpty : Ui.accent));
    final tap = TapGestureRecognizer()..onTap = () => widget.onLink?.call(link);
    _taps.add(tap);
    return TextSpan(
      text: link.url.isNotEmpty ? '${s.text}↗' : s.text,
      style: style.copyWith(
        color: color,
        decoration: TextDecoration.underline,
        decorationColor: link.missing ? DocUi.danger : (link.empty ? DocUi.linkEmpty : DocUi.linkLine),
        decorationStyle: link.missing ? TextDecorationStyle.dashed : (link.empty ? TextDecorationStyle.dotted : TextDecorationStyle.solid),
      ),
      recognizer: tap,
    );
  }
}

/// 띄운 그림 옆을 흐르는 글 조각 하나 — 문단 하나 또는 목록 항목 하나([item]이 있으면 목록 항목).
class _FlowUnit {
  _FlowUnit(this.spans, {this.item, this.first = false, this.last = false});
  final List<DocSpan> spans;
  final DocListItem? item;

  /// 목록의 첫 · 끝 항목(목록 위 .3em · 아래 .6em 여백이 붙는다).
  final bool first, last;
}

/// 둥근 네모의 끊긴 선 — 사전에 없는 그림 자리(css `.wk-fig.is-missing`의 `1px dashed var(--danger)`).
class _DashedBox extends CustomPainter {
  const _DashedBox({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)).deflate(.5));
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 6) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 3, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBox old) => old.color != color || old.radius != radius;
}

/// 읽어 둔 그림 바이트(열쇠 → 바이트) — 창을 닫았다 열거나 다시 그려도 자료 처리부에 다시 묻지 않게. 오래된 것부터 32장까지만 둔다.
final _docImageCache = <String, Uint8List>{}; // 넣은 차례를 지키는 표(LinkedHashMap) — 앞이 오래된 것

/// 그림 바이트를 열쇠로 — 읽어 둔 것이 있으면 그것, 없으면 [loader]로 읽어 둔다.
Future<Uint8List?> docImageBytes(String key, Future<Uint8List?> Function(String key)? loader) async {
  final hit = _docImageCache.remove(key);
  if (hit != null) {
    _docImageCache[key] = hit;
    return hit;
  }
  if (loader == null) return null;
  final bytes = await loader(key);
  if (bytes != null && bytes.isNotEmpty) {
    _docImageCache[key] = bytes;
    while (_docImageCache.length > 32) {
      _docImageCache.remove(_docImageCache.keys.first);
    }
  }
  return bytes;
}

/// 문서 그림 한 장(상자를 꽉 채움 — 상자의 비율은 그림의 원본 비율). 바이트를 받기 전에는 빈 자리(상자의 바탕색)다.
class DocImage extends StatefulWidget {
  const DocImage({super.key, required this.image, this.loader, this.fit = BoxFit.fill});
  final DocImageRef image;
  final Future<Uint8List?> Function(String key)? loader;
  final BoxFit fit;

  @override
  State<DocImage> createState() => _DocImageState();
}

class _DocImageState extends State<DocImage> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(DocImage old) {
    super.didUpdateWidget(old);
    if (old.image.key != widget.image.key) _load();
  }

  Future<void> _load() async {
    final key = widget.image.key;
    _bytes = _docImageCache[key];
    if (_bytes != null) return;
    final bytes = await docImageBytes(key, widget.loader);
    if (mounted && key == widget.image.key) setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) return const SizedBox.expand();
    return SizedBox.expand(
      child: Image.memory(bytes, fit: widget.fit, gaplessPlayback: true, filterQuality: FilterQuality.medium, excludeFromSemantics: true),
    );
  }
}

/// 본문 안에서 자리를 오가는 작은 단추 — 각주 표와 각주 목록의 `[번호]`.
/// [anchor]를 주면 그 자리가 되돌아올 표가 된다.
class _DocJump extends StatelessWidget {
  const _DocJump({this.anchor, required this.onTap, required this.label, required this.child});

  final GlobalKey? anchor;
  final VoidCallback onTap;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: Semantics(
      button: true,
      label: label,
      child: GestureDetector(key: anchor, behavior: HitTestBehavior.opaque, onTap: onTap, child: child),
    ),
  );
}

// ── 표의 격자 ─────────────────────────────────────────────────────────────────────────────────
//  [Table]은 칸 합치기를 모르고, `Expanded(flex:)`는 칸 폭을 고르게만 나눈다. 그래서 표만 따로 쌓는다:
//  ① 칸마다 글에 맞는 폭(`getMaxIntrinsicWidth`)을 재어 칸 폭으로 삼고, 합친 칸이 더 넓으면 그만큼 나눠 더한다
//  ② 표가 자리보다 넓으면 줄이되 낱말 하나보다 좁아지지 않게(`getMinIntrinsicWidth`) 넉넉한 칸부터 줄인다
//  ③ 그 폭에서 줄마다 높이를 재고, 세로로 합친 칸이 더 높으면 그만큼 나눠 더한다.

class _DocGridParentData extends ContainerBoxParentData<RenderBox> {}

/// 표 하나를 격자로 쌓는다. [children]은 [DocGrid.cells]와 같은 차례여야 한다.
class DocTableGrid extends MultiChildRenderObjectWidget {
  const DocTableGrid({super.key, required this.grid, required super.children});

  final DocGrid grid;

  @override
  RenderObject createRenderObject(BuildContext context) => DocTableGridBox(grid);

  @override
  void updateRenderObject(BuildContext context, DocTableGridBox renderObject) => renderObject.grid = grid;
}

class DocTableGridBox extends RenderBox with ContainerRenderObjectMixin<RenderBox, _DocGridParentData>, RenderBoxContainerDefaultsMixin<RenderBox, _DocGridParentData> {
  DocTableGridBox(this._grid);

  DocGrid _grid;
  DocGrid get grid => _grid;
  set grid(DocGrid value) {
    if (identical(_grid, value)) return;
    _grid = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! _DocGridParentData) child.parentData = _DocGridParentData();
  }

  List<RenderBox> get _kids {
    final out = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      out.add(child);
      child = (child.parentData! as _DocGridParentData).nextSibling;
    }
    return out;
  }

  /// 한 칸이 걸친 칸들의 폭 합(가운데 테두리는 칸 안에 들어 있어 더할 것이 없다).
  static double _spanOf(List<double> widths, int from, int count) {
    double sum = 0;
    for (int i = from; i < from + count && i < widths.length; i++) {
      sum += widths[i];
    }
    return sum;
  }

  /// 합친 칸이 제 몫보다 넓으면(높으면) 모자란 만큼을 걸친 칸들에 고르게 나눠 더한다.
  static void _spread(List<double> sizes, int from, int count, double want) {
    final have = _spanOf(sizes, from, count);
    if (want <= have || count <= 0) return;
    final add = (want - have) / count;
    for (int i = from; i < from + count && i < sizes.length; i++) {
      sizes[i] += add;
    }
  }

  /// 칸 폭 — 글에 맞추고, 넘치면 줄인다.
  List<double> _columns(double maxWidth) {
    final kids = _kids;
    final widths = List<double>.filled(_grid.columns, 0);
    final wanted = <double>[];
    for (int i = 0; i < kids.length; i++) {
      final want = kids[i].getMaxIntrinsicWidth(double.infinity);
      wanted.add(want);
      final p = _grid.cells[i];
      if (p.colspan == 1 && p.column < widths.length) widths[p.column] = math.max(widths[p.column], want);
    }
    for (int i = 0; i < kids.length; i++) {
      final p = _grid.cells[i];
      if (p.colspan > 1) _spread(widths, p.column, p.colspan, wanted[i]);
    }
    var total = widths.fold<double>(0, (a, b) => a + b);
    if (!maxWidth.isFinite || total <= maxWidth || total <= 0) return widths;
    // 넘치면: 낱말 하나의 폭(가장 좁게 접었을 때)을 바닥으로 두고 넉넉한 칸부터 줄인다.
    final floor = List<double>.filled(_grid.columns, 0);
    for (int i = 0; i < kids.length; i++) {
      final p = _grid.cells[i];
      if (p.colspan == 1 && p.column < floor.length) floor[p.column] = math.max(floor[p.column], kids[i].getMinIntrinsicWidth(double.infinity));
    }
    final floorTotal = floor.fold<double>(0, (a, b) => a + b);
    if (floorTotal >= maxWidth) {
      final scale = maxWidth / total;
      return [for (final w in widths) w * scale];
    }
    final over = total - maxWidth, slack = total - floorTotal;
    return [for (int i = 0; i < widths.length; i++) widths[i] - over * (widths[i] - floor[i]) / slack];
  }

  /// 칸 폭이 정해진 뒤의 줄 높이.
  List<double> _rows(List<double> widths) {
    final kids = _kids;
    final heights = List<double>.filled(_grid.rows, 0);
    final wanted = <double>[];
    for (int i = 0; i < kids.length; i++) {
      final p = _grid.cells[i];
      final want = kids[i].getMinIntrinsicHeight(_spanOf(widths, p.column, p.colspan));
      wanted.add(want);
      if (p.rowspan == 1 && p.row < heights.length) heights[p.row] = math.max(heights[p.row], want);
    }
    for (int i = 0; i < kids.length; i++) {
      final p = _grid.cells[i];
      if (p.rowspan > 1) _spread(heights, p.row, p.rowspan, wanted[i]);
    }
    return heights;
  }

  Size _measure(BoxConstraints constraints) {
    final widths = _columns(constraints.maxWidth);
    final heights = _rows(widths);
    return constraints.constrain(Size(widths.fold<double>(0, (a, b) => a + b), heights.fold<double>(0, (a, b) => a + b)));
  }

  @override
  double computeMinIntrinsicWidth(double height) => _kids.isEmpty ? 0 : _columns(double.infinity).fold<double>(0, (a, b) => a + b);

  @override
  double computeMaxIntrinsicWidth(double height) => computeMinIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) => _kids.isEmpty ? 0 : _rows(_columns(width)).fold<double>(0, (a, b) => a + b);

  @override
  double computeMaxIntrinsicHeight(double width) => computeMinIntrinsicHeight(width);

  @override
  Size computeDryLayout(BoxConstraints constraints) => _kids.isEmpty ? constraints.smallest : _measure(constraints);

  @override
  void performLayout() {
    final kids = _kids;
    if (kids.isEmpty) {
      size = constraints.smallest;
      return;
    }
    final widths = _columns(constraints.maxWidth);
    final heights = _rows(widths);
    final left = List<double>.filled(widths.length + 1, 0);
    for (int i = 0; i < widths.length; i++) {
      left[i + 1] = left[i] + widths[i];
    }
    final top = List<double>.filled(heights.length + 1, 0);
    for (int i = 0; i < heights.length; i++) {
      top[i + 1] = top[i] + heights[i];
    }
    for (int i = 0; i < kids.length; i++) {
      final p = _grid.cells[i];
      final w = _spanOf(widths, p.column, p.colspan), h = _spanOf(heights, p.row, p.rowspan);
      kids[i].layout(BoxConstraints.tightFor(width: math.max(0, w), height: math.max(0, h)), parentUsesSize: true);
      (kids[i].parentData! as _DocGridParentData).offset = Offset(left[math.min(p.column, widths.length)], top[math.min(p.row, heights.length)]);
    }
    size = constraints.constrain(Size(left.last, top.last));
  }

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);
}

/// 목차 — 왼쪽 칸과 `[목차]` 자리가 함께 쓴다.
class DocToc extends StatelessWidget {
  const DocToc({super.key, required this.headings, required this.onTap, this.size = 12.5});

  final List<DocHeading> headings;
  final Future<void> Function(String id) onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (headings.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '목차',
          style: TextStyle(fontSize: size, height: 1.8, fontWeight: FontWeight.w700, color: Ui.text),
        ),
        const SizedBox(height: 4),
        for (final h in headings)
          Padding(
            padding: EdgeInsets.only(left: size * (h.depth <= 1 ? 0 : (h.depth == 2 ? .9 : (h.depth == 3 ? 1.8 : 2.7)))),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(h.id),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${h.number}. ',
                        style: TextStyle(fontSize: size, height: 1.8, color: Ui.text3),
                      ),
                      TextSpan(
                        text: h.plain,
                        style: TextStyle(fontSize: size, height: 1.8, color: Ui.accent),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// `{{{#!folding 제목 … }}}` — 눌러 펼치는 상자.
class _DocFoldBox extends StatefulWidget {
  const _DocFoldBox({required this.summary, required this.body});
  final Widget summary;
  final List<Widget> body;

  @override
  State<_DocFoldBox> createState() => _DocFoldBoxState();
}

class _DocFoldBoxState extends State<_DocFoldBox> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: 8),
    decoration: BoxDecoration(
      color: Ui.surface2,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Ui.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(_open ? '▾' : '▸', style: const TextStyle(fontSize: 12, height: 1.6, color: Ui.text2)),
                  ),
                  Expanded(child: widget.summary),
                ],
              ),
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: widget.body),
          ),
      ],
    ),
  );
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  4. 문서 창
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 문서(위키) 창. `bus.slot('doc')`에 실린 열쇠를 듣고 열리고 닫힌다.
/// Stack의 자식으로 놓는다 — 닫혀 있으면 아무 자리도 차지하지 않고, 열리면 그 Stack을 덮는다.
// ── 문서 대문 ───────────────────────────────────────────────────────────────────────────────────

/// 대문의 갈래 차례와 이름 — 자료 처리부 `doc_list`의 `group`(항목 기록의 종류 또는 열쇠 앞머리) → 화면 이름.
/// 같은 이름은 한 묶음이다(사건 · 조약). 표에 없는 갈래는 맨 끝 '기타'.
const docFrontGroups = <(String, String)>[
  ('period', '나라'), ('event', '사건'), ('treaty', '사건'), ('figure', '인물'), ('dynasty', '왕조'), ('house', '가문'),
  ('surname', '성씨'), ('organ', '기관'), ('group', '단체'), ('institution', '제도'), ('culture', '문화'), ('epoch', '시대 구분'),
  ('scope', '대범위'), ('cell', '칸'), ('track', '트랙'), ('people', '민족'), ('category', '분류'), ('place', '지명'),
  ('map', '지도'), ('view', '모아 보기 판'),
];

/// 대문의 카드 하나(`doc_list`의 줄 하나).
@immutable
class DocFrontItem {
  const DocFrontItem({required this.key, required this.title, this.meta = '', this.group = '', this.lead = '', this.subs = 0, this.at});

  final String key, title, meta, group;

  /// 본문 앞부분을 푼 글(문법 · 제목 · 각주를 뺀 첫 문단들).
  final String lead;

  /// 하위 문서 수.
  final int subs;

  /// 차례를 매길 때(분) — 기간의 시작 또는 사건의 때. 없으면 이름 차례로 뒤에.
  final double? at;

  /// `doc_list`의 답 → 카드들(이름이 없는 줄은 뺀다).
  static List<DocFrontItem> listFrom(Object? answer) {
    final items = answer is Map ? answer['items'] : null;
    if (items is! List) return const [];
    final out = <DocFrontItem>[];
    for (final one in items) {
      if (one is! Map) continue;
      final key = '${one['key'] ?? ''}', title = '${one['title'] ?? ''}'.trim();
      if (key.isEmpty || title.isEmpty) continue;
      final span = one['span'], at = one['at'];
      out.add(DocFrontItem(
        key: key,
        title: title,
        meta: '${one['meta'] ?? ''}',
        group: '${one['group'] ?? ''}',
        lead: docLead('${one['head'] ?? ''}'),
        subs: one['subs'] is num ? (one['subs'] as num).toInt() : 0,
        at: span is List && span.isNotEmpty && span.first is num ? (span.first as num).toDouble() : (at is num ? at.toDouble() : null),
      ));
    }
    return out;
  }

  /// 갈래 이름별로 묶는다 — 갈래는 [docFrontGroups]의 차례, 안에서는 때 → 이름 차례.
  static List<(String, List<DocFrontItem>)> sections(List<DocFrontItem> items) {
    final names = <String>[];
    for (final g in docFrontGroups) {
      if (!names.contains(g.$2)) names.add(g.$2);
    }
    final byName = <String, List<DocFrontItem>>{};
    for (final item in items) {
      final name = docFrontGroups.firstWhere((g) => g.$1 == item.group, orElse: () => ('', '기타')).$2;
      (byName[name] ??= []).add(item);
    }
    int order(DocFrontItem a, DocFrontItem b) {
      final x = a.at, y = b.at;
      if (x != null && y != null && x != y) return x.compareTo(y);
      if ((x == null) != (y == null)) return x == null ? 1 : -1;
      return a.title.compareTo(b.title);
    }

    return [
      for (final name in [...names, '기타'])
        if (byName[name] != null) (name, byName[name]!..sort(order)),
    ];
  }
}

/// 문서 글 앞부분을 카드에 쓸 맨글로 — 제목 · 표 · 목차 · 각주를 빼고 문단과 목록의 글만 이어 붙인다.
String docLead(String head) {
  if (head.isEmpty) return '';
  final body = parseDocBody(head);
  final out = StringBuffer();
  void spans(List<DocSpan> list) {
    for (final s in list) {
      if (s.footnote > 0) continue;
      out.write(s.lineBreak ? ' ' : s.text);
    }
    out.write(' ');
  }

  for (final node in body.nodes) {
    if (node is DocParagraph) spans(node.spans);
    if (node is DocList) {
      for (final item in node.items) {
        spans(item.spans);
      }
    }
    if (out.length > 200) break;
  }
  return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// 대문의 카드: 흰 바탕 · 1px 먹 20% 테 · 둥근 6 · 올리면 먹 8% — 이름(굵게) · 곁글(먹 60%) · 앞부분(명조 3줄) · 하위 문서 수.
class DocFrontCard extends StatefulWidget {
  const DocFrontCard({super.key, required this.item, required this.onTap});
  final DocFrontItem item;
  final VoidCallback onTap;

  @override
  State<DocFrontCard> createState() => _DocFrontCardState();
}

class _DocFrontCardState extends State<DocFrontCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Semantics(
      button: true,
      label: item.title,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: Motion.microMs),
            curve: Ui.ease,
            height: DocUi.frontCardHeight,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: _hover ? Ui.ink8 : Ui.surface,
              borderRadius: BorderRadius.circular(Ui.controlRadius),
              border: Border.all(color: Ui.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: Ui.title, fontFamilyFallback: Ui.titleFallback, fontSize: 16, height: 1.4, fontWeight: FontWeight.w600, color: Ui.text),
                      ),
                    ),
                    if (item.subs > 0) ...[
                      const SizedBox(width: 8),
                      const LineIcon(LineGlyph.file, size: 12, color: Ui.ink40),
                      const SizedBox(width: 3),
                      Text('${item.subs}', style: const TextStyle(fontSize: 12, height: 1.5, color: Ui.ink40)),
                    ],
                  ],
                ),
                if (item.meta.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(item.meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, height: 1.5, color: Ui.text3)),
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: Text(
                    item.lead,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: Ui.serif, fontFamilyFallback: Ui.serifFallback, fontSize: 13.5, height: 1.6, color: Ui.text),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 맨 위 줄의 문서 단추(기호만 — 서가): 문서 대문을 연다. 문서 창이 떠 있는 동안은 반전 채움이고, 누르면 닫는다.
class DocDockButton extends StatelessWidget {
  const DocDockButton({super.key, required this.bus});
  final AppBus bus;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Object?>(
    valueListenable: bus.slot(docSlot),
    builder: (context, value, _) => DockIconButton(
      glyph: LineGlyph.library,
      on: value != null,
      onPressed: () => bus.slot(docSlot).value = value == null ? docFrontKey : null,
      tooltip: '문서 (W)',
      semantics: value == null ? '문서 대문' : '문서 창 닫기',
    ),
  );
}

class DocWindow extends StatefulWidget {
  const DocWindow({super.key, required this.bus, this.padding = DocUi.pane, this.top = 0});

  final AppBus bus;

  /// 창이 덮는 자리의 가장자리 틈. 앱 틀 안에 놓을 때는 맨 위 띠(60)를 더한다.
  final EdgeInsets padding;

  /// 나란히 볼 때 문서 칸의 위 끝(앱 틀의 맨 위 띠 높이 — 집중 모드면 0).
  final double top;

  @override
  State<DocWindow> createState() => DocWindowState();
}

class DocWindowState extends State<DocWindow> with SingleTickerProviderStateMixin {
  late final SurfaceMotion _enter = SurfaceMotion();
  Animation<double> get _curve => _enter;

  final _history = <String>[];
  final _scroll = ScrollController();
  final _articleKey = GlobalKey<DocArticleState>();

  String _key = '';
  DocRecord? _record;
  DocBody? _body;
  bool _loading = false, _failed = false, _reduceMotion = false;
  int _turn = 0;

  /// 크게 보는 그림(없으면 null) · 막이 보이는가(사라지는 동안은 거짓이고 그림은 남는다).
  DocFigure? _zoom;
  bool _zoomShown = false;

  AppBus get _bus => widget.bus;

  /// 지금 열려 있는 문서의 열쇠(닫혀 있으면 빈 글) — 검사와 앱 틀이 본다.
  String get openKey => _bus.slot(docSlot).value == null ? '' : _key;

  @override
  void initState() {
    super.initState();
    _enter.addStatusListener((_) {
      if (mounted) setState(() {});
    });
    _bus.slot(docSlot).addListener(_onSlot);
    _bus.slot(slotCommand).addListener(_onCommand);
    _bus.slot(docSideSlot).addListener(_onSide);
    _onSlot();
  }

  @override
  void didUpdateWidget(DocWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bus != widget.bus) {
      oldWidget.bus.slot(docSlot).removeListener(_onSlot);
      oldWidget.bus.slot(slotCommand).removeListener(_onCommand);
      oldWidget.bus.slot(docSideSlot).removeListener(_onSide);
      _bus.slot(docSlot).addListener(_onSlot);
      _bus.slot(slotCommand).addListener(_onCommand);
      _bus.slot(docSideSlot).addListener(_onSide);
      _onSlot();
    }
  }

  void _onSide() {
    if (mounted) setState(() {});
  }

  /// 지금 그린 창이 연표 옆 칸인가(창 폭에 따라 덮는 꼴로 물러설 수 있어 그릴 때 정한다).
  bool _sideNow = false;

  /// 나란히 볼 수 있는가 — 나란히를 골랐고, 창이 넓어 문서 칸 왼쪽에 연표가 [DocUi.sideMinTimeline] 넘게 남을 때.
  bool _sideFits(double width) => _bus.slot(docSideSlot).value == true && width - DocUi.sideWidth >= DocUi.sideMinTimeline;

  void _toggleSide() => _bus.slot(docSideSlot).value = !_sideNow;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) _enter.value = _bus.slot(docSlot).value == null ? 0 : 1;
  }

  @override
  void dispose() {
    _bus.slot(docSlot).removeListener(_onSlot);
    _bus.slot(slotCommand).removeListener(_onCommand);
    _bus.slot(docSideSlot).removeListener(_onSide);
    _enter.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ── 여닫기 ────────────────────────────────────────────────────────────────────────────────

  void _onSlot() {
    final value = _bus.slot(docSlot).value;
    final key = value is String ? value.trim() : '';
    if (key.isEmpty) {
      if (_key.isEmpty) return;
      _history.clear();
      _zoom = null;
      _zoomShown = false;
      if (_reduceMotion) {
        _enter.value = 0;
      } else {
        _enter.reverse();
      }
      setState(() {});
      return;
    }
    if (key == _key && _record != null) {
      if (_reduceMotion) {
        _enter.value = 1;
      } else {
        _enter.forward();
      }
      return;
    }
    _load(key);
  }

  /// 단축키 · 메뉴의 명령. `W`(고른 항목의 문서) · 트랙 문서 · Esc.
  void _onCommand() {
    final command = _bus.slot(slotCommand).value;
    if (command is! AppCommand) return;
    if (command.name == Cmd.close) {
      if (_zoom != null) {
        _closeZoom(); // 크게 보기만 닫는다 — 문서 창은 그대로
      } else if (_key.isNotEmpty) {
        close();
      }
      return;
    }
    if (command.name == Cmd.wiki) {
      // 고른 것이 없으면 대문을 연다.
      final uid = command.uid ?? _bus.selection.value?.uid ?? '';
      open(uid.isNotEmpty ? uid : docFrontKey);
      return;
    }
    if (command.name == Cmd.trackWiki && command.trackId != null) open('track:${_trackKey(command.trackId!)}');
  }

  /// 트랙 번호 → 글자 id. `bus.slot('tracks')`는 같은 줄을 글자 열쇠와 번호 열쇠에 함께 두므로
  /// 번호로 찾은 줄과 같은 줄을 가리키는 글자 열쇠를 되찾는다(`app_glue.dart`의 `fillTrackSlots`).
  String _trackKey(int id) {
    final table = _bus.slot('tracks').value;
    if (table is Map) {
      final mine = table['$id'];
      if (mine is Map) {
        for (final one in table.entries) {
          final name = '${one.key}';
          if (name == '$id' || int.tryParse(name) != null) continue;
          final row = one.value;
          if (row is Map && row['name'] == mine['name'] && row['color'] == mine['color']) return name;
        }
      }
    }
    return '$id';
  }

  /// 문서 하나를 연다(바깥에서도 부를 수 있다). [push]가 거짓이면 '이전 문서'에 쌓지 않는다.
  void open(String key, {bool push = true}) {
    if (key.isEmpty) return;
    if (push && _bus.slot(docSlot).value != null && _key.isNotEmpty && _key != key) _history.add(_key);
    _bus.slot(docSlot).value = key;
    if (key == _key) _load(key); // 같은 열쇠를 다시 부르면 슬롯이 알리지 않으므로 여기서
  }

  void close() {
    _history.clear();
    _bus.slot(docSlot).value = null;
  }

  void _back() {
    if (_history.isEmpty) return;
    final prev = _history.removeLast();
    _bus.slot(docSlot).value = prev;
    if (prev == _key) _load(prev);
  }

  /// 대문에 늘어놓을 문서(아직 읽지 않았으면 null).
  List<DocFrontItem>? _front;

  /// 대문 — 서재의 문서를 한 번에 묻는다(`doc_list`). 문서가 하나도 없어도 창은 열고 그 까닭을 적는다.
  Future<void> _loadFront() async {
    final turn = ++_turn;
    setState(() {
      _key = docFrontKey;
      _loading = true;
      _failed = false;
    });
    if (_reduceMotion) {
      _enter.value = 1;
    } else {
      _enter.forward();
    }
    List<DocFrontItem> items;
    try {
      items = DocFrontItem.listFrom(await _bus.ask({'op': 'doc_list'}));
    } catch (_) {
      items = const []; // 옛 자료 처리부(doc_list 없음)도 '문서가 없습니다'로
    }
    if (!mounted || turn != _turn) return;
    setState(() {
      _front = items;
      _record = DocRecord(key: docFrontKey, title: '문서 대문', meta: items.isEmpty ? '' : '문서 ${items.length}개');
      _body = null;
      _zoom = null;
      _zoomShown = false;
      _loading = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _load(String key) async {
    if (key == docFrontKey) return _loadFront();
    final turn = ++_turn;
    setState(() {
      _key = key;
      _loading = true;
      _failed = false;
    });
    if (_reduceMotion) {
      _enter.value = 1;
    } else {
      _enter.forward();
    }
    Map<String, dynamic>? answer;
    try {
      answer = await _bus.ask({'op': 'entity', 'uid': 'doc:$key'});
    } catch (_) {
      answer = null;
    }
    if (!mounted || turn != _turn) return;
    final record = answer == null ? null : DocRecord.fromAnswer(answer);
    if (record == null) {
      // 지금 연표와 같이 — 없는 문서는 창을 열지 않고 한 줄로 알린다(viewer.js 2842).
      _bus.slot(slotNotice).value = '문서를 찾을 수 없습니다.';
      _history.clear();
      _enter.value = 0;
      setState(() {
        _key = '';
        _record = null;
        _body = null;
        _loading = false;
        _failed = true;
      });
      _bus.slot(docSlot).value = null;
      return;
    }
    setState(() {
      _record = record;
      _body = parseDocBody(record.body, links: record.links, images: record.images);
      _zoom = null;
      _zoomShown = false;
      _loading = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  /// 문서 그림 바이트 — 앱 틀이 이은 [docBlob](`archive_blob` · 바이트 그대로)이 먼저, 없으면 `{"op":"blob"}`의 base64 답.
  Future<Uint8List?> _loadImage(String key) async {
    final direct = docBlob;
    if (direct != null) {
      final bytes = await direct(key);
      if (bytes != null && bytes.isNotEmpty) return bytes;
    }
    try {
      final answer = await _bus.ask({'op': 'blob', 'key': key});
      final data = answer['data'];
      return data is String ? base64Decode(data) : null;
    } catch (_) {
      return null;
    }
  }

  /// 그림 크게 보기 — 막이 나타나는 움직임(`--t-in`)을 보이려고 한 장면 뒤에 켠다.
  void _openZoom(DocFigure figure) {
    if (figure.image == null) return;
    setState(() {
      _zoom = figure;
      _zoomShown = _reduceMotion;
    });
    if (!_reduceMotion) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _zoom == figure) setState(() => _zoomShown = true);
      });
    }
  }

  void _closeZoom() {
    if (_zoom == null) return;
    if (_reduceMotion) {
      setState(() {
        _zoom = null;
        _zoomShown = false;
      });
    } else {
      setState(() => _zoomShown = false); // 사라짐(`--t-out`)이 끝나면 [_zoomLayer]의 onEnd가 그림을 내린다
    }
  }

  /// 크게 보기 막 — 화면 전체(paper) · 그림은 원본 크기까지(화면 − 96 · − 140 안에서 줄임) · 아래 설명 · 오른쪽 위 닫기.
  Widget _zoomLayer(BoxConstraints box) {
    final figure = _zoom!, image = figure.image!;
    final maxW = math.max(1.0, box.maxWidth - 96), maxH = math.max(1.0, box.maxHeight - 140);
    final natW = image.width > 0 ? image.width.toDouble() : maxW;
    final natH = natW * image.ratio;
    final scale = [1.0, maxW / natW, maxH / natH].reduce(math.min);
    final caption = image.captionLine;
    return AnimatedOpacity(
      opacity: _zoomShown ? 1 : 0,
      duration: _reduceMotion ? Duration.zero : (_zoomShown ? DocUi.zoomIn : DocUi.zoomOut),
      curve: Ui.ease,
      onEnd: () {
        if (!_zoomShown && mounted) setState(() => _zoom = null);
      },
      child: Semantics(
        label: '그림 크게 보기',
        scopesRoute: true,
        explicitChildNodes: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _closeZoom,
          child: ColoredBox(
            color: DocUi.zoomBack,
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () {}, // 그림을 눌러서는 닫히지 않는다(css: 그림 밖을 누르면 닫힘)
                        child: Container(
                          width: natW * scale,
                          height: natH * scale,
                          decoration: BoxDecoration(color: Ui.paper, borderRadius: BorderRadius.circular(DocUi.figureRadius)),
                          foregroundDecoration: BoxDecoration(borderRadius: BorderRadius.circular(DocUi.figureRadius), border: Border.all(color: Ui.ink20)),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(DocUi.figureRadius),
                            child: DocImage(image: image, loader: _loadImage),
                          ),
                        ),
                      ),
                      if (caption.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: Text(caption, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13.5, height: 1.5, color: DocUi.zoomText)),
                          ),
                        ),
                    ],
                  ),
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: Container(
                    decoration: BoxDecoration(color: Ui.paper, borderRadius: BorderRadius.circular(Ui.controlRadius)),
                    foregroundDecoration: BoxDecoration(borderRadius: BorderRadius.circular(Ui.controlRadius), border: Border.all(color: Ui.ink20)),
                    child: ShellButton(
                      onPressed: _closeZoom,
                      tooltip: '닫기',
                      width: 32,
                      height: 32,
                      radius: Ui.controlRadius,
                      padding: EdgeInsets.zero,
                      child: const Text('✕', style: TextStyle(fontSize: 13, color: Ui.ink)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// `🎯 연표에서` — 그 항목을 고르고 그 기간으로 데려간다. 나란히 보는 중이면 문서는 그대로 둔다(연표가 옆에 보이므로).
  void _goToTimeline() {
    final record = _record;
    if (record == null) return;
    if (record.uid.isNotEmpty) _bus.select(record.uid, cell: record.ref.isEmpty ? null : record.ref);
    final span = record.span;
    if (span != null) _bus.goTo(span[0], span[1] == span[0] ? span[0] + 1 : span[1], ring: record.uid.isEmpty ? null : record.uid);
    if (!_sideNow) close();
  }

  void _follow(DocLink link) {
    if (link.url.isNotEmpty) {
      _openUrl(link.url);
      return;
    }
    if (link.missing) {
      _bus.slot(slotNotice).value = '"${link.name}" 항목이 연표에 없습니다. 그 항목이 든 DLC가 꺼져 있을 수 있습니다.';
      return;
    }
    open(link.key);
  }

  /// 바깥 고리(`[[https://…|글]]`) — [docOpenUrl]을 앱 틀이 채워 두었으면 그것으로 열고,
  /// 아니면 주소를 복사해 안내 한 줄로 알린다(이 시제품에는 바깥 주소를 여는 패키지가 없다 — 보고서의 남은 것).
  Future<void> _openUrl(String url) async {
    final open = docOpenUrl;
    if (open != null && await open(url)) return;
    try {
      await Clipboard.setData(ClipboardData(text: url));
      _bus.slot(slotNotice).value = '바깥 주소를 복사했습니다 — $url';
    } catch (_) {
      _bus.slot(slotNotice).value = '바깥 주소 — $url';
    }
  }

  // ── 그리기 ────────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_key.isEmpty || (_bus.slot(docSlot).value == null && _enter.isDismissed)) return const SizedBox.shrink();
    final closed = _bus.slot(docSlot).value == null;
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: closed,
        child: ExcludeSemantics(
          excluding: closed,
          child: ExcludeFocus(
            excluding: closed,
            child: Shortcuts(
              shortcuts: const {SingleActivator(LogicalKeyboardKey.escape): DismissIntent()},
              child: Actions(
                // Esc: 그림을 크게 보고 있으면 그것만 닫고, 아니면 문서 창을 닫는다.
                actions: {DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) => _zoom != null ? _closeZoom() : close())},
                child: Focus(
                  autofocus: true,
                  child: LayoutBuilder(
                    builder: (context, box) {
                      _sideNow = _sideFits(box.maxWidth);
                      return Stack(
                        children: [
                          // 나란히: 연표 오른쪽 · 상세 칸 자리에 붙은 칸(상세 창은 그 뒤에 남는다) — 칸 밖은 비어 있어 연표가 그대로 눌린다.
                          if (_sideNow)
                            Positioned(top: widget.top, right: 0, bottom: 0, width: DocUi.sideWidth, child: _window())
                          else
                            Positioned.fill(child: Padding(padding: widget.padding, child: _window())),
                          // 크게 보기 막은 문서 창의 여백 밖 화면 전체를 덮는다.
                          if (_zoom != null) Positioned.fill(child: _zoomLayer(box)),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _window() => AnimatedBuilder(
    animation: _curve,
    builder: (context, child) => Opacity(
      opacity: _enter.opacity,
      child: Transform.translate(offset: Offset(DocUi.slide * (1 - _curve.value), 0), child: child),
    ),
    child: _sideNow
        // 연표 옆 칸: 상세 칸과 같은 꼴 — paper 바탕 · 왼쪽 1px 선 · 모서리와 그림자 없음.
        ? DecoratedBox(
            decoration: const BoxDecoration(
              color: Ui.surface,
              border: Border(left: BorderSide(color: Ui.line)),
            ),
            child: _column(),
          )
        : DecoratedBox(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(DocUi.radius), boxShadow: Ui.shadow),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(DocUi.radius),
              child: ColoredBox(color: Ui.surface, child: _column()),
            ),
          ),
  );

  Widget _column() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [_head(), ?_subs(), Expanded(child: _key == docFrontKey ? _frontBody() : _body2())],
  );

  /// 대문의 몸통: 갈래마다 머리글(이름 · 수 · 아래 1px 선)과 카드 격자 — 한 줄의 카드 수는 폭이 정한다(나란히 칸이면 둘).
  Widget _frontBody() {
    final items = _front;
    if (items == null || items.isEmpty) {
      return Center(
        child: Text(
          _loading ? '읽는 중…' : '이 서재에는 문서가 없습니다. 문서는 DLC 메이커에서 씁니다.',
          style: const TextStyle(fontSize: 14, height: 1.5, color: Ui.text3),
        ),
      );
    }
    final sections = DocFrontItem.sections(items);
    return LayoutBuilder(
      builder: (context, box) {
        final inner = math.max(1.0, box.maxWidth - DocUi.bodyPad.horizontal);
        final cols = math.max(1, ((inner + DocUi.frontGap) / (DocUi.frontCardMin + DocUi.frontGap)).floor());
        final cardWidth = (inner - DocUi.frontGap * (cols - 1)) / cols;
        return SingleChildScrollView(
          controller: _scroll,
          padding: DocUi.bodyPad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (name, list) in sections) ...[
                _frontHeading(name, list.length),
                Wrap(
                  spacing: DocUi.frontGap,
                  runSpacing: DocUi.frontGap,
                  children: [
                    for (final item in list) SizedBox(width: cardWidth, child: DocFrontCard(item: item, onTap: () => open(item.key))),
                  ],
                ),
                const SizedBox(height: DocUi.frontSectionGap),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _frontHeading(String name, int count) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.only(bottom: 6),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Ui.line)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(name, style: const TextStyle(fontFamily: Ui.title, fontFamilyFallback: Ui.titleFallback, fontSize: 17, height: 1.4, fontWeight: FontWeight.w700, color: Ui.text)),
        const SizedBox(width: 6),
        Text('$count', style: const TextStyle(fontSize: 13, height: 1.4, color: Ui.ink40)),
      ],
    ),
  );

  Widget _head() {
    final record = _record;
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Ui.line)),
      ),
      child: Padding(
        padding: DocUi.headPad,
        child: Row(
          children: [
            Opacity(
              opacity: _history.isEmpty ? .45 : 1,
              child: ShellButton(
                width: 32,
                padding: EdgeInsets.zero,
                tooltip: '이전 문서',
                onPressed: _history.isEmpty ? null : _back,
                child: const Text('←', style: TextStyle(fontSize: 15)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    record?.title ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: Ui.title, fontFamilyFallback: Ui.titleFallback, fontSize: 22, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: -.55, color: Ui.text),
                  ),
                  if ((record?.meta ?? '').isNotEmpty || (record?.pack ?? '').isNotEmpty)
                    Text(
                      [if ((record?.meta ?? '').isNotEmpty) record!.meta, if ((record?.pack ?? '').isNotEmpty) '${record!.pack}의 문서'].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, height: 1.5, color: Ui.text3),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (record != null && (record.uid.isNotEmpty || record.span != null))
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: DetailSmallButton('연표에서', icon: LineGlyph.locate, onTap: _goToTimeline),
              ),
            // 대문(서가) · 나란히 ↔ 넓게: 기호만(선 아이콘) — 풀이는 올렸을 때의 이름으로.
            if (_key != docFrontKey) ...[
              ShellButton(
                width: 32,
                padding: EdgeInsets.zero,
                tooltip: '대문',
                onPressed: () => open(docFrontKey),
                child: const LineIcon(LineGlyph.library, size: 16),
              ),
              const SizedBox(width: 4),
            ],
            ShellButton(
              width: 32,
              padding: EdgeInsets.zero,
              tooltip: _sideNow ? '넓게 보기' : '나란히 보기',
              onPressed: _toggleSide,
              child: LineIcon(_sideNow ? LineGlyph.expand : LineGlyph.panelRight, size: 16),
            ),
            const SizedBox(width: 4),
            ShellButton(
              width: 32,
              padding: EdgeInsets.zero,
              tooltip: '닫기',
              onPressed: close,
              child: const Text('✕', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  /// 빵 부스러기와 하위 문서 칩 줄. 보여 줄 길도 하위 문서도 없으면 줄을 두지 않는다.
  Widget? _subs() {
    final record = _record;
    if (record == null || (record.crumbs.isEmpty && record.subs.isEmpty)) return null;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: DocUi.subsBack,
        border: Border(bottom: BorderSide(color: Ui.line)),
      ),
      child: Padding(
        padding: DocUi.subsPad,
        child: Wrap(
          spacing: 14,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (record.crumbs.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final c in record.crumbs) ...[
                    _Linky(text: c.label, onTap: () => open(c.key)),
                    const Text('›', style: TextStyle(fontSize: 13, height: 1.5, color: Ui.text3)),
                  ],
                  Text(
                    record.last.isEmpty ? record.title : record.last,
                    style: const TextStyle(fontSize: 13, height: 1.5, fontWeight: FontWeight.w600, color: Ui.text),
                  ),
                ],
              ),
            if (record.subs.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final s in record.subs) DocChip(text: s.label, onTap: () => open(s.key))],
              ),
          ],
        ),
      ),
    );
  }

  Widget _body2() {
    final record = _record, body = _body;
    if (record == null || body == null) {
      return Center(
        child: Text(_failed ? '문서를 찾을 수 없습니다.' : (_loading ? '읽는 중…' : ''), style: const TextStyle(fontSize: 14, color: Ui.text3)),
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= DocUi.narrow && body.toc.isNotEmpty;
        final article = SingleChildScrollView(
          controller: _scroll,
          // 목차가 옆에 서면 왼쪽 여백은 목차 칸이 이미 두었다(지금 연표의 `.wiki-body`는 여백 하나를 둘이 나눠 쓴다).
          padding: wide ? const EdgeInsets.fromLTRB(0, 22, 28, 22) : DocUi.bodyPad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!wide && body.toc.isNotEmpty)
                Padding(padding: const EdgeInsets.only(bottom: 14), child: _tocBox(body)),
              if (record.empty) ..._emptyBody(record) else DocArticle(key: _articleKey, body: body, onLink: _follow, loadImage: _loadImage, onZoom: _openZoom),
              if (body.categories.isNotEmpty) _categories(body.categories),
              if (record.back.isNotEmpty) _backlinks(record.back),
            ],
          ),
        );
        if (!wide) return article;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 22, 0, 22),
              child: SizedBox(
                width: DocUi.tocWidth,
                child: SingleChildScrollView(child: _tocBox(body)),
              ),
            ),
            const SizedBox(width: DocUi.bodyGap),
            Expanded(child: article),
          ],
        );
      },
    );
  }

  Widget _tocBox(DocBody body) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(color: Ui.surface2, borderRadius: BorderRadius.circular(14)),
    child: DocToc(headings: body.toc, onTap: (id) async => _articleKey.currentState?.jumpTo(id)),
  );

  List<Widget> _emptyBody(DocRecord record) => [
    const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Text('아직 문서가 없습니다.', style: TextStyle(fontSize: 15, height: 1.6, color: Ui.text3)),
    ),
    if (record.desc.isNotEmpty) ...[
      const Padding(
        padding: EdgeInsets.only(top: 14, bottom: 4),
        child: Text('설명', style: TextStyle(fontSize: 13, height: 1.5, color: Ui.text3)),
      ),
      Text(
        record.desc,
        style: const TextStyle(fontSize: DocUi.font, height: DocUi.lineHeight, color: Ui.text),
      ),
    ],
  ];

  /// `[[분류:…]]` — 맨 아래의 분류 줄(.88em · 여백은 제 글자 크기 기준).
  Widget _categories(List<String> names) {
    const size = DocUi.font * .88;
    const style = TextStyle(fontSize: size, height: 1.8, color: Ui.text3);
    return Container(
      margin: const EdgeInsets.only(top: size * 1.2),
      padding: const EdgeInsets.only(top: size * .5),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Ui.line)),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('분류:', style: style),
          for (final n in names)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: Ui.surface2,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: Ui.line),
              ),
              child: Text(n, style: style),
            ),
        ],
      ),
    );
  }

  Widget _backlinks(List<DocCrumb> back) => Container(
    margin: const EdgeInsets.only(top: 20),
    padding: const EdgeInsets.only(top: 8),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Ui.line)),
    ),
    child: Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text(
          '이 문서를 가리키는 문서',
          style: TextStyle(fontSize: 12.5, height: 1.8, fontWeight: FontWeight.w700, color: Ui.text3),
        ),
        for (final b in back) _Linky(text: b.label, onTap: () => open(b.key), size: 12.5, height: 1.8),
      ],
    ),
  );
}

/// `.chip.is-doc` — 앞에 11px `📄`가 붙는 알약(높이 28 · 둥근 999 · 12.5px/500 · 바탕 `--surface-2`).
/// 상세 창의 [DetailChip]을 쓰지 않는 까닭: 그 부품은 `Wrap` 안에서 가로로 늘어난다
/// (`AnimatedContainer`에 `alignment`가 있어 느슨한 폭 제약을 통째로 받는다 — 총괄 확인거리).
class DocChip extends StatefulWidget {
  const DocChip({super.key, required this.text, this.onTap});
  final String text;
  final VoidCallback? onTap;

  @override
  State<DocChip> createState() => _DocChipState();
}

class _DocChipState extends State<DocChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final body = AnimatedContainer(
      duration: const Duration(milliseconds: Motion.microMs),
      curve: Ui.ease,
      // 칩: 높이 32 · 둥근 6 · 채움 없이 ink20 선(올리면 ink8) — 상세 창의 칩과 같은 꼴.
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: widget.onTap != null && _hover ? Ui.ink8 : null, borderRadius: BorderRadius.circular(Ui.controlRadius)),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Ui.controlRadius),
        border: Border.all(color: Ui.ink20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const LineIcon(LineGlyph.file, size: 13, color: Ui.ink60),
          const SizedBox(width: 6),
          Text(
            widget.text,
            style: const TextStyle(fontSize: 13, height: 1.5, fontWeight: FontWeight.w400, color: Ui.text),
          ),
        ],
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

/// `.linky` — 밑줄만 그은 글자 단추.
class _Linky extends StatelessWidget {
  const _Linky({required this.text, required this.onTap, this.size = 13, this.height = 1.5});
  final String text;
  final VoidCallback onTap;
  final double size, height;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: Semantics(
      button: true,
      label: text,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Text(
          text,
          style: TextStyle(fontSize: size, height: height, color: Ui.accent, decoration: TextDecoration.underline, decorationColor: Ui.accent),
        ),
      ),
    ),
  );
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  5. 하위 문서 칩 — 상세 창에 다는 부품
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 그 항목 기록이 **새 내보내기로 만든 것**인가 — 미리 푼 값(`x_docs` · `x_members` …)이 하나라도 있으면 그렇다.
/// 새 기록에서는 `x_docs`가 없는 것이 곧 '하위 문서 없음'이라 [DocChips]가 `doc:<uid>`를 되묻지 않는다
/// (되물으면 없는 기록을 묻는 실패가 앱의 실패 기록에 쌓인다 — 검증 보고서 9-2절의 남은 하나).
bool docRecordIsNew(Map<String, dynamic>? json) {
  if (json == null) return false;
  for (final key in json.keys) {
    if (key.startsWith('x_')) return true;
  }
  return false;
}

/// 항목 상세 창 맨 아래의 '하위 문서' 묶음(명세 06의 2-3절 ㈎ 23번 · 지금 연표의 `subdocsHTML`).
/// 항목 기록의 `x_docs`를 읽는다. 옛 저장소의 기록(미리 푼 `x_` 값이 하나도 없는 것)일 때만
/// `doc:<uid>` 기록의 `subs`로 되묻는다. 하위 문서가 없으면 아무것도 그리지 않는다.
class DocChips extends StatefulWidget {
  const DocChips({super.key, required this.bus, required this.uid, this.json});

  final AppBus bus;

  /// 항목 기록의 열쇠(문서 열쇠와 같다).
  final String uid;

  /// 상세 창이 이미 읽어 둔 항목 기록. 새 내보내기로 만든 기록이면([docRecordIsNew]) 여기서 끝내고 되묻지 않는다.
  final Map<String, dynamic>? json;

  @override
  State<DocChips> createState() => _DocChipsState();
}

class _DocChipsState extends State<DocChips> {
  List<DocCrumb> _subs = const [];
  int _turn = 0;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(DocChips oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid || oldWidget.json != widget.json) _read();
  }

  Future<void> _read() async {
    final turn = ++_turn;
    final mine = _of(widget.json?['x_docs']);
    if (mine.isNotEmpty) {
      setState(() => _subs = mine);
      return;
    }
    // 새 내보내기로 만든 기록은 `x_docs`가 없는 것이 곧 '하위 문서 없음'이다 — 되묻지 않는다.
    if (widget.json != null && (widget.json!.containsKey('x_docs') || docRecordIsNew(widget.json))) {
      setState(() => _subs = const []);
      return;
    }
    if (widget.uid.isEmpty) return;
    List<DocCrumb> found = const [];
    try {
      final answer = await widget.bus.ask({'op': 'entity', 'uid': widget.uid});
      final json = _json(answer);
      found = _of(json['x_docs']);
      if (found.isEmpty && !json.containsKey('x_docs') && !docRecordIsNew(json)) found = await _askOldDoc();
    } catch (_) {
      found = const [];
    }
    if (!mounted || turn != _turn) return;
    setState(() => _subs = found);
  }

  /// 옛 저장소에서만 타는 길 — `doc:<uid>` 기록의 `subs`.
  /// **하나짜리 목록으로 묻는다**(`entities`): 그 열쇠의 문서가 없어도 빈 목록이 올 뿐이라
  /// 앱의 실패 기록(`askFailures`)에 '없는 기록을 물었다'가 쌓이지 않는다(`entity` 하나는 거절한다).
  Future<List<DocCrumb>> _askOldDoc() async {
    final answer = await widget.bus.ask({
      'op': 'entities',
      'uids': ['doc:${widget.uid}'],
    });
    final rows = answer['items'] ?? answer['entities'] ?? answer['rows'];
    if (rows is! List || rows.isEmpty) return const [];
    final first = rows.first;
    if (first is! Map) return const [];
    return _of(_json(first.cast<String, dynamic>())['subs']);
  }

  Map<String, dynamic> _json(Map<String, dynamic> answer) {
    final raw = answer['json'];
    if (raw is Map) return raw.cast<String, dynamic>();
    if (raw is String && raw.isNotEmpty) {
      try {
        final v = jsonDecode(raw);
        if (v is Map) return v.cast<String, dynamic>();
      } catch (_) {
        return const {};
      }
    }
    return const {};
  }

  List<DocCrumb> _of(Object? v) {
    if (v is! List) return const [];
    return [
      for (final one in v)
        if (one is Map && _str(one['key']).isNotEmpty) DocCrumb(_str(one['key']), _str(one['sub'])),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_subs.isEmpty) return const SizedBox.shrink();
    return DetailBox(
      title: '하위 문서',
      small: '${_subs.length}',
      children: [
        DetailChipRow([for (final s in _subs) DocChip(text: s.label, onTap: () => widget.bus.slot(docSlot).value = s.key)], top: 0),
      ],
    );
  }
}
