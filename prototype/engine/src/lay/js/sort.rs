//! JS `Array.prototype.sort` — V8의 TimSort(`third_party/v8/builtins/array-sort.tq`)를 비교 부르는 차례까지 그대로 옮겼다.
//! 일관된 비교(엄격 약순서)라면 어느 안정 정렬도 같은 답을 내지만, 비교가 NaN을 내 0으로 읽히는 곳(`a.k - b.k`에서 k가 없음)처럼
//! 일관되지 않은 비교는 알고리즘에 따라 답이 갈린다 — 그래서 V8과 같은 차례로 같은 쌍을 견준다.
//! (벡터가 결과와 함께 비교 부름 수 · 차례 체크섬을 Node와 견준다: `tests/lay_js.rs`의 `sort_is_v8_timsort`.)
//!
//! V8이 정렬 앞뒤로 하는 일: undefined는 비교에 넣지 않고 끝으로 모은다(구멍은 `V`에 없다 — `Undef`로 둔다).
//! 비교 함수의 값이 NaN이면 0(같음)으로 읽는다. 비교가 없는 `sort()`는 둘을 글로 바꿔 UTF-16 차례로 견준다.
//!
//! 옮긴 원본의 고지(허락 전문과 바꾼 것 요약은 저장소 뿌리 `THIRD_PARTY_NOTICES.md` 2-1절):
//! V8 13.6 `third_party/v8/builtins/array-sort.tq` — PSF License Version 2(그 폴더의 `LICENSE`).
//! Copyright (c) 2001, 2002, 2003, 2004, 2005, 2006, 2007, 2008, 2009, 2010,
//! 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018 Python Software Foundation;
//! All Rights Reserved
//! V8 몫: Copyright 2014, the V8 project authors. All rights reserved. — BSD-3-Clause(V8 `LICENSE`).
use super::num::to_str;
use super::value::V;
use std::cmp::Ordering;

/// 갤럽(뜀 찾기)으로 넘어가는 연승 수의 처음 값(V8 `kMinGallopWins`).
const MIN_GALLOP: isize = 7;

/// V8 `sortState.Compare`: 비교 값이 NaN이면 0.
fn order<T, F: FnMut(&T, &T) -> f64>(cmp: &mut F, x: &T, y: &T) -> f64 {
    let v = cmp(x, y);
    if v.is_nan() { 0.0 } else { v }
}

/// JS `arr.sort(cmp)` — `cmp`는 `(a, b) => …`의 값(음수면 a가 앞). undefined는 비교 없이 끝으로.
pub fn sort(arr: &mut Vec<V>, cmp: impl FnMut(&V, &V) -> f64) {
    let total = arr.len();
    let mut work: Vec<V> = Vec::with_capacity(total);
    for v in arr.drain(..) { if !v.is_undef() { work.push(v); } }
    sort_by(&mut work, cmp);
    arr.extend(work);
    arr.resize(total, V::Undef);
}

/// JS `arr.sort()`(비교 없음) — 원소를 글로 바꿔 UTF-16 차례(`'10' < '9'`) · undefined는 끝으로.
pub fn sort_default(arr: &mut Vec<V>) {
    let total = arr.len();
    let mut work: Vec<(super::text::Str, V)> = Vec::with_capacity(total);
    for v in arr.drain(..) { if !v.is_undef() { work.push((to_str(&v), v)); } }
    sort_by(&mut work, |a, b| match a.0.cmp16(&b.0) { Ordering::Less => -1.0, Ordering::Greater => 1.0, Ordering::Equal => 0.0 });
    arr.extend(work.into_iter().map(|(_, v)| v));
    arr.resize(total, V::Undef);
}

/// V8 TimSort 그대로(undefined 처리 없이) — `V`가 아닌 Rust 값을 JS와 같은 차례로 정렬할 때.
pub fn sort_by<T: Clone, F: FnMut(&T, &T) -> f64>(a: &mut [T], mut cmp: F) {
    let n = a.len() as isize;
    if n < 2 { return; }
    let mut st = Tim { min_gallop: MIN_GALLOP, runs: Vec::new() };
    let min_run = min_run_length(n);
    let (mut low, mut remaining) = (0isize, n);
    while remaining != 0 {
        let mut current = count_and_make_run(&mut cmp, a, low, low + remaining);
        if current < min_run {
            let forced = min_run.min(remaining);
            binary_insertion_sort(&mut cmp, a, low, low + current, low + forced);
            current = forced;
        }
        st.runs.push((low, current));
        st.merge_collapse(&mut cmp, a);
        low += current;
        remaining -= current;
    }
    st.merge_force_collapse(&mut cmp, a);
}

