import 'glyph_ranges.dart';
import 'scene.dart';

// 왼쪽 줄 이름 칸이 쓰는 자료. 줄마다 후보 띠를 받아 두고(계약 6-8절), 어느 띠의 이름을 보일지는 보는 때와 화면 폭으로 고른다.
// 자료 처리부에 묻는 일은 줄 수에 비례할 뿐이고(자료량과 무관), 답을 기다리지 않는다 — 오기 전에는 그 줄의 이름을 그리지 않고,
// 도착하면 scene.requestFrame()으로 다음 장면을 부른다.

/// 민족 딱지 하나(`.tl-pchip` — 명세 05의 2.4절). 줄마다 하나뿐이라 그 줄의 후보 띠마다 같은 값이 실려 온다.
/// 그 줄의 정권 민족이 자리를 덮은 민족 칸과 다를 때만 있다. [scope]는 덮개가 대범위 가지일 때(한 단이면 가는 띠).
class RowChip {
  const RowChip(this.id, this.name, this.color, {this.scope = false, this.all = const []});
  final String id, name;
  final int color;
  final bool scope;

  /// 풍선에 적는 그 줄의 다른 민족 이름 모두.
  final List<String> all;

  static RowChip? fromJson(Object? json) {
    if (json is! Map) return null;
    final map = Map<String, dynamic>.from(json);
    final id = (map['id'] ?? '') as String;
    if (id.isEmpty) return null;
    return RowChip(
      id,
      (map['name'] ?? id) as String,
      ((map['color'] ?? 0) as num).toInt(),
      scope: ((map['scope'] ?? 0) as num) != 0,
      all: [for (final v in (map['all'] as List? ?? const [])) '$v'],
    );
  }
}

/// 줄 이름 칸에 함께 적을 원어의 후보 하나(10건 3 · 감독 결정 D2-2 '맨 왼쪽 구분표에서만' — 갈래 D2).
/// 내보내기(export/labels.mjs)가 [첫 원어, 첫 로마자] 차례로 싣는다. [mb]는 내장 띠 표에 없는 글자(빈 목록이면 그릴 수 있음).
class RowOrig {
  const RowOrig(this.text, {this.mb = const []});
  final String text;
  final List<int> mb;
}

/// 줄 이름 칸에 그릴 후보 띠 하나 — `{"op":"row_labels"}`의 답에 실려 오는 원소(계약 6-8절).
class RowLabel {
  const RowLabel({
    this.period = '',
    this.kind = band,
    this.name = '',
    this.years = '',
    this.color = 0,
    this.start = 0,
    this.end = 0,
    this.cap = false,
    this.member = false,
    this.count = 0,
    this.depth = -1,
    this.group = '',
    this.variant = '',
    this.lanes = const [],
    this.chip,
    this.chipOn = const {},
    this.orig = const [],
  });

  /// 0 정권 줄 · 1 그 밖 줄 · 2 접힌 민족 줄.
  static const band = 0, common = 1, foldedGroup = 2;

  /// 그 밖 줄의 이름과 색(지금 연표의 `_drawTrackLabels` 7249).
  static const commonName = '그 밖', commonColor = 0x9c978d;

  final String period, name, years;
  final int kind, color, count;

  /// 접힌 민족 줄(kind 2)일 때 그 묶음의 단계 — 한 줄에 여러 단계의 묶음이 겹치므로 어느 묶음의 것인지 가른다.
  final int depth;

  /// 접힘용 후보(kind 2)가 어느 묶음의 것인가 — 민족·문화는 그 민족 id, 대범위 가지는 `__scope:<uid>`다(지금 연표의 `gp.key`).
  /// 값이 실리지 않은 옛 저장소에서는 빈 글이다(그때는 [depth]로 가른다).
  final String group;

  /// 그 변형에서만 생기는 후보인가(`host:…` · `scope:…`). 빈 글이면 늘 있는 후보다.
  ///
  /// 그 변형에서만 있는 **줄**의 후보는 엔진이 이미 걸러 주므로(켜지 않은 변형의 줄은 이름이 없다) 그냥 쓴다.
  /// 화면이 가려야 하는 것은 하나뿐이다: **기본 줄에 얹히는** 대범위 가지의 접힘용 후보(kind 2) —
  /// 그 가지가 접혔을 때만 쓰고, 같은 줄의 민족 묶음 이름과 단계(늘 0)가 부딪치므로 [RowLabels.pick]이 열쇠로 가른다.
  final String variant;

  /// 띠의 기간(분).
  final int start, end;
  final bool cap, member;

  /// 분류별 글줄의 분류 번호(그리는 쪽은 `layout.spec(row).cats`를 쓴다 — 같은 값이다).
  final List<int> lanes;

  /// 그 줄의 민족 딱지(없으면 null). 줄마다 하나라 그 줄의 모든 후보에 같은 값이 실린다.
  final RowChip? chip;

