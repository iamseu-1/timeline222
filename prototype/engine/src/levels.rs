//! 단계 · 통 · 타일 산수. 시간은 1970-01-01 UTC 기준 정수 분이고 기원전은 음수라서 모든 나눗셈은 내림(div_euclid)이다.

/// 가장 성긴 단계. 통 하나가 4^14분(약 511년)이다.
pub const LEVEL_MAX: usize = 14;
/// 이 단계부터는 넣을 때 요약을 미리 만들어 둔다. 그 아래는 타일을 만들 때 범위 조회로 센다.
pub const PRE_MIN: usize = 8;
/// 타일 하나의 가로 = 통 256개.
pub const TILE_BUCKETS: i64 = 256;
/// 타일 하나의 세로 = 줄 8개.
pub const CHUNK_ROWS: i64 = 8;

/// 단계 L의 통 너비(분) = 4^L.
pub fn bucket_minutes(level: usize) -> i64 {
    1i64 << (2 * level)
}

pub fn bucket_of(minute: i64, level: usize) -> i64 {
    minute.div_euclid(bucket_minutes(level))
}

pub fn tile_of(minute: i64, level: usize) -> i64 {
    bucket_of(minute, level).div_euclid(TILE_BUCKETS)
}

/// 타일이 덮는 분 범위(양 끝 포함).
pub fn tile_range(level: usize, x: i64) -> (i64, i64) {
    let width = TILE_BUCKETS * bucket_minutes(level);
    (x * width, x * width + width - 1)
}

/// 가늘기 등급을 정하는 나눗수의 기본값 — `기간 ≥ 통/8`(화면에서 약 2px).
pub const CELL_LOD_DEFAULT: i64 = 8;

/// 가늘기 등급: 기간이 통 너비의 1/8(화면에서 약 2px) 이상인 가장 성긴 단계. L단계 타일은 이 값이 L 이상인 것만 싣는다.
pub fn lod_of(duration: i64) -> i64 {
    lod_with(duration, CELL_LOD_DEFAULT)
}

/// 나눗수를 골라 재는 가늘기 등급 — `기간 ≥ 통/나눗수`인 가장 성긴 단계.
fn lod_with(duration: i64, divisor: i64) -> i64 {
    let wide = duration.max(0).saturating_mul(divisor);
    (0..=LEVEL_MAX).rev().find(|level| wide >= bucket_minutes(*level)).unwrap_or(0) as i64
}

/// **시험용 손잡이** `ARCHIVE_CELL_LOD` — 띠 안의 칸을 성긴 단계에 얼마나 성기게 실을지 고르는 나눗수(기본 8).
/// 돋보기 구간의 성능(검증 보고서 9-5절)을 두고 "성긴 단계에서 칸을 더 성기게 실으면 그림이 얼마나 달라지고
/// 얼마나 빨라지나"를 감독이 **그림으로 보고 정하려고** 둔 것이다. 값은 **처음 한 번만** 읽고 그 뒤로는 바뀌지 않는다
/// (한 판 안에서 타일마다 문턱이 달라지면 받아 둔 타일과 새 타일이 섞인다).
/// 읽지 못하는 값은 기본 8이고, 1~64 밖은 그 안으로 자른다. DLL(`archive_call`·`archive_tile`)과 `archive-tool`이 같은 값을 쓴다.
pub fn cell_lod_divisor() -> i64 {
    static CHOSEN: std::sync::OnceLock<i64> = std::sync::OnceLock::new();
    *CHOSEN.get_or_init(|| {
        std::env::var("ARCHIVE_CELL_LOD")
            .ok()
            .and_then(|text| text.trim().parse::<i64>().ok())
            .map(|n| n.clamp(1, 64))
            .unwrap_or(CELL_LOD_DEFAULT)
    })
}

/// 띠 안의 칸 하나의 가늘기 등급 — 손잡이가 기본 8이면 `lod_of`와 **한 값도 다르지 않다**(타일이 바이트까지 같다).
pub fn cell_lod_of(duration: i64) -> i64 {
    lod_with(duration, cell_lod_divisor())
}

/// 칸을 고를 때 공간 색인(`cell_bounds.lod_max`)에 넘길 단계.
/// 색인에 적힌 등급은 **넣을 때의 나눗수 8**로 잰 값이라, 손잡이가 8보다 크면(= 더 촘촘하게 실으면)
/// 색인이 걸러 버린 짧은 칸까지 닿도록 단계를 그만큼 되돌려 묻는다. 8 이하면 색인이 이미 넉넉하므로 그대로다.
/// (어느 쪽이든 정확한 판정은 `cell_lod_of`가 다시 한다.)
pub fn cell_lod_query_level(level: usize) -> i64 {
    let divisor = cell_lod_divisor();
    let (mut back, mut span) = (0i64, CELL_LOD_DEFAULT);
    while span < divisor {
        span *= 4;
        back += 1;
    }
    level as i64 - back
}

/// 화면이 단계를 고르는 규칙(`app/lib/scene/levels.dart`의 `levelFor`): 통 하나가 16~64px이 되는 단계를 고르고,
/// 경계에서 깜빡이지 않게 8%를 버틴다. 그래서 **L단계 타일이 쓰이는 동안 통 하나는 아무리 확대해도 이 폭을 넘지 않는다.**
/// 추림의 안전 쪽(가장 확대한 쪽)을 재는 값이라, 화면 쪽 상수가 바뀌면 여기도 함께 고쳐야 한다.
pub const BUCKET_MAX_PX: f64 = 64.0 * 1.08;

