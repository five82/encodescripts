#!/bin/bash

# build_ffmpeg_tumbleweed.sh
# Build FFmpeg with SVT-AV1, Opus, Dav1d, and zimg on openSUSE Tumbleweed.
# Installs into ~/.local to keep the system toolchain untouched.

# --- Configuration ---
INSTALL_PREFIX="$HOME/.local" # User-local install prefix
BUILD_DIR="/tmp/ffmpeg_build_temp" # Scratch workspace
FFMPEG_REPO="https://github.com/FFmpeg/FFmpeg.git"
FFMPEG_BRANCH="master"
SVT_AV1_REPO="https://gitlab.com/AOMediaCodec/SVT-AV1.git"
SVT_AV1_BRANCH="master"
OPUS_REPO="https://github.com/xiph/opus.git"
OPUS_BRANCH="main"
DAV1D_REPO="https://code.videolan.org/videolan/dav1d.git"
DAV1D_BRANCH="master"
ZIMG_REPO="https://github.com/sekrit-twc/zimg.git"
ZIMG_BRANCH="master"

# --- Helper Functions ---
_log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        _log "Error: Required command '$1' not found. Please install it."
        exit 1
    fi
}

# --- Clean Previous Build Directory ---
if [ -d "$BUILD_DIR" ]; then
    _log "Removing previous build directory: $BUILD_DIR"
    rm -rf "$BUILD_DIR"
fi

# --- Strict Mode & Error Handling ---
set -euo pipefail
trap 'echo "Error on line $LINENO"; exit 1' ERR

# --- OS Detection & Setup ---
OS_NAME=$(uname -s)

_log "Detected OS: $OS_NAME"

if [[ "$OS_NAME" != "Linux" ]]; then
    _log "Error: Unsupported operating system '$OS_NAME'."
    exit 1
fi

if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
else
    _log "Error: /etc/os-release not found. Cannot determine distribution."
    exit 1
fi

