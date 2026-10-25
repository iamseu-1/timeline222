import 'dart:ui' as ui;

import 'package:archive_prototype/scene/glyph_atlas.dart';
import 'package:archive_prototype/scene/text_paragraph.dart';
import 'package:flutter_test/flutter_test.dart';

const look = TextLook(12, ui.FontWeight.w500, 0xff2e2820);
const bold = TextLook(12, ui.FontWeight.w700, 0xff2e2820);

ui.Canvas canvas() => ui.Canvas(ui.PictureRecorder());

// 시간 예산은 기계와 첫 글꼴 읽기에 따라 들쭉날쭉하다 — 검사는 개수 한도만 본다.
const noTimeLimit = 1 << 40;

void main() {
  test('같은 글자는 그림판에 한 번만 들어가고, 색은 그림판의 열쇠가 아니다', () {
    final text = AtlasText()
      ..budgetMicros = noTimeLimit
      ..beginFrame();
    expect(text.widthOf('가가가 나', look), isNotNull);
    expect(text.glyphCount, 3, reason: '가 · 빈칸 · 나');
    const red = TextLook(12, ui.FontWeight.w500, 0xffc27a45);
    expect(text.widthOf('가나', red), isNotNull);
    expect(text.glyphCount, 3, reason: '색만 다른 글자는 찍을 때 색을 입힌다');
    expect(text.widthOf('가', bold), isNotNull);
    expect(text.glyphCount, 4, reason: '굵기가 다르면 다른 글자');
  });

  test('폭은 글자 너비의 합이고 글줄 방식의 폭과 3% 안에서 같다', () {
    final atlas = AtlasText()
      ..budgetMicros = noTimeLimit
      ..beginFrame();
    final paragraph = ParagraphText()
      ..budgetMicros = noTimeLimit
      ..beginFrame();
    for (final sample in ['별여울의 첫 기록', '해솔 星河 나루의 긴 기록 0096709', '+38', 'Abc 123']) {
      final a = atlas.widthOf(sample, look)!, p = paragraph.widthOf(sample, look)!;
      expect((a - p).abs() / p, lessThan(.03), reason: sample);
    }
  });

  test('새 글자는 장면마다 정해진 만큼만 준비하고 다음 장면에 이어 간다', () {
    final text = AtlasText()
      ..maxNewPerFrame = 3
      ..budgetMicros = noTimeLimit;
    text.beginFrame();
    expect(text.widthOf('가나다라마바사', look), isNull, reason: '일곱 글자 가운데 셋만 준비됐다');
    expect(text.starved, isTrue);
    expect(text.newThisFrame, 3);
    text.beginFrame();
    expect(text.widthOf('가나다라마바사', look), isNull);
    text.beginFrame();
    expect(text.widthOf('가나다라마바사', look), isNotNull);
    expect(text.starved, isFalse);
    text.beginFrame();
    expect(text.widthOf('가나다라마바사', look), isNotNull);
    expect(text.newThisFrame, 0);
  });

  test('새 글자를 준비하는 시간이 장면의 예산을 넘으면 거기서 멈춘다(가짜 시계)', () {
    int now = 0;
    // 시계를 볼 때마다 0.4ms가 흐른다 → 글자 하나를 준비하는 데 0.4ms.
    final text = AtlasText(clock: () => now += 400)
      ..maxNewPerFrame = 1000
      ..budgetMicros = 1500;
    text.beginFrame();
    expect(text.widthOf('가나다라마바사아자차', look), isNull);
    expect(text.newThisFrame, 4, reason: '넷째 글자에서 1.6ms → 예산 1.5ms를 넘었으니 멈춘다');
    expect(text.spentMs, closeTo(1.6, 1e-9));
    expect(text.starved, isTrue);
    text.beginFrame();
    expect(text.widthOf('가나다라마바사아자차', look), isNull);
    expect(text.newThisFrame, 4);
    text.beginFrame();
    expect(text.widthOf('가나다라마바사아자차', look), isNotNull, reason: '세 장면에 나눠 열 글자를 다 준비했다');
    expect(text.newThisFrame, 2);
  });

  test('그리기는 글자마다 조각 하나를 모았다가 한 번에 내보낸다', () {
    final text = AtlasText()
      ..budgetMicros = noTimeLimit
      ..beginFrame();
    final c = canvas();
    expect(text.paint(c, '별여울 기록', look, 10.4, 20.6), isTrue);
    expect(text.paint(c, '해솔', bold, 10, 40, alpha: .5), isTrue);
    expect(text.pendingSprites, 7, reason: '빈칸은 찍지 않는다: 5 + 2');
    text.flush(c);
    expect(text.pendingSprites, 0);
    expect(text.drawCalls, 1, reason: '그림판 한 장이면 그리기도 한 번');
  });

  test('글자는 하나하나 화면 px에 맞춰 찍는다(흐림 방지) — 배율 1.5에서는 2/3px 단위', () {
    final text = AtlasText()
      ..budgetMicros = noTimeLimit
      ..setScale(1.5)
      ..beginFrame();
    text.paint(canvas(), '가나다', look, 10.4, 20.6);
    final at = text.pendingPositions.toList();
    expect(at.length, 3);
    for (final (x, y) in at) {
      expect((x * 1.5 - (x * 1.5).round()).abs(), lessThan(1e-4), reason: 'x $x');
      expect((y * 1.5 - (y * 1.5).round()).abs(), lessThan(1e-4), reason: 'y $y');
    }
    expect(at.first.$1, closeTo(10.4, .34));
  });

  test('그림판이 차면 새 장을 만든다', () {
    final text = AtlasText(pageSize: 64)
      ..budgetMicros = noTimeLimit
      ..beginFrame();
    text.maxNewPerFrame = 1000;
    expect(text.widthOf('가나다라마바사아자차카타파하거너더러머버서어저처커터퍼허', look), isNotNull);
    expect(text.pageCount, greaterThan(1));
    final c = canvas();
    text.paint(c, '가나다라마바사아자차카타파하거너더러머버서어저처커터퍼허', look, 0, 0);
    text.flush(c);
    expect(text.drawCalls, text.pageCount, reason: '장마다 한 번씩');
  });

  test('돋보기 배율을 여러 번 바꿔도 글자와 그림판 장이 쌓이지 않는다: 지금 · 직전 · 100%의 것만 남긴다', () {
    // 멎은 배율마다 글자 한 벌과 그림판 장(1024² ≈ 4MB)이 새로 생긴다. 버리지 않으면 Ctrl+휠로 크기를 맞출 때마다
    // 메모리가 늘어 앱을 끌 때까지 돌아오지 않는다 — 측정 각본은 배율을 몇 개만 써서 이 현상을 잡지 못한다.
    const sample = '별여울 해솔 은빛 나루의 긴 기록 가나다라마바사아자차카타파하';
    AtlasText make() => AtlasText(pageSize: 256)
      ..budgetMicros = noTimeLimit
      ..maxNewPerFrame = 1000;
    final c = canvas();
    void rest(AtlasText text, double scale) {
      text.setScale(scale);
      for (int i = 0; i < 2; i++) {
        text.beginFrame();
        text.paint(c, sample, look, 0, 0);
        text.flush(c);
      }
    }

    final text = make();
    for (final scale in [1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 2.75, 3.0]) {
      rest(text, scale);
    }
    final fresh = make(); // 100% · 직전 · 지금만 거친 것과 같아야 한다
    for (final scale in [1.0, 2.75, 3.0]) {
      rest(fresh, scale);
    }
    expect(text.glyphCount, fresh.glyphCount);
    expect(text.pageCount, fresh.pageCount);
    text.beginFrame();
    expect(text.paint(c, sample, look, 0, 0), isTrue);
    expect(text.sharpRatio, 1, reason: '지금 배율의 글자는 그대로 선명하다');
    // 100%로 돌아오면 남겨 둔 글자를 그대로 쓴다(다시 뜨지 않는다).
    text.setScale(1);
    text.beginFrame();
    expect(text.paint(c, sample, look, 0, 0), isTrue);
    expect(text.newThisFrame, 0);
    expect(text.sharpRatio, 1);
  });

  test('돋보기 배율이 바뀌면 옛 그림으로 그리면서 뒤에서 새 배율의 글자를 준비한다', () {
    final text = AtlasText()
      ..maxNewPerFrame = 2
      ..budgetMicros = noTimeLimit;
    text.beginFrame();
    text.maxNewPerFrame = 100;
    text.widthOf('가나다라', look);
    text.maxNewPerFrame = 2;
    text.setScale(1.5);
    expect(text.scale, 1.5);
    text.beginFrame();
    final c = canvas();
    expect(text.paint(c, '가나다라', look, 0, 0), isTrue, reason: '새 배율의 글자가 아직 없어도 옛 그림을 키워 그린다');
    expect(text.sharpRatio, lessThan(1));
    text.flush(c);
    text.beginFrame();
    text.paint(c, '가나다라', look, 0, 0);
    text.flush(c);
    text.beginFrame();
    text.paint(c, '가나다라', look, 0, 0);
    expect(text.sharpRatio, 1, reason: '두 장면 뒤에는 네 글자 모두 새 배율');
    text.flush(c);
  });
}
