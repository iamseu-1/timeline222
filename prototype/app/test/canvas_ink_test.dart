import 'dart:io';

import 'package:archive_prototype/scene/color_mix.dart';
import 'package:archive_prototype/scene/paint/bands.dart';
import 'package:archive_prototype/scene/paint/gutter.dart';
import 'package:archive_prototype/scene/paint/ink.dart';
import 'package:archive_prototype/scene/paint/links.dart';
import 'package:archive_prototype/scene/paint/look.dart';
import 'package:archive_prototype/scene/paint/paint_pick.dart';
import 'package:archive_prototype/scene/paint/scopes.dart';
import 'package:archive_prototype/scene/paint/sphere_lines.dart';
import 'package:archive_prototype/scene/paint/sphere_threads.dart';
import 'package:flutter_test/flutter_test.dart';

// 그림판 먹 여섯 단계(scene/paint/ink.dart `CanvasInk` — 4단계 감독 고름 G5 #8 먹 가 · 차례 걸음 11)의 검사:
// 자르기 표(고르기 판 g-g5-8.js SETS.six 그대로) · 스위치 `ink`를 끄면 옛 값 그대로 · 바꾼 값 표 · 그림판에 날 먹 값이 남지 않음(글 훑기).

String hex(int argb) => (argb & 0xffffffff).toRadixString(16).padLeft(8, '0');

