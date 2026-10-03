#!/bin/bash
# Cross-build Proton 11.0 (x86_64 + i386) for Android.
# ESYNC + FSYNC. Output: a .wcp package for GameNative/Winlator.

set -e

# Toolchain & paths
export ARCH="x86_64"
export WIN_ARCH="x86_64,i386"
export OUTPUT_DIR="${OUTPUT_DIR:-$HOME/compiled-files-x86_64}"

export deps="${deps:-$HOME/termuxfs/x86_64/data/data/com.termux/files/usr}"
export RUNTIME_PATH="/data/data/com.termux/files/usr"
export install_dir="$deps/../opt/wine"

export TOOLCHAIN="${TOOLCHAIN:-$HOME/Android/Sdk/ndk/27.3.13750724/toolchains/llvm/prebuilt/linux-x86_64/bin}"
export LLVM_MINGW_TOOLCHAIN="${LLVM_MINGW_TOOLCHAIN:-$HOME/toolchains/llvm-mingw-20250920-ucrt-ubuntu-22.04-x86_64/bin}"
export TARGET=x86_64-linux-android28
export PATH="$LLVM_MINGW_TOOLCHAIN:$PATH"

# ccache wrapper (optional)
if command -v ccache >/dev/null 2>&1; then
  export CCACHE_DIR="${CCACHE_DIR:-$HOME/.ccache}"
  ccache -M 3G >/dev/null 2>&1 || true
  mkdir -p "$HOME/ccache-bin"
  ln -sf "$(command -v ccache)" "$HOME/ccache-bin/clang"
  ln -sf "$(command -v ccache)" "$HOME/ccache-bin/clang++"
  export PATH="$HOME/ccache-bin:$PATH"
  export CC="ccache $TOOLCHAIN/$TARGET-clang"
  export CXX="ccache $TOOLCHAIN/$TARGET-clang++"
else
  export CC="$TOOLCHAIN/$TARGET-clang"
  export CXX="$TOOLCHAIN/$TARGET-clang++"
fi

export AS="$TOOLCHAIN/$TARGET-clang"
export AR="$TOOLCHAIN/llvm-ar"
export LD="$TOOLCHAIN/ld"
export RANLIB="$TOOLCHAIN/llvm-ranlib"
export STRIP="$TOOLCHAIN/llvm-strip"
export DLLTOOL="$LLVM_MINGW_TOOLCHAIN/llvm-dlltool"

# Wine's WINE_CHECK_HOST_TOOL skips the non-prefixed pkg-config fallback;
# point PKG_CONFIG at the host tool explicitly.
export PKG_CONFIG="${PKG_CONFIG:-$(command -v pkg-config)}"
export PKG_CONFIG_LIBDIR="$deps/lib/pkgconfig:$deps/share/pkgconfig"
export ACLOCAL_PATH="$deps/lib/aclocal:$deps/share/aclocal"
export CPPFLAGS="--sysroot=$TOOLCHAIN/../sysroot -idirafter $deps/include"

# -g1 keeps line-tables so crash backtraces show file:line.
# ANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES + max-page-size=16384 give 16KB page
# support on a single SDK 28 target.
export C_OPTS="-g1 -O2 -DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES -march=x86-64 -mtune=generic -Wno-declaration-after-statement -Wno-implicit-function-declaration -Wno-int-conversion"
export CFLAGS="$C_OPTS"
export CXXFLAGS="$C_OPTS"
export CROSSCFLAGS="-g1 -O2"
export LDFLAGS="-L$deps/lib -Wl,-rpath=$RUNTIME_PATH/lib -Wl,-z,max-page-size=16384"

export FREETYPE_CFLAGS="-I$deps/include/freetype2"
export PULSE_CFLAGS="-I$deps/include/pulse"
export PULSE_LIBS="-L$deps/lib/pulseaudio -lpulse"
export SDL2_CFLAGS="-I$deps/include/SDL2"
export SDL2_LIBS="-L$deps/lib -lSDL2"
export X_CFLAGS="-I$deps/include/X11"
export X_LIBS=""
export GSTREAMER_CFLAGS="-I$deps/include/gstreamer-1.0 -I$deps/include/glib-2.0 -I$deps/lib/glib-2.0/include -I$deps/glib-2.0/include -I$deps/lib/gstreamer-1.0/include"
export GSTREAMER_LIBS="-L$deps/lib -lgstgl-1.0 -lgstapp-1.0 -lgstvideo-1.0 -lgstaudio-1.0 -lglib-2.0 -lgobject-2.0 -lgio-2.0 -lgsttag-1.0 -lgstbase-1.0 -lgstreamer-1.0"
export FFMPEG_CFLAGS="-I$deps/include/libavutil -I$deps/include/libavcodec -I$deps/include/libavformat"
export FFMPEG_LIBS="-L$deps/lib -lavutil -lavcodec -lavformat"

