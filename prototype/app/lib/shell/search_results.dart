import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'line_icon.dart';
import 'look.dart';
import 'sheet_look.dart';
import 'sheet_parts.dart';

// 검색 결과 — 서고 꼴(감독 고름 G5 #9 · 다듬기 판 `shs-search` · 목업 `.claude/research/stage4-choose/themes/g-sheet-search.js`의 `drawSearch` — git 밖).
//  폴더 '찾음 · 〈찾는 말〉 〈수〉'(폭 480 · 검색 칸 왼쪽 끝 아래 8 — 앱 틀이 자리를 준다) 안에
//    맨 위 이동 줄(날짜 · 간지 — 흰 이름 종이 줄) → 갈래 상자(객체 · 칸 · 사건 · 조약 · 인물 · 문서 — 뚜껑의 흰 라벨 + 수).
//  상자 안의 줄은 가로대(먹 12)에서 실로 매단 꼬리표 24(이름 13 굵게 · 곁글 12 · 때 12 오른쪽 · 한 바탕선):
//    객체 = 제 색 꼬리표 · 사건 = 주인 색 꼬리표 머리의 점(조약 = 마름모) · 인물 = 흰 사람 띠(둥근 끝) · 문서 = 흰 이름 종이 + 문서 그림 ·
//    칸 = 같은 정권의 칸을 주인 꼬리표 하나(머리 = 주인 이름 · 칸 갈래)의 흰 층 줄로.
//  고른 줄 = 고른 테(먹 100 · 1.5 — 칸 줄은 층 안쪽) · 올림 = 먹 4 · '다음 50개' = 흰 이름 종이 단추. 키가 넘치면 폴더 안에서 넘긴다.
//  줄을 고르는 일 · 차례 · 키보드는 부르는 쪽(`ui/search.dart`의 SearchController)이 맡는다 — 이 파일은 그리기만 한다.

/// 줄의 꼴.
enum ResultMark {
  /// 맨 위 이동 줄(날짜 · 간지): 흰 이름 종이(모따기 3 · 먹 45) — 실에 매달지 않는다.
  paper,

  /// 객체(정권 · 시대 · 대범위 · 왕조 · 기관 · 문화 · 가문): 제 색 꼬리표.
  tag,

  /// 사건: 주인 색 꼬리표 머리의 점.
  dot,

  /// 조약: 주인 색 꼬리표 머리의 마름모.
  diamond,

  /// 인물: 흰 사람 띠(둥근 끝 · 먹 45).
  person,

  /// 문서: 흰 이름 종이 + 문서 그림.
  doc,
}

/// 상자 안의 것 하나 — 줄([ResultRow]) 또는 칸 묶음([ResultCells]).
sealed class ResultItem {
  const ResultItem();
}

/// 목록의 한 줄: 이름 · 곁글(이름 뒤 옅게) · 때(오른쪽 끝).
class ResultRow extends ResultItem {
  const ResultRow({
    required this.title,
    required this.when,
    required this.onTap,
    this.sub = '',
    this.mark = ResultMark.dot,
    this.color,
    this.kind = SheetTagKind.cham,
    this.selected = false,
  });
  final String title, when;

  /// 이름 뒤에 옅게 붙는 곁글(`국가 · 하연`). 없으면 붙이지 않는다.
  final String sub;
  final ResultMark mark;
  final VoidCallback onTap;

  /// 꼬리표의 제 색(객체) · 주인 색(사건 · 조약). 없으면 흰 종이 · 먹 45.
  final Color? color;

  /// 꼬리표의 끝 꼴(객체 — 다스림은 모따기 · 영토 밖은 둥근 끝).
  final SheetTagKind kind;
  final bool selected;
}

/// 칸 묶음: 같은 정권(주인)의 칸을 주인 꼬리표 하나의 흰 층 줄로. [rows]의 [ResultRow.mark] · 색은 쓰지 않는다.
class ResultCells extends ResultItem {
  const ResultCells({required this.owner, required this.rows, this.kind = '', this.track = '', this.color});

  /// 머리의 주인 이름(굵게)과 칸 갈래('지도자' — '· 지도자'로 적는다) · 오른쪽 끝의 트랙.
  final String owner, kind, track;
  final Color? color;
  final List<ResultRow> rows;
}