void main() {
  tearDown(PaintPick.reset);

  group('자르기 표', () {
    test('단계 여섯과 자르기 표는 고르기 판 SETS.six 그대로', () {
      expect(CanvasInk.steps, [.85, .60, .45, .25, .12, .04]);
      expect(CanvasInk.cut, [(70.0, .85), (52.0, .60), (33.0, .45), (17.0, .25), (7.0, .12), (0.0, .04)]);
    });

    test('옛 짙기 → 단계(70 이상 85 · 52 이상 60 · 33 이상 45 · 17 이상 25 · 7 이상 12 · 나머지 4)', () {
      final table = <double, double>{
        1: .85, .92: .85, .85: .85, .80: .85, .78: .85, .75: .85, .72: .85, .70: .85,
        .69: .60, .65: .60, .60: .60, .55: .60, .52: .60,
        .51: .45, .50: .45, .45: .45, .40: .45, .35: .45, .33: .45,
        .32: .25, .30: .25, .25: .25, .20: .25, .18: .25, .17: .25,
        .16: .12, .15: .12, .12: .12, .095: .12, .07: .12,
        .069: .04, .06: .04, .05: .04, .04: .04, .035: .04, .03: .04, .025: .04, .001: .04,
      };
      for (final MapEntry(key: old, value: to) in table.entries) {
        expect(CanvasInk.snap(old), to, reason: '옛 ${old * 100}');
        expect(CanvasInk.step(old), to, reason: '스위치 켬(기본) — 옛 ${old * 100}');
      }
      expect(CanvasInk.snap(0), 0, reason: '먹 없음(투명)은 0 그대로');
    });

    test('단계의 종이 위 고른 색 = 먹과 종이를 그 단계로 섞은 회색', () {
      for (int i = 0; i < CanvasInk.steps.length; i++) {
        expect(hex(CanvasInk.colors[i]), hex(mixSrgb(Look.ink, Look.paper, CanvasInk.steps[i])), reason: '단계 ${CanvasInk.steps[i]}');
        expect(hex(CanvasInk.gray(CanvasInk.steps[i])), hex(CanvasInk.colors[i]), reason: '단계 위의 값은 그대로');
      }
      expect([CanvasInk.k85, CanvasInk.k60, CanvasInk.k45, CanvasInk.k25, CanvasInk.k12, CanvasInk.k4], CanvasInk.colors);
      expect([CanvasInk.a85, CanvasInk.a60, CanvasInk.a45, CanvasInk.a25, CanvasInk.a12, CanvasInk.a4], CanvasInk.steps);
    });

    test('날 색 → 단계: 불투명 회색은 고른 회색 · 먹 알파는 먹 알파 · 이미 단계 위면 그대로 · 나라 색은 그대로', () {
      expect(hex(CanvasInk.of(Look.ink)), hex(CanvasInk.k85), reason: '먹 100 → 85');
      expect(hex(CanvasInk.of(0xff474747)), hex(CanvasInk.k85), reason: '사건 이름 72 → 85');
      expect(hex(CanvasInk.of(0xff737373)), hex(CanvasInk.k60), reason: '주기 칸 글 55 → 60');
      expect(hex(CanvasInk.of(0xff808080)), hex(CanvasInk.k45), reason: '옮겨 앉기 실 50 → 45');
      expect(hex(CanvasInk.of(Look.line)), hex(CanvasInk.k25), reason: '먹 20 → 25');
      expect(hex(CanvasInk.of(0xb3000000)), hex(withAlpha(Look.ink, .85)), reason: '먹 알파 70 → 85(알파 그대로의 꼴)');
      expect(hex(CanvasInk.of(0x29666666)), hex(withAlpha(Look.ink, .12)), reason: 'muted 16% 알파(종이 위 약 10) → 먹 알파 12');
      for (final same in [Look.muted, CanvasInk.k85, 0xd9000000, 0x73000000, withAlpha(Look.muted, .42), withAlpha(Look.line, .6), 0xffabb3c9, Look.paper, 0x00000000]) {
        expect(hex(CanvasInk.of(same)), hex(same), reason: '${hex(same)} — 이미 단계 위 · 나라 색 · 종이 · 투명');
      }
      expect(CanvasInk.inkOf(0xffabb3c9), isNull, reason: '회색이 아니면 짙기가 없다');
      expect(CanvasInk.inkOf(0xff666666), .6);
      expect(CanvasInk.inkOf(0x99cccccc), .12);
    });
  });

  group('스위치 ink 끔(--paint-off=ink) — 옛 값 그대로', () {
    test('step · gray · alpha · of가 옛 값을 돌려준다', () {
      PaintPick.ink = false;
      for (final old in [1.0, .85, .80, .78, .75, .72, .70, .65, .60, .55, .50, .45, .42, .40, .35, .30, .25, .20, .15, .12, .09, .05, .04, .035, .03, .025, 0.0]) {
        expect(CanvasInk.step(old), old);
        expect(hex(CanvasInk.gray(old)), hex(mixSrgb(Look.ink, Look.paper, old)), reason: 'gray $old');
        for (final times in [1.0, .58, .45, .2]) {
          expect(hex(CanvasInk.alpha(old, times)), hex(withAlpha(Look.ink, old * times)), reason: 'alpha $old × $times');
        }
      }
      expect(hex(CanvasInk.alpha(.20)), hex(withAlpha(Look.ink, .20)));
      for (final raw in [Look.ink, Look.muted, Look.line, 0xff474747, 0xff262626, 0xff737373, 0xff666666, 0xff808080, 0xd9000000, 0x73000000, 0xb3000000, 0x29666666, 0x6b666666, 0x99cccccc]) {
        expect(hex(CanvasInk.of(raw)), hex(raw), reason: hex(raw));
      }
    });
  });

  group('바꾼 값 표(계획 과제 9 걸음 2 덧글) — 옛 값 → 단계', () {
    test('폴더 · 상자 · 작은 꼬리표 · 열쇠표', () {
      expect(hex(CanvasInk.alpha(FolderLook.innerAlpha)), hex(withAlpha(Look.ink, .12)), reason: '안쪽 겹선 12 그대로');
      expect(hex(CanvasInk.gray(ScopeLook.boxEdge)), hex(CanvasInk.k25), reason: '상자 테 25 그대로');
      expect(hex(CanvasInk.gray(ScopeLook.boxLid)), hex(CanvasInk.k4), reason: '상자 뚜껑 4 그대로');
      // 과제 7 걸음 2: 뚜껑 밑선은 먹 12(예전 테 25) · 접힌 상자의 칠 6 · 테 30 · ▸ 50은 단계에 없어 가까운 단계 4 · 25 · 45로.
      expect(hex(CanvasInk.gray(ScopeLook.boxRule)), hex(CanvasInk.k12), reason: '상자 뚜껑 밑선 12');
      expect(hex(CanvasInk.gray(ScopeLook.closedFill)), hex(CanvasInk.k4), reason: '접힌 상자 칠 6 → 4');
      expect(hex(CanvasInk.gray(ScopeLook.closedEdge)), hex(CanvasInk.k25), reason: '접힌 상자 테 30 → 25');
      expect(hex(CanvasInk.gray(ScopeLook.closedArrowInk)), hex(CanvasInk.k45), reason: '접힌 상자 ▸ 50 → 45');
      expect(hex(CanvasInk.gray(FolderLook.threadPct)), hex(CanvasInk.k45), reason: '매다는 실 45 그대로');
      expect(hex(CanvasInk.gray(.4)), hex(CanvasInk.k45), reason: '라벨 종이 테 · +n 칩 테 · 머리 단 구멍 테 40 → 45');
      expect(hex(CanvasInk.gray(.5)), hex(CanvasInk.k45), reason: '폴더 수 50 → 45');
      expect(hex(CanvasInk.gray(.75)), hex(CanvasInk.k85), reason: '이름표 시대 탭 글 75 → 85');
      expect(hex(CanvasInk.gray(.65)), hex(CanvasInk.k60), reason: '열쇠표 글 65 → 60');
    });

    test('문화권 머리 단 · 그 밑 줄 · 실 · 뿔', () {
      expect(hex(CanvasInk.gray(Gut.sphereFill)), hex(CanvasInk.k4), reason: '머리 단 칠 3 → 4');
      expect(hex(CanvasInk.gray(Gut.sphereEdge)), hex(CanvasInk.k25), reason: '머리 단 테 25 그대로');
      expect(hex(CanvasInk.gray(SphereLinesLook.chipEdge)), hex(CanvasInk.k25), reason: '시대 칩 테 30 → 25');
      expect(hex(CanvasInk.gray(SphereLinesLook.cycleFill)), hex(CanvasInk.k4), reason: '주기 줄 칠 2.5 → 4');
      expect(hex(CanvasInk.gray(SphereLinesLook.cycleEdge)), hex(CanvasInk.k12), reason: '주기 줄 테 15 → 12');
      expect(hex(CanvasInk.gray(SphereLinesLook.cellEdge)), hex(CanvasInk.k12), reason: '칸 금 12 그대로');
      expect(hex(CanvasInk.gray(SphereLinesLook.firstEdge)), hex(CanvasInk.k45), reason: '첫 이름 금 35 → 45');
      expect(hex(CanvasInk.gray(SphereLinesLook.personEdge)), hex(CanvasInk.k45), reason: '사람 띠 테 50 → 45');
      expect(hex(SphereLinesLook.cell.color), hex(CanvasInk.k60), reason: '주기 칸 글 55 → 60');
      expect(hex(SphereLinesLook.personWhen.color), hex(CanvasInk.k60), reason: '사람 띠 때 글 55 → 60');
      expect(hex(SphereLinesLook.chip.color), hex(CanvasInk.k85));
      expect(hex(CanvasInk.gray(SphereThreadLook.ink)), hex(CanvasInk.k45), reason: '실 50 → 45');
      expect(hex(CanvasInk.gray(SphereThreadLook.hornInk)), hex(CanvasInk.k45), reason: '뿔 테 45 그대로');
    });

    test('사건 이름 · 출처 글 · 옮겨 앉기 실', () {
      for (final look in [Look.event3, Look.event2, Look.event1]) {
        expect(hex(look.color), hex(CanvasInk.k85), reason: '사건 이름 100 · 72 → 85');
      }
      expect(hex(BandLayer.borrowLook.color), hex(CanvasInk.k60), reason: '빌린 층 출처 글 55 → 60');
      expect(hex(BandLayer.powerNameLook.color), hex(CanvasInk.k85), reason: '제 안의 실권자 이름 100 → 85');
      expect(hex(MoveLook.ink), hex(CanvasInk.k45), reason: '옮겨 앉기 실 · 매듭 50 → 45');
    });
  });

  group('날 먹 값 훑기', () {
    test('훑개가 날 값을 찾아낸다(훑개 자체의 검사)', () {
      const bad = [
        'final a = mixSrgb(Look.ink, Look.paper, .45);',
        'final b = withAlpha(Look.ink, .20 * dim);',
        'final c = mixSrgb( Look.ink , Look.paper , FolderLook.threadPct);',
        'static const look = TextLook(8, ui.FontWeight.w400, 0xff737373);',
        'final d = withAlpha(Look.muted, alpha);',
        'final e = Look.line;',
      ];
      for (final line in bad) {
        expect(rawInkOf(line), isNotEmpty, reason: line);
      }
      const good = [
        'final a = CanvasInk.gray(.45);',
        'final b = CanvasInk.alpha(.20, dim);',
        'final c = CanvasInk.of(0xff737373);',
        'final d = withAlpha(CanvasInk.of(Look.muted), alpha);',
        'final e = mixOklab(0xff000000 | rgb, Look.ink, .84);',
        'final f = withAlpha(Look.paper, dim);',
        '/// 옛 `mixSrgb(Look.ink, Look.paper, .4)`',
      ];
      for (final line in good) {
        expect(rawInkOf(line), isEmpty, reason: line);
      }
    });

    test('그림판(scene/paint/*.dart) · 사건 글자(label_batch · labels)에 날 먹 값이 빼는 목록 밖에 없다', () {
      final files = [
        for (final f in Directory('lib/scene/paint').listSync().whereType<File>())
          if (f.path.endsWith('.dart') && !_skipFiles.contains(_name(f.path))) f,
        File('lib/scene/label_batch.dart'),
        File('lib/scene/labels.dart'),
      ];
      expect(files.length, greaterThan(15));
      final found = <String>[];
      final used = <String>{};
      for (final f in files) {
        final name = _name(f.path);
        final lines = f.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final hits = rawInkOf(lines[i]);
          if (hits.isEmpty) continue;
          final allow = _allow.where((a) => a.$1 == name && lines[i].contains(a.$2)).toList();
          if (allow.isNotEmpty) {
            used.addAll(allow.map((a) => '${a.$1} ${a.$2}'));
            continue;
          }
          found.add('$name:${i + 1} ${hits.join(' · ')} — ${lines[i].trim()}');
        }
      }
      expect(found, isEmpty, reason: '그림판 먹은 CanvasInk(gray · alpha · of)로 — 그대로 두는 것은 빼는 목록에 까닭과 함께');
      expect(used, {for (final a in _allow) '${a.$1} ${a.$2}'}, reason: '빼는 목록에 쓰이지 않는 줄이 남지 않게');
    });
  });
}

