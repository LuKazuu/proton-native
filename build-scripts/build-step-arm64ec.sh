#!/bin/bash
# Cross-build Proton 11.0 (ARM64EC + AArch64 + i386) for Android.
# ESYNC + FSYNC. Output: a zstd-compressed .wcp for GameNative/Winlator.

set -e

# Toolchain & paths
export ARCH="aarch64"
export WIN_ARCH="arm64ec,aarch64,i386"
export OUTPUT_DIR="${OUTPUT_DIR:-$HOME/compiled-files-aarch64}"

export deps="${deps:-$HOME/termuxfs/aarch64/data/data/com.termux/files/usr}"
export RUNTIME_PATH="/data/data/com.termux/files/usr"
export install_dir="$deps/../opt/wine"

export TOOLCHAIN="${TOOLCHAIN:-$HOME/Android/Sdk/ndk/27.3.13750724/toolchains/llvm/prebuilt/linux-$(uname -m)/bin}"
export LLVM_MINGW_TOOLCHAIN="${LLVM_MINGW_TOOLCHAIN:-$HOME/toolchains/llvm-mingw-20250920-ucrt-ubuntu-22.04-$(uname -m)/bin}"
export TARGET=aarch64-linux-android28
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

# Point PKG_CONFIG at the host tool explicitly (Wine skips the fallback).
export PKG_CONFIG="${PKG_CONFIG:-$(command -v pkg-config)}"
export PKG_CONFIG_LIBDIR="$deps/lib/pkgconfig:$deps/share/pkgconfig"
export ACLOCAL_PATH="$deps/lib/aclocal:$deps/share/aclocal"
export CPPFLAGS="--sysroot=$TOOLCHAIN/../sysroot -idirafter $deps/include"

# -g1: line-tables for backtraces. -Oz: size. --gc-sections: dead code drop.
# 16KB page support via ANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES + max-page-size=16384.
export C_OPTS="-g1 -Oz -ffunction-sections -fdata-sections -DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES -Wno-declaration-after-statement -Wno-implicit-function-declaration -Wno-int-conversion"
export CFLAGS="$C_OPTS"
export CXXFLAGS="$C_OPTS"
export CROSSCFLAGS="-g1 -Oz -ffunction-sections -fdata-sections"
export LDFLAGS="-L$deps/lib -Wl,-rpath=$RUNTIME_PATH/lib -Wl,-z,max-page-size=16384 -Wl,--gc-sections -Wl,--icf=safe -Wl,--rosegment"

export FREETYPE_CFLAGS="-I$deps/include/freetype2"
export PULSE_CFLAGS="-I$deps/include/pulse"
export PULSE_LIBS="-L$deps/lib/pulseaudio -lpulse"
export SDL2_CFLAGS="-I$deps/include/SDL2"
export SDL2_LIBS="-L$deps/lib -lSDL2"
export X_CFLAGS="-I$deps/include/X11"
export X_LIBS="-landroid-sysvshm"
export GSTREAMER_CFLAGS="-I$deps/include/gstreamer-1.0 -I$deps/include/glib-2.0 -I$deps/lib/glib-2.0/include -I$deps/glib-2.0/include -I$deps/lib/gstreamer-1.0/include"
export GSTREAMER_LIBS="-L$deps/lib -lgstgl-1.0 -lgstapp-1.0 -lgstvideo-1.0 -lgstaudio-1.0 -lglib-2.0 -lgobject-2.0 -lgio-2.0 -lgsttag-1.0 -lgstbase-1.0 -lgstreamer-1.0"
export FFMPEG_CFLAGS="-I$deps/include/libavutil -I$deps/include/libavcodec -I$deps/include/libavformat"
export FFMPEG_LIBS="-L$deps/lib -lavutil -lavcodec -lavformat"

