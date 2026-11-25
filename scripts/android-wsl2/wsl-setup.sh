#!/usr/bin/env bash
# Provisiona Ubuntu 22.04 (WSL2 / Linux x86_64) para compilar Krita Android (SDK 36 + NDK 27.3.13750724 + CMake 3.31)
set -euo pipefail

KRITA_SOURCE_INPUT="${1:-/mnt/c/Users/Usuario/Documents/KRITAAPP/krita}"
WORK_ROOT="${KRITA_ANDROID_ROOT:-$HOME/krita-android}"

echo "=== [1/4] Instalando pacotes de build, CMake 3.31 e qmlimportscanner host ==="
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  ca-certificates build-essential ninja-build ccache pkg-config \
  git curl wget unzip zip rsync file patch perl gperf bison flex gettext \
  python3 python3-venv python3-pip python3-dev \
  openjdk-17-jdk-headless qtdeclarative5-dev-tools \
  libgl1 libglib2.0-0 libdbus-1-3 libfontconfig1 libxkbcommon0 \
  libicu70 libpcre2-16-0 libdouble-conversion3 libzstd1 zlib1g

sudo pip3 install --upgrade "cmake>=3.30,<4.0"

mkdir -p "$WORK_ROOT/sdk" "$WORK_ROOT/wd-x86_64" "$WORK_ROOT/wd-arm64-v8a"
export ANDROID_HOME="$WORK_ROOT/sdk"
export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"

echo "=== [2/4] Instalando Android SDK 36, Build-Tools 36.0.0 e NDK 27.3.13750724 ==="
if [ ! -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]; then
  curl -fsSL https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -o /tmp/cmdtools.zip
  mkdir -p "$ANDROID_HOME/cmdline-tools"
  rm -rf "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
  unzip -q /tmp/cmdtools.zip -d "$ANDROID_HOME/cmdline-tools"
  mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
  rm -f /tmp/cmdtools.zip
fi

yes | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --licenses >/dev/null || true
"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" \
  "platform-tools" \
  "platforms;android-36" \
  "build-tools;36.0.0" \
  "ndk;27.3.13750724"

echo "=== [3/4] Sincronizando código-fonte do Krita para ext4 ==="
rsync -a --delete --exclude='krita-deps-management' --exclude='venv' \
  "$KRITA_SOURCE_INPUT/" "$WORK_ROOT/krita-src/"

find "$WORK_ROOT/krita-src/packaging/android" -type f \( -name 'gradlew' -o -name '*.sh' -o -name '*.properties*' -o -name '*.gradle' \) -exec sed -i 's/\r$//' {} +
chmod +x "$WORK_ROOT/krita-src/packaging/android/apk/gradlew"

echo "=== [4/4] Configurando krita-deps-management ==="
cd "$WORK_ROOT/krita-src"
git config --global --add safe.directory "$WORK_ROOT/krita-src"

if [ ! -d "$WORK_ROOT/krita-src/.git" ]; then
  git init -q
  git add -A
  git -c user.name="local" -c user.email="local@localhost" commit -qm "baseline"
fi

if [ ! -d krita-deps-management ]; then
  git clone --depth=1 https://invent.kde.org/packaging/krita-deps-management.git
fi
if [ ! -d krita-deps-management/ci-utilities ]; then
  git clone --depth=1 https://invent.kde.org/packaging/krita-ci-utilities.git krita-deps-management/ci-utilities
fi

python3 -m venv venv --upgrade-deps
./venv/bin/pip install --quiet -r krita-deps-management/requirements.txt

./venv/bin/python3 -u krita-deps-management/tools/replace-branch-in-seed-file.py \
  krita-deps-management/latest/krita-deps.yml -p -o branch-corrected-deps.yml -d master
./venv/bin/python3 -u krita-deps-management/tools/generate-deps-file.py \
  -s branch-corrected-deps.yml -o .kde-ci.yml

echo "=== Ambiente Android WSL2 pronto em $WORK_ROOT ==="