/// 갈래 상자 하나(뚜껑의 흰 라벨 + 줄 수).
class ResultBox {
  const ResultBox({required this.label, required this.items});
  final String label;
  final List<ResultItem> items;

  /// 상자에 든 줄의 수(칸 묶음은 칸마다).
  int get count => items.fold(0, (n, item) => n + switch (item) {
    ResultRow() => 1,
    ResultCells(:final rows) => rows.length,
  });
}

/// 검색 칸 아래에 붙는 검색 결과 폴더. 키는 [maxHeight](앱 틀이 더 낮게 주면 그것) 안이고, 넘치면 상자들이 폴더 안에서 넘어간다.
/// 화살표로 고른 줄이 바뀌면 그 줄이 보이게 넘긴다(줄이 스스로 — [_reveal]).
class SearchResultsPanel extends StatelessWidget {
  const SearchResultsPanel({
    super.key,
    this.title = '찾음',
    this.count,
    this.note,
    this.lead = const [],
    this.boxes = const [],
    this.hasMore = false,
    this.onMore,
    this.maxHeight = Ui.resultsMaxHeight,
  });

  /// 폴더 탭의 맨 글('찾음 · 설원')과 수.
  final String title;
  final String? count;

  /// 폴더 맨 위의 안내 글(못 찾음 · 앞의 60건만 · 간지 · 필터 · 오류). 없으면 두지 않는다.
  final String? note;

  /// 맨 위 이동 줄(날짜 · 간지).
  final List<ResultRow> lead;
  final List<ResultBox> boxes;
  final bool hasMore;
  final VoidCallback? onMore;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final lead = [for (final row in this.lead) _ResultTile(row: row, paper: true)];
    final boxes = <Widget>[];
    for (final box in this.boxes) {
      if (box.items.isEmpty) continue;
      final kinds = <SheetTagKind>[];
      final items = <Widget>[];
      for (final item in box.items) {
        switch (item) {
          case ResultRow():
            kinds.add(_tagKindOf(item));
            items.add(_ResultTile(row: item));
          case ResultCells():
            kinds.add(SheetTagKind.cham);
            items.add(_CellTag(cells: item));
        }
      }
      boxes.add(
        SheetBox(
          label: box.label,
          count: '${box.count}',
          padding: const EdgeInsets.fromLTRB(SheetLook.boxInset, SheetLook.searchTop, SheetLook.boxInset, SheetLook.searchBottom),
          child: SheetThreadColumn(rails: true, gap: SheetLook.searchRowGap, kinds: kinds, children: items),
        ),
      );
    }

    final body = <Widget>[
      for (var i = 0; i < lead.length; i++) ...[if (i > 0) const SizedBox(height: SheetLook.chipGap), lead[i]],
      if (lead.isNotEmpty && boxes.isNotEmpty) const SizedBox(height: SheetLook.listBoxGap),
      for (var i = 0; i < boxes.length; i++) ...[if (i > 0) const SizedBox(height: SheetLook.listBoxGap), boxes[i]],
      if (hasMore)
        Padding(
          padding: const EdgeInsets.only(top: SheetLook.listBoxGap),
          child: Center(child: SheetPaperButton(label: '다음 50개', onTap: onMore)),
        ),
    ];
    final note = this.note;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SizedBox(
        width: SheetLook.searchWidth,
        child: SheetFolder(
          label: title,
          count: count,
          padding: const EdgeInsets.all(SheetLook.listPad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (note != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    note,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: SheetLook.noteText, height: SheetLook.noteLine / SheetLook.noteText, color: SheetLook.ink60),
                  ),
                ),
                if (body.isNotEmpty) const SizedBox(height: SheetLook.noteGap),
              ],
              if (body.isNotEmpty)
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: body),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

SheetTagKind _tagKindOf(ResultRow row) => switch (row.mark) {
  ResultMark.person => SheetTagKind.key,
  ResultMark.tag => row.kind == SheetTagKind.plain ? SheetTagKind.cham : row.kind,
  _ => SheetTagKind.cham,
};

/// 고른 줄이 된 그 그리기 뒤에 [rect](상자 크기에서 셈 · 없으면 [context]의 상자 전체)가 폴더 안에서 보이게 넘긴다(화살표로 상자를 건널 때).
/// 크기는 배치가 끝난 뒤에만 읽을 수 있어 셈도 그리기 뒤로 미룬다.
void _reveal(BuildContext context, [Rect Function(Size size)? rect]) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    final box = context.findRenderObject();
    if (box is RenderBox && box.attached && box.hasSize) box.showOnScreen(rect: rect?.call(box.size));
  });
}

