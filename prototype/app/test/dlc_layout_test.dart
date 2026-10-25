import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/ui/dlc_add.dart';
import 'package:archive_prototype/ui/dlc_layout_import.dart';
import 'package:archive_prototype/ui/dlc_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pack_scene.dart';

// 예전 아카이브 배치 파일(.htlayout)은 앱이 받지 않는다(계획 P4 과제 11c · 판정 R41) — 고르면 엔진에 닿기 전에 쉬운 알림만([dlcOldLayoutText]).
// 카드의 판 · `원본 없음`([DlcPackFacts] — 예전 배치로만 든 DLC)과 DLC 관리 창의 그 표시도 여기서 본다.
//
// 고정 자료 `test/fixtures/tiny.htlayout`: 가상의 작은 DLC 하나(`tiny-reed` «작은 갈대 기록집» v1.0.0)를 예전 메이커 내보내기로 담은 배치
// (2026-10-12 · 기준 90d0284 — packs[]에 판이 실리기 전의 배치). 앱은 받지 않지만, 검사가 원본 없이 든 DLC의 옛 저장소를 짓는 데 쓴다
// (`support/archive_import.dart` — engine_ffi_test · seed_carry_test).

const tiny = 'test/fixtures/tiny.htlayout';

/// 팩 파일 머리 + 압축 본문(지문은 0 — 지문 검사는 자료 처리부의 몫이라 앱 쪽 검사는 보지 않는다).
Uint8List sealed(int kind, String text) {
  final plain = utf8.encode(text);
  final body = ZLibCodec().encode(plain);
  final head = Uint8List(packFileHeader)
    ..setAll(0, packFileMagic)
    ..[8] = packFileVersion
    ..[9] = kind
    ..[10] = 1;
  ByteData.sublistView(head)
    ..setUint32(12, plain.length, Endian.little)
    ..setUint32(16, body.length, Endian.little);
  return Uint8List.fromList([...head, ...body]);
}

