#!/usr/bin/env bash
# Android APK of the standalone timeline app on Linux (release workflow, job native-android) - the same steps as
# prototype/scripts/build-android.ps1 (the Windows PC script), for arm64 only:
#   1) the Rust engine as libarchive_engine.so for aarch64-linux-android with the NDK's clang,
#   2) a copy of the Flutter app (lib, android, pubspec) in a scratch folder - the bundled store goes into the COPY only,
#      so the source tree and the Windows build never carry it,
#   3) libarchive_engine.so -> <copy>/android/app/src/main/jniLibs/arm64-v8a, the store -> <copy>/assets/seed/archive.db
#      with seed.json (stamp = size + SHA-256, the app re-places the store when it changes - lib/archive_app.dart _placeSeed)
#      and manifest.json,
#   4) flutter build apk --release --target-platform android-arm64 (signing: android/app/build.gradle.kts as it is - debug key),
#   5) checks the APK: native-code arm64-v8a (aapt2), the engine .so and the seed inside.
#
# Usage: prototype/scripts/release/build-android.sh <store archive.db> <output .apk> [copy folder]
#        prototype/scripts/release/build-android.sh --prepare-only <store archive.db> <copy folder>   (steps 2-3 without the engine .so - for checking the copy)
# Needs: ANDROID_HOME (or ANDROID_SDK_ROOT) with ndk/<NDK_VERSION> (default 28.2.13676358, the ndkVersion in build.gradle.kts;
#        ANDROID_NDK_HOME only when that folder is missing),
#        rustup target aarch64-linux-android, flutter on PATH (or FLUTTER=<path>), Java 17+.
set -euo pipefail

prepare_only=0
if [ "${1:-}" = "--prepare-only" ]; then prepare_only=1; shift; fi
db=${1:?store archive.db}
if [ "$prepare_only" = 1 ]; then
  apk=''
  copy=${2:?copy folder}
else
  apk=${2:?output .apk}
  copy=${3:-}
fi
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
proto=$(cd "$here/../.." && pwd)
app="$proto/app"
flutter=${FLUTTER:-flutter}
[ -f "$db" ] || { echo "store not found: $db" >&2; exit 1; }
db=$(cd "$(dirname "$db")" && pwd)/$(basename "$db")
if [ -n "$apk" ]; then  # absolute, because step 4 runs inside the copy
  mkdir -p "$(dirname "$apk")"
  apk=$(cd "$(dirname "$apk")" && pwd)/$(basename "$apk")
fi
[ -n "$copy" ] || copy=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/ht-android-XXXXXX")
mkdir -p "$copy"
copy=$(cd "$copy" && pwd)

so=''
if [ "$prepare_only" = 0 ]; then
  sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:?ANDROID_HOME is not set}}
  # The NDK named in build.gradle.kts (ndkVersion) first - runner images also set ANDROID_NDK_HOME to some other NDK.
  ndk="$sdk/ndk/${NDK_VERSION:-28.2.13676358}"
  [ -d "$ndk" ] || ndk=${ANDROID_NDK_HOME:-$ndk}
  bin="$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin"
  [ -x "$bin/aarch64-linux-android24-clang" ] || { echo "NDK clang not found under $bin" >&2; exit 1; }
  # 1) engine (.so) - cc (rusqlite's bundled SQLite) and the linker both use the NDK's clang for API 24.
  export CC_aarch64_linux_android="$bin/aarch64-linux-android24-clang"
  export AR_aarch64_linux_android="$bin/llvm-ar"
  export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$bin/aarch64-linux-android24-clang"
  cargo build --locked --manifest-path "$proto/engine/Cargo.toml" --release --lib --target aarch64-linux-android
  so="$proto/engine/target/aarch64-linux-android/release/libarchive_engine.so"
  [ -f "$so" ] || { echo "engine build did not produce $so" >&2; exit 1; }
fi

# 2) the copy (lib and assets mirrored; android without build caches and local.properties).
rm -rf "${copy:?}/lib" "${copy:?}/assets"
cp -a "$app/lib" "$copy/lib"
mkdir -p "$copy/assets" "$copy/android"
# Shared assets travel with pubspec; the requested seed is generated below, never copied from the app.
(cd "$app/assets" && tar --exclude=./seed -cf - .) | (cd "$copy/assets" && tar -xf -)
(cd "$app/android" && tar --exclude=./build --exclude=./.gradle --exclude=./app/build --exclude=./local.properties -cf - .) | (cd "$copy/android" && tar -xf -)
for f in pubspec.yaml pubspec.lock analysis_options.yaml; do cp "$app/$f" "$copy/$f"; done

# 3) engine and seed inside the copy only.
if [ -n "$so" ]; then
  mkdir -p "$copy/android/app/src/main/jniLibs/arm64-v8a"
  cp "$so" "$copy/android/app/src/main/jniLibs/arm64-v8a/libarchive_engine.so"
fi
seed="$copy/assets/seed"
mkdir -p "$seed/originals"
cp "$db" "$seed/archive.db"
stamp="$(stat -c %s "$db")-$(sha256sum "$db" | cut -c1-16)"
printf '{"database":"archive.db","stamp":"%s"}' "$stamp" > "$seed/seed.json"
[ -f "$seed/manifest.json" ] || printf '[]' > "$seed/manifest.json"
echo "copy: $copy  seed: $stamp"
if [ "$prepare_only" = 1 ]; then exit 0; fi

# 4) APK.
cd "$copy"
"$flutter" pub get
"$flutter" build apk --release --target-platform android-arm64
built="$copy/build/app/outputs/flutter-apk/app-release.apk"
[ -f "$built" ] || { echo "flutter did not produce $built" >&2; exit 1; }
cp "$built" "$apk"

# 5) checks.
tools=$(find "$sdk/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)
# Whole outputs into variables first: with pipefail, 'aapt2 | grep -q' can fail when grep stops reading early.
badging=$("$tools/aapt2" dump badging "$apk")
grep -q "^native-code: 'arm64-v8a'" <<<"$badging" || { echo "APK native-code is not arm64-v8a: $(grep native-code <<<"$badging" || true)" >&2; exit 1; }
listing=$(unzip -l "$apk")
for entry in \
  lib/arm64-v8a/libarchive_engine.so \
  assets/flutter_assets/assets/seed/archive.db \
  assets/flutter_assets/assets/seed/seed.json \
  assets/flutter_assets/assets/seed/manifest.json \
  assets/flutter_assets/assets/fonts/Pretendard-Regular.otf \
  assets/flutter_assets/assets/fonts/Pretendard-SemiBold.otf \
  assets/flutter_assets/assets/fonts/Pretendard-Bold.otf \
  assets/flutter_assets/assets/fonts/ChosunKm.ttf \
  assets/flutter_assets/assets/fonts/Pretendard-OFL.txt \
  assets/flutter_assets/assets/fonts/ChosunKm-LICENSE.txt; do
  grep -q " $entry\$" <<<"$listing" || { echo "missing in APK: $entry" >&2; exit 1; }
done
sed -n '1,3p' <<<"$badging"
echo "APK: $apk ($(stat -c %s "$apk") bytes) seed=$stamp"