/// 올리면 바탕에 먹 4를 얹는다(흰 종이면 먹 4 그대로 · 제 색이면 그 위에 검정 4%).
Color _lift(Color fill, bool hover) => hover ? Color.alphaBlend(const Color(0x0a000000), fill) : fill;

/// 줄의 바탕 — 꼴마다 칠 · 테 · 구멍.
SheetShape resultShapeOf(ResultRow row, {bool hover = false}) {
  final c = row.color;
  switch (row.mark) {
    case ResultMark.paper:
      return SheetShape(chamfer: SheetLook.paperChamfer, fill: _lift(SheetLook.paper, hover), stroke: SheetLook.ink45);
    case ResultMark.person:
      return SheetShape(kind: SheetTagKind.key, fill: _lift(SheetLook.paper, hover), stroke: SheetLook.ink45, hole: true);
    case ResultMark.doc:
      return SheetShape(chamfer: SheetLook.paperChamfer, fill: _lift(SheetLook.paper, hover), stroke: SheetLook.ink45, hole: true);
    case ResultMark.tag:
    case ResultMark.dot:
    case ResultMark.diamond:
      final kind = _tagKindOf(row);
      return SheetShape(
        kind: kind,
        fill: _lift(c == null ? SheetLook.paper : SheetLook.tagFill(c), hover),
        stroke: c == null ? SheetLook.ink45 : SheetLook.tagEdge(c),
        hole: true,
      );
  }
}

/// 한 줄의 글 — 이름(13 굵게) · 곁글(12 · 이름 뒤 8) · 때(12 · 오른쪽 끝)를 한 바탕선에. 넘치면 곁글부터 줄이고 그다음 이름을 줄인다.
/// 이름 · 곁글 · 때는 저마다 글 하나다(이름만 찾는 검사 · 읽기 도구가 이름을 그대로 읽게).
class _RowText extends StatelessWidget {
  const _RowText({required this.name, required this.sub, required this.when, required this.nameInk, required this.subInk});
  final String name, sub, when;
  final Color nameInk, subInk;

  @override
  Widget build(BuildContext context) {
    final subStyle = sheetText(SheetLook.searchSub, color: subInk);
    Widget line(String text, TextStyle style) => Text(text, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: style);
    return _LineRow(
      hasSub: sub.isNotEmpty,
      hasWhen: when.isNotEmpty,
      children: [
        line(name, sheetText(SheetLook.searchName, bold: true, color: nameInk)),
        if (sub.isNotEmpty) line(sub, subStyle),
        if (when.isNotEmpty) Text(when, maxLines: 1, softWrap: false, style: subStyle),
      ],
    );
  }
}

/// [_RowText]의 배치: 자식 = 이름 · (곁글) · (때). 때는 제 폭으로 오른쪽 끝, 이름은 남은 폭까지, 곁글은 이름 뒤 8부터 남은 만큼
/// (12보다 좁으면 그리지 않음). 셋의 바탕선을 하나로 맞추고 줄은 받은 키의 가운데에 세운다.
class _LineRow extends MultiChildRenderObjectWidget {
  const _LineRow({required this.hasSub, required this.hasWhen, required super.children});
  final bool hasSub, hasWhen;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderLineRow(hasSub, hasWhen);

  @override
  void updateRenderObject(BuildContext context, _RenderLineRow renderObject) => renderObject.set(hasSub, hasWhen);
}

class _LineData extends ContainerBoxParentData<RenderBox> {}

class _RenderLineRow extends RenderBox with ContainerRenderObjectMixin<RenderBox, _LineData>, RenderBoxContainerDefaultsMixin<RenderBox, _LineData> {
  _RenderLineRow(this._hasSub, this._hasWhen);
  bool _hasSub, _hasWhen;

  /// 곁글이 들 자리가 있었는가(마지막 배치).
  bool _subShown = false;
  double _baseline = 0;