/// 훑지 않는 파일: 날짜 칸(틀 먹) · 먹 토큰 자리 그 자체.
const _skipFiles = {'axis.dart', 'ink.dart'};

/// 빼는 목록(파일 · 줄에 든 글 · 까닭) — 그림판 먹 단계로 내지 않고 그대로 두는 자리.
const _allow = <(String, String, String)>[
  ('gutter.dart', 'static int _ink(double a) => mixSrgb(Look.ink, Look.paper, a);', '왼쪽 칸의 머리 단 밖(줄 이름 · 트랙 · 폴더 그림) — 틀 먹 B안'),
  ('look.dart', 'static const paper = ', '바탕 토큰(종이 · 먹 · muted · line · accent)'),
  ('look.dart', 'static const text2 = ', '바탕 토큰'),
  ('look.dart', 'static const ground = ', '그림판 바탕 6% — 감독이 따로 고름'),
  ('look.dart', 'static const gridLine = ', '세로 눈금'),
  ('grid.dart', 'mixSrgb(0xffa0bcc5, 0xffcccccc, .6)', '세로 눈금(0년 금)'),
  ('bands.dart', 'final base = refuted ? Look.muted : c;', '부정된 띠의 칠 — 나라 색 자리에 muted를 넣는 띠 색 섞임(설계 4-4)'),
  ('bands.dart', 'final fogEdge = refuted ? withAlpha(Look.muted, .50) : edge;', '부정된 띠의 테 — 띠 색 섞임'),
  ('bands.dart', 'mixOklab(Look.muted, Look.ink, .84)', '부정된 운동 띠의 기둥 — 띠 색 섞임'),
  ('figures.dart', 'mixSrgb(color, Look.muted, .30)', '인물 이름 — 나라 색 + muted'),
  ('hangs.dart', 'mixSrgb(c, Look.muted, .35)', '구역 탭 글 — 나라 색 + muted'),
];