  /// 변형(소속 펼치기 · 대범위 모아 보기)을 켰을 때의 민족 딱지 — 변형 열쇠 → 그때의 딱지(없어지면 null).
  /// 보기 조건이 줄 구성을 바꾸면 그 줄을 덮은 민족 칸이 달라져 딱지도 달라진다(계약 6-8절) —
  /// 대범위를 켜면 그 가지에 든 줄에 딱지가 새로 생긴다. 줄 이름 표에는 변형 열이 없어 이름 글 안에 함께 싣는다.
  final Map<String, RowChip?> chipOn;

  /// 원어 후보([RowOrig] — 이름 목록이 없는 띠 · 옛 저장소는 빈 목록).
  final List<RowOrig> orig;

  /// 함께 적을 원어: 후보 가운데 띠 표(내장 + 켜진 글꼴 팩의 띠에 그릴 수 있는 범위 [bandExtra])로 그릴 수 있는 첫 것 — 없으면 빈 글
  /// (웹 HT.bandOrig — 첫 원어 → 첫 로마자 → 적지 않음).
  String origFor(List<GlyphRange> bandExtra) {
    for (final o in orig) {
      if (o.text.isNotEmpty && stillMissing(o.mb, bandExtra).isEmpty) return o.text;
    }
    return '';
  }

  factory RowLabel.fromJson(Map<String, dynamic> json) => RowLabel(
    period: (json['period'] ?? '') as String,
    kind: (json['kind'] ?? 0) as int,
    name: (json['name'] ?? '') as String,
    years: (json['years'] ?? '') as String,
    color: ((json['color'] ?? 0) as num).toInt(),
    start: ((json['start'] ?? 0) as num).toInt(),
    end: ((json['end'] ?? 0) as num).toInt(),
    cap: ((json['cap'] ?? 0) as num) != 0,
    member: ((json['member'] ?? 0) as num) != 0,
    count: ((json['count'] ?? 0) as num).toInt(),
    depth: ((json['depth'] ?? -1) as num).toInt(),
    group: (json['group'] ?? '') as String,
    variant: (json['variant'] ?? '') as String,
    lanes: [for (final v in (json['lanes'] as List? ?? const [])) (v as num).toInt()],
    chip: RowChip.fromJson(json['chip']),
    chipOn: json['chipOn'] is Map
        ? {for (final e in (json['chipOn'] as Map).entries) '${e.key}': RowChip.fromJson(e.value)}
        : const {},
    orig: json['orig'] is List
        ? [
            for (final o in json['orig'] as List)
              if (o is Map && o['text'] is String) RowOrig(o['text'] as String, mb: codePoints(o['mb'])),
          ]
        : const [],
  );

  /// 켠 변형([variants] — `layout.variantKeys`)에서의 민족 딱지. 켠 것 가운데 뒤엣것이 이긴다(줄 쌓기의 차례와 같다).
  RowChip? chipFor(List<String> variants) {
    RowChip? out = chip;
    for (final key in variants) {
      if (chipOn.containsKey(key)) out = chipOn[key];
    }
    return out;
  }
}

/// 줄마다의 후보 띠를 받아 보관한다. 한 줄은 한 번만 묻고(자료는 넣을 때 정해진다), 답이 오면 [version]이 오른다.
class RowLabels {
  TimelineScene? _scene;
  final _rows = <int, List<RowLabel>>{};
  final _asked = <int>{};
  int _busy = 0;

  /// 답이 올 때마다 오른다 — 그리는 쪽이 적어 둔 이름 자리를 새로 고칠 때 본다.
  int version = 0;

  /// 아직 답을 기다리는 물음이 있는가.
  bool get pending => _busy > 0;

  /// 물어본 적이 없거나 답이 오지 않은 줄.
  bool has(int row) {
    _sync();
    return _rows.containsKey(row);
  }

  List<RowLabel> of(int row) {
    _sync();
    return _rows[row] ?? const [];
  }

  /// 받아 둔 장면의 저장소 판([TimelineScene.storeVersion]). 저장소를 바꿔 넣으면 같은 번호의 줄이 다른 나라라 받아 둔 것을 모두 버린다
  /// (예전에는 남아, DLC를 빼거나 더해 다시 지은 뒤 왼쪽 칸에 옛 저장소의 줄 이름이 섰다).
  int _store = 0;

  void _sync() {
    final scene = _scene;
    if (scene == null || scene.storeVersion == _store) return;
    _store = scene.storeVersion;
    _rows.clear();
    _asked.clear();
    version++;
  }

  /// 켠 변형(`layout.variantKeys`) — 딱지를 고를 때 본다. 그리는 쪽이 장면마다 넣어 준다.
  List<String> variants = const [];