/// 쌓인 덩이(시작, 길이)와 갤럽 문턱.
struct Tim { min_gallop: isize, runs: Vec<(isize, isize)> }

fn ix(i: isize) -> usize { i as usize }

/// V8 `ComputeMinRunLength`.
fn min_run_length(mut n: isize) -> isize {
    let mut r = 0;
    while n >= 64 { r |= n & 1; n >>= 1; }
    n + r
}

/// V8 `BinaryInsertionSort(low, start, high)`: [low, start)는 정렬됨 — [start, high)를 하나씩 이분 찾기로 끼운다.
fn binary_insertion_sort<T: Clone, F: FnMut(&T, &T) -> f64>(cmp: &mut F, a: &mut [T], low: isize, start_arg: isize, high: isize) {
    let mut start = if low == start_arg { start_arg + 1 } else { start_arg };
    while start < high {
        let (mut left, mut right) = (low, start);
        let pivot = a[ix(start)].clone();
        while left < right {
            let mid = left + ((right - left) >> 1);
            if order(cmp, &pivot, &a[ix(mid)]) < 0.0 { right = mid; } else { left = mid + 1; }
        }
        a[ix(left)..=ix(start)].rotate_right(1); // [left, start)를 한 칸 뒤로 · pivot을 left에
        start += 1;
    }
}

/// V8 `CountAndMakeRun(low, high)`: low에서 시작하는 오름(같음 포함) 또는 엄격한 내림 덩이의 길이 — 내림이면 뒤집는다.
fn count_and_make_run<T, F: FnMut(&T, &T) -> f64>(cmp: &mut F, a: &mut [T], low_arg: isize, high: isize) -> isize {
    let low = low_arg + 1;
    if low == high { return 1; }
    let mut run = 2;
    let descending = order(cmp, &a[ix(low)], &a[ix(low - 1)]) < 0.0;
    let mut i = low + 1;
    while i < high {
        let o = order(cmp, &a[ix(i)], &a[ix(i - 1)]);
        if descending { if o >= 0.0 { break; } } else if o < 0.0 { break; }
        run += 1;
        i += 1;
    }
    if descending { a[ix(low_arg)..ix(low_arg + run)].reverse(); }
    run
}

/// V8 `GallopLeft`: 정렬된 arr[base, base+length)에서 key가 들어갈 가장 왼쪽 자리(arr[k−1] < key ≤ arr[k]), hint에서 뛰며 찾는다.
fn gallop_left<T, F: FnMut(&T, &T) -> f64>(cmp: &mut F, arr: &[T], key: &T, base: isize, length: isize, hint: isize) -> isize {
    let (mut last, mut offset) = (0isize, 1isize);
    if order(cmp, &arr[ix(base + hint)], key) < 0.0 {
        // arr[hint] < key: 오른쪽으로 뛴다 — arr[hint+last] < key ≤ arr[hint+offset].
        let max = length - hint;
        while offset < max {
            if order(cmp, &arr[ix(base + hint + offset)], key) >= 0.0 { break; }
            last = offset;
            offset = (offset << 1) + 1;
            if offset <= 0 { offset = max; }
        }
        if offset > max { offset = max; }
        last += hint;
        offset += hint;
    } else {
        // key ≤ arr[hint]: 왼쪽으로 뛴다 — arr[hint−offset] < key ≤ arr[hint−last].
        let max = hint + 1;
        while offset < max {
            if order(cmp, &arr[ix(base + hint - offset)], key) < 0.0 { break; }
            last = offset;
            offset = (offset << 1) + 1;
            if offset <= 0 { offset = max; }
        }
        if offset > max { offset = max; }
        let tmp = last;
        last = hint - offset;
        offset = hint - tmp;
    }
    last += 1;
    while last < offset {
        let m = last + ((offset - last) >> 1);
        if order(cmp, &arr[ix(base + m)], key) < 0.0 { last = m + 1; } else { offset = m; }
    }
    offset
}

