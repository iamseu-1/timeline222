import 'dart:io';

// 검사가 자료 처리부 원본(prototype/engine/src)에서 읽는 약속 값. 진짜 DLL로 도는 검사가 "지금 엔진이 짓는 것"과 견줄 때 쓴다
// — 엔진이 값을 올리면(리메이크 3단계의 저장소 판 '4' 같은 것) 앱 검사의 기대도 손대지 않고 따라간다.

String _schemaSource() => File('../engine/src/schema.rs').readAsStringSync();

/// 새로 짓는 저장소의 판(`schema.rs`의 `pub const VERSION`) — 새로 지은 저장소의 `meta.schema`가 이것이어야 한다.
/// 리메이크 3단계의 저장소 몫(스키마 4)이 든 엔진은 '4'다. DLL이 원본보다 낡았으면 견줌이 떨어진다(다시 지으라는 뜻).
String engineSchemaVersion() {
  final found = RegExp(r'pub const VERSION: &str = "([^"]+)";').firstMatch(_schemaSource());
  if (found == null) throw StateError('engine/src/schema.rs에서 새로 짓는 저장소의 판(VERSION)을 찾지 못했습니다');
  return found.group(1)!;
}

/// 지금 엔진이 여는 판(`schema.rs`의 `pub const OPENS` — 스키마 4 엔진은 '3' · '3.1' · '4' · '4.1').
/// 따로 지어 둔 저장소(`data/v3-100k` — 지은 도구의 판에 따라 '3'이기도 '4'이기도 하다)를 열 때 판이 이 가운데 하나인지 본다.
List<String> engineOpensVersions() {
  final found = RegExp(r'pub const OPENS: \[&str; \d+\] = \[([^\]]*)\];').firstMatch(_schemaSource());
  if (found == null) throw StateError('engine/src/schema.rs에서 여는 판(OPENS)을 찾지 못했습니다');
  final versions = [for (final m in RegExp(r'"([^"]+)"').allMatches(found.group(1)!)) m.group(1)!];
  if (versions.isEmpty) throw StateError('engine/src/schema.rs의 OPENS가 비었습니다');
  return versions;
}
