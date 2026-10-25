// 단계 · 통 · 타일 산수. 자료 처리부(engine/src/levels.rs)와 같은 식이어야 한다.
// 시간은 1970-01-01 UTC 기준 분이고 기원전은 음수라서 나눗셈은 모두 내림이다.

const levelMax = 14;
const tileBuckets = 256;
const chunkRows = 8;

/// 화면에서 통 하나가 차지할 최소 · 최대 폭(px)과, 경계에서 지금 단계를 붙드는 비율(지금 연표의 LOD_GAP과 같은 8%).
const bucketMinPx = 16.0, bucketMaxPx = 64.0, levelGap = .08;

/// 단계 L의 통 너비(분) = 4^L.
int bucketMinutes(int level) => 1 << (2 * level);

int tileSpan(int level) => tileBuckets * bucketMinutes(level);

int tileOf(num minute, int level) => (minute / tileSpan(level)).floor();

int tileOrigin(int level, int x) => x * tileSpan(level);

/// 통이 16px 이상이 되는 가장 작은 단계. [current]를 주면 통이 14.72~69.12px인 동안은 그 단계를 붙든다 — 경계에서 깜빡이지 않게.
int levelFor(double pxPerMinute, {int? current}) {
  if (current != null) {
    final px = bucketMinutes(current) * pxPerMinute;
    if (px >= bucketMinPx * (1 - levelGap) && px < bucketMaxPx * (1 + levelGap)) {
      return current;
    }
  }
  for (int level = 0; level < levelMax; level++) {
    if (bucketMinutes(level) * pxPerMinute >= bucketMinPx) return level;
  }
  return levelMax;
}
