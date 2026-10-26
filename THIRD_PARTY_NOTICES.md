# 남의 저작물 고지 (Third-Party Notices)

이 저장소에는 HistoryTime 저작자가 만들지 않은 것이 조금 들어 있습니다. 그것들은 뿌리 [LICENSE](LICENSE)('모든 권리 보유 · 열람만')를 따르지 않고, 아래에 적은 저마다의 허락을 따릅니다. 허락 원문(영어)은 고치지 않고 그대로 옮겼고, 한국어 설명을 곁들였습니다.

지도 자료(`지도/` 폴더의 지형 팩 · 단위 팩 · 견본)의 출처와 허락은 [지도/LICENSE-DATA.md](지도/LICENSE-DATA.md)에 따로 적었습니다.

| 절 | 무엇 | 저장소 안 자리 | 허락 |
| --- | --- | --- | --- |
| [1](#1-lucide-아이콘) | Lucide 아이콘의 선 경로 | `js/viewer.js` · `prototype/app/lib/shell/line_icon.dart` · `prototype/app/lib/mock/kit.dart` 외 | ISC (Feather에서 온 몫은 MIT) |
| [2-1](#2-1-v8의-timsort--sortrs) | V8의 TimSort를 옮긴 코드 | `prototype/engine/src/lay/js/sort.rs` | PSF-2.0 (원본 파일 — V8 `third_party/v8/builtins/`) · BSD-3-Clause (V8 — 조심하는 뜻에서) |
| [2-2](#2-2-fdlibm의-cbrt--jsdart) | fdlibm의 세제곱근 셈을 옮긴 코드 | `prototype/app/lib/mock/js.dart` | Sun Microsystems 고지 |
| [3](#3-글꼴) | 글꼴 셋 | `fonts/` · `prototype/app/assets/fonts/` | SIL OFL 1.1 · 조선일보 이용 조건 |
| [4](#4-flutter-앱-틀) | Flutter 앱 틀 | `prototype/app/android` · `ios` · `windows` | BSD-3-Clause (Flutter) |
| [5](#5-의존-꾸러미-목록) | 의존 꾸러미(크레이트 · 패키지) 목록 | 잠금 파일 넷 | 표마다 |
| [6](#6-고지가-필요-없는-것) | 고지가 필요 없는 짧은 공개 셈법 · 시험 자료 | 여러 곳 | 공개 도메인 · 사실 |
| [7](#7-확인할-것) | 원본과 더 견줄 것 | — | — |

---

## 1. Lucide 아이콘

- **무엇:** 화면의 선 아이콘(24칸 격자 · 선 굵기 1.5)의 SVG 경로를 [Lucide](https://lucide.dev)에서 그대로 옮겼습니다.
- **자리:**
  - `js/viewer.js` — `ICONS`(경로 25개 · 연표와 DLC 메이커가 함께 씀)
  - `prototype/app/lib/shell/line_icon.dart` — `LineGlyph`(33개 · 주석 'Lucide 그대로')
  - `prototype/app/lib/mock/kit.dart` — `ICON`(14개)과 그 원본인 `prototype/app/test/mock/source/kit.js` — `ICON`(14개)
  - `css/viewer.css` — `.ctx-item.is-checked::before`의 CSS 마스크(데이터 URI 속 check 경로 · `mask`와 `-webkit-mask` 두 번)
  - `prototype/app/test/mock/svg_lite_test.dart` — 시험 글 속 search 경로
  - 꺾쇠(chevron)만 쓰는 곳: `prototype/app/lib/mock/themes/s4_common.dart` · `prototype/app/test/mock/source/themes/s4-0-common.js` · `prototype/app/lib/ui/detail_shell.dart`(`LineGlyph.chevronDown`)
- **허락:** ISC. Lucide의 아이콘 가운데 Feather에서 온 것(아래 목록 — 이 저장소에서는 check · chevron-down · download · minus · plus · search · x · zoom-in 같은 것)은 Feather의 MIT 허락도 함께 따릅니다. 두 허락 모두 '모든 사본에 저작권 고지와 이 허락 글을 함께 실을 것'만 요구합니다.
- **원문:** Lucide 저장소의 LICENSE 글입니다(이 PC의 사본 — lucide-react 1.51.0에 딸린 글). 옮겨 온 판이 언제 것인지 기록이 없어, 지금 판의 글을 실었습니다.

```text
ISC License

Copyright (c) 2026 Lucide Icons and Contributors

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

---

The following Lucide icons are derived from the Feather project:

airplay, alert-circle, alert-octagon, alert-triangle, aperture, arrow-down-circle, arrow-down-left, arrow-down-right, arrow-down, arrow-left-circle, arrow-left, arrow-right-circle, arrow-right, arrow-up-circle, arrow-up-left, arrow-up-right, arrow-up, at-sign, calendar, cast, check, chevron-down, chevron-left, chevron-right, chevron-up, chevrons-down, chevrons-left, chevrons-right, chevrons-up, circle, clipboard, clock, code, columns, command, compass, corner-down-left, corner-down-right, corner-left-down, corner-left-up, corner-right-down, corner-right-up, corner-up-left, corner-up-right, crosshair, database, divide-circle, divide-square, dollar-sign, download, external-link, feather, frown, hash, headphones, help-circle, info, italic, key, layout, life-buoy, link-2, link, loader, lock, log-in, log-out, maximize, meh, minimize, minimize-2, minus-circle, minus-square, minus, monitor, moon, more-horizontal, more-vertical, move, music, navigation-2, navigation, octagon, pause-circle, percent, plus-circle, plus-square, plus, power, radio, rss, search, server, share, shopping-bag, sidebar, smartphone, smile, square, table-2, tablet, target, terminal, trash-2, trash, triangle, tv, type, upload, x-circle, x-octagon, x-square, x, zoom-in, zoom-out

The MIT License (MIT) (for the icons listed above)

Copyright (c) 2013-present Cole Bemis

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## 2. 옮긴 코드

### 2-1. V8의 TimSort → sort.rs

- **무엇:** JS `Array.prototype.sort`와 같은 답을 내려고, V8(크롬 · Node.js의 자바스크립트 엔진)의 TimSort를 Rust로 옮겼습니다. 비교 함수를 부르는 차례까지 같게 했으므로 원본 코드의 2차적 저작물로 봅니다. 기준은 Node 24가 쓰는 V8 13.6의 TimSort 판입니다(V8은 그 뒤 같은 파일을 PowerSort로 바꿨습니다).
- **자리:** `prototype/engine/src/lay/js/sort.rs`(머리 주석: V8 `third_party/v8/builtins/array-sort.tq`에서 옮김 · 이 절을 가리키는 줄). 설명은 `prototype/engine/src/lay/js.rs` 머리의 '옮긴 원본' 목록.
- **원본 파일의 저작권 줄:** V8 13.6.233.10의 `third_party/v8/builtins/array-sort.tq` 머리는 V8 저작권 줄이 아니라 아래 PSF 저작권 줄입니다(2026-10-25 원본과 대 봄). 그 파일은 CPython의 TimSort(`Objects/listobject.c` · `Objects/listsort.txt`)를 바탕으로 했다고 밝힙니다.

```text
Copyright (c) 2001, 2002, 2003, 2004, 2005, 2006, 2007, 2008, 2009, 2010,
2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018 Python Software Foundation;
All Rights Reserved
```

- **허락 (원본 파일 — PSF License Version 2):** 그 파일이 든 폴더의 `third_party/v8/builtins/LICENSE`는 CPython의 LICENSE 전문(역사와 PSF · BeOpen · CNRI · CWI 허락)이고, 아래는 그 가운데 PSF License Version 2입니다. V8 13.6.233.10의 그 파일과 바이트로 같음을 2026-10-25에 대 봤습니다. PSF 허락 3항이 요구하는 '바꾼 것 요약': V8의 Torque 코드를 Rust로 옮김 · 비교 값이 NaN이면 0으로 읽음 · undefined는 비교하지 않고 끝으로 모음 · 구멍은 undefined로 둠 · 갤럽 · 병합의 차례는 V8과 같게 둠.

```text
PYTHON SOFTWARE FOUNDATION LICENSE VERSION 2
--------------------------------------------

1. This LICENSE AGREEMENT is between the Python Software Foundation
("PSF"), and the Individual or Organization ("Licensee") accessing and
otherwise using this software ("Python") in source or binary form and
its associated documentation.

2. Subject to the terms and conditions of this License Agreement, PSF hereby
grants Licensee a nonexclusive, royalty-free, world-wide license to reproduce,
analyze, test, perform and/or display publicly, prepare derivative works,
distribute, and otherwise use Python alone or in any derivative version,
provided, however, that PSF's License Agreement and PSF's notice of copyright,
i.e., "Copyright (c) 2001, 2002, 2003, 2004, 2005, 2006, 2007, 2008, 2009, 2010,
2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018 Python Software Foundation; All
Rights Reserved" are retained in Python alone or in any derivative version
prepared by Licensee.

3. In the event Licensee prepares a derivative work that is based on
or incorporates Python or any part thereof, and wants to make
the derivative work available to others as provided herein, then
Licensee hereby agrees to include in any such work a brief summary of
the changes made to Python.

4. PSF is making Python available to Licensee on an "AS IS"
basis.  PSF MAKES NO REPRESENTATIONS OR WARRANTIES, EXPRESS OR
IMPLIED.  BY WAY OF EXAMPLE, BUT NOT LIMITATION, PSF MAKES NO AND
DISCLAIMS ANY REPRESENTATION OR WARRANTY OF MERCHANTABILITY OR FITNESS
FOR ANY PARTICULAR PURPOSE OR THAT THE USE OF PYTHON WILL NOT
INFRINGE ANY THIRD PARTY RIGHTS.

5. PSF SHALL NOT BE LIABLE TO LICENSEE OR ANY OTHER USERS OF PYTHON
FOR ANY INCIDENTAL, SPECIAL, OR CONSEQUENTIAL DAMAGES OR LOSS AS
A RESULT OF MODIFYING, DISTRIBUTING, OR OTHERWISE USING PYTHON,
OR ANY DERIVATIVE THEREOF, EVEN IF ADVISED OF THE POSSIBILITY THEREOF.

6. This License Agreement will automatically terminate upon a material
breach of its terms and conditions.

7. Nothing in this License Agreement shall be deemed to create any
relationship of agency, partnership, or joint venture between PSF and
Licensee.  This License Agreement does not grant permission to use PSF
trademarks or trade name in a trademark sense to endorse or promote
products or services of Licensee, or any third party.

8. By copying, installing or otherwise using Python, Licensee
agrees to be bound by the terms and conditions of this License
Agreement.
```

- **허락 (V8 — BSD-3-Clause, 조심하는 뜻에서):** Torque 판을 쓴 것은 V8 저작자이고, V8 뿌리 LICENSE는 따로 관리하는 라이브러리 말고는 V8 전체에 BSD-3-Clause를 적용하며 하위 폴더의 LICENSE도 보라고 합니다. 그래서 V8의 고지도 함께 싣습니다. 아래는 V8 13.6.233.10 뿌리 LICENSE의 BSD 글이고, 저작권 줄과 본문 모두 그 파일과 바이트로 같습니다(2026-10-25 대 봄).

```text
Copyright 2014, the V8 project authors. All rights reserved.
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google Inc. nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

### 2-2. fdlibm의 cbrt → js.dart

- **무엇:** Dart에는 JS `Math.cbrt`가 없고 `pow(v, 1/3)`은 끝자리가 달라서, V8이 쓰는 fdlibm의 셈을 그대로 옮겼습니다. 마법 상수(715094163 · 696219795)와 다항식 계수 다섯이 원본 그대로입니다.
- **자리:** `prototype/app/lib/mock/js.dart`의 `jsCbrt`(66~105줄 언저리 — 바로 위 주석에 아래 Sun 고지를 그대로 둠).
- **어디서 왔나:** FreeBSD `lib/msun/src/s_cbrt.c`와 V8 13.6.233.10 `src/base/ieee754.cc`의 `cbrt`는 상수 · 계수 · 23비트 자르기 · 뉴턴 걸음이 같아, 어느 쪽을 거쳐 왔는지 코드로는 가릴 수 없습니다(2026-10-25 두 원본과 대 봄). 그래서 두 머리 글을 모두 싣습니다.
- **허락:** Sun Microsystems 고지 — '이 고지를 남길 것'만 요구합니다. 첫째 글은 FreeBSD `s_cbrt.c` 머리와 같은 글(주석 표시만 뺌)이고, 둘째 글은 V8 `ieee754.cc` 머리입니다. V8이 고친 몫은 2-1절의 V8 BSD-3-Clause 글을 따릅니다.

```text
====================================================
Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.

Developed at SunPro, a Sun Microsystems, Inc. business.
Permission to use, copy, modify, and distribute this
software is freely granted, provided that this notice
is preserved.
====================================================

Optimized by Bruce D. Evans.
```

```text
The following is adapted from fdlibm (http://www.netlib.org/fdlibm).

====================================================
Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.

Developed at SunSoft, a Sun Microsystems, Inc. business.
Permission to use, copy, modify, and distribute this
software is freely granted, provided that this notice
is preserved.
====================================================

The original source code covered by the above license above has been
modified significantly by Google Inc.
Copyright 2016 the V8 project authors. All rights reserved.
```

---

## 3. 글꼴

글꼴 파일은 받은 원본을 바꾸지 않고 그대로 두었고, 허락 글을 바로 옆에 두었습니다. `fonts/`와 `prototype/app/assets/fonts/`의 파일은 같은 바이트입니다. 웹 연표 · 메이커의 배포(`scripts/build-web.mjs` · `sw.js`)에는 Pretendard와 조선굵은명조만 실립니다.

| 글꼴 | 파일 | 저작권 | 허락 | 허락 글 |
| --- | --- | --- | --- | --- |
| Pretendard (Regular · SemiBold · Bold) | `Pretendard-*.otf` | Copyright (c) 2021, Kil Hyung-jin (https://github.com/orioncactus/pretendard), with Reserved Font Name Pretendard. | SIL Open Font License 1.1 | `fonts/Pretendard-OFL.txt` · `prototype/app/assets/fonts/Pretendard-OFL.txt` |
| 리디바탕 (RIDIBatang) | `RIDIBatang.otf` | Copyright RIDI Corporation. (리디주식회사) | SIL Open Font License 1.1 | `fonts/RIDIBatang-OFL.txt` · `prototype/app/assets/fonts/RIDIBatang-OFL.txt` |
| 조선굵은명조 (ChosunKm) | `ChosunKm.ttf` | 지적재산권: (주)조선일보사 | 조선일보 전용서체 이용 조건 | `fonts/ChosunKm-LICENSE.txt` · `prototype/app/assets/fonts/ChosunKm-LICENSE.txt` |

요점:

- **SIL OFL 1.1 (Pretendard · 리디바탕):** 글꼴을 쓰고 · 고치고 · 함께 실어 나르고 · 팔 수 있습니다. 다만 ① 글꼴 파일만 따로 팔 수 없고, ② 사본마다 저작권 고지와 이 허락 글을 실어야 하며, ③ 고친 글꼴에는 예약된 글꼴 이름(Pretendard 등)을 쓸 수 없고, ④ 고친 글꼴도 OFL로만 내놓을 수 있습니다. 전문은 위 허락 글 파일에 있습니다.
- **조선굵은명조:** 개인 · 기업 모두 무료로 쓰고 남에게 자유롭게 나눠 줄 수 있습니다. 다만 어떤 경우에도 복사 · 배포의 대가를 받을 수 없고, 고쳐서 팔 수 없으며, 받은 형태 그대로 써야 합니다. `ChosunKm-LICENSE.txt`는 공식 안내(https://event.chosun.com/100/100font.html)의 조건을 옮겨 적은 것입니다(7절).
- 독립형 앱(Flutter)은 Pretendard와 조선굵은명조를 싣고 두 허락 글도 함께 싣습니다(`prototype/app/pubspec.yaml`). 리디바탕은 웹 배포에도 앱 꾸러미에도 실리지 않고, 앱의 목업 · 골든 시험(`prototype/app/lib/mock/svg_lite.dart` · `kit.dart`, 그 원본 `prototype/app/test/mock/source/kit.js`)이 저장소의 파일을 읽어 쓸 뿐입니다.

---

## 4. Flutter 앱 틀

- **무엇:** `prototype/app/`의 플랫폼 틀(`android/` · `ios/` · `windows/`의 빌드 설정과 `MainActivity.kt` · `AppDelegate.swift` · `windows/runner/*.cpp` 같은 실행 틀)은 `flutter create`가 Flutter SDK의 견본 틀로 만든 것을 바탕으로 고쳤습니다. 틀 파일에는 저작권 머리가 없지만, Flutter 저장소의 허락이 BSD-3-Clause이므로 조심하는 뜻에서 그 고지를 싣습니다.
- **앱 아이콘 · 시작 그림:** 아래 파일은 Flutter 견본 그림과 같은 바이트입니다(이 PC의 Flutter SDK 틀 · `flutter_template_images` 5.0.0과 견줌 — 허락은 아래와 같은 BSD-3-Clause, 그 꾸러미의 저작권 줄은 "Copyright 2013 The Flutter Authors. All rights reserved."). 아이콘의 그림은 Flutter 로고이고 Flutter 로고는 Google의 상표이므로, 앱을 다시 내보내기 전에 `icons/app-1024.png`에서 만든 그림으로 바꾸는 것이 맞습니다.
  - `prototype/app/android/app/src/main/res/mipmap-*/ic_launcher.png`
  - `prototype/app/ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png` · `LaunchImage.imageset/*.png`(빈 시작 그림)
  - `prototype/app/windows/runner/resources/app_icon.ico`
- **원문:** Flutter SDK의 LICENSE(이 PC의 사본 — Flutter 3.47).

```text
Copyright 2014 The Flutter Authors. All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google Inc. nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

---

## 5. 의존 꾸러미 목록

이 저장소에는 남의 꾸러미 원본이 들어 있지 않고, 어떤 판을 쓸지 적은 잠금 파일만 있습니다(`prototype/engine/Cargo.lock` · `src-tauri/Cargo.lock` · `prototype/app/pubspec.lock` · `package-lock.json`). 아래 표는 그 잠금 파일의 꾸러미마다 이름 · 판 · 허락 종류를 적은 것입니다. 꾸러미는 빌드할 때 저마다의 허락에 따라 받아 씁니다.

- **다시 뽑기:** `node prototype/scripts/third-party-list.mjs --write` — 아래 표시 줄 사이를 다시 짓습니다(네트워크를 쓰지 않고, 이 컴퓨터에 받아 둔 Cargo · Pub 캐시와 잠금 파일만 읽음). 표를 손으로 고치지 마십시오.
- **'확인 못 함':** 이 컴퓨터가 그 꾸러미를 받은 적이 없다는 뜻입니다(대부분 다른 운영체제 전용 크레이트 — 리눅스의 GTK · 맥의 Cocoa 따위). 그 꾸러미를 받은 컴퓨터에서 다시 돌리면 채워집니다.
- **목록 밖의 개발 도구:** 잠금 파일 없이 대본이 불러오는 npm 꾸러미 — 지도 대본의 `topojson-server` · `topojson-simplify` · `topojson-client` · `shapefile` · `polygon-clipping`, 브라우저 검사 대본(`prototype/scripts/cleartype-fixtures.mjs` · `mock-golden.mjs` 따위)의 `playwright` — 는 저장소에도 실행본에도 실리지 않아 아래 표에 없습니다. 저마다의 허락에 따라 따로 깔아 씁니다.
- **실행본에 싣는 고지(알아 둘 것):** Flutter 앱은 빌드가 Dart 패키지 · Flutter 엔진의 허락 글을 모아 `NOTICES`로 함께 싣습니다. 그러나 0.0.4 Windows 배포본의 `NOTICES`를 풀어 보니, 함께 실리는 `pdfium.dll`(pdfrx가 받아 오는 PDFium 실행본 — PDFium은 BSD-3-Clause 등)과 `MaterialIcons-Regular.otf`(Material 아이콘 글꼴 — Apache-2.0)의 허락 글은 이름으로 찾지 못했습니다. Rust 크레이트(연표 엔진 `archive_engine` · `archive-tool`, Tauri 앱)의 허락 글을 실행본에 모아 싣는 단계도 아직 없습니다. 실행본을 다시 내보낼 때는 이 파일이나 `cargo about` 같은 도구의 결과, PDFium의 허락 글을 함께 실어야 합니다. 연표 엔진은 `rusqlite`의 `bundled` 기능으로 SQLite를 함께 짓습니다(SQLite는 공개 도메인).

<!-- third-party-list:start — 아래는 prototype/scripts/third-party-list.mjs가 짓습니다. 손으로 고치지 말고 대본을 다시 돌리십시오 -->

### Rust 크레이트 (연표 엔진) — `prototype/engine/Cargo.lock`

57개. 잠금 파일의 모든 크레이트입니다(시험 · 다른 운영체제 전용 포함). 이 저장소의 크레이트(archive_engine)는 뺐습니다.

허락 종류별: MIT OR Apache-2.0 41 · MIT 5 · MIT/Apache-2.0 4 · Unlicense OR MIT 2 · Zlib 2 · (MIT OR Apache-2.0) AND Unicode-3.0 1 · 0BSD OR MIT OR Apache-2.0 1 · MIT OR Zlib OR Apache-2.0 1

| 이름 | 판 | 허락 | 근거 |
| --- | --- | --- | --- |
| adler2 | 2.0.1 | 0BSD OR MIT OR Apache-2.0 | Cargo.toml |
| aho-corasick | 1.1.5 | Unlicense OR MIT | Cargo.toml |
| bitflags | 2.13.2 | MIT OR Apache-2.0 | Cargo.toml |
| block-buffer | 0.10.4 | MIT OR Apache-2.0 | Cargo.toml |
| cc | 1.4.7 | MIT OR Apache-2.0 | Cargo.toml |
| cfg-if | 1.0.5 | MIT OR Apache-2.0 | Cargo.toml |
| cpufeatures | 0.2.17 | MIT OR Apache-2.0 | Cargo.toml |
| crc32fast | 1.5.2 | MIT OR Apache-2.0 | Cargo.toml |
| crypto-common | 0.1.7 | MIT OR Apache-2.0 | Cargo.toml |
| digest | 0.10.7 | MIT OR Apache-2.0 | Cargo.toml |
| fallible-iterator | 0.3.0 | MIT/Apache-2.0 | Cargo.toml |
| fallible-streaming-iterator | 0.1.9 | MIT/Apache-2.0 | Cargo.toml |
| find-msvc-tools | 0.1.13 | MIT OR Apache-2.0 | Cargo.toml |
| flate2 | 1.1.10 | MIT OR Apache-2.0 | Cargo.toml |
| foldhash | 0.1.5 | Zlib | Cargo.toml |
| generic-array | 0.14.7 | MIT | Cargo.toml |
| hashbrown | 0.15.5 | MIT OR Apache-2.0 | Cargo.toml |
| hashlink | 0.10.0 | MIT OR Apache-2.0 | Cargo.toml |
| itoa | 1.0.18 | MIT OR Apache-2.0 | Cargo.toml |
| libc | 0.2.189 | MIT OR Apache-2.0 | Cargo.toml |
| libsqlite3-sys | 0.35.0 | MIT | Cargo.toml |
| memchr | 2.8.3 | Unlicense OR MIT | Cargo.toml |
| miniz_oxide | 0.9.1 | MIT OR Zlib OR Apache-2.0 | Cargo.toml |
| pkg-config | 0.3.34 | MIT OR Apache-2.0 | Cargo.toml |
| proc-macro2 | 1.0.107 | MIT OR Apache-2.0 | Cargo.toml |
| quote | 1.0.47 | MIT OR Apache-2.0 | Cargo.toml |
| regex | 1.13.1 | MIT OR Apache-2.0 | Cargo.toml |
| regex-automata | 0.4.18 | MIT OR Apache-2.0 | Cargo.toml |
| regex-syntax | 0.8.11 | MIT OR Apache-2.0 | Cargo.toml |
| rusqlite | 0.37.0 | MIT | Cargo.toml |
| serde | 1.0.229 | MIT OR Apache-2.0 | Cargo.toml |
| serde_core | 1.0.229 | MIT OR Apache-2.0 | Cargo.toml |
| serde_derive | 1.0.229 | MIT OR Apache-2.0 | Cargo.toml |
| serde_json | 1.0.151 | MIT OR Apache-2.0 | Cargo.toml |
| sha2 | 0.10.9 | MIT OR Apache-2.0 | Cargo.toml |
| shlex | 2.0.1 | MIT OR Apache-2.0 | Cargo.toml |
| simd-adler32 | 0.3.10 | MIT | Cargo.toml |
| smallvec | 1.16.1 | MIT OR Apache-2.0 | Cargo.toml |
| syn | 2.0.119 | MIT OR Apache-2.0 | Cargo.toml |
| syn | 3.0.6 | MIT OR Apache-2.0 | Cargo.toml |
| typenum | 1.20.1 | MIT OR Apache-2.0 | Cargo.toml |
| unicode-ident | 1.0.26 | (MIT OR Apache-2.0) AND Unicode-3.0 | Cargo.toml |
| vcpkg | 0.2.15 | MIT/Apache-2.0 | Cargo.toml |
| version_check | 0.9.5 | MIT/Apache-2.0 | Cargo.toml |
| windows | 0.61.3 | MIT OR Apache-2.0 | Cargo.toml |
| windows-collections | 0.2.0 | MIT OR Apache-2.0 | Cargo.toml |
| windows-core | 0.61.2 | MIT OR Apache-2.0 | Cargo.toml |
| windows-future | 0.2.1 | MIT OR Apache-2.0 | Cargo.toml |
| windows-implement | 0.60.2 | MIT OR Apache-2.0 | Cargo.toml |
| windows-interface | 0.59.3 | MIT OR Apache-2.0 | Cargo.toml |
| windows-link | 0.1.3 | MIT OR Apache-2.0 | Cargo.toml |
| windows-numerics | 0.2.0 | MIT OR Apache-2.0 | Cargo.toml |
| windows-result | 0.3.4 | MIT OR Apache-2.0 | Cargo.toml |
| windows-strings | 0.4.2 | MIT OR Apache-2.0 | Cargo.toml |
| windows-threading | 0.1.0 | MIT OR Apache-2.0 | Cargo.toml |
| zlib-rs | 0.6.8 | Zlib | Cargo.toml |
| zmij | 1.0.23 | MIT | Cargo.toml |

### Rust 크레이트 (Windows 앱 · DLC 메이커 — Tauri) — `src-tauri/Cargo.lock`

490개 (그중 확인 못 함 218개). 잠금 파일의 모든 크레이트입니다(빌드 · 다른 운영체제 전용 포함). 이 저장소의 크레이트(app)는 뺐습니다.

허락 종류별: 확인 못 함 218 · MIT OR Apache-2.0 132 · MIT 48 · Apache-2.0 OR MIT 32 · Unicode-3.0 18 · MIT/Apache-2.0 11 · Unlicense OR MIT 8 · MPL-2.0 5 · BSD-3-Clause 2 · MIT OR Zlib OR Apache-2.0 2 · Unlicense/MIT 2 · Zlib 2 · (MIT OR Apache-2.0) AND Unicode-3.0 1 · 0BSD OR MIT OR Apache-2.0 1 · Apache-2.0 1 · Apache-2.0 / MIT 1 · Apache-2.0 AND MIT 1 · BSD-3-Clause AND MIT 1 · BSD-3-Clause/MIT 1 · CC0-1.0 OR MIT-0 OR Apache-2.0 1 · MIT OR Apache-2.0 OR Zlib 1 · Zlib OR Apache-2.0 OR MIT 1

| 이름 | 판 | 허락 | 근거 |
| --- | --- | --- | --- |
| adler2 | 2.0.1 | 0BSD OR MIT OR Apache-2.0 | Cargo.toml |
| aho-corasick | 1.1.5 | Unlicense OR MIT | Cargo.toml |
| alloc-no-stdlib | 2.0.4 | BSD-3-Clause | Cargo.toml |
| alloc-stdlib | 0.2.4 | BSD-3-Clause | Cargo.toml |
| android_log-sys | 0.3.2 | 확인 못 함 | 캐시에 없음 |
| android_logger | 0.15.1 | 확인 못 함 | 캐시에 없음 |
| android_system_properties | 0.1.6 | 확인 못 함 | 캐시에 없음 |
| anyhow | 1.0.104 | MIT OR Apache-2.0 | Cargo.toml |
| async-broadcast | 0.7.2 | 확인 못 함 | 캐시에 없음 |
| async-channel | 2.5.0 | 확인 못 함 | 캐시에 없음 |
| async-executor | 1.14.0 | 확인 못 함 | 캐시에 없음 |
| async-io | 2.6.0 | 확인 못 함 | 캐시에 없음 |
| async-lock | 3.4.2 | 확인 못 함 | 캐시에 없음 |
| async-process | 2.5.0 | 확인 못 함 | 캐시에 없음 |
| async-recursion | 1.1.1 | 확인 못 함 | 캐시에 없음 |
| async-signal | 0.2.14 | 확인 못 함 | 캐시에 없음 |
| async-task | 4.7.1 | 확인 못 함 | 캐시에 없음 |
| async-trait | 0.1.92 | 확인 못 함 | 캐시에 없음 |
| atk | 0.18.2 | 확인 못 함 | 캐시에 없음 |
| atk-sys | 0.18.2 | 확인 못 함 | 캐시에 없음 |
| atomic-waker | 1.1.2 | 확인 못 함 | 캐시에 없음 |
| autocfg | 1.5.1 | Apache-2.0 OR MIT | Cargo.toml |
| base64 | 0.21.7 | 확인 못 함 | 캐시에 없음 |
| base64 | 0.22.1 | MIT OR Apache-2.0 | Cargo.toml |
| base64 | 0.23.1 | MIT OR Apache-2.0 | Cargo.toml |
| bit-set | 0.8.0 | Apache-2.0 OR MIT | Cargo.toml |
| bit-vec | 0.8.0 | Apache-2.0 OR MIT | Cargo.toml |
| bitflags | 1.3.2 | MIT/Apache-2.0 | Cargo.toml |
| bitflags | 2.13.2 | MIT OR Apache-2.0 | Cargo.toml |
| block-buffer | 0.10.4 | MIT OR Apache-2.0 | Cargo.toml |
| block2 | 0.6.2 | 확인 못 함 | 캐시에 없음 |
| blocking | 1.7.0 | 확인 못 함 | 캐시에 없음 |
| brotli | 8.0.4 | BSD-3-Clause AND MIT | Cargo.toml |
| brotli-decompressor | 5.0.3 | BSD-3-Clause/MIT | Cargo.toml |
| bs58 | 0.5.1 | MIT/Apache-2.0 | Cargo.toml |
| bumpalo | 3.20.3 | MIT OR Apache-2.0 | Cargo.toml |
| bytemuck | 1.25.2 | 확인 못 함 | 캐시에 없음 |
| byteorder | 1.5.0 | Unlicense OR MIT | Cargo.toml |
| bytes | 1.12.1 | MIT | Cargo.toml |
| cairo-rs | 0.18.5 | 확인 못 함 | 캐시에 없음 |
| cairo-sys-rs | 0.18.2 | 확인 못 함 | 캐시에 없음 |
| camino | 1.2.6 | MIT OR Apache-2.0 | Cargo.toml |
| cargo-platform | 0.1.9 | MIT OR Apache-2.0 | Cargo.toml |
| cargo_metadata | 0.19.2 | MIT | Cargo.toml |
| cargo_toml | 0.22.3 | Apache-2.0 OR MIT | Cargo.toml |
| cc | 1.4.6 | MIT OR Apache-2.0 | Cargo.toml |
| cesu8 | 1.1.0 | 확인 못 함 | 캐시에 없음 |
| cfb | 0.7.3 | MIT | Cargo.toml |
| cfg-expr | 0.15.8 | 확인 못 함 | 캐시에 없음 |
| cfg-if | 1.0.4 | MIT OR Apache-2.0 | Cargo.toml |
| chrono | 0.4.45 | MIT OR Apache-2.0 | Cargo.toml |
| combine | 4.6.8 | 확인 못 함 | 캐시에 없음 |
| concurrent-queue | 2.5.0 | 확인 못 함 | 캐시에 없음 |
| cookie | 0.18.2 | MIT OR Apache-2.0 | Cargo.toml |
| core-foundation | 0.10.1 | 확인 못 함 | 캐시에 없음 |
| core-foundation-sys | 0.8.7 | 확인 못 함 | 캐시에 없음 |
| core-graphics | 0.25.0 | 확인 못 함 | 캐시에 없음 |
| core-graphics-types | 0.2.0 | 확인 못 함 | 캐시에 없음 |
| cpufeatures | 0.2.17 | MIT OR Apache-2.0 | Cargo.toml |
| crc32fast | 1.5.2 | MIT OR Apache-2.0 | Cargo.toml |
| crossbeam-channel | 0.5.17 | MIT OR Apache-2.0 | Cargo.toml |
| crossbeam-utils | 0.8.23 | MIT OR Apache-2.0 | Cargo.toml |
| crypto-common | 0.1.7 | MIT OR Apache-2.0 | Cargo.toml |
| cssparser | 0.36.0 | MPL-2.0 | Cargo.toml |
| cssparser-macros | 0.6.1 | MPL-2.0 | Cargo.toml |
| ctor | 0.8.0 | Apache-2.0 OR MIT | Cargo.toml |
| ctor-proc-macro | 0.0.7 | Apache-2.0 OR MIT | Cargo.toml |
| darling | 0.24.1 | MIT | Cargo.toml |
| darling_core | 0.24.1 | MIT | Cargo.toml |
| darling_macro | 0.24.1 | MIT | Cargo.toml |
| dbus | 0.9.12 | 확인 못 함 | 캐시에 없음 |
| defmt | 1.1.1 | MIT OR Apache-2.0 | Cargo.toml |
| defmt-macros | 1.1.1 | MIT OR Apache-2.0 | Cargo.toml |
| defmt-parser | 1.0.0 | MIT OR Apache-2.0 | Cargo.toml |
| deranged | 0.5.8 | MIT OR Apache-2.0 | Cargo.toml |
| derive_more | 2.1.1 | MIT | Cargo.toml |
| derive_more-impl | 2.1.1 | MIT | Cargo.toml |
| digest | 0.10.7 | MIT OR Apache-2.0 | Cargo.toml |
| dirs | 6.0.0 | MIT OR Apache-2.0 | Cargo.toml |
| dirs-sys | 0.5.0 | MIT OR Apache-2.0 | Cargo.toml |
| dispatch2 | 0.3.1 | 확인 못 함 | 캐시에 없음 |
| displaydoc | 0.2.7 | MIT OR Apache-2.0 | Cargo.toml |
| dlopen2 | 0.8.2 | 확인 못 함 | 캐시에 없음 |
| dlopen2_derive | 0.4.3 | 확인 못 함 | 캐시에 없음 |
| dom_query | 0.27.0 | MIT | Cargo.toml |
| dpi | 0.1.2 | Apache-2.0 AND MIT | Cargo.toml |
| dtoa | 1.0.11 | MIT OR Apache-2.0 | Cargo.toml |
| dtoa-short | 0.3.5 | MPL-2.0 | Cargo.toml |
| dtor | 0.3.0 | Apache-2.0 OR MIT | Cargo.toml |
| dtor-proc-macro | 0.0.6 | Apache-2.0 OR MIT | Cargo.toml |
| dunce | 1.0.5 | CC0-1.0 OR MIT-0 OR Apache-2.0 | Cargo.toml |
| dyn-clone | 1.0.20 | MIT OR Apache-2.0 | Cargo.toml |
| embed-resource | 3.0.11 | MIT | Cargo.toml |
| embed_plist | 1.2.2 | 확인 못 함 | 캐시에 없음 |
| endi | 1.1.1 | 확인 못 함 | 캐시에 없음 |
| enumflags2 | 0.7.12 | 확인 못 함 | 캐시에 없음 |
| enumflags2_derive | 0.7.12 | 확인 못 함 | 캐시에 없음 |
| env_filter | 0.1.4 | 확인 못 함 | 캐시에 없음 |
| equivalent | 1.0.2 | Apache-2.0 OR MIT | Cargo.toml |
| erased-serde | 0.4.10 | MIT OR Apache-2.0 | Cargo.toml |
| errno | 0.3.14 | 확인 못 함 | 캐시에 없음 |
| event-listener | 5.4.2 | 확인 못 함 | 캐시에 없음 |
| event-listener-strategy | 0.5.4 | 확인 못 함 | 캐시에 없음 |
| fastrand | 2.5.0 | Apache-2.0 OR MIT | Cargo.toml |
| fdeflate | 0.3.7 | MIT OR Apache-2.0 | Cargo.toml |
| fern | 0.7.1 | MIT | Cargo.toml |
| field-offset | 0.3.6 | 확인 못 함 | 캐시에 없음 |
| find-msvc-tools | 0.1.12 | MIT OR Apache-2.0 | Cargo.toml |
| flate2 | 1.1.10 | MIT OR Apache-2.0 | Cargo.toml |
| fnv | 1.0.7 | Apache-2.0 / MIT | Cargo.toml |
| foldhash | 0.2.0 | Zlib | Cargo.toml |
| foreign-types | 0.5.0 | 확인 못 함 | 캐시에 없음 |
| foreign-types-macros | 0.2.4 | 확인 못 함 | 캐시에 없음 |
| foreign-types-shared | 0.3.1 | 확인 못 함 | 캐시에 없음 |
| form_urlencoded | 1.2.2 | MIT OR Apache-2.0 | Cargo.toml |
| futures-channel | 0.3.34 | 확인 못 함 | 캐시에 없음 |
| futures-core | 0.3.34 | 확인 못 함 | 캐시에 없음 |
| futures-executor | 0.3.34 | 확인 못 함 | 캐시에 없음 |
| futures-io | 0.3.34 | 확인 못 함 | 캐시에 없음 |
| futures-lite | 2.6.1 | 확인 못 함 | 캐시에 없음 |
| futures-macro | 0.3.34 | 확인 못 함 | 캐시에 없음 |
| futures-sink | 0.3.34 | 확인 못 함 | 캐시에 없음 |
| futures-task | 0.3.34 | 확인 못 함 | 캐시에 없음 |
| futures-util | 0.3.34 | 확인 못 함 | 캐시에 없음 |
| gdk | 0.18.2 | 확인 못 함 | 캐시에 없음 |
| gdk-pixbuf | 0.18.5 | 확인 못 함 | 캐시에 없음 |
| gdk-pixbuf-sys | 0.18.0 | 확인 못 함 | 캐시에 없음 |
| gdk-sys | 0.18.2 | 확인 못 함 | 캐시에 없음 |
| gdkwayland-sys | 0.18.2 | 확인 못 함 | 캐시에 없음 |
| gdkx11 | 0.18.2 | 확인 못 함 | 캐시에 없음 |
| gdkx11-sys | 0.18.2 | 확인 못 함 | 캐시에 없음 |
| generic-array | 0.14.7 | MIT | Cargo.toml |
| getrandom | 0.3.4 | MIT OR Apache-2.0 | Cargo.toml |
| getrandom | 0.4.3 | MIT OR Apache-2.0 | Cargo.toml |
| gio | 0.18.4 | 확인 못 함 | 캐시에 없음 |
| gio-sys | 0.18.1 | 확인 못 함 | 캐시에 없음 |
| glib | 0.18.5 | 확인 못 함 | 캐시에 없음 |
| glib-macros | 0.18.5 | 확인 못 함 | 캐시에 없음 |
| glib-sys | 0.18.1 | 확인 못 함 | 캐시에 없음 |
| glob | 0.3.4 | MIT OR Apache-2.0 | Cargo.toml |
| gobject-sys | 0.18.0 | 확인 못 함 | 캐시에 없음 |
| gtk | 0.18.2 | 확인 못 함 | 캐시에 없음 |
| gtk-sys | 0.18.2 | 확인 못 함 | 캐시에 없음 |
| gtk3-macros | 0.18.2 | 확인 못 함 | 캐시에 없음 |
| hashbrown | 0.12.3 | MIT OR Apache-2.0 | Cargo.toml |
| hashbrown | 0.17.1 | MIT OR Apache-2.0 | Cargo.toml |
| heck | 0.4.1 | 확인 못 함 | 캐시에 없음 |
| heck | 0.5.0 | MIT OR Apache-2.0 | Cargo.toml |
| hermit-abi | 0.5.3 | 확인 못 함 | 캐시에 없음 |
| hex | 0.4.3 | MIT OR Apache-2.0 | Cargo.toml |
| html5ever | 0.38.0 | MIT OR Apache-2.0 | Cargo.toml |
| http | 1.5.0 | MIT OR Apache-2.0 | Cargo.toml |
| http-body | 1.1.0 | 확인 못 함 | 캐시에 없음 |
| http-body-util | 0.1.5 | 확인 못 함 | 캐시에 없음 |
| httparse | 1.10.1 | 확인 못 함 | 캐시에 없음 |
| hyper | 1.11.1 | 확인 못 함 | 캐시에 없음 |
| hyper-util | 0.1.20 | 확인 못 함 | 캐시에 없음 |
| iana-time-zone | 0.1.65 | 확인 못 함 | 캐시에 없음 |
| iana-time-zone-haiku | 0.1.2 | 확인 못 함 | 캐시에 없음 |
| ico | 0.5.0 | MIT | Cargo.toml |
| icu_collections | 2.3.0 | Unicode-3.0 | Cargo.toml |
| icu_locale_core | 2.3.0 | Unicode-3.0 | Cargo.toml |
| icu_normalizer | 2.3.0 | Unicode-3.0 | Cargo.toml |
| icu_normalizer_data | 2.3.0 | Unicode-3.0 | Cargo.toml |
| icu_properties | 2.3.0 | Unicode-3.0 | Cargo.toml |
| icu_properties_data | 2.3.0 | Unicode-3.0 | Cargo.toml |
| icu_provider | 2.3.1 | Unicode-3.0 | Cargo.toml |
| ident_case | 1.0.1 | MIT/Apache-2.0 | Cargo.toml |
| idna | 1.1.0 | MIT OR Apache-2.0 | Cargo.toml |
| idna_adapter | 1.2.2 | Apache-2.0 OR MIT | Cargo.toml |
| indexmap | 1.9.3 | Apache-2.0 OR MIT | Cargo.toml |
| indexmap | 2.14.2 | Apache-2.0 OR MIT | Cargo.toml |
| infer | 0.19.0 | MIT | Cargo.toml |
| ipnet | 2.12.2 | 확인 못 함 | 캐시에 없음 |
| is-docker | 0.2.0 | 확인 못 함 | 캐시에 없음 |
| is-wsl | 0.4.0 | 확인 못 함 | 캐시에 없음 |
| itoa | 1.0.18 | MIT OR Apache-2.0 | Cargo.toml |
| javascriptcore-rs | 1.1.2 | 확인 못 함 | 캐시에 없음 |
| javascriptcore-rs-sys | 1.1.1 | 확인 못 함 | 캐시에 없음 |
| jiff | 0.2.37 | Unlicense OR MIT | Cargo.toml |
| jiff-core | 0.1.1 | Unlicense OR MIT | Cargo.toml |
| jiff-static | 0.2.37 | 확인 못 함 | 캐시에 없음 |
| jiff-tzdb | 0.1.8 | Unlicense OR MIT | Cargo.toml |
| jiff-tzdb-platform | 0.1.3 | Unlicense OR MIT | Cargo.toml |
| jni | 0.21.1 | 확인 못 함 | 캐시에 없음 |
| jni-sys | 0.3.1 | 확인 못 함 | 캐시에 없음 |
| jni-sys | 0.4.1 | 확인 못 함 | 캐시에 없음 |
| jni-sys-macros | 0.4.1 | 확인 못 함 | 캐시에 없음 |
| js-sys | 0.3.105 | 확인 못 함 | 캐시에 없음 |
| json-patch | 3.0.1 | MIT/Apache-2.0 | Cargo.toml |
| jsonptr | 0.6.3 | MIT OR Apache-2.0 | Cargo.toml |
| keyboard-types | 0.7.0 | MIT OR Apache-2.0 | Cargo.toml |
| libappindicator | 0.9.0 | 확인 못 함 | 캐시에 없음 |
| libappindicator-sys | 0.9.0 | 확인 못 함 | 캐시에 없음 |
| libc | 0.2.189 | MIT OR Apache-2.0 | Cargo.toml |
| libdbus-sys | 0.2.7 | 확인 못 함 | 캐시에 없음 |
| libloading | 0.7.4 | 확인 못 함 | 캐시에 없음 |
| libredox | 0.1.24 | 확인 못 함 | 캐시에 없음 |
| linux-raw-sys | 0.12.1 | 확인 못 함 | 캐시에 없음 |
| litemap | 0.8.3 | Unicode-3.0 | Cargo.toml |
| lock_api | 0.4.14 | MIT OR Apache-2.0 | Cargo.toml |
| log | 0.4.34 | MIT OR Apache-2.0 | Cargo.toml |
| markup5ever | 0.38.0 | MIT OR Apache-2.0 | Cargo.toml |
| memchr | 2.8.3 | Unlicense OR MIT | Cargo.toml |
| memoffset | 0.9.1 | 확인 못 함 | 캐시에 없음 |
| mime | 0.3.17 | MIT OR Apache-2.0 | Cargo.toml |
| miniz_oxide | 0.8.9 | MIT OR Zlib OR Apache-2.0 | Cargo.toml |
| miniz_oxide | 0.9.1 | MIT OR Zlib OR Apache-2.0 | Cargo.toml |
| mio | 1.2.3 | MIT | Cargo.toml |
| muda | 0.19.3 | Apache-2.0 OR MIT | Cargo.toml |
| ndk | 0.9.0 | 확인 못 함 | 캐시에 없음 |
| ndk-sys | 0.6.0+11769913 | 확인 못 함 | 캐시에 없음 |
| new_debug_unreachable | 1.0.6 | MIT | Cargo.toml |
| num-conv | 0.2.2 | MIT OR Apache-2.0 | Cargo.toml |
| num-traits | 0.2.19 | MIT OR Apache-2.0 | Cargo.toml |
| num_enum | 0.7.6 | 확인 못 함 | 캐시에 없음 |
| num_enum_derive | 0.7.6 | 확인 못 함 | 캐시에 없음 |
| num_threads | 0.1.7 | 확인 못 함 | 캐시에 없음 |
| objc2 | 0.6.4 | 확인 못 함 | 캐시에 없음 |
| objc2-app-kit | 0.3.2 | 확인 못 함 | 캐시에 없음 |
| objc2-cloud-kit | 0.3.2 | 확인 못 함 | 캐시에 없음 |
| objc2-core-data | 0.3.2 | 확인 못 함 | 캐시에 없음 |
| objc2-core-foundation | 0.3.2 | 확인 못 함 | 캐시에 없음 |
| objc2-core-graphics | 0.3.2 | 확인 못 함 | 캐시에 없음 |
| objc2-core-image | 0.3.2 | 확인 못 함 | 캐시에 없음 |
| objc2-core-location | 0.3.2 | 확인 못 함 | 캐시에 없음 |
| objc2-core-text | 0.3.2 | 확인 못 함 | 캐시에 없음 |
| objc2-encode | 4.1.0 | 확인 못 함 | 캐시에 없음 |
| objc2-exception-helper | 0.1.1 | 확인 못 함 | 캐시에 없음 |
| objc2-foundation | 0.3.2 | 확인 못 함 | 캐시에 없음 |
| objc2-io-surface | 0.3.2 | 확인 못 함 | 캐시에 없음 |
| objc2-quartz-core | 0.3.2 | 확인 못 함 | 캐시에 없음 |
| objc2-ui-kit | 0.3.2 | 확인 못 함 | 캐시에 없음 |
| objc2-user-notifications | 0.3.2 | 확인 못 함 | 캐시에 없음 |
| objc2-web-kit | 0.3.2 | 확인 못 함 | 캐시에 없음 |
| once_cell | 1.21.4 | MIT OR Apache-2.0 | Cargo.toml |
| open | 5.4.4 | MIT | Cargo.toml |
| option-ext | 0.2.0 | MPL-2.0 | Cargo.toml |
| ordered-stream | 0.2.0 | 확인 못 함 | 캐시에 없음 |
| pango | 0.18.3 | 확인 못 함 | 캐시에 없음 |
| pango-sys | 0.18.0 | 확인 못 함 | 캐시에 없음 |
| parking | 2.2.1 | 확인 못 함 | 캐시에 없음 |
| parking_lot | 0.12.5 | MIT OR Apache-2.0 | Cargo.toml |
| parking_lot_core | 0.9.12 | MIT OR Apache-2.0 | Cargo.toml |
| percent-encoding | 2.3.2 | MIT OR Apache-2.0 | Cargo.toml |
| phf | 0.13.1 | MIT | Cargo.toml |
| phf_codegen | 0.13.1 | MIT | Cargo.toml |
| phf_generator | 0.13.1 | MIT | Cargo.toml |
| phf_macros | 0.13.1 | MIT | Cargo.toml |
| phf_shared | 0.13.1 | MIT | Cargo.toml |
| pin-project-lite | 0.2.17 | Apache-2.0 OR MIT | Cargo.toml |
| piper | 0.2.5 | 확인 못 함 | 캐시에 없음 |
| pkg-config | 0.3.34 | MIT OR Apache-2.0 | Cargo.toml |
| plist | 1.10.1 | MIT | Cargo.toml |
| png | 0.17.16 | MIT OR Apache-2.0 | Cargo.toml |
| png | 0.18.1 | 확인 못 함 | 캐시에 없음 |
| polling | 3.11.0 | 확인 못 함 | 캐시에 없음 |
| portable-atomic | 1.15.0 | 확인 못 함 | 캐시에 없음 |
| portable-atomic-util | 0.2.8 | 확인 못 함 | 캐시에 없음 |
| potential_utf | 0.1.6 | Unicode-3.0 | Cargo.toml |
| powerfmt | 0.2.0 | MIT OR Apache-2.0 | Cargo.toml |
| precomputed-hash | 0.1.1 | MIT | Cargo.toml |
| proc-macro-crate | 1.3.1 | 확인 못 함 | 캐시에 없음 |
| proc-macro-crate | 2.0.2 | 확인 못 함 | 캐시에 없음 |
| proc-macro-crate | 3.5.0 | 확인 못 함 | 캐시에 없음 |
| proc-macro-error | 1.0.4 | 확인 못 함 | 캐시에 없음 |
| proc-macro-error-attr | 1.0.4 | 확인 못 함 | 캐시에 없음 |
| proc-macro2 | 1.0.107 | MIT OR Apache-2.0 | Cargo.toml |
| quick-xml | 0.42.0 | MIT | Cargo.toml |
| quote | 1.0.47 | MIT OR Apache-2.0 | Cargo.toml |
| r-efi | 5.3.0 | 확인 못 함 | 캐시에 없음 |
| r-efi | 6.0.0 | 확인 못 함 | 캐시에 없음 |
| raw-window-handle | 0.6.2 | MIT OR Apache-2.0 OR Zlib | Cargo.toml |
| redox_syscall | 0.5.18 | 확인 못 함 | 캐시에 없음 |
| redox_users | 0.5.3 | 확인 못 함 | 캐시에 없음 |
| ref-cast | 1.0.27 | MIT OR Apache-2.0 | Cargo.toml |
| ref-cast-impl | 1.0.27 | MIT OR Apache-2.0 | Cargo.toml |
| regex | 1.13.1 | MIT OR Apache-2.0 | Cargo.toml |
| regex-automata | 0.4.18 | MIT OR Apache-2.0 | Cargo.toml |
| regex-syntax | 0.8.11 | MIT OR Apache-2.0 | Cargo.toml |
| reqwest | 0.13.5 | 확인 못 함 | 캐시에 없음 |
| rfd | 0.16.0 | MIT | Cargo.toml |
| rustc-hash | 2.1.3 | Apache-2.0 OR MIT | Cargo.toml |
| rustc_version | 0.4.1 | MIT OR Apache-2.0 | Cargo.toml |
| rustix | 1.1.4 | 확인 못 함 | 캐시에 없음 |
| rustversion | 1.0.23 | 확인 못 함 | 캐시에 없음 |
| same-file | 1.0.6 | Unlicense/MIT | Cargo.toml |
| schemars | 0.8.22 | MIT | Cargo.toml |
| schemars | 0.9.0 | MIT | Cargo.toml |
| schemars | 1.2.2 | MIT | Cargo.toml |
| schemars_derive | 0.8.22 | MIT | Cargo.toml |
| scopeguard | 1.2.0 | MIT OR Apache-2.0 | Cargo.toml |
| selectors | 0.36.1 | MPL-2.0 | Cargo.toml |
| semver | 1.0.28 | MIT OR Apache-2.0 | Cargo.toml |
| serde | 1.0.229 | MIT OR Apache-2.0 | Cargo.toml |
| serde-untagged | 0.1.9 | MIT OR Apache-2.0 | Cargo.toml |
| serde_core | 1.0.229 | MIT OR Apache-2.0 | Cargo.toml |
| serde_derive | 1.0.229 | MIT OR Apache-2.0 | Cargo.toml |
| serde_derive_internals | 0.29.1 | MIT OR Apache-2.0 | Cargo.toml |
| serde_json | 1.0.151 | MIT OR Apache-2.0 | Cargo.toml |
| serde_repr | 0.1.21 | MIT OR Apache-2.0 | Cargo.toml |
| serde_spanned | 0.6.9 | 확인 못 함 | 캐시에 없음 |
| serde_spanned | 1.1.1 | MIT OR Apache-2.0 | Cargo.toml |
| serde_with | 3.23.0 | MIT OR Apache-2.0 | Cargo.toml |
| serde_with_macros | 3.23.0 | MIT OR Apache-2.0 | Cargo.toml |
| serialize-to-javascript | 0.1.2 | MIT OR Apache-2.0 | Cargo.toml |
| serialize-to-javascript-impl | 0.1.2 | MIT OR Apache-2.0 | Cargo.toml |
| servo_arc | 0.4.3 | MIT OR Apache-2.0 | Cargo.toml |
| sha2 | 0.10.9 | MIT OR Apache-2.0 | Cargo.toml |
| shlex | 2.0.1 | MIT OR Apache-2.0 | Cargo.toml |
| signal-hook-registry | 1.4.8 | 확인 못 함 | 캐시에 없음 |
| simd-adler32 | 0.3.10 | MIT | Cargo.toml |
| siphasher | 1.0.3 | MIT/Apache-2.0 | Cargo.toml |
| slab | 0.4.12 | 확인 못 함 | 캐시에 없음 |
| smallvec | 1.16.1 | MIT OR Apache-2.0 | Cargo.toml |
| socket2 | 0.6.5 | MIT OR Apache-2.0 | Cargo.toml |
| softbuffer | 0.4.8 | MIT OR Apache-2.0 | Cargo.toml |
| soup3 | 0.5.0 | 확인 못 함 | 캐시에 없음 |
| soup3-sys | 0.5.0 | 확인 못 함 | 캐시에 없음 |
| stable_deref_trait | 1.2.1 | MIT OR Apache-2.0 | Cargo.toml |
| string_cache | 0.9.0 | MIT OR Apache-2.0 | Cargo.toml |
| string_cache_codegen | 0.6.1 | MIT OR Apache-2.0 | Cargo.toml |
| strsim | 0.11.1 | MIT | Cargo.toml |
| swift-rs | 1.0.8 | 확인 못 함 | 캐시에 없음 |
| syn | 1.0.109 | 확인 못 함 | 캐시에 없음 |
| syn | 2.0.119 | MIT OR Apache-2.0 | Cargo.toml |
| syn | 3.0.5 | MIT OR Apache-2.0 | Cargo.toml |
| sync_wrapper | 1.0.2 | 확인 못 함 | 캐시에 없음 |
| synstructure | 0.14.0 | MIT | Cargo.toml |
| system-deps | 6.2.2 | 확인 못 함 | 캐시에 없음 |
| tao | 0.35.3 | Apache-2.0 | Cargo.toml |
| tao-macros | 0.1.4 | 확인 못 함 | 캐시에 없음 |
| target-lexicon | 0.12.16 | 확인 못 함 | 캐시에 없음 |
| tauri | 2.11.5 | Apache-2.0 OR MIT | Cargo.toml |
| tauri-build | 2.6.3 | Apache-2.0 OR MIT | Cargo.toml |
| tauri-codegen | 2.6.3 | Apache-2.0 OR MIT | Cargo.toml |
| tauri-macros | 2.6.3 | Apache-2.0 OR MIT | Cargo.toml |
| tauri-plugin | 2.6.3 | Apache-2.0 OR MIT | Cargo.toml |
| tauri-plugin-dialog | 2.7.3 | Apache-2.0 OR MIT | Cargo.toml |
| tauri-plugin-fs | 2.5.2 | Apache-2.0 OR MIT | Cargo.toml |
| tauri-plugin-log | 2.9.1 | Apache-2.0 OR MIT | Cargo.toml |
| tauri-plugin-opener | 2.5.5 | Apache-2.0 OR MIT | Cargo.toml |
| tauri-runtime | 2.11.3 | Apache-2.0 OR MIT | Cargo.toml |
| tauri-runtime-wry | 2.11.4 | Apache-2.0 OR MIT | Cargo.toml |
| tauri-utils | 2.9.3 | Apache-2.0 OR MIT | Cargo.toml |
| tauri-winres | 0.3.6 | MIT | Cargo.toml |
| tempfile | 3.27.0 | 확인 못 함 | 캐시에 없음 |
| tendril | 0.5.1 | MIT OR Apache-2.0 | Cargo.toml |
| thiserror | 1.0.69 | MIT OR Apache-2.0 | Cargo.toml |
| thiserror | 2.0.20 | MIT OR Apache-2.0 | Cargo.toml |
| thiserror-impl | 1.0.69 | MIT OR Apache-2.0 | Cargo.toml |
| thiserror-impl | 2.0.20 | MIT OR Apache-2.0 | Cargo.toml |
| time | 0.3.55 | MIT OR Apache-2.0 | Cargo.toml |
| time-core | 0.1.9 | MIT OR Apache-2.0 | Cargo.toml |
| time-macros | 0.2.32 | MIT OR Apache-2.0 | Cargo.toml |
| tinystr | 0.8.4 | Unicode-3.0 | Cargo.toml |
| tinyvec | 1.13.3 | Zlib OR Apache-2.0 OR MIT | Cargo.toml |
| tokio | 1.53.1 | MIT | Cargo.toml |
| tokio-util | 0.7.19 | 확인 못 함 | 캐시에 없음 |
| toml | 0.8.2 | 확인 못 함 | 캐시에 없음 |
| toml | 0.9.12+spec-1.1.0 | MIT OR Apache-2.0 | Cargo.toml |
| toml | 1.1.6+spec-1.1.0 | MIT OR Apache-2.0 | Cargo.toml |
| toml_datetime | 0.6.3 | 확인 못 함 | 캐시에 없음 |
| toml_datetime | 0.7.5+spec-1.1.0 | MIT OR Apache-2.0 | Cargo.toml |
| toml_datetime | 1.1.1+spec-1.1.0 | MIT OR Apache-2.0 | Cargo.toml |
| toml_edit | 0.19.15 | 확인 못 함 | 캐시에 없음 |
| toml_edit | 0.20.2 | 확인 못 함 | 캐시에 없음 |
| toml_edit | 0.25.15+spec-1.1.0 | 확인 못 함 | 캐시에 없음 |
| toml_parser | 1.1.3+spec-1.1.0 | MIT OR Apache-2.0 | Cargo.toml |
| toml_writer | 1.1.2+spec-1.1.0 | MIT OR Apache-2.0 | Cargo.toml |
| tower | 0.5.3 | 확인 못 함 | 캐시에 없음 |
| tower-http | 0.6.11 | 확인 못 함 | 캐시에 없음 |
| tower-layer | 0.3.3 | 확인 못 함 | 캐시에 없음 |
| tower-service | 0.3.3 | 확인 못 함 | 캐시에 없음 |
| tracing | 0.1.44 | MIT | Cargo.toml |
| tracing-attributes | 0.1.31 | MIT | Cargo.toml |
| tracing-core | 0.1.36 | MIT | Cargo.toml |
| tray-icon | 0.24.2 | MIT OR Apache-2.0 | Cargo.toml |
| try-lock | 0.2.5 | 확인 못 함 | 캐시에 없음 |
| typeid | 1.0.3 | MIT OR Apache-2.0 | Cargo.toml |
| typenum | 1.20.1 | MIT OR Apache-2.0 | Cargo.toml |
| uds_windows | 1.2.1 | 확인 못 함 | 캐시에 없음 |
| unic-char-property | 0.9.0 | MIT/Apache-2.0 | Cargo.toml |
| unic-char-range | 0.9.0 | MIT/Apache-2.0 | Cargo.toml |
| unic-common | 0.9.0 | MIT/Apache-2.0 | Cargo.toml |
| unic-ucd-ident | 0.9.0 | MIT/Apache-2.0 | Cargo.toml |
| unic-ucd-version | 0.9.0 | MIT/Apache-2.0 | Cargo.toml |
| unicode-ident | 1.0.24 | (MIT OR Apache-2.0) AND Unicode-3.0 | Cargo.toml |
| unicode-segmentation | 1.13.3 | MIT OR Apache-2.0 | Cargo.toml |
| url | 2.5.8 | MIT OR Apache-2.0 | Cargo.toml |
| urlpattern | 0.3.0 | MIT | Cargo.toml |
| utf8_iter | 1.0.4 | Apache-2.0 OR MIT | Cargo.toml |
| uuid | 1.26.1 | Apache-2.0 OR MIT | Cargo.toml |
| version-compare | 0.2.1 | 확인 못 함 | 캐시에 없음 |
| version_check | 0.9.5 | MIT/Apache-2.0 | Cargo.toml |
| vswhom | 0.1.0 | MIT | Cargo.toml |
| vswhom-sys | 0.1.3 | MIT | Cargo.toml |
| walkdir | 2.5.0 | Unlicense/MIT | Cargo.toml |
| want | 0.3.1 | 확인 못 함 | 캐시에 없음 |
| wasi | 0.11.1+wasi-snapshot-preview1 | 확인 못 함 | 캐시에 없음 |
| wasip2 | 1.0.4+wasi-0.2.12 | 확인 못 함 | 캐시에 없음 |
| wasm-bindgen | 0.2.128 | 확인 못 함 | 캐시에 없음 |
| wasm-bindgen-futures | 0.4.78 | 확인 못 함 | 캐시에 없음 |
| wasm-bindgen-macro | 0.2.128 | 확인 못 함 | 캐시에 없음 |
| wasm-bindgen-macro-support | 0.2.128 | 확인 못 함 | 캐시에 없음 |
| wasm-bindgen-shared | 0.2.128 | 확인 못 함 | 캐시에 없음 |
| wasm-streams | 0.5.0 | 확인 못 함 | 캐시에 없음 |
| web-sys | 0.3.105 | 확인 못 함 | 캐시에 없음 |
| web_atoms | 0.2.6 | MIT OR Apache-2.0 | Cargo.toml |
| webkit2gtk | 2.0.2 | 확인 못 함 | 캐시에 없음 |
| webkit2gtk-sys | 2.0.2 | 확인 못 함 | 캐시에 없음 |
| webview2-com | 0.38.2 | MIT | Cargo.toml |
| webview2-com-macros | 0.8.1 | MIT | Cargo.toml |
| webview2-com-sys | 0.38.2 | MIT | Cargo.toml |
| winapi | 0.3.9 | 확인 못 함 | 캐시에 없음 |
| winapi-i686-pc-windows-gnu | 0.4.0 | 확인 못 함 | 캐시에 없음 |
| winapi-util | 0.1.11 | Unlicense OR MIT | Cargo.toml |
| winapi-x86_64-pc-windows-gnu | 0.4.0 | 확인 못 함 | 캐시에 없음 |
| window-vibrancy | 0.6.0 | Apache-2.0 OR MIT | Cargo.toml |
| windows | 0.61.3 | MIT OR Apache-2.0 | Cargo.toml |
| windows-collections | 0.2.0 | MIT OR Apache-2.0 | Cargo.toml |
| windows-core | 0.61.2 | MIT OR Apache-2.0 | Cargo.toml |
| windows-core | 0.62.2 | 확인 못 함 | 캐시에 없음 |
| windows-future | 0.2.1 | MIT OR Apache-2.0 | Cargo.toml |
| windows-implement | 0.60.2 | MIT OR Apache-2.0 | Cargo.toml |
| windows-interface | 0.59.3 | MIT OR Apache-2.0 | Cargo.toml |
| windows-link | 0.1.3 | MIT OR Apache-2.0 | Cargo.toml |
| windows-link | 0.2.1 | MIT OR Apache-2.0 | Cargo.toml |
| windows-numerics | 0.2.0 | MIT OR Apache-2.0 | Cargo.toml |
| windows-result | 0.3.4 | MIT OR Apache-2.0 | Cargo.toml |
| windows-result | 0.4.1 | 확인 못 함 | 캐시에 없음 |
| windows-strings | 0.4.2 | MIT OR Apache-2.0 | Cargo.toml |
| windows-strings | 0.5.1 | 확인 못 함 | 캐시에 없음 |
| windows-sys | 0.45.0 | 확인 못 함 | 캐시에 없음 |
| windows-sys | 0.59.0 | MIT OR Apache-2.0 | Cargo.toml |
| windows-sys | 0.60.2 | MIT OR Apache-2.0 | Cargo.toml |
| windows-sys | 0.61.2 | MIT OR Apache-2.0 | Cargo.toml |
| windows-targets | 0.42.2 | 확인 못 함 | 캐시에 없음 |
| windows-targets | 0.52.6 | MIT OR Apache-2.0 | Cargo.toml |
| windows-targets | 0.53.5 | MIT OR Apache-2.0 | Cargo.toml |
| windows-threading | 0.1.0 | MIT OR Apache-2.0 | Cargo.toml |
| windows-version | 0.1.7 | MIT OR Apache-2.0 | Cargo.toml |
| windows_aarch64_gnullvm | 0.42.2 | 확인 못 함 | 캐시에 없음 |
| windows_aarch64_gnullvm | 0.52.6 | 확인 못 함 | 캐시에 없음 |
| windows_aarch64_gnullvm | 0.53.1 | 확인 못 함 | 캐시에 없음 |
| windows_aarch64_msvc | 0.42.2 | 확인 못 함 | 캐시에 없음 |
| windows_aarch64_msvc | 0.52.6 | 확인 못 함 | 캐시에 없음 |
| windows_aarch64_msvc | 0.53.1 | 확인 못 함 | 캐시에 없음 |
| windows_i686_gnu | 0.42.2 | 확인 못 함 | 캐시에 없음 |
| windows_i686_gnu | 0.52.6 | 확인 못 함 | 캐시에 없음 |
| windows_i686_gnu | 0.53.1 | 확인 못 함 | 캐시에 없음 |
| windows_i686_gnullvm | 0.52.6 | 확인 못 함 | 캐시에 없음 |
| windows_i686_gnullvm | 0.53.1 | 확인 못 함 | 캐시에 없음 |
| windows_i686_msvc | 0.42.2 | 확인 못 함 | 캐시에 없음 |
| windows_i686_msvc | 0.52.6 | 확인 못 함 | 캐시에 없음 |
| windows_i686_msvc | 0.53.1 | 확인 못 함 | 캐시에 없음 |
| windows_x86_64_gnu | 0.42.2 | 확인 못 함 | 캐시에 없음 |
| windows_x86_64_gnu | 0.52.6 | 확인 못 함 | 캐시에 없음 |
| windows_x86_64_gnu | 0.53.1 | 확인 못 함 | 캐시에 없음 |
| windows_x86_64_gnullvm | 0.42.2 | 확인 못 함 | 캐시에 없음 |
| windows_x86_64_gnullvm | 0.52.6 | 확인 못 함 | 캐시에 없음 |
| windows_x86_64_gnullvm | 0.53.1 | 확인 못 함 | 캐시에 없음 |
| windows_x86_64_msvc | 0.42.2 | 확인 못 함 | 캐시에 없음 |
| windows_x86_64_msvc | 0.52.6 | MIT OR Apache-2.0 | Cargo.toml |
| windows_x86_64_msvc | 0.53.1 | MIT OR Apache-2.0 | Cargo.toml |
| winnow | 0.5.40 | 확인 못 함 | 캐시에 없음 |
| winnow | 0.7.15 | MIT | Cargo.toml |
| winnow | 1.0.4 | MIT | Cargo.toml |
| winreg | 0.55.0 | MIT | Cargo.toml |
| wit-bindgen | 0.57.1 | 확인 못 함 | 캐시에 없음 |
| writeable | 0.6.4 | Unicode-3.0 | Cargo.toml |
| wry | 0.55.1 | Apache-2.0 OR MIT | Cargo.toml |
| x11 | 2.21.0 | 확인 못 함 | 캐시에 없음 |
| x11-dl | 2.21.0 | 확인 못 함 | 캐시에 없음 |
| yoke | 0.8.3 | Unicode-3.0 | Cargo.toml |
| yoke-derive | 0.8.3 | Unicode-3.0 | Cargo.toml |
| zbus | 5.19.0 | 확인 못 함 | 캐시에 없음 |
| zbus_macros | 5.19.0 | 확인 못 함 | 캐시에 없음 |
| zbus_names | 4.3.4 | 확인 못 함 | 캐시에 없음 |
| zcheapstr | 1.1.0 | 확인 못 함 | 캐시에 없음 |
| zerofrom | 0.1.8 | Unicode-3.0 | Cargo.toml |
| zerofrom-derive | 0.1.8 | Unicode-3.0 | Cargo.toml |
| zerotrie | 0.2.5 | Unicode-3.0 | Cargo.toml |
| zerovec | 0.11.8 | Unicode-3.0 | Cargo.toml |
| zerovec-derive | 0.11.6 | Unicode-3.0 | Cargo.toml |
| zlib-rs | 0.6.8 | Zlib | Cargo.toml |
| zmij | 1.0.23 | MIT | Cargo.toml |
| zvariant | 5.15.0 | 확인 못 함 | 캐시에 없음 |
| zvariant_derive | 5.15.0 | 확인 못 함 | 캐시에 없음 |
| zvariant_utils | 4.2.0 | 확인 못 함 | 캐시에 없음 |

### Dart 패키지 (독립형 연표 앱 — Flutter) — `prototype/app/pubspec.lock`

75개. 쓰임은 pubspec.lock의 dependency 칸입니다(direct main · direct dev · transitive). sdk 패키지는 Flutter SDK와 함께 오는 것입니다. Dart 패키지에는 허락 칸이 없어 LICENSE 글의 꼴로 가렸습니다 — 허락 칸의 '·'는 그 글들에서 찾은 허락을 모두 늘어놓은 것이니(고를지 · 모두 지킬지는 가리지 않음) 자세한 것은 그 글을 보십시오.

허락 종류별: BSD-3-Clause 61 · MIT 7 · Apache-2.0 4 · MIT · Apache-2.0 · BSD-3-Clause 1 · MIT · BSD-2-Clause 1 · 여러 허락 모음 1

| 이름 | 판 | 쓰임 | 허락 | 근거 |
| --- | --- | --- | --- | --- |
| archive | 4.3.0 | transitive | MIT · BSD-2-Clause | LICENSE · LICENSE-other.md |
| args | 2.7.0 | transitive | BSD-3-Clause | LICENSE |
| async | 2.13.1 | transitive | BSD-3-Clause | LICENSE |
| boolean_selector | 2.1.2 | transitive | BSD-3-Clause | LICENSE |
| characters | 1.4.1 | transitive | BSD-3-Clause | LICENSE |
| clock | 1.1.3 | transitive | Apache-2.0 | LICENSE |
| code_assets | 1.2.1 | transitive | BSD-3-Clause | LICENSE |
| collection | 1.19.1 | transitive | BSD-3-Clause | LICENSE |
| crypto | 3.0.7 | transitive | BSD-3-Clause | LICENSE |
| cupertino_ui | 1.1.0 | transitive | BSD-3-Clause | LICENSE |
| fake_async | 1.3.3 | transitive | Apache-2.0 | LICENSE |
| ffi | 2.2.0 | direct main | BSD-3-Clause | LICENSE |
| flutter | SDK | direct main | BSD-3-Clause | Flutter SDK LICENSE |
| flutter_lints | 6.0.0 | direct dev | BSD-3-Clause | LICENSE |
| flutter_localizations | SDK | transitive | BSD-3-Clause | Flutter SDK 뿌리 LICENSE |
| flutter_test | SDK | direct dev | BSD-3-Clause | Flutter SDK 뿌리 LICENSE |
| flutter_web_plugins | SDK | transitive | BSD-3-Clause | Flutter SDK 뿌리 LICENSE |
| hooks | 2.0.2 | transitive | BSD-3-Clause | LICENSE |
| http | 1.6.0 | transitive | BSD-3-Clause | LICENSE |
| http_parser | 4.1.2 | transitive | BSD-3-Clause | LICENSE |
| image | 4.10.1 | transitive | MIT · Apache-2.0 · BSD-3-Clause | LICENSE · LICENSE-other.md |
| intl | 0.20.3 | transitive | BSD-3-Clause | LICENSE |
| jni | 1.0.3 | transitive | BSD-3-Clause | LICENSE |
| jni_flutter | 1.0.3 | transitive | BSD-3-Clause | LICENSE |
| jni_util | 1.0.0 | transitive | BSD-3-Clause | LICENSE |
| leak_tracker | 11.0.2 | transitive | BSD-3-Clause | LICENSE |
| leak_tracker_flutter_testing | 3.0.10 | transitive | BSD-3-Clause | LICENSE |
| leak_tracker_testing | 3.0.2 | transitive | BSD-3-Clause | LICENSE |
| lints | 6.1.0 | transitive | BSD-3-Clause | LICENSE |
| logging | 1.3.0 | transitive | BSD-3-Clause | LICENSE |
| matcher | 0.12.20 | transitive | BSD-3-Clause | LICENSE |
| material_color_utilities | 0.13.0 | transitive | Apache-2.0 | LICENSE |
| material_ui | 1.3.0 | transitive | BSD-3-Clause | LICENSE |
| meta | 1.18.3 | transitive | BSD-3-Clause | LICENSE |
| objective_c | 9.5.0 | transitive | BSD-3-Clause | LICENSE |
| package_config | 3.0.0 | transitive | BSD-3-Clause | LICENSE |
| path | 1.9.1 | transitive | BSD-3-Clause | LICENSE |
| path_provider | 2.1.6 | direct main | BSD-3-Clause | LICENSE |
| path_provider_android | 2.3.1 | transitive | BSD-3-Clause | LICENSE |
| path_provider_foundation | 2.6.0 | transitive | BSD-3-Clause | LICENSE |
| path_provider_linux | 2.2.2 | transitive | BSD-3-Clause | LICENSE |
| path_provider_platform_interface | 2.1.3 | transitive | BSD-3-Clause | LICENSE |
| path_provider_windows | 2.3.0 | transitive | BSD-3-Clause | LICENSE |
| pdfium_dart | 0.3.1 | transitive | MIT | LICENSE |
| pdfium_flutter | 0.3.1 | transitive | MIT | LICENSE |
| pdfrx | 2.6.5 | direct main | MIT | LICENSE |
| pdfrx_engine | 0.6.1 | transitive | MIT | LICENSE |
| platform | 3.2.0 | transitive | BSD-3-Clause | LICENSE |
| plugin_platform_interface | 2.1.8 | transitive | BSD-3-Clause | LICENSE |
| posix | 6.5.2 | transitive | MIT | LICENSE |
| pub_semver | 2.2.1 | transitive | BSD-3-Clause | LICENSE |
| record_use | 0.6.0 | transitive | BSD-3-Clause | LICENSE |
| rxdart | 0.28.0 | transitive | Apache-2.0 | LICENSE |
| sky_engine | SDK | transitive | 여러 허락 모음 | Flutter SDK license |
| source_span | 1.10.2 | transitive | BSD-3-Clause | LICENSE |
| stack_trace | 1.12.2 | transitive | BSD-3-Clause | LICENSE |
| stream_channel | 2.1.4 | transitive | BSD-3-Clause | LICENSE |
| string_scanner | 1.4.1 | transitive | BSD-3-Clause | LICENSE |
| synchronized | 3.4.2 | transitive | MIT | LICENSE |
| term_glyph | 1.2.2 | transitive | BSD-3-Clause | LICENSE |
| test_api | 0.7.12 | transitive | BSD-3-Clause | LICENSE |
| typed_data | 1.4.0 | transitive | BSD-3-Clause | LICENSE |
| url_launcher | 6.3.2 | transitive | BSD-3-Clause | LICENSE |
| url_launcher_android | 6.3.33 | transitive | BSD-3-Clause | LICENSE |
| url_launcher_ios | 6.4.2 | transitive | BSD-3-Clause | LICENSE |
| url_launcher_linux | 3.2.3 | transitive | BSD-3-Clause | LICENSE |
| url_launcher_macos | 3.2.6 | transitive | BSD-3-Clause | LICENSE |
| url_launcher_platform_interface | 2.3.2 | transitive | BSD-3-Clause | LICENSE |
| url_launcher_web | 2.4.3 | transitive | BSD-3-Clause | LICENSE |
| url_launcher_windows | 3.1.6 | transitive | BSD-3-Clause | LICENSE |
| vector_math | 2.4.0 | transitive | BSD-3-Clause | LICENSE |
| vm_service | 15.3.0 | transitive | BSD-3-Clause | LICENSE |
| web | 1.1.1 | transitive | BSD-3-Clause | LICENSE |
| xdg_directories | 1.1.0 | transitive | BSD-3-Clause | LICENSE |
| yaml | 3.1.4 | transitive | MIT | LICENSE |

### npm 꾸러미 (빌드 도구) — `package-lock.json`

12개. 모두 개발용(Tauri 명령 줄 도구)이고 앱에 실리지 않습니다.

허락 종류별: Apache-2.0 OR MIT 12

| 이름 | 판 | 쓰임 | 허락 | 근거 |
| --- | --- | --- | --- | --- |
| @tauri-apps/cli | 2.11.4 | 개발 | Apache-2.0 OR MIT | package-lock.json |
| @tauri-apps/cli-darwin-arm64 | 2.11.4 | 개발 · 고를 수 있음(운영체제별) | Apache-2.0 OR MIT | package-lock.json |
| @tauri-apps/cli-darwin-x64 | 2.11.4 | 개발 · 고를 수 있음(운영체제별) | Apache-2.0 OR MIT | package-lock.json |
| @tauri-apps/cli-linux-arm-gnueabihf | 2.11.4 | 개발 · 고를 수 있음(운영체제별) | Apache-2.0 OR MIT | package-lock.json |
| @tauri-apps/cli-linux-arm64-gnu | 2.11.4 | 개발 · 고를 수 있음(운영체제별) | Apache-2.0 OR MIT | package-lock.json |
| @tauri-apps/cli-linux-arm64-musl | 2.11.4 | 개발 · 고를 수 있음(운영체제별) | Apache-2.0 OR MIT | package-lock.json |
| @tauri-apps/cli-linux-riscv64-gnu | 2.11.4 | 개발 · 고를 수 있음(운영체제별) | Apache-2.0 OR MIT | package-lock.json |
| @tauri-apps/cli-linux-x64-gnu | 2.11.4 | 개발 · 고를 수 있음(운영체제별) | Apache-2.0 OR MIT | package-lock.json |
| @tauri-apps/cli-linux-x64-musl | 2.11.4 | 개발 · 고를 수 있음(운영체제별) | Apache-2.0 OR MIT | package-lock.json |
| @tauri-apps/cli-win32-arm64-msvc | 2.11.4 | 개발 · 고를 수 있음(운영체제별) | Apache-2.0 OR MIT | package-lock.json |
| @tauri-apps/cli-win32-ia32-msvc | 2.11.4 | 개발 · 고를 수 있음(운영체제별) | Apache-2.0 OR MIT | package-lock.json |
| @tauri-apps/cli-win32-x64-msvc | 2.11.4 | 개발 · 고를 수 있음(운영체제별) | Apache-2.0 OR MIT | package-lock.json |

<!-- third-party-list:end -->

---

## 6. 고지가 필요 없는 것

아래는 남의 것과 닮았거나 남의 것에서 왔지만, 저작권 고지가 필요 없다고 본 것입니다. 찾을 때 헷갈리지 않게 적어 둡니다.

- **V8 `Math.hypot`의 셈**(`prototype/app/lib/mock/js.dart`의 `jsHypot`) — 가장 큰 값으로 나눈 뒤 카핸 합으로 더하는 몇 줄짜리 표준 셈법을 V8과 같은 차례로 다시 쓴 것입니다. 코드를 옮기지 않았습니다.
- **mulberry32 난수**(`prototype/scripts/js-vectors.mjs`의 `rng`) — Tommy Ettinger가 공개 도메인으로 내놓은 몇 줄짜리 셈법입니다.
- **CRC-32**(`scripts/make-icons.mjs` · `scripts/fixtures/packfile-v1.js`) — 표준 다항식으로 표를 만드는 흔한 셈이며, 스스로 쓴 것입니다.
- **나무위키 문법**(`js/wiki.js`) — 문서를 쓰는 '문법'만 따랐고, 렌더러는 스스로 짰습니다. 나무위키의 글을 가져오지 않았습니다.
- **보조 달력 표** — 음력 달의 시작 날짜는 Node.js의 ICU로 셈해 앱의 자료 저장소(archive.db)에 싣는 사실 자료입니다(`prototype/app/lib/scene/aux_calendar.dart`).
- **시험 자료:** `prototype/fixtures/별여울-원문.pdf`는 ReportLab으로 만든 시험용 PDF이고, 몇 글자를 위해 맑은 고딕(Microsoft)의 부분 글꼴이 문서 안에 박혀 있습니다(문서 박기 — 글꼴 파일을 따로 나눠 주는 것이 아님). `prototype/app/test/fixtures/cleartype/chrome-*.png`는 크롬이 Pretendard로 그린 글자를 찍은 조각입니다.
- **앱 아이콘**(`icons/` · `src-tauri/icons/`) — `icons/`는 `scripts/make-icons.mjs`(`npm run icons`)가 외부 그림 없이 스스로 그린 것이고, `src-tauri/icons/`는 그 `icons/app-1024.png`에서 `tauri icon`(`npm run desktop:icons`)으로 만든 것입니다.

---

## 7. 확인할 것

이 고지는 처음에 네트워크를 쓰지 않고 이 PC의 파일만으로 만들었고, 2026-10-25에 V8 · FreeBSD 원본과 대 봤습니다(2 · 3 — 끝남). 남은 것은 원본과 더 견주어야 하는 것입니다.

1. **Lucide 판** — 옮겨 온 판을 모르므로 지금 판(lucide-react 1.51.0)의 LICENSE를 실었습니다. 저작권 해 표기는 판마다 다르지만 허락 조건은 같습니다.
2. **V8 원본 파일 — 끝남(2026-10-25)** — V8 13.6.233.10(Node 24의 V8)의 `third_party/v8/builtins/array-sort.tq` 머리는 PSF 저작권 줄이고, 그 폴더의 `LICENSE`는 CPython의 LICENSE 전문입니다. 2-1절의 PSF 글 · 저작권 줄 · V8 BSD 글을 그 원본과 바이트로 대 봤습니다(앞서 실었던 'Copyright 2018 the V8 project authors' 줄은 원본에 없어 걷었습니다).
3. **fdlibm 판 — 끝남(2026-10-25)** — FreeBSD `s_cbrt.c`와 V8 `ieee754.cc`의 `cbrt`가 같은 셈이라 어느 쪽에서 왔는지 가릴 수 없어, 2-2절에 두 머리 글을 모두 실었습니다(둘 다 원본과 바이트로 대 봄).
4. **조선굵은명조 이용 조건 원문** — `ChosunKm-LICENSE.txt`는 공식 안내의 조건을 옮겨 적은 것이라, 공식 원문을 받아 함께 두는 것이 좋습니다. 유료로 파는 물건에 이 글꼴을 싣는 것은 '배포의 대가'로 읽힐 수 있습니다.
5. **'확인 못 함' 크레이트** — 5절 Tauri 표의 '확인 못 함'은 이 PC가 받지 않은 다른 운영체제용 크레이트입니다. `src-tauri`에서 `cargo fetch`(네트워크 — 모든 운영체제의 크레이트를 받음)를 한 뒤 다시 뽑거나, `cargo about`으로 채웁니다.