String _name(String path) => path.replaceAll('\\', '/').split('/').last;

final _mixInk = RegExp(r'mixSrgb\(\s*Look\.ink\s*,\s*Look\.paper\s*,');
final _alphaInk = RegExp(r'withAlpha\(\s*Look\.ink\s*,');
final _grayHex = RegExp(r'0x([0-9a-fA-F]{2})([0-9a-fA-F]{2})\2\2(?![0-9a-fA-F])');
final _mutedLine = RegExp(r'(^|[^A-Za-z_])Look\.(muted|line)(?![A-Za-z_0-9])');

/// 먹 · 종이로만 된 색이 날 값으로 든 자리(주석 밖) — 쓰임새 이름 목록. 빈 목록이면 깨끗하다.
/// 날 값 = `mixSrgb(Look.ink, Look.paper, …)` · `withAlpha(Look.ink, …)` · 회색 16진 상수(R = G = B — 종이 · 먹 · 마스크는 뺌 · `CanvasInk.of(` 안은 옛 값이라 뺌) ·
/// [Look.muted] · [Look.line]을 CanvasInk 없이 쓴 줄.
List<String> rawInkOf(String line) {
  final t = line.trimLeft();
  if (t.startsWith('//')) return const [];
  final cut = line.indexOf(' //');
  final code = cut < 0 ? line : line.substring(0, cut);
  final out = <String>[];
  if (_mixInk.hasMatch(code)) out.add('mixSrgb(Look.ink, Look.paper, …)');
  if (_alphaInk.hasMatch(code)) out.add('withAlpha(Look.ink, …)');
  for (final m in _grayHex.allMatches(code)) {
    final v = m.group(0)!.toLowerCase();
    if (const {'0xff000000', '0xffffffff', '0x00ffffff', '0x00000000', '0x7fffffff', '0x3fffffff'}.contains(v)) continue;
    if (code.substring(0, m.start).endsWith('CanvasInk.of(')) continue;
    out.add('회색 $v');
  }
  if (_mutedLine.hasMatch(code) && !code.contains('CanvasInk.')) out.add('Look.muted · Look.line');
  return out;
}
