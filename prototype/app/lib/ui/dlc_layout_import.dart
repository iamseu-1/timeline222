import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// DLC 파일의 머리 읽기 — 팩 파일(js/packfile.js의 전용 팩) 머리 · 본문 맨 바깥의 글자 id · 판 · 이름([readDlcFileHead]), 판 견주기([compareDlcVersion]),
// 카드의 판 · 원본([DlcPackFacts]). 넣기 · 빼기는 모두 엔진 `add_pack` · `remove_pack`이 한다(계약 2-7-1 · 계획 P4 과제 10b · 11).
//
// 예전의 아카이브 배치 파일(.htlayout — 메이커의 '아카이브용으로 내보내기'가 만들던 팩 파일 종류 3)은 받지 않는다(계획 P4 과제 11c · 판정 R41):
// 고르면 엔진에 닿기 전에 쉬운 알림([dlcOldLayoutText])만 한다. 예전에 그 배치로만 든 DLC(원본 없음)는 그 DLC의 .htpack을 더해 원본을 채운다
// (엔진 `add_pack` — 표 없는 옛 저장소면 앱이 DLC 폴더에 두었다가 시드 잇기가 새 판 자료로 함께 옮긴다 · `ui/dlc_add.dart`).

/// 팩 파일 머리(`js/packfile.js` — 52바이트: 식별 8 · 규격 · 종류 · 압축 1 · 0 · 풀린 크기 · 압축 크기 · 지문 32)의 식별 바이트 `HTPACK\r\n`.
const packFileMagic = <int>[72, 84, 80, 65, 67, 75, 13, 10];

/// 머리의 길이 · 규격 판(8번 바이트).
const packFileHeader = 52, packFileVersion = 2;

/// 머리 9번 바이트(종류): 1 DLC · 2 전체 백업 · 3 아카이브 배치(예전 — 받지 않음).
const packKindDlc = 1, packKindBackup = 2, packKindLayout = 3;

/// 예전 아카이브 배치 파일(.htlayout)을 골랐을 때의 알림(계획 P4 과제 11c) — 앱은 이제 DLC 파일(.htpack)만 받는다.
String dlcOldLayoutText(String name) => '$name — 예전 배치 파일(.htlayout)입니다 — 메이커에서 .htpack으로 저장해 넣어 주세요.';

/// 받는 크기 — `js/packfile.js`의 LIMITS(파일 64MB · 풀린 본문 128MB).
const packFileLimit = 64 * 1024 * 1024, packPlainLimit = 128 * 1024 * 1024;

/// 경로의 마지막 마디(파일 이름). 다른 꾸러미를 더하지 않으려고 나눔표 둘을 함께 본다.
String fileBaseName(String path) => path.split(RegExp(r'[\\/]')).last;

String _mb(int n) => '${(n / (1024 * 1024)).round()}MB';

