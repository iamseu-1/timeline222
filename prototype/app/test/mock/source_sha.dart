import 'dart:io';

/// 원본 사본의 지문 — test/mock/source/mock-sha.txt의 'SHA-256 앞 12자, 빈칸, *파일 이름' 줄을 파일 이름 → 지문으로.
/// 정답지(fixtures)가 옮긴 판과 같은 판에서 뽑혔는지 견주는 검사가 쓴다.
Map<String, String> mockSourceSha() {
  final out = <String, String>{};
  for (final line in File('test/mock/source/mock-sha.txt').readAsLinesSync()) {
    final m = RegExp(r'^([0-9a-f]{12})\s+\*?(.+)$').firstMatch(line);
    if (m != null) out[m[2]!.trim()] = m[1]!;
  }
  return out;
}
