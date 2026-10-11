#!/usr/bin/env bash
# Experimental base-game build for Apple Silicon tvOS Simulator only.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
automation=OFF
case "${1:-}" in
    --automation) automation=ON ;;
    '') ;;
    *) printf 'Usage: %s [--automation]\n' "$0" >&2; exit 2 ;;
esac
[[ $(uname -m) == arm64 ]] || { echo 'Apple Silicon Mac required' >&2; exit 1; }
for file in Assets/main.dol Assets/StaticR.rel generated/build_shards/shards.cmake Assets/DATA/sys/boot.bin; do
    [[ -f "$file" ]] || { echo "Missing $file; prepare the verified PAL base-game translation first" >&2; exit 1; }
done
[[ $(shasum -a 256 Assets/main.dol | awk '{print $1}') == 80d18895b39c63bd80f457398bfcbb91b7d16ac116a41a88967e954080155b05 ]]
[[ $(shasum -a 256 Assets/StaticR.rel | awk '{print $1}') == 16d9d146112541fefea701ecb5bc1a496f9d50e4a752fbb5b6778e7c6399f67d ]]
cmake_bin=${MKW_CMAKE:-/opt/homebrew/bin/cmake}
python_bin=${MKW_PYTHON:-/opt/homebrew/bin/python3.14}
[[ -x "$python_bin" ]] || python_bin=$(command -v python3)
args=(-S runtime -B build-tvos-simulator -G Ninja
    -DCMAKE_SYSTEM_NAME=tvOS -DCMAKE_OSX_SYSROOT=appletvsimulator
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=27.0
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_IGNORE_PREFIX_PATH='/opt/homebrew;/usr/local'
    -DCMAKE_CXX_FLAGS=-std=c++20 -DCMAKE_OBJCXX_FLAGS=-std=c++20
    -DMKW_BUILD_PRODUCTS=ON -DMKW_TRANSLATED_COMPILE_JOBS=8
    "-DMKW_SIMULATOR_AUTOMATION=$automation"
    -DAURORA_DAWN_PROVIDER=vendor -DAURORA_DAWN_LINKAGE=static
    -DAURORA_SDL3_PROVIDER=vendor -DAURORA_SDL3_LINKAGE=static
    -DBUILD_SHARED_LIBS=OFF -DSDL_VULKAN=OFF
    -DDAWN_BUILD_PROTOBUF=OFF -DTINT_BUILD_GLSL_VALIDATOR=OFF
    "-DPython3_EXECUTABLE=$python_bin")
# Reuse sources already fetched locally; never reuse macOS object files.
local_dawn="$root/tools/tvos-deps/dawn-13abc3bc8ea2d3c2050f9e77a12d012108ceee24"
[[ ! -f "$local_dawn/CMakeLists.txt" ]] || args+=("-DFETCHCONTENT_SOURCE_DIR_DAWN=$local_dawn")
"$cmake_bin" "${args[@]}"
"$cmake_bin" --build build-tvos-simulator --target WiiCompiled --parallel "${MKW_BUILD_JOBS:-12}"
app="$root/build-tvos-simulator/WiiCompiled.app"
[[ -f "$app/DATA/sys/boot.bin" ]] || ditto Assets/DATA "$app/DATA"
"$root/Launcher/apply-local-branding.command" tvos-simulator "$app"
codesign --force --sign - "$app"
printf 'Simulator app: %s\n' "$app"
