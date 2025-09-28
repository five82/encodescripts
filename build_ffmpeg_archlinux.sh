#!/bin/bash

# build_ffmpeg_archlinux.sh
# Builds FFmpeg binaries on Arch Linux
# Includes: libsvtav1, libopus, libdav1d, libzimg

# --- Configuration ---
INSTALL_PREFIX="$HOME/.local" # Install into user's local directory
BUILD_DIR="/tmp/ffmpeg_build_temp"
FFMPEG_REPO="https://github.com/FFmpeg/FFmpeg.git"
FFMPEG_BRANCH="master"
SVT_AV1_REPO="https://gitlab.com/AOMediaCodec/SVT-AV1.git" # svt-av1
#SVT_AV1_REPO="https://github.com/BlueSwordM/svt-av1-psyex.git" # svt-av1-psyex
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
# if [ -d "$INSTALL_PREFIX" ]; then # DO NOT remove /usr/local
#     _log "Removing previous install directory: $INSTALL_PREFIX"
#     # rm -rf "$INSTALL_PREFIX" # DO NOT remove /usr/local
# fi

# --- Strict Mode & Error Handling ---
set -euo pipefail
trap 'echo "Error on line $LINENO"; exit 1' ERR

# --- OS Detection & Setup ---
OS_NAME=$(uname -s)

_log "Detected OS: $OS_NAME"