/// V8 `GallopRight`: key가 들어갈 가장 오른쪽 자리(arr[k−1] ≤ key < arr[k]).
fn gallop_right<T, F: FnMut(&T, &T) -> f64>(cmp: &mut F, arr: &[T], key: &T, base: isize, length: isize, hint: isize) -> isize {
    let (mut last, mut offset) = (0isize, 1isize);
    if order(cmp, key, &arr[ix(base + hint)]) < 0.0 {
        // key < arr[hint]: 왼쪽으로 뛴다 — arr[hint−offset] ≤ key < arr[hint−last].
        let max = hint + 1;
        while offset < max {
            if order(cmp, key, &arr[ix(base + hint - offset)]) >= 0.0 { break; }
            last = offset;
            offset = (offset << 1) + 1;
            if offset <= 0 { offset = max; }
        }
        if offset > max { offset = max; }
        let tmp = last;
        last = hint - offset;
        offset = hint - tmp;
    } else {
        // arr[hint] ≤ key: 오른쪽으로 뛴다 — arr[hint+last] ≤ key < arr[hint+offset].
        let max = length - hint;
        while offset < max {
            if order(cmp, key, &arr[ix(base + hint + offset)]) < 0.0 { break; }
            last = offset;
            offset = (offset << 1) + 1;
            if offset <= 0 { offset = max; }
        }
        if offset > max { offset = max; }
        last += hint;
        offset += hint;
    }
    last += 1;
    while last < offset {
        let m = last + ((offset - last) >> 1);
        if order(cmp, key, &arr[ix(base + m)]) < 0.0 { offset = m; } else { last = m + 1; }
    }
    offset
}

/// a[src, src+n) → a[dst, dst+n) — 겹치면 V8 `Copy`처럼 방향을 골라 옮긴다.
fn copy_within<T: Clone>(a: &mut [T], src: isize, dst: isize, n: isize) {
    if src < dst {
        for k in (0..n).rev() { a[ix(dst + k)] = a[ix(src + k)].clone(); }
    } else {
        for k in 0..n { a[ix(dst + k)] = a[ix(src + k)].clone(); }
    }
}
/// temp[src, src+n) → a[dst, dst+n).
fn copy_from<T: Clone>(temp: &[T], src: isize, a: &mut [T], dst: isize, n: isize) {
    a[ix(dst)..ix(dst + n)].clone_from_slice(&temp[ix(src)..ix(src + n)]);
}

/// 합치기가 끝나는 두 길(V8의 레이블).
enum End { Succeed, CopyRest }