# Per-argument actions
for arg in "$@"; do
  case "$arg" in
    --build-sysvshm)
      # Build the android_sysvshm shim (provides SysV shared memory on Bionic).
      SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
      if [ -d "$PROJECT_ROOT/android/android_sysvshm" ]; then
        echo "Building android_sysvshm..."
        ( cd "$PROJECT_ROOT/android/android_sysvshm" && bash ./build-x86_64.sh )
        if [ $? -eq 0 ]; then
          mkdir -p "$deps/lib"
          cp "$PROJECT_ROOT/android/android_sysvshm/build-x86_64/libandroid-sysvshm.so" "$deps/lib/"
          echo "Copied libandroid-sysvshm.so to $deps/lib/"
        else
          echo "Warning: android_sysvshm build failed"
        fi
      fi
      ;;

    --configure)
      ./configure \
        --enable-archs="$WIN_ARCH" \
        --host="$TARGET" \
        --prefix "$install_dir" \
        --bindir "$install_dir/bin" \
        --libdir "$install_dir/lib" \
        --exec-prefix "$install_dir" \
        --with-mingw=clang \
        --with-wine-tools=./wine-tools \
        --enable-win64 \
        --disable-win16 \
        --enable-nls \
        --disable-amd_ags_x64 \
        --enable-wineandroid_drv=no \
        --disable-tests \
        --with-alsa \
        --without-capi \
        --without-coreaudio \
        --without-cups \
        --without-dbus \
        --without-ffmpeg \
        --with-fontconfig \
        --with-freetype \
        --without-gcrypt \
        --with-gettext \
        --with-gettextpo=no \
        --without-gphoto \
        --with-gnutls \
        --without-gssapi \
        --with-gstreamer \
        --without-inotify \
        --without-krb5 \
        --without-netapi \
        --without-opencl \
        --with-opengl \
        --without-oss \
        --without-pcap \
        --without-pcsclite \
        --without-piper \
        --with-pthread \
        --with-pulse \
        --without-sane \
        --with-sdl \
        --without-udev \
        --without-unwind \
        --without-usb \
        --without-v4l2 \
        --without-vosk \
        --with-vulkan \
        --without-wayland \
        --without-xcomposite \
        --without-xfixes \
        --without-xinerama \
        --with-xrandr \
        --with-xrender \
        --without-xshape \
        --without-xshm \
        --without-xxf86vm

      echo "Applying patches..."

      PATCHES=(
        # Android networking
        "common/dlls_dnsapi_libresolv_c.patch"
        "common/dlls_dnsapi_record_c.patch"
        "common/dlls_nsiproxy_sys_ip_c.patch"
        "common/dlls_nsiproxy_sys_ndis_c.patch"
        "common/dlls_nsiproxy_sys_nsi_common_h.patch"
        "common/dlls_user32_makefile_in.patch"
        "common/dlls_ws2_32_socket_c.patch"
        "common/dlls_crypt32_cert_c.patch"
        "common/server_token_c.patch"
        "common/server_unicode_c.patch"

        # MIDI support
        "common/midi_support.patch"

        # SDL gamepad init
        "common/dlls_winebus_sys_bus_sdl_c.patch"

        # FSYNC: shm_utils shim for Android SysV shared memory
        "common/dlls_ntdll_unix_fsync_c.patch"
        "common/server_fsync_c.patch"

        # ESYNC: eventfd-based sync objects (new files)
        "common/dlls_ntdll_unix_esync_c.patch"
        "common/dlls_ntdll_unix_esync_h.patch"
        "common/server_esync_c.patch"
        "common/server_esync_h.patch"

        # ESYNC integration into the sync dispatch
        "common/server_protocol_def.patch"
        "common/server_main_c.patch"
        "common/dlls_ntdll_makefile_in.patch"
        "common/dlls_ntdll_unix_sync_c.patch"
        "common/server_makefile_in.patch"
        "common/server_inproc_sync_c.patch"
        "common/server_thread_c.patch"

        # winex11 driver
        "common/dlls_winex11_drv_bitblt_c.patch"
        "common/dlls_winex11_drv_desktop_c.patch"
        "common/dlls_winex11_drv_keyboard_c.patch"
        "common/dlls_winex11_drv_mouse_c.patch"
        "common/dlls_winex11_drv_opengl_c.patch"
        "common/dlls_winex11_drv_window_c.patch"
        "common/dlls_winex11_drv_x11drv_h.patch"
        "common/dlls_winex11_drv_x11drv_main_c.patch"

        # Address space / preloader
        "common/loader_preloader_c.patch"
        "x86_64/dlls_ntdll_unix_virtual_c.patch"

        # Syscall interception
        "x86_64/dlls_ntdll_unix_signal_x86_64_c.patch"

        # PulseAudio
        "common/dlls_winepulse_drv_pulse_c.patch"

        # OpenGL32
        "common/dlls_opengl32_unix_wgl_c.patch"

        # Explorer desktop
        "common/programs_explorer_desktop_c.patch"

        # ntdll server path
        "common/dlls_ntdll_unix_server_c.patch"

        # Winlator AMD AGS shim
        "common/dlls_amd_ags_x64_unixlib_c.patch"

        # Shortcut creation
        "common/programs_winemenubuilder_winemenubuilder_c.patch"

        # advapi32 token/user
        "common/dlls_advapi32_advapi_c.patch"

        # Wine browser
        "common/programs_winebrowser_makefile_in.patch"
        "common/programs_winebrowser_main_c.patch"

        # Clipboard
        "common/dlls_user32_clipboard_c.patch"
        "common/dlls_win32u_clipboard_c.patch"

        # x86_64 unix loader
        "x86_64/dlls_ntdll_unix_loader_c.patch"

        # FEX unixlib loader (MemoryWineLoadUnixLibByName)
        "common/include_winternl_h.patch"
        "common/include_wine_unixlib_h.patch"
        "common/dlls_wow64_virtual_c.patch"
        "common/dlls_ntdll_unix_unix_private_h.patch"

        # Bionic fixes
        "common/dlls_ntdll_unix_env_c.patch"
        "common/dlls_shell32_shlfileop_c.patch"

        # rsaenh crypto
        "common/dlls_rsaenh_rsaenh_c.patch"
      )

      for patch in "${PATCHES[@]}"; do
        git apply "./patches/$patch"
      done
      ;;

    --package-wcp)
      # Package $OUTPUT_DIR as a .wcp (uncompressed tar).
      # Layout: profile.json, bin/, lib/, share/, prefixPack.txz.
      # The inner prefixPack.txz is xz-compressed pre-built payload from
      # GameNative/bionic-prefix-files; the outer .wcp is plain tar.
      WCP_NAME="${WCP_NAME:-proton-11.0-x86_64.wcp}"
      WCP_TYPE="${WCP_TYPE:-Proton}"
      ARCH_NAME="x86_64"
      WCP_VERSION_CODE="${WCP_VERSION_CODE:-1}"
      WCP_PREFIX_PACK="${WCP_PREFIX_PACK:-}"
      SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
      STAGING="$(mktemp -d)"
      trap 'rm -rf "$STAGING"' EXIT

      if [ ! -d "$OUTPUT_DIR/bin" ] || [ ! -d "$OUTPUT_DIR/lib/wine" ]; then
        echo "ERROR: $OUTPUT_DIR is not populated; run --install first." >&2
        exit 1
      fi

      cp -a "$OUTPUT_DIR/bin" "$OUTPUT_DIR/lib" "$OUTPUT_DIR/share" "$STAGING/"

      if [ -z "$WCP_PREFIX_PACK" ] && [ -f "$PROJECT_ROOT/android/prefixPack-$ARCH_NAME.txz" ]; then
        WCP_PREFIX_PACK="$PROJECT_ROOT/android/prefixPack-$ARCH_NAME.txz"
      fi
      if [ -z "$WCP_PREFIX_PACK" ]; then
        PREFIX_PACK_URL="https://github.com/GameNative/bionic-prefix-files/raw/main/prefixPack-$ARCH_NAME-11.txz"
        echo "Downloading prefixPack from $PREFIX_PACK_URL ..."
        if wget -q -O "$PROJECT_ROOT/android/prefixPack-$ARCH_NAME.txz" "$PREFIX_PACK_URL"; then
          WCP_PREFIX_PACK="$PROJECT_ROOT/android/prefixPack-$ARCH_NAME.txz"
        else
          rm -f "$PROJECT_ROOT/android/prefixPack-$ARCH_NAME.txz"
          echo "Warning: prefixPack download failed."
        fi
      fi
      if [ -n "$WCP_PREFIX_PACK" ] && [ -f "$WCP_PREFIX_PACK" ]; then
        cp "$WCP_PREFIX_PACK" "$STAGING/prefixPack.txz"
      else
        echo "Note: no prefixPack.txz found; packaging an empty one (GameNative will create the prefix on first launch)."
        mkdir -p "$STAGING/empty-prefix"
        tar -C "$STAGING/empty-prefix" -cJf "$STAGING/prefixPack.txz" --files-from /dev/null
        rm -rf "$STAGING/empty-prefix"
      fi

      cat > "$STAGING/profile.json" <<EOF
{
  "type": "$WCP_TYPE",
  "versionName": "11.0-$ARCH_NAME",
  "versionCode": $WCP_VERSION_CODE,
  "description": "Proton 11.0 $ARCH_NAME (bionic) - ESYNC + FSYNC + Android fixes. SDK 28 + 16KB pages. Needs a fresh $ARCH_NAME container.",
  "files": [],
  "wine": {
    "binPath": "bin",
    "libPath": "lib",
    "prefixPack": "prefixPack.txz"
  }
}
EOF

      out="$(dirname "$OUTPUT_DIR")/$WCP_NAME"
      rm -f "$out"
      # Plain tar -> .wcp.
      tar -C "$STAGING" -cf "$out" profile.json prefixPack.txz bin lib share
      rm -rf "$STAGING"
      trap - EXIT
      echo "WCP package: $out ($(du -m "$out" | cut -f1)MB)"
      ;;

    --build)
      echo "Building..."
      rm -rf "$OUTPUT_DIR/bin" "$OUTPUT_DIR/lib" "$OUTPUT_DIR/share" "$install_dir"
      make -j"$(nproc)"
      ;;

    --install)
      echo "Installing..."
      mkdir -p "$OUTPUT_DIR/bin" "$OUTPUT_DIR/lib" "$OUTPUT_DIR/share" "$install_dir"
      make install -j"$(nproc)"
      cp -r "$install_dir/bin/wine"* "$OUTPUT_DIR/bin"
      cp -r "$install_dir/bin/reg"* "$OUTPUT_DIR/bin"
      cp -r "$install_dir/bin/msi"* "$OUTPUT_DIR/bin"
      cp -r "$install_dir/bin/notepad" "$OUTPUT_DIR/bin"
      cp -r "$install_dir/lib/wine" "$OUTPUT_DIR/lib"
      cp -r "$install_dir/share/wine" "$OUTPUT_DIR/share"

      # Delete dev artifacts (static libs, def files, headers, man pages)
      # but KEEP .symtab and .debug_line so WINEDEBUG + crash backtraces
      # show real function names and file:line.
      echo "Removing dev artifacts (static libs, headers, man pages)..."
      find "$OUTPUT_DIR/lib" "$OUTPUT_DIR/bin" -type f \
        \( -name '*.a' -o -name '*.lib' -o -name '*.def' \) -delete 2>/dev/null || true
      rm -rf "$OUTPUT_DIR/include" "$OUTPUT_DIR/share/man" 2>/dev/null || true
      echo "Install complete (no strip, -g1 -O2, full perf)."

      # Symlink the wine loader binaries into the install/bin tree.
      ln -sf ../lib/wine/x86_64-unix/wine "$install_dir/bin/wine"
      ln -sf ../lib/wine/x86_64-unix/wine "$OUTPUT_DIR/bin/wine"
      ln -sf ../lib/wine/x86_64-unix/wine-preloader "$OUTPUT_DIR/bin/wine-preloader"
      ln -sf ../lib/wine/x86_64-unix/wine-preloader "$install_dir/bin/wine-preloader"
      echo "Wine loader symlinks:"
      ls -la "$OUTPUT_DIR/bin/wine" "$OUTPUT_DIR/bin/wine-preloader"
      ;;
  esac
done
