#!/usr/bin/env bash
# Android build of P5R on macOS/Linux: the same steps as build_android.cmd -Nce -Release (android/build_apk.ps1).
# cmake (NDK) -> libp5r.so + libp5rimport.so, with libspirvharness.so (games/p5r/tools/build_harness_android.sh)
# -> aapt2 -> javac + d8 (games/p5r/java) -> zipalign -> apksigner (your debug key). APK: private/p5r/apk_nce/p5r.apk
#
# Usage: games/p5r/tools/build_android.sh [--install] [--serial <adb serial>] [--dev]
#   --install   adb install -r the APK when it is built (--serial picks the device when more than one is attached)
#   --dev       without NX_RELEASE (keeps nx.log and the file-triggered diagnostics); the default is the release build
#
# The launcher icon: private/p5r/icon/res when it exists (your own, e.g. from games/p5r/tools/make_nova_icon.py; never
# committed), else the project's games/p5r/icon/res.
# Needs the Android SDK (ANDROID_HOME, default ~/Library/Android/sdk) with NDK 28.2.13676358, build-tools 35.0.0 and
# platform 35; a JDK (javac); cmake and ninja (private/venv/bin, else on PATH); the Vulkan headers
# (private/third_party/Vulkan-Headers-1.4.357, else VULKAN_SDK, else Homebrew's vulkan-headers).
set -euo pipefail
root="$(cd "$(dirname "$0")/../../.." && pwd)"
game=p5r
install=0
serial=""
release=ON
while [ $# -gt 0 ]; do
    case "$1" in
        --install) install=1; shift ;;
        --serial) serial="$2"; shift 2 ;;
        --dev) release=OFF; shift ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

sdk="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
ndk="$sdk/ndk/28.2.13676358"
bt="$sdk/build-tools/35.0.0"
jar="$sdk/platforms/android-35/android.jar"
llvm="$ndk/toolchains/llvm/prebuilt/$(uname -s | tr '[:upper:]' '[:lower:]')-x86_64/bin"
priv="$root/private/$game"
out="$priv/apk_nce"
build="$priv/ba_nce"
harness="$root/private/build/spirv_harness_android/libspirvharness.so"

[ -d "$root/private/venv/bin" ] && export PATH="$root/private/venv/bin:$PATH"
if [ -d "$root/private/third_party/Vulkan-Headers-1.4.357" ]; then
    export VULKAN_SDK="$root/private/third_party/Vulkan-Headers-1.4.357"
else
    export VULKAN_SDK="${VULKAN_SDK:-$(brew --prefix vulkan-headers 2>/dev/null || true)}"
fi
for f in "$ndk" "$bt" "$jar"; do
    [ -e "$f" ] || { echo "missing $f (Android SDK: NDK 28.2.13676358, build-tools 35.0.0, platform 35)" >&2; exit 1; }
done
if [ ! -f "$harness" ]; then
    echo "missing $harness. Build it once, with Docker running, from the repository root:" >&2
    echo "  docker run --rm -v \"\$PWD:/src\" -w /src mcr.microsoft.com/dotnet/sdk:10.0 sh games/p5r/tools/build_harness_android.sh" >&2
    exit 1
fi

# native libraries
if [ ! -f "$build/build.ninja" ]; then
    cmake -S "$root" -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE="$ndk/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-29 -DANDROID_STL=c++_static \
        -DNX_GAME=$game -DNX_NCE=ON
fi
cmake -B "$build" -DNX_RELEASE=$release >/dev/null
cmake --build "$build" --target $game p5rimport

rm -rf "$out"
mkdir -p "$out/lib/arm64-v8a" "$out/classes" "$out/dex"
for lib in "$build/lib$game.so" "$build/libp5rimport.so" "$harness"; do
    "$llvm/llvm-strip" --strip-unneeded -o "$out/lib/arm64-v8a/$(basename "$lib")" "$lib"
done

# resources, the icon and the manifest
icon="$root/games/$game/icon/res"
[ -d "$priv/icon/res" ] && icon="$priv/icon/res"
echo "icon: $icon"
"$bt/aapt2" compile --dir "$root/android/res" -o "$out/res.zip"
"$bt/aapt2" compile --dir "$icon" -o "$out/icon.zip"
sed 's/<application/<application android:icon="@mipmap\/ic_launcher"/' "$root/games/$game/AndroidManifest.xml" \
    > "$out/AndroidManifest.xml"
"$bt/aapt2" link -o "$out/base.apk" -I "$jar" --manifest "$out/AndroidManifest.xml" "$out/res.zip" "$out/icon.zip"
(cd "$out" && zip -q -r -9 base.apk lib)

# the launcher (Java)
find "$root/games/$game/java" -name '*.java' > "$out/sources.txt"
javac -nowarn -encoding UTF-8 --release 11 -Xlint:-options -cp "$jar" -d "$out/classes" @"$out/sources.txt"
find "$out/classes" -name '*.class' > "$out/classes.txt"
"$bt/d8" --release --min-api 30 --lib "$jar" --output "$out/dex" @"$out/classes.txt"
(cd "$out/dex" && zip -q -9 ../base.apk classes.dex)

# align and sign
"$bt/zipalign" -f -p 4 "$out/base.apk" "$out/aligned.apk"
"$bt/apksigner" sign --ks "$HOME/.android/debug.keystore" --ks-pass pass:android --key-pass pass:android \
    --out "$out/$game.apk" "$out/aligned.apk"
"$bt/apksigner" verify "$out/$game.apk"
echo "APK: $out/$game.apk ($(du -h "$out/$game.apk" | cut -f1))"

if [ "$install" = 1 ]; then
    if [ -n "$serial" ]; then "$sdk/platform-tools/adb" -s "$serial" install -r "$out/$game.apk"
    else "$sdk/platform-tools/adb" install -r "$out/$game.apk"; fi
fi