impl Tim {
    /// V8 `RunInvariantEstablished`: len[n−2] > len[n−1] + len[n].
    fn invariant(&self, n: isize) -> bool {
        if n < 2 { return true; }
        let len = |i: isize| self.runs[ix(i)].1;
        len(n - 2) > len(n - 1) + len(n)
    }
    /// V8 `MergeCollapse`.
    fn merge_collapse<T: Clone, F: FnMut(&T, &T) -> f64>(&mut self, cmp: &mut F, a: &mut [T]) {
        while self.runs.len() > 1 {
            let mut n = self.runs.len() as isize - 2;
            if !self.invariant(n + 1) || !self.invariant(n) {
                if self.runs[ix(n - 1)].1 < self.runs[ix(n + 1)].1 { n -= 1; }
                self.merge_at(cmp, a, n);
            } else if self.runs[ix(n)].1 <= self.runs[ix(n + 1)].1 {
                self.merge_at(cmp, a, n);
            } else {
                break;
            }
        }
    }
    /// V8 `MergeForceCollapse`.
    fn merge_force_collapse<T: Clone, F: FnMut(&T, &T) -> f64>(&mut self, cmp: &mut F, a: &mut [T]) {
        while self.runs.len() > 1 {
            let mut n = self.runs.len() as isize - 2;
            if n > 0 && self.runs[ix(n - 1)].1 < self.runs[ix(n + 1)].1 { n -= 1; }
            self.merge_at(cmp, a, n);
        }
    }
    /// V8 `MergeAt(i)`: 덩이 i와 i+1을 합친다.
    fn merge_at<T: Clone, F: FnMut(&T, &T) -> f64>(&mut self, cmp: &mut F, a: &mut [T], i: isize) {
        let size = self.runs.len() as isize;
        let (mut base_a, mut len_a) = self.runs[ix(i)];
        let (base_b, mut len_b) = self.runs[ix(i + 1)];
        self.runs[ix(i)].1 = len_a + len_b;
        if i == size - 3 { self.runs[ix(i + 1)] = self.runs[ix(i + 2)]; }
        self.runs.pop();

        // b의 첫째가 a의 어디에 드나 — 그 앞의 a는 이미 제자리.
        let key = a[ix(base_b)].clone();
        let k = gallop_right(cmp, a, &key, base_a, len_a, 0);
        base_a += k;
        len_a -= k;
        if len_a == 0 { return; }
        // a의 끝이 b의 어디에 드나 — 그 뒤의 b는 이미 제자리.
        let key = a[ix(base_a + len_a - 1)].clone();
        len_b = gallop_left(cmp, a, &key, base_b, len_b, len_b - 1);
        if len_b == 0 { return; }
        if len_a <= len_b { self.merge_low(cmp, a, base_a, len_a, base_b, len_b); } else { self.merge_high(cmp, a, base_a, len_a, base_b, len_b); }
    }
    /// V8 `MergeLow`: a(짧은 쪽)를 임시로 빼 두고 앞에서부터 합친다.
    fn merge_low<T: Clone, F: FnMut(&T, &T) -> f64>(&mut self, cmp: &mut F, a: &mut [T], base_a: isize, len_a: isize, base_b: isize, len_b: isize) {
        let (mut len_a, mut len_b) = (len_a, len_b);
        let temp: Vec<T> = a[ix(base_a)..ix(base_a + len_a)].to_vec();
        let (mut dest, mut cursor_temp, mut cursor_b) = (base_a, 0isize, base_b);
        a[ix(dest)] = a[ix(cursor_b)].clone();
        dest += 1;
        cursor_b += 1;
        let end = 'merge: {
            len_b -= 1;
            if len_b == 0 { break 'merge End::Succeed; }
            if len_a == 1 { break 'merge End::CopyRest; }
            let mut min_gallop = self.min_gallop;
            loop {
                let (mut wins_a, mut wins_b) = (0isize, 0isize);
                // 한 쪽이 잇달아 이길 때까지 하나씩.
                loop {
                    if order(cmp, &a[ix(cursor_b)], &temp[ix(cursor_temp)]) < 0.0 {
                        a[ix(dest)] = a[ix(cursor_b)].clone();
                        dest += 1;
                        cursor_b += 1;
                        wins_b += 1;
                        len_b -= 1;
                        wins_a = 0;
                        if len_b == 0 { break 'merge End::Succeed; }
                        if wins_b >= min_gallop { break; }
                    } else {
                        a[ix(dest)] = temp[ix(cursor_temp)].clone();
                        dest += 1;
                        cursor_temp += 1;
                        wins_a += 1;
                        len_a -= 1;
                        wins_b = 0;
                        if len_a == 1 { break 'merge End::CopyRest; }
                        if wins_a >= min_gallop { break; }
                    }
                }
                // 갤럽: 어느 쪽도 잇달아 이기지 않을 때까지 뛰어 옮긴다.
                min_gallop += 1;
                let mut first = true;
                while wins_a >= MIN_GALLOP || wins_b >= MIN_GALLOP || first {
                    first = false;
                    min_gallop = (min_gallop - 1).max(1);
                    self.min_gallop = min_gallop;

                    let key = a[ix(cursor_b)].clone();
                    wins_a = gallop_right(cmp, &temp, &key, cursor_temp, len_a, 0);
                    if wins_a > 0 {
                        copy_from(&temp, cursor_temp, a, dest, wins_a);
                        dest += wins_a;
                        cursor_temp += wins_a;
                        len_a -= wins_a;
                        if len_a == 1 { break 'merge End::CopyRest; }
                        if len_a == 0 { break 'merge End::Succeed; } // 일관되지 않은 비교에서만
                    }
                    a[ix(dest)] = a[ix(cursor_b)].clone();
                    dest += 1;
                    cursor_b += 1;
                    len_b -= 1;
                    if len_b == 0 { break 'merge End::Succeed; }

                    let key = temp[ix(cursor_temp)].clone();
                    wins_b = gallop_left(cmp, a, &key, cursor_b, len_b, 0);
                    if wins_b > 0 {
                        copy_within(a, cursor_b, dest, wins_b);
                        dest += wins_b;
                        cursor_b += wins_b;
                        len_b -= wins_b;
                        if len_b == 0 { break 'merge End::Succeed; }
                    }
                    a[ix(dest)] = temp[ix(cursor_temp)].clone();
                    dest += 1;
                    cursor_temp += 1;
                    len_a -= 1;
                    if len_a == 1 { break 'merge End::CopyRest; }
                }
                min_gallop += 1; // 갤럽을 그만둔 벌
                self.min_gallop = min_gallop;
            }
        };
        match end {
            End::Succeed => if len_a > 0 { copy_from(&temp, cursor_temp, a, dest, len_a); },
            End::CopyRest => {
                // a의 마지막 하나가 합친 끝에 선다.
                copy_within(a, cursor_b, dest, len_b);
                a[ix(dest + len_b)] = temp[ix(cursor_temp)].clone();
            }
        }
    }
    /// V8 `MergeHigh`: b(짧은 쪽)를 임시로 빼 두고 뒤에서부터 합친다.
    fn merge_high<T: Clone, F: FnMut(&T, &T) -> f64>(&mut self, cmp: &mut F, a: &mut [T], base_a: isize, len_a: isize, base_b: isize, len_b: isize) {
        let (mut len_a, mut len_b) = (len_a, len_b);
        let temp: Vec<T> = a[ix(base_b)..ix(base_b + len_b)].to_vec();
        let (mut dest, mut cursor_temp, mut cursor_a) = (base_b + len_b - 1, len_b - 1, base_a + len_a - 1);
        a[ix(dest)] = a[ix(cursor_a)].clone();
        dest -= 1;
        cursor_a -= 1;
        let end = 'merge: {
            len_a -= 1;
            if len_a == 0 { break 'merge End::Succeed; }
            if len_b == 1 { break 'merge End::CopyRest; }
            let mut min_gallop = self.min_gallop;
            loop {
                let (mut wins_a, mut wins_b) = (0isize, 0isize);
                loop {
                    if order(cmp, &temp[ix(cursor_temp)], &a[ix(cursor_a)]) < 0.0 {
                        a[ix(dest)] = a[ix(cursor_a)].clone();
                        dest -= 1;
                        cursor_a -= 1;
                        wins_a += 1;
                        len_a -= 1;
                        wins_b = 0;
                        if len_a == 0 { break 'merge End::Succeed; }
                        if wins_a >= min_gallop { break; }
                    } else {
                        a[ix(dest)] = temp[ix(cursor_temp)].clone();
                        dest -= 1;
                        cursor_temp -= 1;
                        wins_b += 1;
                        len_b -= 1;
                        wins_a = 0;
                        if len_b == 1 { break 'merge End::CopyRest; }
                        if wins_b >= min_gallop { break; }
                    }
                }
                min_gallop += 1;
                let mut first = true;
                while wins_a >= MIN_GALLOP || wins_b >= MIN_GALLOP || first {
                    first = false;
                    min_gallop = (min_gallop - 1).max(1);
                    self.min_gallop = min_gallop;

                    let key = temp[ix(cursor_temp)].clone();
                    let k = gallop_right(cmp, a, &key, base_a, len_a, len_a - 1);
                    wins_a = len_a - k;
                    if wins_a > 0 {
                        dest -= wins_a;
                        cursor_a -= wins_a;
                        copy_within(a, cursor_a + 1, dest + 1, wins_a);
                        len_a -= wins_a;
                        if len_a == 0 { break 'merge End::Succeed; }
                    }
                    a[ix(dest)] = temp[ix(cursor_temp)].clone();
                    dest -= 1;
                    cursor_temp -= 1;
                    len_b -= 1;
                    if len_b == 1 { break 'merge End::CopyRest; }

                    let key = a[ix(cursor_a)].clone();
                    let k = gallop_left(cmp, &temp, &key, 0, len_b, len_b - 1);
                    wins_b = len_b - k;
                    if wins_b > 0 {
                        dest -= wins_b;
                        cursor_temp -= wins_b;
                        copy_from(&temp, cursor_temp + 1, a, dest + 1, wins_b);
                        len_b -= wins_b;
                        if len_b == 1 { break 'merge End::CopyRest; }
                        if len_b == 0 { break 'merge End::Succeed; } // 일관되지 않은 비교에서만
                    }
                    a[ix(dest)] = a[ix(cursor_a)].clone();
                    dest -= 1;
                    cursor_a -= 1;
                    len_a -= 1;
                    if len_a == 0 { break 'merge End::Succeed; }
                }
                min_gallop += 1;
                self.min_gallop = min_gallop;
            }
        };
        match end {
            End::Succeed => if len_b > 0 { copy_from(&temp, 0, a, dest - (len_b - 1), len_b); },
            End::CopyRest => {
                // b의 첫 하나가 합친 앞에 선다.
                dest -= len_a;
                cursor_a -= len_a;
                copy_within(a, cursor_a + 1, dest + 1, len_a);
                a[ix(dest)] = temp[ix(cursor_temp)].clone();
            }
        }
    }
}