  void set(bool hasSub, bool hasWhen) {
    if (hasSub == _hasSub && hasWhen == _hasWhen) return;
    _hasSub = hasSub;
    _hasWhen = hasWhen;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _LineData) child.parentData = _LineData();
  }

  RenderBox? get _sub => _hasSub ? childAfter(firstChild!) : null;
  RenderBox? get _when => _hasWhen ? lastChild : null;

  static const _subGap = SheetLook.searchSubGap, _whenGap = SheetLook.searchWhenRight, _subMin = 12.0;

  double _natural(double Function(RenderBox) of) {
    final sub = _sub, when = _when;
    return of(firstChild!) + (sub == null ? 0 : _subGap + of(sub)) + (when == null ? 0 : _whenGap + of(when));
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;
  @override
  double computeMaxIntrinsicWidth(double height) => firstChild == null ? 0 : _natural((c) => c.getMaxIntrinsicWidth(double.infinity));
  @override
  double computeMinIntrinsicHeight(double width) => _tallest((c) => c.getMinIntrinsicHeight(double.infinity));
  @override
  double computeMaxIntrinsicHeight(double width) => _tallest((c) => c.getMaxIntrinsicHeight(double.infinity));

  double _tallest(double Function(RenderBox) of) {
    var h = 0.0;
    for (var c = firstChild; c != null; c = childAfter(c)) {
      h = math.max(h, of(c));
    }
    return h;
  }

  @override
  void performLayout() {
    final name = firstChild;
    if (name == null) {
      size = constraints.smallest;
      return;
    }
    final sub = _sub, when = _when;
    final bounded = constraints.hasBoundedWidth;
    final loose = BoxConstraints(maxWidth: bounded ? constraints.maxWidth : double.infinity);
    var ww = 0.0;
    if (when != null) {
      when.layout(loose, parentUsesSize: true);
      ww = when.size.width;
    }
    final whole = bounded ? constraints.maxWidth : double.infinity;
    final room = math.max(0.0, whole - (when == null ? 0 : ww + _whenGap));
    name.layout(BoxConstraints(maxWidth: room), parentUsesSize: true);
    final rest = room - name.size.width - _subGap;
    _subShown = sub != null && rest >= _subMin;
    if (sub != null) sub.layout(BoxConstraints(maxWidth: math.max(0.0, rest)), parentUsesSize: true);
    final shown = [name, if (_subShown) sub!, ?when];
    double base(RenderBox b) => b.getDistanceToBaseline(TextBaseline.alphabetic) ?? b.size.height;
    var above = 0.0, below = 0.0;
    for (final b in shown) {
      above = math.max(above, base(b));
      below = math.max(below, b.size.height - base(b));
    }
    final width = bounded ? constraints.maxWidth : name.size.width + (_subShown ? _subGap + sub!.size.width : 0) + (when == null ? 0 : _whenGap + ww);
    final height = constraints.hasBoundedHeight ? constraints.maxHeight : above + below;
    size = constraints.constrain(Size(width, height));
    // 바탕선은 온 화소에(목업 `rowText` — 글 바탕선은 정수 픽셀).
    _baseline = ((size.height - above - below) / 2 + above).roundToDouble();
    void put(RenderBox b, double x) => (b.parentData! as _LineData).offset = Offset(x, _baseline - base(b));
    put(name, 0);
    if (sub != null) put(sub, name.size.width + _subGap);
    if (when != null) put(when, size.width - ww);
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => _baseline;

  @override
  void paint(PaintingContext context, Offset offset) {
    for (var c = firstChild; c != null; c = childAfter(c)) {
      if (c == _sub && !_subShown) continue;
      context.paintChild(c, offset + (c.parentData! as _LineData).offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);
}

/// 줄 하나(상자 안의 꼬리표 · 맨 위의 흰 종이). 올리면 먹 4, 고르면 고른 테.
class _ResultTile extends StatefulWidget {
  const _ResultTile({required this.row, this.paper = false});
  final ResultRow row;

  /// 맨 위 이동 줄 — 흰 종이(글 앞 10).
  final bool paper;

  @override
  State<_ResultTile> createState() => _ResultTileState();
}

class _ResultTileState extends State<_ResultTile> {
  bool _hover = false;

  @override
  void didUpdateWidget(_ResultTile old) {
    super.didUpdateWidget(old);
    if (widget.row.selected && !old.row.selected) _reveal(context);
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final mark = widget.paper ? ResultMark.paper : row.mark;
    final shown = widget.paper ? ResultRow(title: row.title, when: row.when, onTap: row.onTap, sub: row.sub, mark: ResultMark.paper, selected: row.selected) : row;
    final c = row.color;
    final colored = c != null && (mark == ResultMark.tag || mark == ResultMark.dot || mark == ResultMark.diamond);
    // 글 빛깔: 객체 = 탭 글 · 이름 글(제 색 + 먹) / 사건 · 조약 = 먹 85 · 이름 글 / 그 밖 = 먹 85 · 60.
    final nameInk = colored && mark == ResultMark.tag ? SheetLook.tagInk(c) : SheetLook.ink85;
    final subInk = colored ? SheetLook.nameInk(c) : SheetLook.ink60;
    final lead = switch (mark) {
      ResultMark.paper => SheetLook.searchPaperLead,
      ResultMark.tag || ResultMark.person => SheetLook.searchLead,
      _ => SheetLook.searchMarkLead,
    };
    final text = _RowText(name: row.title, sub: row.sub, when: row.when, nameInk: nameInk, subInk: subInk);
    Widget content = Padding(padding: EdgeInsets.only(left: lead, right: SheetLook.searchWhenRight), child: text);
    if (mark == ResultMark.dot || mark == ResultMark.diamond || mark == ResultMark.doc) {
      content = Stack(children: [
        Positioned(left: 0, top: 0, bottom: 0, width: SheetLook.searchMarkLead, child: _Mark(mark: mark, color: c)),
        content,
      ]);
    }
    return SheetPickRing(
      on: row.selected,
      kind: _tagKindOf(shown),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: row.onTap,
          child: SheetTag(shape: resultShapeOf(shown, hover: _hover), height: SheetLook.searchRow, child: content),
        ),
      ),
    );
  }
}

/// 줄 머리의 표 — 사건 점 · 조약 마름모(주인 색) · 문서 그림. 가운데는 왼쪽 24.
class _Mark extends StatelessWidget {
  const _Mark({required this.mark, required this.color});
  final ResultMark mark;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (mark == ResultMark.doc) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.only(left: SheetLook.searchMark - SheetLook.searchDocIcon / 2),
          child: LineIcon(LineGlyph.file, size: SheetLook.searchDocIcon, color: SheetLook.ink60),
        ),
      );
    }
    return CustomPaint(painter: _MarkPainter(mark, color));
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.mark, this.color);
  final ResultMark mark;
  final Color? color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = color;
    final at = Offset(SheetLook.searchMark, SheetLook.searchRow / 2);
    if (mark == ResultMark.diamond) {
      canvas.drawPath(sheetDiamondPath(at, half: SheetLook.searchDiamond), Paint()..color = c == null ? SheetLook.ink60 : SheetLook.diamondInk(c));
    } else {
      canvas.drawCircle(at, SheetLook.searchDot, Paint()..color = c == null ? SheetLook.ink60 : SheetLook.tagEdge(c));
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.mark != mark || old.color != color;
}

