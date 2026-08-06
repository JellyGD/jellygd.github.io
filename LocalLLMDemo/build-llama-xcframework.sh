#!/usr/bin/env bash
#
# 把 llama.cpp 编译成 llama.xcframework
#   - 真机 arm64 + 模拟器 arm64/x86_64
#   - 开 LLAMA_METAL=ON（不开就全跑 CPU，又慢又烫）
#   - 关闭测试/示例，减小体积
#
# 用法：./build-llama-xcframework.sh /path/to/llama.cpp
#
set -euo pipefail

LLAMA_DIR="${1:-llama.cpp}"
OUT="$(pwd)/llama.xcframework"

if [ ! -d "$LLAMA_DIR" ]; then
  echo "❌ 找不到 llama.cpp，先 clone："
  echo "   git clone https://github.com/ggml-org/llama.cpp.git"
  exit 1
fi

build_slice() {
  local sdk="$1" arch="$2" dest="$3"
  echo "► 编译 $dest ($arch)…"
  cmake -S "$LLAMA_DIR" -B "build-$dest" \
    -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_ARCHITECTURES="$arch" \
    -DCMAKE_OSX_SYSROOT="$sdk" \
    -DLLAMA_METAL=ON \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_EXAMPLES=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_BUILD_TYPE=Release

  xcodebuild archive \
    -scheme llama \
    -configuration Release \
    -destination "generic/platform=$dest" \
    -archivePath "arch-$dest" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES
}

build_slice iphoneos         arm64          "iOS"
build_slice iphonesimulator  "arm64;x86_64" "iOS Simulator"

rm -rf "$OUT"
xcodebuild -create-xcframework \
  -framework "arch-iOS.xcarchive/Products/Library/Frameworks/llama.framework" \
  -framework "arch-iOS Simulator.xcarchive/Products/Library/Frameworks/llama.framework" \
  -output "$OUT"

echo "✅ 生成完毕：$OUT"
echo "   把 llama.xcframework 拖进 Xcode → Embed & Sign，并在 Bridging Header 里 #import <llama/llama.h>"