/// 판(점으로 적은 수 — "1.0.5")을 마디마다 수로 견준다 — 엔진(`packs.rs` `compare_versions`) · `add-dlc.mjs`의 compareVersion과 같은 규칙
/// (마디의 앞 숫자만 · 없으면 0 · 빈 마디는 0).
int compareDlcVersion(String a, String b) {
  List<int> parts(String v) => [for (final n in v.split('.')) int.tryParse(RegExp(r'^\d*').stringMatch(n.trim()) ?? '') ?? 0];
  final x = parts(a), y = parts(b);
  for (int i = 0; i < (x.length > y.length ? x.length : y.length); i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

/// DLC 파일 하나의 머리 — 본문 맨 바깥의 글자 id · 판 · 이름([readDlcFileHead]).
class DlcFileHead {
  const DlcFileHead(this.path, this.id, this.version, this.name);
  final String path, id, version, name;
}

/// [readDlcFileHead]의 답 — 머리([head]) 또는 사람에게 보일 까닭([problem]) 하나.
class DlcFileRead {
  const DlcFileRead.ok(DlcFileHead this.head) : problem = null;
  const DlcFileRead.bad(String this.problem) : head = null;
  final DlcFileHead? head;
  final String? problem;
}

/// 고른 파일이 DLC인지 엔진에 주기 전에 본다(계획 P4 과제 10b — 엔진 `add_pack`이 받는 것: .htpack 형식 1 ~ 4 · .json 본문): 팩 파일이면 머리(종류 1 ·
/// 규격 · 크기)를 보고 압축 본문을 **앞에서부터 조금씩** 풀어, `.json`이면 그대로 맨 바깥의 `format` · `id` · `version` · `name`을 읽는다(넷을 다 찾으면
/// 거기서 멈춘다 — 큰 본문 전체를 풀거나 해석하지 않는다). 지문(SHA-256) · 내용 검사는 엔진이 한다. 이름 · 지문으로 같은 DLC를 알아보는 데에도 쓴다
/// (DLC 폴더의 같은 id 다른 파일 · 끈 DLC를 다시 더함). 예전 배치 파일(.htlayout — 이름이나 머리의 종류 3)은 [dlcOldLayoutText]로 알린다.
DlcFileRead readDlcFileHead(String path) {
  final name = fileBaseName(path);
  final file = File(path);
  final lower = path.toLowerCase();
  if (lower.endsWith('.htlayout')) return DlcFileRead.bad(dlcOldLayoutText(name));
  if (!file.existsSync()) return DlcFileRead.bad('파일이 없습니다: $name');
  RandomAccessFile? raf;
  try {
    final length = file.lengthSync();
    if (length > packFileLimit) return DlcFileRead.bad('$name — 파일이 너무 큽니다(${_mb(packFileLimit)}까지).');
    raf = file.openSync();
    final head = raf.readSync(packFileHeader);
    final pack = head.length >= packFileMagic.length && [for (int i = 0; i < packFileMagic.length; i++) head[i] == packFileMagic[i]].every((same) => same);
    final scan = _TopFields();
    if (pack) {
      if (head.length < packFileHeader) return DlcFileRead.bad('$name — 팩 파일의 머리 부분이 잘렸습니다.');
      if (head[8] != packFileVersion) return DlcFileRead.bad('$name — 지원하지 않는 팩 형식입니다. 메이커와 연표의 버전을 확인하세요.');
      if (head[9] == packKindLayout) return DlcFileRead.bad(dlcOldLayoutText(name));
      if (head[9] == packKindBackup) return DlcFileRead.bad('$name — 전체 백업 팩이라 DLC로 넣을 수 없습니다.');
      if (head[9] != packKindDlc || head[10] != 1 || head[11] != 0) return DlcFileRead.bad('$name — 팩 파일의 머리 부분이 올바르지 않습니다.');
      if (!lower.endsWith('.htpack')) return DlcFileRead.bad('$name — DLC 팩 파일은 이름이 .htpack으로 끝나야 합니다(이름을 바꿔 다시 골라 주세요).');
      final view = ByteData.sublistView(head);
      final size = view.getUint32(12, Endian.little), packed = view.getUint32(16, Endian.little);
      if (size == 0 || size > packPlainLimit) return DlcFileRead.bad('$name — 팩을 풀면 허용 크기(${_mb(packPlainLimit)})를 넘거나 내용이 없습니다.');
      if (packed == 0 || packed != length - packFileHeader) return DlcFileRead.bad('$name — 팩 파일이 잘렸거나 불필요한 내용이 붙었습니다.');
      final filter = RawZLibFilter.inflateFilter();
      var ended = false;
      while (!ended && !scan.done) {
        final chunk = raf.readSync(64 * 1024);
        ended = chunk.isEmpty;
        if (!ended) filter.process(chunk, 0, chunk.length);
        while (!scan.done) {
          final out = ended ? filter.processed(end: true) : filter.processed(flush: false);
          if (out == null) break;
          scan.feed(out);
        }
      }
    } else if (lower.endsWith('.json')) {
      raf.setPositionSync(0);
      while (!scan.done) {
        final chunk = raf.readSync(64 * 1024);
        if (chunk.isEmpty) break;
        scan.feed(chunk);
      }
    } else {
      return DlcFileRead.bad('$name — DLC 파일(.htpack)이 아닙니다.');
    }
    if (scan.broken) return DlcFileRead.bad('$name — DLC 본문을 읽을 수 없습니다(파일이 손상되었을 수 있습니다).');
    if (scan.fields['format'] != 'history-timeline-dlc') return DlcFileRead.bad('$name — DLC 본문이 아닙니다.');
    final id = scan.fields['id'] ?? '';
    if (id.isEmpty) return DlcFileRead.bad('$name — DLC에 id가 없습니다.');
    return DlcFileRead.ok(DlcFileHead(path, id, scan.fields['version'] ?? '', (scan.fields['name'] ?? '').isEmpty ? id : scan.fields['name']!));
  } catch (_) {
    return DlcFileRead.bad('$name — 팩 내용을 풀 수 없습니다. 파일이 손상되었습니다.');
  } finally {
    raf?.closeSync();
  }
}

/// JSON 본문의 맨 바깥 칸 몇 개(`format` · `id` · `version` · `name`)를 바이트로 조금씩 받아 읽는다 — 구조 글자는 모두 ASCII라 UTF-8 여러 바이트 글자 안에서
/// 잘못 갈리지 않는다. 안쪽 칸(트랙 · 사건의 `id`)은 깊이로 거른다. 넷을 다 찾으면 [done].
class _TopFields {
  static const wanted = {'format', 'id', 'version', 'name'};
  final fields = <String, String>{};
  bool broken = false;
  int _depth = 0;
  bool _inString = false, _escaped = false, _expectKey = false, _started = false;
  String? _key;
  BytesBuilder? _text; // 맨 바깥 칸의 글(따옴표 안) 또는 글이 아닌 값(수 · 참거짓)
  bool _scalar = false;

  bool get done => broken || wanted.every(fields.containsKey) || (_started && _depth == 0);

  void feed(List<int> bytes) {
    for (final b in bytes) {
      if (done) return;
      if (_inString) {
        if (_escaped) {
          _escaped = false;
        } else if (b == 0x5c) {
          _escaped = true;
        } else if (b == 0x22) {
          _inString = false;
          if (_depth == 1 && _text != null) _endString();
          continue;
        }
        _text?.addByte(b);
        continue;
      }
      if (_scalar) {
        if (b == 0x2c || b == 0x7d || b == 0x20 || b == 0x0a || b == 0x0d || b == 0x09) {
          _endScalar();
        } else {
          _text!.addByte(b);
          continue;
        }
      }
      switch (b) {
        case 0x22: // "
          _inString = true;
          _text = _depth == 1 ? BytesBuilder(copy: false) : null;
        case 0x7b || 0x5b: // { [
          if (!_started) {
            if (b != 0x7b) {
              broken = true;
              return;
            }
            _started = true;
            _expectKey = true;
          }
          _depth++;
        case 0x7d || 0x5d: // } ]
          _depth--;
        case 0x3a: // :
          if (_depth == 1) _expectKey = false;
        case 0x2c: // ,
          if (_depth == 1) {
            _expectKey = true;
            _key = null;
          }
        case 0x20 || 0x0a || 0x0d || 0x09 || 0xef || 0xbb || 0xbf: // 빈칸 · 맨 앞 BOM
          break;
        default:
          if (!_started) {
            broken = true;
            return;
          }
          if (_depth == 1 && !_expectKey && _key != null) {
            _scalar = true;
            _text = BytesBuilder(copy: false)..addByte(b);
          }
      }
    }
  }

  void _endString() {
    final text = _decode();
    if (_expectKey) {
      _key = text;
    } else if (_key != null && wanted.contains(_key)) {
      fields.putIfAbsent(_key!, () => text ?? '');
    }
    _text = null;
  }

  void _endScalar() {
    _scalar = false;
    final raw = utf8.decode(_text!.takeBytes(), allowMalformed: true);
    _text = null;
    if (_key != null && wanted.contains(_key) && raw != 'null') fields.putIfAbsent(_key!, () => raw);
  }

  String? _decode() {
    try {
      return jsonDecode('"${utf8.decode(_text!.takeBytes())}"') as String;
    } catch (_) {
      broken = true;
      return null;
    }
  }
}

/// DLC 카드에 적는 판 · 원본(5-6). 글자 id마다 하나. 값은 모두 자료 처리부가 준 것이다 — 옛 저장소에는 없다(빈 표).
class DlcPackFacts {
  const DlcPackFacts({this.version = '', this.original = true});

  /// DLC의 판(모르면 빈 글).
  final String version;

  /// 원본 팩을 저장소에 품었는가. 거짓이면 카드에 `원본 없음`(예전 메이커 배치로만 든 DLC) — 그 DLC의 .htpack을 더해 원본을 채운다.
  final bool original;

  /// `original` 칸 읽기 — false · 0 · "0" · "false"만 거짓(빠지면 참: 옛 저장소는 늘 원본을 품었다).
  static bool _truthy(Object? v) => !(v == false || v == 0 || v == '0' || v == 'false');

  static String _text(Object? v) => v == null ? '' : '$v';

  /// 가져오기가 남긴 `meta.pack_info`(`{"<번호>":{"id","version","category","original"}}` — JSON 글 또는 표) → 글자 id마다.
  static Map<String, DlcPackFacts> fromMeta(Map? meta) {
    final raw = meta?['pack_info'];
    Object? info = raw;
    if (raw is String) {
      try {
        info = jsonDecode(raw);
      } catch (_) {
        return const {};
      }
    }
    if (info is! Map) return const {};
    return {
      for (final v in info.values)
        if (v is Map && _text(v['id']).isNotEmpty) _text(v['id']): DlcPackFacts(version: _text(v['version']), original: _truthy(v['original'])),
    };
  }

  /// `{"op":"layout"}`의 `packs[]`(`key` · `version` · `original`) → 글자 id마다. 열쇠가 없는 옛 저장소의 줄은 빠진다.
  static Map<String, DlcPackFacts> fromLayoutJson(Map? layout) => {
    for (final p in (layout?['packs'] as List?) ?? const [])
      if (p is Map && _text(p['key']).isNotEmpty) _text(p['key']): DlcPackFacts(version: _text(p['version']), original: _truthy(p['original'])),
  };
}
