import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'line_icon.dart';
import 'look.dart';
import 'parts.dart';

// 검색 결과와 묶음 목록의 한 줄 · 목록 · 알약 창 아래로 내려오는 유리 카드.
// 지금 연표의 .search-results · .sr-dot · .sr-title · .sr-when에서 값을 옮겼다.

/// 줄 앞의 점 모양(명세 5-2): 사건은 원 · 시대는 둥근 네모 · 칸은 테두리만 있는 네모 ·
/// 인물은 둥근 막대 · 조약은 마름모 · 하위 문서는 `📄`.
enum ResultMark { dot, band, cell, bar, diamond, doc }

/// 목록의 한 줄: 점 · 제목(한 줄 · 말줄임 · 뒤에 작은 글) · 오른쪽 끝의 때와 트랙.
class ResultRow {
  const ResultRow({
    required this.title,
    required this.when,
    required this.onTap,
    this.sub = '',
    this.mark = ResultMark.dot,
    this.color = Ui.text3,
    this.selected = false,
  });
  final String title, when;

  /// 제목 뒤에 옅게 붙는 작은 글(`인물 · 탐험가 · 유리항 패총국`). 없으면 붙이지 않는다.
  final String sub;
  final ResultMark mark;
  final VoidCallback onTap;
  final Color color;
  final bool selected;
}

/// 줄 앞의 점 하나(9px 자리를 차지하되 모양마다 크기가 다르다 — 명세 5-2).
class ResultDot extends StatelessWidget {
  const ResultDot({super.key, required this.mark, required this.color});
  final ResultMark mark;
  final Color color;

  /// 어떤 모양이든 이만큼의 자리를 차지한다 — 제목이 줄마다 들쭉날쭉하지 않게.
  static const slot = 14.0;

  @override
  Widget build(BuildContext context) {
    if (mark == ResultMark.doc) {
      return const SizedBox(width: slot, height: slot, child: Center(child: LineIcon(LineGlyph.file, size: 13, color: Ui.ink60)));
    }
    final (width, height, radius) = switch (mark) {
      ResultMark.band => (14.0, 8.0, 2.5),
      ResultMark.cell => (10.0, 10.0, 2.0),
      ResultMark.bar => (14.0, 7.0, 3.5),
      _ => (9.0, 9.0, 4.5),
    };
    Widget body = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: mark == ResultMark.cell ? const Color(0x00000000) : color,
        border: mark == ResultMark.cell ? Border.all(color: color, width: 2) : null,
        borderRadius: BorderRadius.circular(mark == ResultMark.diamond ? 1 : radius),
      ),
    );
    if (mark == ResultMark.diamond) body = Transform.rotate(angle: math.pi / 4, child: body);
    return SizedBox(width: slot, height: slot, child: Center(child: body));
  }
}

/// 줄 목록 + 맨 아래 '다음 50개'. 스스로 스크롤한다.
class ResultList extends StatelessWidget {
  const ResultList({super.key, required this.rows, this.hasMore = false, this.onMore, this.padding = const EdgeInsets.all(6)});
  final List<ResultRow> rows;
  final bool hasMore;
  final VoidCallback? onMore;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => ListView.builder(
    shrinkWrap: true,
    padding: padding,
    itemCount: rows.length + (hasMore ? 1 : 0),
    itemBuilder: (context, index) => index == rows.length
        ? Align(alignment: Alignment.center, child: TextButton(onPressed: onMore, child: const Text('다음 50개')))
        : _ResultTile(row: rows[index]),
  );
}

class _ResultTile extends StatefulWidget {
  const _ResultTile({required this.row});
  final ResultRow row;
  @override
  State<_ResultTile> createState() => _ResultTileState();
}

class _ResultTileState extends State<_ResultTile> {
  bool _hover = false;

  static const _titleStyle = TextStyle(fontSize: 14, height: 1.5, color: Ui.text);

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    // 고른 줄은 반전 채움이라 글자도 뒤집는다.
    final title = row.selected ? _titleStyle.copyWith(color: Ui.paper) : _titleStyle;
    final soft = row.selected ? Ui.paper60 : Ui.text3;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: row.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          // 올린 줄은 ink8, 화살표로 고른 줄은 반전 채움(ink 바탕 + paper 글자).
          decoration: BoxDecoration(
            color: row.selected ? Ui.ink : (_hover ? Ui.ink8 : const Color(0x00000000)),
            borderRadius: BorderRadius.circular(Ui.innerRadius),
          ),
          child: Row(
            children: [
              ResultDot(mark: row.mark, color: row.color),
              const SizedBox(width: 8),
              // 작은 글이 없으면 글 하나로 둔다 — 제목만 찾는 검사와 읽기 도구가 그대로 읽게.
              Expanded(
                child: row.sub.isEmpty
                    ? Text(row.title, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: title)
                    : Text.rich(
                        TextSpan(
                          text: row.title,
                          children: [TextSpan(text: ' ${row.sub}', style: TextStyle(fontSize: 12.5, color: soft))],
                        ),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: title,
                      ),
              ),
              const SizedBox(width: 10),
              Text(row.when, maxLines: 1, softWrap: false, style: TextStyle(fontSize: 12, height: 1.5, color: soft)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 검색 칸 아래에 붙는 검색 결과: 폭 460 · 둥근 12 · paper 바탕 · ink20 선.
class SearchResultsPanel extends StatelessWidget {
  const SearchResultsPanel({super.key, required this.rows, this.hasMore = false, this.onMore, this.note});
  final List<ResultRow> rows;
  final bool hasMore;
  final VoidCallback? onMore;

  /// 목록 맨 위의 작은 안내 글(건수 따위). 없으면 두지 않는다.
  final String? note;

  @override
  Widget build(BuildContext context) => GlassCard(
    radius: Ui.resultsRadius,
    blur: Ui.blurWide,
    shadow: Ui.shadow,
    child: SizedBox(
      width: Ui.resultsWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (note != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Text(note!, style: const TextStyle(fontSize: 12, height: 1.5, color: Ui.text3)),
            ),
          Flexible(child: ResultList(rows: rows, hasMore: hasMore, onMore: onMore)),
        ],
      ),
    ),
  );
}