# Generate a minimal prefixPack.txz from scratch (no external download).
# It holds only the drive_c skeleton and header-only stub registry hives.
# There is deliberately NO .update-timestamp, so on first launch wineboot
# runs, applies THIS build's share/wine/wine.inf and rebuilds the registry
# (Wow64 FEX keys, fonts, etc. all come from the fresh build).
# The stub hives are needed because the app edits user.reg/system.reg before
# Wine's first start and its editor does not write the "WINE REGISTRY" header.
generate_prefix_pack() {
  local out="$1" root w
  root="$(mktemp -d)"
  w="$root/.wine"
  mkdir -p "$w/dosdevices" \
           "$w/drive_c/windows" \
           "$w/drive_c/Program Files" \
           "$w/drive_c/Program Files (x86)" \
           "$w/drive_c/ProgramData" \
           "$w/drive_c/users/Public" \
           "$w/drive_c/users/xuser"
  ln -s ../drive_c "$w/dosdevices/c:"

  cat > "$w/system.reg" <<'REG'
WINE REGISTRY Version 2
;; All keys relative to REGISTRY\\Machine

#arch=win64

REG
  cat > "$w/user.reg" <<'REG'
WINE REGISTRY Version 2
;; All keys relative to REGISTRY\\User\\S-1-5-21-0-0-0-1000

#arch=win64

REG
  cat > "$w/userdef.reg" <<'REG'
WINE REGISTRY Version 2
;; All keys relative to REGISTRY\\User\\.Default

#arch=win64

REG

  tar -C "$root" --owner=0 --group=0 --numeric-owner --sort=name -cJf "$out" .wine
  rm -rf "$root"
  echo "Generated prefixPack: $out ($(du -k "$out" | cut -f1)KB)"
}

