#!/usr/bin/env bash
# Compila o Krita para Android (x86_64 por padrão, ou passe arm64-v8a como 1º argumento) e empacota o APK debug
set -euo pipefail

ABI="${1:-x86_64}"
WORK_ROOT="${KRITA_ANDROID_ROOT:-$HOME/krita-android}"
APK_OUT_DIR="${2:-/mnt/c/Users/Usuario/Documents/KRITAAPP/apks}"

cd "$WORK_ROOT/krita-src"

export KDECI_ANDROID_ABI="$ABI"
export ANDROID_HOME="$WORK_ROOT/sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export KDECI_ANDROID_SDK_ROOT="$ANDROID_HOME"
export KDECI_ANDROID_NDK_ROOT="$ANDROID_HOME/ndk/27.3.13750724"
export ANDROID_NDK_ROOT="$KDECI_ANDROID_NDK_ROOT"
export ANDROID_NDK="$KDECI_ANDROID_NDK_ROOT"
export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
export PATH="/usr/local/bin:$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"

export KDECI_WORKDIR_PATH="$WORK_ROOT/wd-$ABI"
export KDECI_CC_CACHE="$WORK_ROOT/ccache/$ABI"
export KDECI_CACHE_PATH="$WORK_ROOT/artifacts/$ABI"
export EXTERNALS_DOWNLOAD_DIR="$WORK_ROOT/downloads"

export KDECI_GITLAB_SERVER="https://invent.kde.org/"
export KDECI_PACKAGE_PROJECT="teams/ci-artifacts/krita-android-$ABI"
export KDECI_REPO_METADATA_PATH="$PWD/krita-deps-management/repo-metadata"
export KDECI_BUILD_TYPE="Release"
export KDECI_COMPRESS_PACKAGES_ON_DOWNLOAD="False"
export KDECI_SKIP_ECM_ANDROID_TOOLCHAIN="True"
export CI_COMMIT_REF_PROTECTED="true"
export CI_PROJECT_NAME="krita"
export CI_COMMIT_REF_NAME="master"

export CMAKE_TOOLCHAIN_FILE="$PWD/krita-deps-management/tools/android-toolchain-krita.cmake"
export KDECI_EXTRA_CMAKE_ARGS="-DHIDE_SAFE_ASSERTS=OFF -DBUILD_TESTING=OFF -DANDROID_ENABLE_STDIO_FORWARDING=ON"
export KRITACI_ANDROID_PACKAGE_TYPE="debug"
export KRITACI_ARCHIVE_ARTIFACTS="False"
export KRITACI_SKIP_COMMON_ARTIFACTS="False"

mkdir -p "$KDECI_WORKDIR_PATH" "$KDECI_CC_CACHE" "$KDECI_CACHE_PATH" "$EXTERNALS_DOWNLOAD_DIR"

echo "=== [1/3] Compilando Krita ($ABI) via run-ci-build.py ==="
./venv/bin/python3 -u krita-deps-management/ci-utilities/run-ci-build.py \
  --project krita \
  --branch master \
  --platform "Android/$KDECI_ANDROID_ABI/Qt5/Shared" \
  --only-build \
  --skip-publishing 2>&1 | tee "$WORK_ROOT/build-krita-$ABI.log"

# Substitui o qmlimportscanner host de ext_qt pelo nativo do Ubuntu 22.04 (evita SIGSEGV no WSL2)
if [ -x /usr/lib/qt5/bin/qmlimportscanner ]; then
  cp -f /usr/lib/qt5/bin/qmlimportscanner "$KDECI_WORKDIR_PATH/krita/_install/bin/qmlimportscanner"
fi

echo "=== [2/3] Empacotando APK Debug ($ABI) ==="
./venv/bin/python3 -u build-tools/ci-scripts/build-android-package.py 2>&1 | tee "$WORK_ROOT/build-apk-$ABI.log"

echo "=== [3/3] Exportando APK para $APK_OUT_DIR ==="
mkdir -p "$APK_OUT_DIR"
cp -vf "$KDECI_WORKDIR_PATH"/krita/_packaging/*.apk "$APK_OUT_DIR/"
ls -lh "$APK_OUT_DIR/"
