import 'dart:io';

import 'package:archive_prototype/engine.dart';
import 'package:archive_prototype/scene/fonts.dart';
import 'package:archive_prototype/ui/app_memory.dart';
import 'package:archive_prototype/ui/names_display.dart';
import 'package:flutter_test/flutter_test.dart';

// D2 PC 저장소의 원본 글꼴을 실제로 읽고, 사용자 자료 폴더 대신 이 작업판의 결과 폴더에서 기억을 왕복한다.
void main() {
  final dll = File('../engine/target/release/archive_engine.dll');
  final db = File('../data/d2-pc-names/archive.db');
  test('진짜 엔진의 글꼴과 저장한 표기 설정을 다음 시작에서 읽고 기본으로 되돌린다', () async {
    ScriptFonts.instance.resetForTest();
    addTearDown(ScriptFonts.instance.resetForTest);
    final engine = ArchiveEngine(libraryPath: dll.absolute.path);
    addTearDown(engine.close);
    await engine.start(db.absolute.path);
    final failures = <Object?>[];
    Future<Map<String, dynamic>> ask(Map<String, dynamic> query) async {
      final answer = await engine.call(query);
      if (answer['ok'] != true) failures.add(answer);
      expect(answer['ok'], true, reason: '$query');
      return Map<String, dynamic>.from(answer['data'] as Map);
    }

    final info = await ask({'op': 'names_info'});
    expect((info['fonts'] as List).map((f) => f['uid']), contains('font:hangul-mock'));
    final dir = await Directory('../results/d2-memory-${DateTime.now().microsecondsSinceEpoch}').create(recursive: true);
    final memory = await AppMemory.open(folder: dir, delay: Duration.zero);
    const selected = NamesUi(orig: 'band', person: false, screen: 'font:hangul-mock');
    memory.parts[slotNames] = selected.toJson();
    await memory.flush();
    memory.dispose();
    final restored = await readSavedNamesUi(folder: dir);
    expect(restored, selected);
    expect(await applySavedScreenFont(ask, saved: restored), true);
    expect(sceneFamilyNow, 'HT 글꼴 font:hangul-mock');
    expect(sceneFallbackNow.first, 'Pretendard');

    final reopened = await AppMemory.open(folder: dir, delay: Duration.zero);
    reopened.parts[slotNames] = const NamesUi().toJson();
    await reopened.flush();
    reopened.dispose();
    ScriptFonts.instance.resetForTest(); // 앱을 새로 켰을 때의 기본 상태
    expect(await applySavedScreenFont(ask, saved: await readSavedNamesUi(folder: dir)), false);
    expect(sceneFamilyNow, 'Pretendard');
    expect(failures, isEmpty);
  }, skip: !dll.existsSync() || !db.existsSync() ? 'D2 PC 저장소와 DLL을 먼저 준비한다' : false);
}