if [[ "${ID:-}" == "opensuse-tumbleweed" || " ${ID_LIKE:-} " == *" suse "* ]]; then
    _log "openSUSE flavor detected (${PRETTY_NAME:-unknown})."
    CPU_COUNT=$(nproc)

    REQUIRED_PKGS=(
        patterns-devel-base-devel_basis
        gcc
        gcc-c++
        make
        cmake
        nasm
        yasm
        git
        wget
        autoconf
        automake
        libtool
        clang
        libva-devel
        meson
        ninja
    )

    _log "Checking/installing required packages via zypper..."
    PACKAGES_TO_INSTALL=()
    for pkg in "${REQUIRED_PKGS[@]}"; do
        if rpm -q "$pkg" &> /dev/null; then
            _log "$pkg is already installed."
        else
            _log "$pkg is NOT installed."
            PACKAGES_TO_INSTALL+=("$pkg")
        fi
    done

    if [ ${#PACKAGES_TO_INSTALL[@]} -gt 0 ]; then
        _log "The following required packages are missing: ${PACKAGES_TO_INSTALL[*]}"
        if command -v sudo &> /dev/null; then
            _log "Attempting to install missing packages using: sudo zypper --non-interactive install --no-recommends ${PACKAGES_TO_INSTALL[*]}"
            if sudo zypper --non-interactive install --no-recommends "${PACKAGES_TO_INSTALL[@]}"; then
                _log "Successfully installed missing packages via zypper."
            else
                _log "Error: Failed to install required packages using zypper. Please install them manually."
                exit 1
            fi
        else
            _log "Error: sudo command not found. Please install the following packages manually using zypper: ${PACKAGES_TO_INSTALL[*]}"
            exit 1
        fi
    fi
    _log "Required package check complete."

    check_command pkg-config
else
    _log "Error: This script is intended for openSUSE Tumbleweed. Detected ID='${ID:-unknown}', ID_LIKE='${ID_LIKE:-unknown}'."
    exit 1
fi

_log "Using CPU cores: $CPU_COUNT"

# --- Environment Configuration ---
_log "Using standard build environment for $INSTALL_PREFIX installation."

# --- Prepare Directories ---
_log "Creating directories..."
mkdir -p "$BUILD_DIR"
mkdir -p "$INSTALL_PREFIX"
rm -rf "$BUILD_DIR/ffmpeg"
rm -rf "$BUILD_DIR/SVT-AV1"
rm -rf "$BUILD_DIR/opus"
rm -rf "$BUILD_DIR/dav1d"
rm -rf "$BUILD_DIR/zimg"

# --- Build SVT-AV1 from Source ---
_log "Cloning SVT-AV1 source (branch: $SVT_AV1_BRANCH)..."
cd "$BUILD_DIR"
git clone --depth 1 --branch "$SVT_AV1_BRANCH" "$SVT_AV1_REPO" SVT-AV1
cd SVT-AV1

_log "Configuring SVT-AV1..."
mkdir -p Build
cd Build
_log "Using system clang/clang++"
CLANG_PATH=$(command -v clang)
CLANGPP_PATH=$(command -v clang++)
if [[ ! -x "$CLANG_PATH" || ! -x "$CLANGPP_PATH" ]]; then
    _log "Error: clang or clang++ not found in PATH. Ensure the 'clang' package is installed correctly."
    exit 1
fi

cmake .. \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
    -DCMAKE_C_COMPILER="$CLANG_PATH" \
    -DCMAKE_CXX_COMPILER="$CLANGPP_PATH" \
    -DBUILD_SHARED_LIBS=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_APPS=OFF \
    -DSVT_AV1_LTO=ON \
    -DNATIVE=ON \
    -DCMAKE_C_FLAGS="-O3" \
    -DCMAKE_CXX_FLAGS="-O3"

_log "Building SVT-AV1 (using $CPU_COUNT cores)..."
make -j"$CPU_COUNT"
_log "Installing SVT-AV1..."
make install
_log "SVT-AV1 installation complete."

# --- Build opus from Source ---
_log "Cloning opus source (branch: $OPUS_BRANCH)..."
cd "$BUILD_DIR"
git clone --depth 1 --branch "$OPUS_BRANCH" "$OPUS_REPO" opus
cd opus

_log "Configuring opus..."
./autogen.sh
./configure \
    --prefix="$INSTALL_PREFIX" \
    --disable-static \
    --enable-shared \
    --disable-doc \
    --disable-extra-programs

_log "Building opus (using $CPU_COUNT cores)..."
make -j"$CPU_COUNT"
_log "Installing opus..."
make install
_log "opus installation complete."

# --- Build dav1d from Source ---
_log "Cloning dav1d source (branch: $DAV1D_BRANCH)..."
cd "$BUILD_DIR"
git clone --depth 1 --branch "$DAV1D_BRANCH" "$DAV1D_REPO" dav1d
cd dav1d

_log "Configuring dav1d..."
mkdir -p build
cd build
meson setup .. \
    --prefix="$INSTALL_PREFIX" \
    --buildtype=release \
    --default-library=shared \
    -Denable_tools=false \
    -Denable_tests=false

_log "Building dav1d (using $CPU_COUNT cores)..."
ninja -j"$CPU_COUNT"
_log "Installing dav1d..."
ninja install
_log "dav1d installation complete."

# --- Build zimg from Source ---
_log "Cloning zimg source (branch: $ZIMG_BRANCH)..."
cd "$BUILD_DIR"
git clone --depth 1 --branch "$ZIMG_BRANCH" "$ZIMG_REPO" zimg
cd zimg

_log "Initializing zimg submodules..."
git submodule update --init --recursive

_log "Configuring zimg..."
./autogen.sh
./configure \
    --prefix="$INSTALL_PREFIX" \
    --disable-static \
    --enable-shared

_log "Building zimg (using $CPU_COUNT cores)..."
make -j"$CPU_COUNT"
_log "Installing zimg..."
make install
_log "zimg installation complete."

# --- Download FFmpeg ---
_log "Downloading FFmpeg source (branch: $FFMPEG_BRANCH)..."
cd "$BUILD_DIR"
git clone --depth 1 --branch "$FFMPEG_BRANCH" "$FFMPEG_REPO" ffmpeg
cd ffmpeg

SYSTEM_PKGCONFIG_PATH="/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig"
export PKG_CONFIG_PATH="${INSTALL_PREFIX}/lib/pkgconfig:${INSTALL_PREFIX}/lib64/pkgconfig:${SYSTEM_PKGCONFIG_PATH}:${PKG_CONFIG_PATH:-}"
_log "PKG_CONFIG_PATH set to: $PKG_CONFIG_PATH"
if command -v /usr/bin/pkg-config &> /dev/null; then
    export PKG_CONFIG=/usr/bin/pkg-config
    _log "Explicitly using PKG_CONFIG=$PKG_CONFIG"
else
    _log "Warning: /usr/bin/pkg-config not found, relying on default pkg-config in PATH."
fi

# --- Add VAAPI support if available ---
FFMPEG_EXTRA_FLAGS=""
EXTRA_LDFLAGS_VAL=""
_log "Checking for VAAPI support..."
if command -v pkg-config &> /dev/null && pkg-config --exists libva; then
    _log "System VAAPI found via pkg-config. Enabling VAAPI support."
    FFMPEG_EXTRA_FLAGS="--enable-vaapi"
else
    _log "Warning: System VAAPI not found via pkg-config. Skipping --enable-vaapi."
    _log "         Ensure 'libva-devel' (or equivalent) is installed via zypper."
fi

EXTRA_LDFLAGS_VAL="-Wl,-rpath,${INSTALL_PREFIX}/lib:${INSTALL_PREFIX}/lib64"

CONFIGURE_ARGS=(
    --prefix="$INSTALL_PREFIX"
    --disable-static
    --enable-shared
    --enable-gpl
    --enable-libsvtav1
    --enable-libopus
    --enable-libdav1d
    --enable-libzimg
    --disable-xlib
    --disable-libxcb
    --disable-vdpau
    --disable-libdrm
)

CONFIGURE_ARGS+=(--extra-ldflags="$EXTRA_LDFLAGS_VAL")
if [[ -n "$FFMPEG_EXTRA_FLAGS" ]]; then
    read -ra flags <<< "$FFMPEG_EXTRA_FLAGS"
    CONFIGURE_ARGS+=("${flags[@]}")
fi

_log "Executing configure with arguments:"
printf "  %s\n" "${CONFIGURE_ARGS[@]}"
./configure "${CONFIGURE_ARGS[@]}"

_log "FFmpeg configuration complete."

_log "Building FFmpeg (using $CPU_COUNT cores)..."
make -j"$CPU_COUNT"
_log "Build complete. Installing FFmpeg..."
make install
_log "Installation complete."

_log "Cleaning up build directory..."
_log "Build directory $BUILD_DIR kept for inspection. Remove manually if desired."

_log "--------------------------------------------------"
_log "FFmpeg build successful!"
_log "ffmpeg and ffprobe are located at: $INSTALL_PREFIX/bin/"
_log "--------------------------------------------------"

exit 0
