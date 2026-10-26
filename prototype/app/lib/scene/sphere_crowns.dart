// 사람 띠의 왕관이 가리키는 띠 · 지도자 칸의 자리(리메이크 4단계 과제 4 걸음 2 — 실 · 뿔 매듭 · 정한 것 #7 이음줄 걷기).
// 사람 띠(문화권 단위 줄 kind 1)의 data는 왕관 목록 `[{uid: 띠 uid, cell: 지도자 칸 순번}]`이다 — 그림판은 띠 번호 · 줄 · 칸의 때를 알아야 실을 긋는다.
// 저장소를 바꿔 넣을 때(장면의 storeVersion)마다 한 번 자료 처리부에 묻는다:
//   ① `{"op":"ids_of"}`(계약 2-1 — 앱 틀 app_glue.dart `placesOf`와 같은 길: 모르는 처리부면 `id_of`를 하나씩) → 띠 번호 · 줄 · 띠의 시작 · 끝(분)
//   ② 띠마다 `{"op":"cells_of","band":번호,"kind":1}` → 그 띠의 지도자 칸(시작 · 끝 · style — 순번은 15 ~ 26비트 − 1 · 앞 칸 이음은 비트 2)
// 칸의 때를 타일이 아니라 답으로 받는 까닭: 미리보기(js/timeline.js `_drawF4Threads`)는 화면 아래로 벗어난 띠까지 실을 긋는다(트랙 DOM이 다 있음) —
// 앱의 타일은 보이는 줄 묶음만 와서, 타일로 칸을 찾으면 화면 밖 띠로 가는 실이 통째로 빠진다. 성긴 단계에서 엔진이 싣지 않는 짧은 칸(levels.rs `lod_of`)도 답에는 있다.
// 풀리기 전에는 실을 긋지 않고(동군연합 이음줄도 쉰다 — 풀린 뒤 걷힐 줄이 한 장면 비쳤다 사라지지 않게), 풀리면 장면을 다시 청한다.
// 사람 띠가 없는 저장소는 묻지 않고 곧바로 빈 표다(그림 · 이음줄이 4단계 전과 같다).
import 'layout.dart' show SceneLayout;

/// 왕관 띠의 지도자 칸 하나(`cells_of`의 답 — 시작 · 끝은 분).
class CrownCell {
  const CrownCell(this.start, this.end, this.style);
  final int start, end, style;

  /// 그 띠 지도자 목록에서의 순번(style 15 ~ 26비트 − 1 · 싣지 않았거나 넘치면 −1 — strips.dart `CellStyle.seqOf`와 같은 셈).
  int get seq {
    final v = (style >> 15) & 0xfff;
    return v == 0 || v == 0xfff ? -1 : v - 1;
  }

  /// 앞 칸과 같은 무리(style 비트 2 — strips.dart `CellStyle.joinLeft`).
  bool get joinLeft => style & 4 != 0;

  @override
  String toString() => 'CrownCell($start ~ $end · 순번 $seq)';
}

/// 왕관이 든 띠 하나의 자리 — 띠 번호(타일의 번호) · 줄 · 띠의 시작 · 끝(분 — 끝을 모르면 null) · 지도자 칸들(시작 차례).
class CrownBand {
  const CrownBand(this.id, this.row, this.start, this.end, this.leaders);
  final int id, row;
  final int? start, end;
  final List<CrownCell> leaders;

  /// 순번 [seq]의 지도자 칸이 [leaders]의 몇째인가(없으면 −1).
  int indexOf(int seq) {
    for (int i = 0; i < leaders.length; i++) {
      if (leaders[i].seq == seq) return i;
    }
    return -1;
  }

  @override
  String toString() => 'CrownBand(띠 $id · 줄 $row · 지도자 ${leaders.length})';
}

/// 장면 곁의 왕관 표(띠 uid → [CrownBand]). 장면이 준비마다 [sync]를 부르고, 그림판(실 · 이음줄)이 읽는다.
class CrownTable {
  CrownTable({this.ask, this.onReady});

