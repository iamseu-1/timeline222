// 인물 항목 기록의 칭호 묶음 `x_titles`(스키마 4 — docs/계약-아카이브-3단계.md 1-1절 '항목 기록')를 사람 창이 쓰는 칭호 목록으로 푸는 순수 풀개.
// 값을 짓는 쪽은 내보내기 JS(prototype/scripts/export/entities.mjs — HT.personTitles와 같은 칸 · 같은 차례)와 그 거울인 엔진(m/entities.rs titles_of)이다.
// 원소: { uid: 객체(띠) uid, cell: 칸 순번, office: '지도자' | '내각', name: 객체 이름, start · end: 분, rank: 지위 } — 시작 차례 · 칭호가 없는 인물은 열쇠가 없다.
//
// 리메이크 4단계 과제 1 걸음 1이 풀개를 두고, 과제 4 걸음 3(사람 창)의 인물 창(detail_people.dart FigureDetail의 '칭호' 묶음)이 쓴다.
// 이 파일은 순수 풀개라 그림판도 창도 import하지 않는다.
// 읽기는 일부러 너그럽다 — 빠진 열쇠는 빈 값, 수는 글로 와도 읽고, 원소가 표가 아니거나 객체 uid · 이름이 모두 없으면 그 원소만 버린다(옛 · 다른 판의 답이
// 사람 창을 깨지 않게). 차례는 받은 그대로 둔다(시작 차례는 짓는 쪽의 몫).

import 'dart:convert';

/// 칭호가 든 직위 줄 — 지도자 줄(칸 종류 1) · 내각 줄(칸 종류 2). 모르는 글은 [other].
enum TitleOffice {
  leader('leader', '지도자'),
  cabinet('cabinet', '내각'),
  other('', '');

  const TitleOffice(this.prefix, this.label);

  /// 칸 참조의 앞머리(`leader:3`의 `leader`) — [other]는 빈 글.
  final String prefix;

  /// 사람 창에 적는 직위 이름(계약의 글 '지도자' · '내각') — [other]는 빈 글.
  final String label;

  /// `x_titles`의 office 글 → 갈래. 계약의 글('지도자' · '내각')과 칸 참조 앞머리('leader' · 'cabinet')를 받는다.
  static TitleOffice of(Object? raw) => switch (raw is String ? raw.trim() : '') {
    '지도자' || 'leader' => leader,
    '내각' || 'cabinet' => cabinet,
    _ => other,
  };
}

/// 칭호 하나 — 한 사람이 한 객체의 지도자 · 내각 칸 하나를 쥔 것.
class PersonTitle {
  const PersonTitle({required this.uid, required this.cell, required this.office, required this.name, this.start, this.end, this.rank = ''});

  /// 객체(띠)의 uid — 누르면 그 객체로 가는 열쇠. 빠졌으면 빈 글.
  final String uid;

  /// 그 객체의 직위 줄 안 칸 순번(0부터). 빠졌거나 수가 아니면 −1.
  final int cell;

  /// 지도자 · 내각 · 모름.
  final TitleOffice office;

  /// 객체 이름(빠졌으면 빈 글).
  final String name;

  /// 칸의 시작 · 끝(분 — 1970-01-01 UTC부터). 빠졌거나 셈하지 못한 값(JS의 NaN이 JSON null로 온 것)이면 null.
  final int? start, end;

  /// 지위(칸의 rank — 비었으면 빈 글).
  final String rank;

  /// 상세 창 · 고르기의 칸 참조(`leader:3` · `cabinet:0`). 직위 줄을 모르거나 순번이 없으면 null.
  String? get cellRef => office == TitleOffice.other || cell < 0 ? null : '${office.prefix}:$cell';

  @override
  bool operator ==(Object other) =>
      other is PersonTitle && other.uid == uid && other.cell == cell && other.office == office && other.name == name &&
      other.start == start && other.end == end && other.rank == rank;

  @override
  int get hashCode => Object.hash(uid, cell, office, name, start, end, rank);

  @override
  String toString() => 'PersonTitle($uid ${cellRef ?? office.name} $name $start~$end $rank)';
}

/// `x_titles`의 풀개.
abstract final class PersonTitles {
  /// 항목 기록의 열쇠 이름.
  static const key = 'x_titles';

  /// 인물 항목 기록(풀린 JSON 표)에서 칭호 목록 — 열쇠가 없거나 꼴이 다르면 빈 목록.
  static List<PersonTitle> of(Map<dynamic, dynamic>? record) => record == null ? const [] : read(record[key]);

  /// `x_titles`의 값 하나를 읽는다 — 목록이거나, 목록을 담은 JSON 글. 그 밖은 빈 목록.
  static List<PersonTitle> read(Object? raw) {
    final list = switch (raw) {
      final List v => v,
      final String v => _decodeList(v),
      _ => const [],
    };
    if (list.isEmpty) return const [];
    return List.unmodifiable([
      for (final x in list)
        if (x is Map) ?_one(x),
    ]);
  }

  static List _decodeList(String text) {
    if (text.trim().isEmpty) return const [];
    try {
      final v = jsonDecode(text);
      return v is List ? v : const [];
    } on FormatException {
      return const [];
    }
  }

  static PersonTitle? _one(Map x) {
    final uid = _text(x['uid']), name = _text(x['name']);
    if (uid.isEmpty && name.isEmpty) return null; // 가리킬 객체도 보일 이름도 없다
    return PersonTitle(
      uid: uid,
      cell: _int(x['cell']) ?? -1,
      office: TitleOffice.of(x['office']),
      name: name,
      start: _int(x['start']),
      end: _int(x['end']),
      rank: _text(x['rank']),
    );
  }

  static String _text(Object? v) => switch (v) {
    null => '',
    final String s => s,
    final num n => '$n',
    _ => '',
  };

  /// 정수로 — 수(소수는 반올림 · 무한 · NaN은 null) · 수를 담은 글. 그 밖은 null.
  static int? _int(Object? v) => switch (v) {
    final int n => n,
    final double n => n.isFinite ? n.round() : null,
    final String s => int.tryParse(s.trim()) ?? _int(double.tryParse(s.trim())),
    _ => null,
  };
}