# Per-argument actions
for arg in "$@"; do
  case "$arg" in
    --build-sysvshm)
      # Build the android_sysvshm shim.
      SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
      if [ -d "$PROJECT_ROOT/android/android_sysvshm" ]; then
        echo "Building android_sysvshm..."
        ( cd "$PROJECT_ROOT/android/android_sysvshm" && bash ./build-aarch64.sh )
        if [ $? -eq 0 ]; then
          mkdir -p "$deps/lib"
          cp "$PROJECT_ROOT/android/android_sysvshm/build-aarch64/libandroid-sysvshm.so" "$deps/lib/"
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
        --with-ffmpeg \
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
        --with-xshm \
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

        # winedmo: ffmpeg API compat fix
        "common/dlls_winedmo_ffmpeg_compat.patch"

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
        "arm64ec/dlls_ntdll_unix_virtual_c.patch"

        # FEX arm64ec loader
        "arm64ec/dlls_ntdll_loader_c.patch"
        "arm64ec/dlls_ntdll_unix_loader_c.patch"

        # wineboot build fix
        "arm64ec/programs_wineboot_wineboot_c.patch"

        # PulseAudio
        "common/dlls_winepulse_drv_pulse_c.patch"

        # OpenGL32
        "common/dlls_opengl32_unix_wgl_c.patch"
        # OpenGL32 wow64: always disable the Vulkan buffer-storage path on
        # this Android fork. On stacks (Zink-over-Vulkan on Termux-X11)
        # where vkMapMemory2KHR with VK_MEMORY_MAP_PLACED_BIT_EXT returns
        # a host_ptr different from the requested pPlacedAddress, 32-bit
        # apps crash in wow64_map_buffer() with:
        #   assertion "buffer->host_ptr == buffer->vm_ptr" failed
        # the first time wined3d's D3D7 vertex buffer pool is persistently
        # mapped via glBufferStorage + glMapBuffer. 64-bit contexts are
        # unaffected (the Vulkan buffer-storage branch is only entered on
        # wow64 in make_context_current()). Always-on, no env var gate.
        "common/dlls_opengl32_unix_wgl_c_vk_buffer_storage_fallback.patch"

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

        # FEX unixlib loader
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

      echo "Applying ${#PATCHES[@]} patches..."
      applied=0
      skipped=0
      for patch in "${PATCHES[@]}"; do
        # Apply each patch. Skip silently only if already applied
        # (reverse applies cleanly). Fail loudly on context mismatch
        # or missing file so we don't ship a broken binary that
        # crashes at runtime (this is what hid the M_PERTURB loader
        # patch failure and the first opengl32 wow64 patch failure).
        if [ ! -f "./patches/$patch" ]; then
          echo "" >&2
          echo "FATAL: patch file not found: patches/$patch" >&2
          exit 1
        fi
        if git apply --check "./patches/$patch" 2>/dev/null; then
          git apply "./patches/$patch"
          applied=$((applied + 1))
        elif git apply --check --reverse "./patches/$patch" 2>/dev/null; then
          skipped=$((skipped + 1))
        else
          echo "" >&2
          echo "FATAL: patch failed to apply: $patch" >&2
          echo "--- error details (git apply --check) ---" >&2
          git apply --check "./patches/$patch" >&2 || true
          echo "------------------------------------------" >&2
          exit 1
        fi
      done
      echo "Patches: $applied applied, $skipped skipped (already applied)."
      ;;

    --package-wcp)
      # Package $OUTPUT_DIR as a .wcp (zstd-compressed tar).
      # Layout: profile.json, bin/, lib/, share/, prefixPack.txz.
      WCP_NAME="${WCP_NAME:-proton-11.0-arm64ec.wcp}"
      WCP_TYPE="${WCP_TYPE:-Proton}"
      ARCH_NAME="arm64ec"
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

      # wineboot rebuilds the registry from share/wine/wine.inf on first launch
      # (the prefix pack ships no registry), so the package is useless without it.
      if [ ! -f "$OUTPUT_DIR/share/wine/wine.inf" ]; then
        echo "ERROR: $OUTPUT_DIR/share/wine/wine.inf missing; the prefix would stay empty." >&2
        exit 1
      fi
      for f in wineboot.exe rundll32.exe; do
        if [ ! -f "$OUTPUT_DIR/lib/wine/aarch64-windows/$f" ]; then
          echo "ERROR: lib/wine/aarch64-windows/$f missing; wineboot cannot initialise the prefix." >&2
          exit 1
        fi
      done

      cp -a "$OUTPUT_DIR/bin" "$OUTPUT_DIR/lib" "$OUTPUT_DIR/share" "$STAGING/"

      # Prefix: generated fresh on every packaging run. WCP_PREFIX_PACK can
      # still point at a ready-made .txz to override (escape hatch).
      if [ -n "$WCP_PREFIX_PACK" ] && [ -f "$WCP_PREFIX_PACK" ]; then
        echo "Using provided prefixPack: $WCP_PREFIX_PACK"
        cp "$WCP_PREFIX_PACK" "$STAGING/prefixPack.txz"
      else
        generate_prefix_pack "$STAGING/prefixPack.txz"
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
      # zstd tar -> .wcp. -T0 = all cores, -19 = high ratio.
      tar -C "$STAGING" -I 'zstd -T0 -19' -cf "$out" profile.json prefixPack.txz bin lib share
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

      # Remove dev artifacts; keep .symtab + .debug_line for backtraces.
      echo "Removing dev artifacts (static libs, headers, man pages)..."
      find "$OUTPUT_DIR/lib" "$OUTPUT_DIR/bin" -type f \
        \( -name '*.a' -o -name '*.lib' -o -name '*.def' \) -delete 2>/dev/null || true
      rm -rf "$OUTPUT_DIR/include" "$OUTPUT_DIR/share/man" 2>/dev/null || true
      echo "Install complete (no strip, -g1 -O2, full perf)."

      # Symlink the wine loader binaries.
      ln -sf ../lib/wine/aarch64-unix/wine "$install_dir/bin/wine"
      ln -sf ../lib/wine/aarch64-unix/wine "$OUTPUT_DIR/bin/wine"
      ln -sf ../lib/wine/aarch64-unix/wine-preloader "$OUTPUT_DIR/bin/wine-preloader"
      ln -sf ../lib/wine/aarch64-unix/wine-preloader "$install_dir/bin/wine-preloader"
      echo "Wine loader symlinks:"
      ls -la "$OUTPUT_DIR/bin/wine" "$OUTPUT_DIR/bin/wine-preloader"
      ;;
  esac
done