  /// 자료 처리부에 묻는 길(장면의 `ask` — 없으면 묻지 않고 빈 표).
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> query)? ask;

  /// 답이 와서 표가 바뀌었다(장면이 다시 그린다).
  final void Function()? onReady;

  Map<String, CrownBand> _bands = const {};
  Set<(int, int)> _cells = const {};

  /// 맞춘 저장소 판(장면의 storeVersion — 처음은 −1)과 묻는 차례(늦게 온 옛 답을 버린다).
  int _store = -1, _turn = 0;
  bool _pending = false;

  /// 답을 기다리는 중인가 — 장면의 '가라앉음'([TimelineScene.settled])이 본다(그림을 뜨는 도구가 실이 다 선 뒤에 뜨게).
  bool get pending => _pending;

  /// 답이 올 때마다 오른다.
  int version = 0;

  /// 띠 uid의 자리(모르면 null).
  CrownBand? bandOf(String uid) => _bands[uid];

  /// 왕관 칸 묶음(띠 번호, 지도자 순번) — 동군연합 이음줄 층이 그 짝을 걷는다(정한 것 #7).
  Set<(int, int)> get cells => _cells;

  /// 지금 배치([layout]의 머리 단 문화권에 든 사람 띠)로 표를 맞춘다 — 저장소 판 [store]가 바뀌었을 때만 다시 묻는다.
  void sync(SceneLayout layout, int store) {
    if (store == _store) return;
    _store = store;
    final turn = ++_turn;
    final wanted = <String>{
      for (int k = 0; k < layout.spheres.length; k++)
        for (final p in layout.sphereRowsOf(k).persons)
          for (final c in p.crowns)
            if (c.uid.isNotEmpty) c.uid,
    };
    final had = _bands.isNotEmpty;
    _bands = const {};
    _cells = const {};
    final ask = this.ask;
    if (wanted.isEmpty || ask == null) {
      _pending = false;
      if (had) {
        version++;
        onReady?.call();
      }
      return;
    }
    _pending = true;
    _resolve(ask, wanted.toList(), turn, layout);
  }

  /// 검사 · 그림 저장이 표를 바로 넣는다([store]는 그 장면의 storeVersion — 같은 판의 [sync]는 이 표를 그대로 둔다).
  void put(Map<String, CrownBand> bands, SceneLayout layout, {required int store}) {
    _store = store;
    _turn++;
    _pending = false;
    _accept(bands, layout);
  }

  void _accept(Map<String, CrownBand> bands, SceneLayout layout) {
    _bands = Map.unmodifiable(bands);
    _cells = {
      for (int k = 0; k < layout.spheres.length; k++)
        for (final p in layout.sphereRowsOf(k).persons)
          for (final c in p.crowns)
            if (_bands[c.uid] != null) (_bands[c.uid]!.id, c.cell),
    };
    version++;
  }

  Future<void> _resolve(Future<Map<String, dynamic>> Function(Map<String, dynamic>) ask, List<String> uids, int turn, SceneLayout layout) async {
    final places = <String, ({int id, int row, int? start, int? end})>{};
    int? toInt(Object? v) => v is num ? v.toInt() : null;
    void read(Object? list) {
      if (list is! List) return;
      for (final one in list) {
        if (one is! Map) continue;
        final uid = one['uid'], id = toInt(one['id']);
        if (uid is! String || id == null || places.containsKey(uid)) continue;
        places[uid] = (id: id, row: toInt(one['row']) ?? -1, start: toInt(one['start']), end: toInt(one['end']));
      }
    }

    try {
      for (int at = 0; at < uids.length; at += 2000) {
        final part = uids.sublist(at, at + 2000 > uids.length ? uids.length : at + 2000); // 계약 2-1: 한 번에 2000개까지
        read((await ask({'op': 'ids_of', 'uids': part}))['bands']);
      }
    } catch (_) {
      // ids_of를 아직 모르는 자료 처리부 — id_of를 하나씩(app_glue.dart `placesOf`와 같은 물러섬)
      for (final uid in uids) {
        if (places.containsKey(uid)) continue;
        try {
          final one = await ask({'op': 'id_of', 'uid': uid});
          final id = toInt(one['band']);
          if (id != null) places[uid] = (id: id, row: toInt(one['row']) ?? -1, start: toInt(one['start']), end: toInt(one['end']));
        } catch (_) {
          break;
        }
      }
    }
    if (turn != _turn) return;
    final ids = {for (final p in places.values) p.id};
    final leaders = <int, List<CrownCell>>{};
    await Future.wait([
      for (final id in ids)
        () async {
          try {
            final answer = await ask({'op': 'cells_of', 'band': id, 'kind': 1});
            final items = answer['items'];
            leaders[id] = [
              if (items is List)
                for (final c in items)
                  if (c is Map && c['start'] is num && c['end'] is num)
                    CrownCell((c['start'] as num).toInt(), (c['end'] as num).toInt(), toInt(c['style']) ?? 0),
            ]..sort((a, b) => a.start != b.start ? a.start.compareTo(b.start) : a.end.compareTo(b.end));
          } catch (_) {
            leaders[id] = const [];
          }
        }(),
    ]);
    if (turn != _turn) return;
    _pending = false;
    _accept({for (final e in places.entries) e.key: CrownBand(e.value.id, e.value.row, e.value.start, e.value.end, List.unmodifiable(leaders[e.value.id] ?? const <CrownCell>[]))}, layout);
    onReady?.call();
  }
}

