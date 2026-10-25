#!/usr/bin/env bash
# DLC 메이커 안드로이드 APK(Tauri — 메이커 웹 폴더 dist/maker를 띄우는 같은 껍데기) — 릴리즈 워크플로의 maker-android가 부릅니다.
#   1) npm ci → tauri android init(--config src-tauri/tauri.maker.conf.json — 앱 이름 HistoryTimelineMaker · 꾸러미 com.historytimeline.maker)
#      src-tauri/gen/android는 git에 담지 않으므로 지을 때마다 새로 만들고, 첫 화면(MainActivity)만 src-tauri/android/의 것으로 바꿉니다.
#   2) tauri android build --apk --target aarch64 (beforeBuildCommand의 npm run web이 dist/maker를 지음) → 서명 없는 release APK
#   3) zipalign · apksigner로 디버그 키 서명(독립형 연표 앱 APK와 같은 수준 — 키가 없으면 새로 만듦: 판마다 키가 달라
#      새 판으로 바꿀 때는 지우고 다시 설치해야 합니다 — 작업본은 먼저 .htpack으로 내보내 둠)
#   4) 서명 확인 · 든 것 확인(arm64-v8a 라이브러리 — 메이커 화면은 tauri가 그 안에 묶어 넣음)
#
# 쓰는 법: prototype/scripts/release/build-maker-android.sh <나갈 .apk>
# 필요한 것: ANDROID_HOME(또는 ANDROID_SDK_ROOT)과 그 아래 ndk/<NDK_VERSION>(기본 28.2.13676358) · build-tools, Java 17+,
#           Node.js · Rust(rustup — aarch64-linux-android는 tauri android init이 없으면 깖)
# Windows PC에서 짓는 법(이 스크립트의 같은 단계): 한글 · 빈칸이 든 경로에서는 tauri가 자산 폴더를 찾지 못하므로(AssetDirOutsideOfAppRoot)
#   git archive로 영문 경로(예: %TEMP%\htm-build)에 풀어 그곳에서 ANDROID_HOME · NDK_HOME을 두고 2) 단계까지.
set -euo pipefail

out=${1:?나갈 .apk 경로}
case "$out" in /*) ;; *) out="$PWD/$out" ;; esac
sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
[ -n "$sdk" ] || { echo "ANDROID_HOME(또는 ANDROID_SDK_ROOT)이 없습니다" >&2; exit 1; }
export ANDROID_HOME="$sdk"
export NDK_HOME="${NDK_HOME:-$sdk/ndk/${NDK_VERSION:-28.2.13676358}}"
[ -d "$NDK_HOME" ] || { echo "NDK가 없습니다: $NDK_HOME" >&2; exit 1; }
conf=src-tauri/tauri.maker.conf.json

npm ci --no-audit --no-fund
rm -rf src-tauri/gen/android
npx tauri android init --ci -c "$conf"
# 첫 화면을 우리 것으로(상태 줄 · 탐색 줄 · 키보드만큼 들임 — src-tauri/android/MainActivity.kt)
cp src-tauri/android/MainActivity.kt src-tauri/gen/android/app/src/main/java/com/historytimeline/maker/MainActivity.kt
npx tauri android build --apk --target aarch64 -c "$conf"

unsigned=$(find src-tauri/gen/android/app/build/outputs/apk -name '*release-unsigned.apk' | head -n 1)
[ -f "$unsigned" ] || { echo "서명 없는 release APK를 찾지 못했습니다" >&2; find src-tauri/gen/android/app/build/outputs -name '*.apk' >&2 || true; exit 1; }
tools="$(find "$sdk/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)"
ks="${MAKER_KEYSTORE:-$HOME/.android/debug.keystore}"
if [ ! -f "$ks" ]; then
  mkdir -p "$(dirname "$ks")"
  keytool -genkeypair -keystore "$ks" -storepass android -keypass android -alias androiddebugkey \
    -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
fi
mkdir -p "$(dirname "$out")"
work=$(mktemp -d)
"$tools/zipalign" -f -p 4 "$unsigned" "$work/aligned.apk"
"$tools/apksigner" sign --ks "$ks" --ks-pass pass:android --key-pass pass:android --out "$out" "$work/aligned.apk"
rm -rf "$work"

"$tools/apksigner" verify --print-certs "$out"
list=$(unzip -l "$out")
grep -q 'lib/arm64-v8a/libapp_lib.so' <<<"$list" || { echo "APK에 lib/arm64-v8a/libapp_lib.so가 없습니다" >&2; exit 1; }
ls -l "$out"