/// 칸 묶음 = 주인 꼬리표 하나: 머리 24(제 색 칠 · 주인 이름 · 칸 갈래 · 트랙) 아래 흰 층을 칸마다 한 줄 26(사이 금 먹 25).
/// 줄마다 따로 누르고, 올린 줄은 먹 4 · 고른 줄은 층 안쪽 고른 테(먹 100 · 1.5).
class _CellTag extends StatefulWidget {
  const _CellTag({required this.cells});
  final ResultCells cells;

  @override
  State<_CellTag> createState() => _CellTagState();
}

class _CellTagState extends State<_CellTag> {
  int _hover = -1;

  @override
  void didUpdateWidget(_CellTag old) {
    super.didUpdateWidget(old);
    final now = widget.cells.rows.indexWhere((r) => r.selected), before = old.cells.rows.indexWhere((r) => r.selected);
    if (now >= 0 && now != before) {
      _reveal(context, (size) => Rect.fromLTWH(0, SheetLook.cellHead + now * SheetLook.cellFloor, size.width, SheetLook.cellFloor));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cells = widget.cells, c = cells.color;
    final head = c == null ? SheetLook.ink85 : SheetLook.tagInk(c), soft = c == null ? SheetLook.ink60 : SheetLook.nameInk(c);
    final selected = cells.rows.indexWhere((r) => r.selected);
    return SheetPixelBox(
      child: CustomPaint(
        painter: _CellTagPainter(color: c, floors: cells.rows.length, hover: _hover, selected: selected),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: SheetLook.cellHead,
              child: Padding(
                padding: const EdgeInsets.only(left: SheetLook.searchLead, right: SheetLook.searchWhenRight),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Text.rich(
                          TextSpan(
                            text: cells.owner,
                            style: sheetText(SheetLook.cellHeadText, bold: true, color: head),
                            children: [
                              if (cells.kind.isNotEmpty) ...[
                                const WidgetSpan(alignment: PlaceholderAlignment.middle, child: SizedBox(width: SheetLook.cellHeadGap)),
                                TextSpan(text: '· ${cells.kind}', style: sheetText(SheetLook.cellHeadText, color: soft)),
                              ],
                            ],
                          ),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (cells.track.isNotEmpty) ...[
                        const SizedBox(width: SheetLook.searchWhenRight),
                        Text(cells.track, maxLines: 1, softWrap: false, style: sheetText(SheetLook.cellHeadText, color: soft)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            for (var i = 0; i < cells.rows.length; i++)
              MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _hover = i),
                onExit: (_) => setState(() => _hover = _hover == i ? -1 : _hover),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: cells.rows[i].onTap,
                  child: SizedBox(
                    height: SheetLook.cellFloor,
                    child: Padding(
                      padding: const EdgeInsets.only(left: SheetLook.searchLead, right: SheetLook.searchWhenRight),
                      child: _RowText(name: cells.rows[i].title, sub: cells.rows[i].sub, when: cells.rows[i].when, nameInk: SheetLook.ink85, subInk: SheetLook.ink60),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CellTagPainter extends CustomPainter {
  const _CellTagPainter({required this.color, required this.floors, required this.hover, required this.selected});
  final Color? color;
  final int floors, hover, selected;

  @override
  void paint(Canvas canvas, Size size) {
    final c = color;
    final box = Offset.zero & size;
    final edge = c == null ? SheetLook.ink45 : SheetLook.tagEdge(c);
    final outline = sheetTagPath(box, SheetTagKind.cham);
    canvas.drawPath(outline, Paint()..color = c == null ? SheetLook.ink4 : SheetLook.tagFill(c));
    // 흰 층 — 머리 밑선(반 픽셀)부터 아래 끝까지 · 왼쪽 아래 귀는 꼬리표와 같은 모따기.
    final x0 = .5, x1 = size.width - .5, ys = SheetLook.cellHead - .5, yb = size.height - .5, ch = SheetLook.tagChamfer;
    final floor = Path()
      ..moveTo(x1, ys)
      ..lineTo(x0, ys)
      ..lineTo(x0, yb - ch)
      ..lineTo(x0 + ch, yb)
      ..lineTo(x1, yb)
      ..close();
    canvas.drawPath(floor, Paint()..color = SheetLook.paper);
    if (hover >= 0 && hover < floors) {
      final top = SheetLook.cellHead + hover * SheetLook.cellFloor;
      canvas.save();
      canvas.clipPath(floor);
      canvas.drawRect(Rect.fromLTWH(1, top, size.width - 2, SheetLook.cellFloor - (hover < floors - 1 ? 1 : 0)), Paint()..color = SheetLook.ink4);
      canvas.restore();
    }
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawLine(Offset(x0 + .5, ys), Offset(x1, ys), line..color = edge);
    for (var i = 1; i < floors; i++) {
      final y = ys + i * SheetLook.cellFloor;
      canvas.drawLine(Offset(x0 + 1, y), Offset(x1 - .5, y), line..color = SheetLook.ink25);
    }
    canvas.drawPath(sheetTagRing(box, SheetTagKind.cham), Paint()..color = edge);
    final hole = sheetHoleAt(box, SheetTagKind.cham);
    canvas.drawCircle(hole, SheetLook.holeRadius, Paint()..color = SheetLook.paper);
    canvas.drawCircle(hole, SheetLook.holeRadius, line..color = SheetLook.ink45);
    if (selected >= 0 && selected < floors) {
      final top = SheetLook.cellHead + selected * SheetLook.cellFloor;
      canvas.drawPath(
        SheetPickRing.insidePath(Rect.fromLTWH(0, top, size.width, SheetLook.cellFloor)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = SheetLook.pickWidth
          ..color = SheetLook.pickInk,
      );
    }
  }

  @override
  bool shouldRepaint(_CellTagPainter old) => old.color != color || old.floors != floors || old.hover != hover || old.selected != selected;
}