if [[ "$OS_NAME" == "Linux" ]]; then
    if [[ -f /etc/arch-release || -d /etc/pacman.d ]]; then
        _log "Arch Linux detected."
        CPU_COUNT=$(nproc)

        # --- Install Dependencies via pacman ---
        _log "Checking/installing required Arch packages via pacman..."
        REQUIRED_PKGS=(
            base-devel # Common build tools (make, gcc, etc.)
            cmake
            nasm
            yasm # Often needed by FFmpeg assembly
            pkgconf
            git
            wget
            autoconf
            automake
            libtool
            clang # Use system clang
            libva
            meson # Required for dav1d
            ninja
            python
        )
        PACKAGES_TO_INSTALL=()
        for pkg in "${REQUIRED_PKGS[@]}"; do
            if pacman -Qi "$pkg" &> /dev/null; then
                _log "$pkg is already installed."
            else
                _log "$pkg is NOT installed."
                PACKAGES_TO_INSTALL+=("$pkg")
            fi
        done

        if [ ${#PACKAGES_TO_INSTALL[@]} -gt 0 ]; then
            _log "The following required Arch packages are missing: ${PACKAGES_TO_INSTALL[*]}"
            if command -v sudo &> /dev/null; then
                _log "Attempting to install missing packages using: sudo pacman -Sy --needed ${PACKAGES_TO_INSTALL[*]}"
                if sudo pacman -Sy --needed --noconfirm "${PACKAGES_TO_INSTALL[@]}"; then
                    _log "Successfully installed missing Arch packages."
                else
                    _log "Error: Failed to install required Arch packages using pacman. Please install them manually."
                    exit 1
                fi
            else
                _log "Error: sudo command not found. Please install the following packages manually using pacman: ${PACKAGES_TO_INSTALL[*]}"
                exit 1
            fi
        fi
        _log "Required Arch packages check complete."

    else
        _log "Error: Non-Arch Linux detected. This script now requires Arch/pacman."
        exit 1
    fi
else
    _log "Error: Unsupported operating system '$OS_NAME'."
    exit 1
fi

_log "Using CPU cores: $CPU_COUNT"

# --- Environment Configuration ---
# No custom environment needed for standard shared build
_log "Using standard build environment for $INSTALL_PREFIX installation."

# --- Prepare Directories ---
_log "Creating directories..."
mkdir -p "$BUILD_DIR"
mkdir -p "$INSTALL_PREFIX"
rm -rf "$BUILD_DIR/ffmpeg" # Clean previous ffmpeg source attempt
rm -rf "$BUILD_DIR/SVT-AV1" # Clean previous svt-av1 source attempt
rm -rf "$BUILD_DIR/opus" # Clean previous opus source attempt
rm -rf "$BUILD_DIR/dav1d" # Clean previous dav1d source attempt
rm -rf "$BUILD_DIR/zimg" # Clean previous zimg source attempt

# --- Build SVT-AV1 from Source ---
_log "Cloning SVT-AV1 source (branch: $SVT_AV1_BRANCH)..."
cd "$BUILD_DIR"
git clone --depth 1 --branch "$SVT_AV1_BRANCH" "$SVT_AV1_REPO" SVT-AV1
cd SVT-AV1

_log "Configuring SVT-AV1..."
mkdir -p Build # Use standard CMake build directory convention
cd Build
# Use system clang/clang++ (should be in PATH after installing base-devel/clang)
_log "Using system clang/clang++"
CLANG_PATH=$(command -v clang)
CLANGPP_PATH=$(command -v clang++)
if [[ ! -x "$CLANG_PATH" || ! -x "$CLANGPP_PATH" ]]; then
    _log "Error: clang or clang++ not found in PATH. Ensure 'clang' package is installed correctly."
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
    -DCMAKE_CXX_FLAGS="-O3" # We only need the library, add PSY optimizations

_log "Building SVT-AV1 (using $CPU_COUNT cores)..."
make -j"$CPU_COUNT"
_log "Installing SVT-AV1..."
make install # No sudo needed for $HOME/.local
_log "SVT-AV1 installation complete."

# --- Build opus from Source ---
_log "Cloning opus source (branch: $OPUS_BRANCH)..."
cd "$BUILD_DIR"
git clone --depth 1 --branch "$OPUS_BRANCH" "$OPUS_REPO" opus
cd opus

_log "Configuring opus..."
./autogen.sh # Opus requires autogen before configure
./configure \
    --prefix="$INSTALL_PREFIX" \
    --disable-static \
    --enable-shared \
    --disable-doc \
    --disable-extra-programs

_log "Building opus (using $CPU_COUNT cores)..."
make -j"$CPU_COUNT"
_log "Installing opus..."
make install # No sudo needed for $HOME/.local
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
ninja install # No sudo needed for $HOME/.local
_log "dav1d installation complete."

# --- Build zimg from Source ---
_log "Cloning zimg source (branch: $ZIMG_BRANCH)..."
cd "$BUILD_DIR"
git clone --depth 1 --branch "$ZIMG_BRANCH" "$ZIMG_REPO" zimg
cd zimg

# Initialize submodules (required for zimg build)
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
make install # No sudo needed for $HOME/.local
_log "zimg installation complete."


# --- Download FFmpeg ---
_log "Downloading FFmpeg source (branch: $FFMPEG_BRANCH)..."
cd "$BUILD_DIR" # Go back to build dir
git clone --depth 1 --branch "$FFMPEG_BRANCH" "$FFMPEG_REPO" ffmpeg
cd ffmpeg

# Ensure pkg-config finds the libraries installed in the custom prefix
# Ensure pkg-config finds libraries installed in our custom prefix
# Explicitly add system pkgconfig path and custom prefix path
SYSTEM_PKGCONFIG_PATH="/usr/lib/pkgconfig:/usr/share/pkgconfig" # Common system paths on Arch
CUSTOM_PKG_CONFIG_PATH="${INSTALL_PREFIX}/lib/pkgconfig:${SYSTEM_PKGCONFIG_PATH}"
if [[ -n "${PKG_CONFIG_PATH:-}" ]]; then
    export PKG_CONFIG_PATH="${CUSTOM_PKG_CONFIG_PATH}:${PKG_CONFIG_PATH}"
else
    export PKG_CONFIG_PATH="$CUSTOM_PKG_CONFIG_PATH"
fi
_log "PKG_CONFIG_PATH set to: $PKG_CONFIG_PATH"
# Also ensure PKG_CONFIG points to the system version if it exists
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
    _log "         Ensure 'libva' (or equivalent) is installed via pacman."
fi

# Add rpath to LDFLAGS to find libs in INSTALL_PREFIX
EXTRA_LDFLAGS_VAL="-Wl,-rpath,${INSTALL_PREFIX}/lib"

# --- Build configure arguments array ---
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

# Add LDFLAGS to the array
CONFIGURE_ARGS+=(--extra-ldflags="$EXTRA_LDFLAGS_VAL")
if [[ -n "$FFMPEG_EXTRA_FLAGS" ]]; then
    # Split FFMPEG_EXTRA_FLAGS in case it contains multiple flags in the future
    read -ra flags <<< "$FFMPEG_EXTRA_FLAGS"
    CONFIGURE_ARGS+=("${flags[@]}")
fi

# --- Execute configure ---
_log "Executing configure with arguments:"
printf "  %s\n" "${CONFIGURE_ARGS[@]}" # Log arguments for debugging
# PKG_CONFIG should be set correctly above or found in PATH
./configure "${CONFIGURE_ARGS[@]}"

_log "FFmpeg configuration complete."

# --- Build and Install ---
_log "Building FFmpeg (using $CPU_COUNT cores)..."
make -j"$CPU_COUNT"
_log "Build complete. Installing FFmpeg..."
make install # No sudo needed for $HOME/.local
_log "Installation complete."

# --- Validate Static Linking ---
# Removed static linking validation for shared build

# --- Cleanup ---
_log "Cleaning up build directory..."
# cd "$HOME" # Go back home before removing build dir
# rm -rf "$BUILD_DIR"
_log "Build directory $BUILD_DIR kept for inspection. Remove manually if desired."

# --- Final Message ---
_log "--------------------------------------------------"
_log "FFmpeg build successful!"
_log "ffmpeg and ffprobe are located at: $INSTALL_PREFIX/bin/"
_log "--------------------------------------------------"

exit 0