/// 띠 안의 칸 층(`app/lib/scene/paint/strips.dart`)이 칸 하나를 그리는 가장 좁은 폭(px).
/// 층은 `p.r - p.l < minW`인 칸을 건너뛰고 앞 칸을 늘려 빈틈을 메운다. 이어 붙은 칸은 좌우 0.5px 틈이 없어
/// 폭이 곧 `minW`와 겨루므로, **이어 붙었을 때(가장 너그러운 쪽)를 기준**으로 잡아야 그림이 바뀌지 않는다.
pub const CELL_MIN_PX: f64 = 1.0;

/// 그 띠가 칸을 하나라도 그리는 가장 좁은 폭(px) — 층의 `if (hi - lo < 1) return`.
/// `lo = 상자 왼쪽 + 1 + pad2(3)` · `hi = 상자 오른쪽 - 1 - pad2(3)`이라 상자가 9px은 되어야 한다.
pub const HOST_MIN_PX: f64 = 9.0;

/// 단계 L에서 px 폭을 분으로 바꾼다 — **가장 확대한 쪽**이라 가장 작은(가장 안전한) 값이다.
fn minutes_of_px(level: usize, px: f64) -> i64 {
    (px * bucket_minutes(level) as f64 / BUCKET_MAX_PX).ceil() as i64
}

/// 단계 L에서 칸 층이 **아무리 확대해도 그리지 않는** 칸의 기간(분 · 양 끝 포함) 문턱.
/// 이 값보다 짧은 칸은 그 단계의 타일에서 빼도 그림이 바뀌지 않는다.
pub fn cell_min_span(level: usize) -> i64 {
    minutes_of_px(level, CELL_MIN_PX).max(1)
}

/// 단계 L에서 띠가 너무 좁아 **제 칸을 하나도 그리지 않는** 기간(분 · 양 끝 포함) 문턱.
pub fn host_min_span(level: usize) -> i64 {
    minutes_of_px(level, HOST_MIN_PX).max(1)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 통_너비는_단계마다_네_배() {
        assert_eq!(bucket_minutes(0), 1);
        assert_eq!(bucket_minutes(8), 65_536);
        assert_eq!(bucket_minutes(14), 268_435_456);
    }

    #[test]
    fn 기원전의_통_번호는_내림한다() {
        assert_eq!(bucket_of(-1, 0), -1);
        assert_eq!(bucket_of(-1, 8), -1);
        assert_eq!(bucket_of(65_535, 8), 0);
        assert_eq!(bucket_of(65_536, 8), 1);
    }

    #[test]
    fn 타일은_통_256개를_양_끝_포함으로_덮는다() {
        assert_eq!(tile_range(8, -1), (-16_777_216, -1));
        assert_eq!(tile_range(8, 0), (0, 16_777_215));
    }

    #[test]
    fn 어느_분이든_제_타일_범위_안에_있다() {
        for level in 0..=LEVEL_MAX {
            for minute in [-1_296_000_000_i64, -65_537, -1, 0, 1, 65_536, 26_640_000, 1_584_144_000] {
                let (lo, hi) = tile_range(level, tile_of(minute, level));
                assert!(lo <= minute && minute <= hi, "단계 {level} · {minute}분");
                assert_eq!(hi - lo + 1, TILE_BUCKETS * bucket_minutes(level));
            }
        }
    }

    #[test]
    fn 가늘기_등급은_두_픽셀_규칙을_따른다() {
        assert_eq!(lod_of(0), 0);
        assert_eq!(lod_of(1), 1);
        assert_eq!(lod_of(8_192), 8);
        assert_eq!(lod_of(8_191), 7);
        assert_eq!(lod_of(i64::MAX / 2), 14);
    }

    #[test]
    fn 손잡이를_건드리지_않으면_칸의_등급은_예전과_한_값도_다르지_않다() {
        // 검사는 환경 변수를 두지 않고 돌리므로 나눗수는 기본 8이다.
        assert_eq!(cell_lod_divisor(), CELL_LOD_DEFAULT);
        for duration in [0, 1, 8_191, 8_192, 65_536, 1_440 * 365, i64::MAX / 2] {
            assert_eq!(cell_lod_of(duration), lod_of(duration), "기간 {duration}");
        }
        for level in 0..=LEVEL_MAX {
            assert_eq!(cell_lod_query_level(level), level as i64, "단계 {level}");
        }
    }

    #[test]
    fn 나눗수를_줄이면_짧은_칸이_성긴_단계에서_빠진다() {
        // 통 하나 = 65,536분(단계 8)일 때 통/8 = 8,192 · 통/4 = 16,384.
        assert_eq!(lod_with(8_192, 8), 8);
        assert_eq!(lod_with(8_192, 4), 7, "나눗수를 반으로 줄이면 한 단계 아래로 내려간다");
        assert_eq!(lod_with(16_384, 4), 8);
        // 나눗수를 키우면 더 촘촘해진다(색인을 되돌려 물어야 하는 쪽).
        assert_eq!(lod_with(8_192, 32), 9);
    }
}