/// 임시 폴더(검사가 끝나면 지운다).
Directory scratch() {
  final dir = Directory.systemTemp.createTempSync('ht-dlc-layout-');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

String put(Directory dir, String name, List<int> bytes) => (File('${dir.path}${Platform.pathSeparator}$name')..writeAsBytesSync(bytes)).path;

/// DLC 파일(종류 1)의 흉내 — 머리만 진짜와 같다.
List<int> dlcFile(String id, String version) => sealed(packKindDlc, jsonEncode({'format': 'history-timeline-dlc', 'id': id, 'version': version}));

void main() {
  group('예전 배치 파일(.htlayout) — 받지 않고 쉬운 알림만(계획 P4 과제 11c)', () {
    test("머리 읽기: 이름이 .htlayout이거나 머리의 종류가 3(배치)이면 '예전 배치 파일' 알림 — 메이커에서 .htpack으로 저장해 넣으라", () {
      final dir = scratch();
      expect(readDlcFileHead(tiny).problem, dlcOldLayoutText('tiny.htlayout'));
      expect(dlcOldLayoutText('tiny.htlayout'), 'tiny.htlayout — 예전 배치 파일(.htlayout)입니다 — 메이커에서 .htpack으로 저장해 넣어 주세요.');
      expect(readDlcFileHead('${dir.path}${Platform.pathSeparator}없는-파일.htlayout').problem, dlcOldLayoutText('없는-파일.htlayout'), reason: '이름만으로도');
      final renamed = put(dir, '이름만-바뀐.htpack', sealed(packKindLayout, jsonEncode({'name': '배치', 'packs': []})));
      expect(readDlcFileHead(renamed).problem, dlcOldLayoutText('이름만-바뀐.htpack'), reason: '머리(종류 3)로도');
      final dlc = put(dir, 'reed-v1.0.0.htpack', dlcFile('reed', '1.0.0'));
      expect(readDlcFileHead(dlc).head?.id, 'reed', reason: 'DLC 파일은 그대로 읽는다');
    });

    test('넣기: 고른 것에 예전 배치 파일이 섞이면 엔진에 닿지 않고 알린다 — 저장소 · DLC 폴더 그대로', () async {
      final dir = scratch();
      final db = put(dir, 'archive.db', utf8.encode('지금 저장소'));
      final layout = File(tiny).copySync('${dir.path}${Platform.pathSeparator}tiny.htlayout').path;
      final dlc = put(dir, 'reed-v1.0.0.htpack', dlcFile('reed', '1.0.0'));
      final job = DlcJob()..applier = (request) async => fail('엔진에 닿으면 안 된다: $request');
      final done = await job.apply(db: db, files: [layout, dlc]);
      expect(done.ok, isFalse);
      expect(done.storeChanged, isFalse);
      expect(job.status, dlcOldLayoutText('tiny.htlayout'));
      expect(File(db).readAsStringSync(), '지금 저장소');
      expect(Directory('${dir.path}${Platform.pathSeparator}DLC').existsSync(), isFalse);
    });

    test('도구 자리 — 검사 실행본 곁에는 도구가 없으므로 엔진 하나로(Node 없음) · 휴대폰의 길은 엔진 도구 없이', () {
      expect(DlcTools.find(), isNotNull, reason: '앱 틀은 null이면 더하기 단추를 세우지 않는다');
      expect(DlcTools.find()!.archiveTool, isEmpty);
      expect(DlcTools.engineOnly.phone, isFalse);
      expect(DlcTools.phoneOnly.phone, isTrue);
    });
  });

  group('판 · 원본 읽기(DlcPackFacts)', () {
    test('meta.pack_info · layout.packs[] — 둘 다 글자 id마다, 원본은 거짓으로 적힌 것만 없음', () {
      final meta = {
        'pack_keys': '{"1":"east-asia-base"}',
        'pack_info': '{"1":{"id":"east-asia-base","version":"2.0.0","category":"","original":true},"2":{"id":"east-band","version":"1.0.3","original":false},"3":{"id":"reed-isle","original":0}}',
      };
      final fromMeta = DlcPackFacts.fromMeta(meta);
      expect(fromMeta.keys, ['east-asia-base', 'east-band', 'reed-isle']);
      expect([for (final f in fromMeta.values) (f.version, f.original)], [('2.0.0', true), ('1.0.3', false), ('', false)]);
      expect(DlcPackFacts.fromMeta({'schema': '3'}), isEmpty, reason: '옛 저장소');
      expect(DlcPackFacts.fromMeta({'pack_info': '깨진 글'}), isEmpty);
      final fromLayout = DlcPackFacts.fromLayoutJson({
        'packs': [
          {'id': 1, 'name': '별여울', 'events': 1, 'key': 'east-asia-base', 'version': '2.0.0', 'original': 1},
          {'id': 2, 'name': '덧팩', 'events': 1, 'key': 'east-band', 'version': '1.0.3', 'original': 0},
          {'id': 3, 'name': '옛 줄', 'events': 1},
        ],
      });
      expect(fromLayout.keys, ['east-asia-base', 'east-band']);
      expect(fromLayout['east-band']!.original, isFalse);
      expect(fromLayout['east-asia-base']!.original, isTrue);
    });
  });

  group('DLC 관리 창 — 판 · 원본 없음 · 도구 없는 곳', () {
    Future<void> pump(WidgetTester tester, {Map<String, DlcPackFacts>? facts, DlcJob? job, Future<void> Function(DlcCardInfo card)? onRemove, Future<void> Function()? onAddFiles}) async {
      final (scene, _, _) = makePackScene();
      scene.layout.replaceWith(
        SceneLayout.fromJson({
          'packs': [
            {'id': 1, 'name': '별여울 기록집', 'events': 1250, 'key': 'east-asia-base'},
            {'id': 2, 'name': '해솔 기록집', 'events': 2, 'key': 'haesol'},
            {'id': 3, 'name': '은빛 나루 기록집', 'events': 2, 'key': 'silverbay'},
          ],
          'tracks': [
            {'id': 1, 'pack': 1, 'ord': 0, 'name': '별여울 갈래', 'rows': [packRow(0), packRow(1)]},
            {'id': 2, 'pack': 2, 'ord': 1, 'name': '해솔 갈래', 'rows': [packRow(2), packRow(3)]},
            {'id': 3, 'pack': 3, 'ord': 2, 'name': '은빛 나루 갈래', 'rows': [packRow(4), packRow(5)]},
          ],
          'epochs': [],
        }),
      );
      tester.view.physicalSize = const Size(1300, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: DlcManager(scene: scene, packFacts: facts, job: job, onRemove: onRemove, onAddFiles: onAddFiles))));
    }

    testWidgets('카드에 판이 이름 뒤에 · 원본이 없으면 `원본 없음` 딱지가 붙고, 자세히에 판 · 원본 줄과 되찾는 길(.htpack을 파일에서 더하기)이 선다', (tester) async {
      await pump(tester, facts: {
        'east-asia-base': const DlcPackFacts(version: '2.0.0'),
        'haesol': const DlcPackFacts(version: '1.2.0', original: false),
      });
      expect(find.textContaining('v1.2.0'), findsOneWidget);
      expect(find.textContaining('v2.0.0'), findsNWidgets(2), reason: '기본팩 카드와 (처음 고른) 자세히');
      expect(find.byKey(const ValueKey('dlc-tag-no-original')), findsOneWidget, reason: '해솔 카드에만');
      expect(find.byKey(const ValueKey('dlc-no-original')), findsNothing, reason: '자세히는 아직 기본팩');
      await tester.tap(find.text('은빛 나루 기록집').first);
      await tester.pump();
      expect(find.text('판'), findsNothing, reason: '판을 모르면 자세히에 판 줄이 없다');
      await tester.tap(find.textContaining('해솔 기록집').first);
      await tester.pump();
      expect(find.text('판'), findsOneWidget);
      expect(find.text('원본'), findsOneWidget);
      expect(find.text(dlcNoOriginalText), findsOneWidget);
      expect(dlcNoOriginalText, allOf(contains(".htpack을 '파일에서 더하기'로 넣어 주세요"), isNot(contains('다시 지으려면'))), reason: 'Node 다시 짓기 말은 걷었다(과제 11c)');
    });

    testWidgets('판 · 원본을 모르면(옛 저장소) 예전 카드 그대로', (tester) async {
      await pump(tester);
      expect(find.textContaining(RegExp(r' v\d')), findsNothing);
      expect(find.byKey(const ValueKey('dlc-tag-no-original')), findsNothing);
    });

    testWidgets('더하기 단추는 서고 · 삭제 단추는 바탕(첫 DLC) 말고 선다(엔진 remove_pack — 계획 P4 과제 10b · 판정 R43)', (tester) async {
      final job = DlcJob();
      await pump(tester, job: job, onAddFiles: () async {}, onRemove: (card) async {});
      expect(find.byKey(const ValueKey('dlc-add-files')), findsOneWidget);
      expect(find.byKey(const ValueKey('dlc-remove')), findsNothing, reason: '처음 고른 카드는 바탕 — 엔진이 빼지 못한다');
      await tester.tap(find.text('해솔 기록집').first);
      await tester.pump();
      expect(find.byKey(const ValueKey('dlc-remove')), findsOneWidget, reason: '바탕이 아니면 엔진으로 뺀다');
    });

    testWidgets('앱 틀이 뼈대를 다시 읽으면(factsFrom) 떠 있는 창의 카드가 새 판 · 원본으로 바뀐다 — 원본을 채우면 `원본 없음`이 빠진다', (tester) async {
      final job = DlcJob();
      await pump(tester, job: job, facts: {'silverbay': const DlcPackFacts(version: '0.2.0', original: false)});
      expect(find.textContaining('v0.2.0'), findsOneWidget);
      expect(find.byKey(const ValueKey('dlc-tag-no-original')), findsOneWidget);
      job.factsFrom({
        'packs': [
          {'id': 1, 'name': '별여울 기록집', 'key': 'east-asia-base', 'version': '2.0.0', 'original': 1},
          {'id': 3, 'name': '은빛 나루 기록집', 'key': 'silverbay', 'version': '0.3.0', 'original': 1},
        ],
      });
      await tester.pump();
      expect(find.textContaining('v0.3.0'), findsOneWidget, reason: '새 뼈대의 판이 덮는다');
      expect(find.textContaining('v0.2.0'), findsNothing);
      expect(find.byKey(const ValueKey('dlc-tag-no-original')), findsNothing);
    });
  });
}