  /// 그 줄의 민족 딱지. 어느 띠의 이름을 보이든 딱지는 줄마다 하나라 첫 후보에서 읽는다.
  /// 답이 오지 않은 줄은 null(딱지를 그리지 않는다 — 다음 장면에 온다).
  /// 대범위를 켜면 그 가지에 든 줄에 딱지가 새로 생긴다([RowLabel.chipFor] · 계약 6-8절).
  RowChip? chipOf(int row) {
    for (final label in of(row)) {
      final chip = label.chipFor(variants);
      if (chip != null) return chip;
    }
    return null;
  }

  void attach(TimelineScene scene) => _scene = scene;

  /// 검사에서 답을 바로 넣을 때.
  void accept(Map<int, List<RowLabel>> rows) {
    _rows.addAll(rows);
    _asked.addAll(rows.keys);
    version++;
  }

  /// 이번 장면에 보이는 줄. 아직 묻지 않은 줄이 있으면 한 번에 묻는다(`at`은 자료 처리부가 아직 쓰지 않지만 약속대로 함께 보낸다).
  void want(Iterable<int> rows, {int at = 0}) {
    final scene = _scene, ask = _scene?.ask;
    if (scene == null || ask == null) return;
    _sync();
    final store = _store;
    final missing = <int>[];
    for (final row in rows) {
      if (_asked.add(row)) missing.add(row);
    }
    if (missing.isEmpty) return;
    _busy++;
    ask({'op': 'row_labels', 'rows': missing, 'at': at}).then(
      (data) {
        _busy--;
        if (store != _store) return; // 그 사이 저장소를 바꿔 넣었다 — 옛 저장소의 답은 버린다(다음 장면에 다시 묻는다)
        _read(data);
        version++;
        scene.requestFrame();
      },
      onError: (Object _) {
        _busy--;
        if (store != _store) return;
        // 답을 못 받은 줄은 이름 없이 그린다(다시 묻지 않는다 — 자료가 없는 저장소일 수 있다).
        for (final row in missing) {
          _rows[row] ??= const [];
        }
        version++;
        scene.requestFrame();
      },
    );
  }

  void _read(Map<String, dynamic> data) {
    for (final entry in (data['labels'] as List? ?? const [])) {
      if (entry == null) continue;
      final map = Map<String, dynamic>.from(entry as Map);
      final row = ((map['row'] ?? -1) as num).toInt();
      if (row < 0) continue;
      final items = map['items'] as List? ?? const [];
      _rows[row] = [
        for (final item in items)
          if (item is Map) RowLabel.fromJson(Map<String, dynamic>.from(item)),
      ];
    }
  }

  /// 어느 띠의 이름을 보이는가(계약 6-8절 · 명세 05의 3.1절): 보는 때 [at]을 품은 띠, 없으면 화면에 가장 넓게 걸친 띠.
  /// 둘 다 없으면 null(빈 줄 이름 — 색 점만). [left] · [right]는 그림 영역의 양 끝(배치 px), [xOf]는 분 → 배치 x.
  /// [foldedDepth]가 0 이상이면 그 줄은 **접힌 묶음 줄**이다 — 그 단계의 묶음 이름(kind 2)을 고른다.
  /// 접힘 자료는 펴진 상태에도 함께 실려 오므로(계약 6-8절), 접히지 않은 줄에서는 kind 2 후보를 건너뛴다.
  /// [foldedVariant]가 있으면 **대범위 가지**의 합쳐진 줄이다 — 단계가 아니라 그 변형의 후보를 고른다
  /// (가지는 깊이 0이라 같은 줄의 민족 묶음과 단계가 부딪친다).
  RowLabel? pick(int row,
      {required int at,
      required double Function(num minute) xOf,
      required double left,
      required double right,
      int foldedDepth = -1,
      String foldedVariant = ''}) {
    if (foldedDepth >= 0) {
      RowLabel? any;
      for (final label in of(row)) {
        if (label.kind != RowLabel.foldedGroup) continue;
        if (foldedVariant.isNotEmpty) {
          if (label.variant == foldedVariant) return label;
          continue;
        }
        if (label.variant.isNotEmpty) continue; // 변형의 가지 이름은 그 가지가 접혔을 때만 쓴다
        if (label.depth == foldedDepth) return label;
        any ??= label;
      }
      if (any != null) return any;
    }
    RowLabel? atCenter, best;
    double bestWidth = 0;
    for (final label in of(row)) {
      if (label.kind == RowLabel.foldedGroup) continue; // 펴져 있는 줄 — 접힘용 후보는 건너뛴다
      // 그 밖 줄은 후보가 하나뿐이다.
      if (label.kind != RowLabel.band) return label;
      // 지금 연표는 뒤의 띠가 이긴다(겹친 띠가 있을 때).
      if (label.start <= at && at <= label.end) atCenter = label;
      final x0 = xOf(label.start), x1 = xOf(label.end);
      final width = (x1 < right ? x1 : right) - (x0 > left ? x0 : left);
      if (width > bestWidth) {
        bestWidth = width;
        best = label;
      }
    }
    return atCenter ?? best;
  }
}
