# proton-wine-p11

Patch overlay + Android build scripts for **Proton 11.0** (Valve Wine 11.0 base).

This repo is applied on top of an upstream Wine 11.0 source tree to produce a
Proton 11.0 build for Android (GameNative / Winlator). It contains only:

- `patches/`       — Proton-specific patches, grouped by architecture scope
- `build-scripts/` — host-side build entry points (configure / build / install / package)
- `android/`       — small runtime shims (`shm_utils`, `android_sysvshm`)
- `.github/`       — CI workflow
- `LICENSE`, `COPYING.LIB` — LGPL-2.1 (Wine license)

It does not contain the Wine source itself. Clone upstream Wine 11.0 and
apply the patches on top.

## Sync backend

ESYNC (eventfd-based) + FSYNC (futex-based), auto-selected at runtime:

- `WINEFSYNC=1` enables FSYNC (requires kernel `futex_waitv`, Linux 5.16+).
- `WINEESYNC=1` enables ESYNC (requires raised `ulimit -n`, ~1M FDs).
- Otherwise, classic server-side synchronization is used.

## Patch layout

```
patches/
├── common/         # applied for the arm64ec build
└── arm64ec/        # arm64ec-specific patches
```

The full ordered list lives in the `PATCHES=(...)` block inside
`build-scripts/build-step-arm64ec.sh` under `--configure`.

## CI / GitHub Actions

`.github/workflows/build-proton.yml` checks out upstream `ValveSoftware/wine` `proton_11.0`,
overlays this repo's patches on top, and builds arm64ec.
On push to `main` / `master` (or manual dispatch) it publishes a
date-tagged GitHub Release with the `.wcp` artifact.

See `.github/workflows/README.md` for details.

## Build prerequisites

- Wine 11.0 source tree (`ValveSoftware/wine` `proton_11.0` branch).
- Android NDK r27d or newer (SDK 28 target).
- `llvm-mingw` toolchain (2025-09-20 ucrt build verified).
- Termux filesystem at `$HOME/termuxfs/aarch64/` with dev headers for
  `freetype2`, `pulseaudio`, `SDL2`, `X11`, `gstreamer-1.0`, `gnutls`,
  `vulkan`, `alsa`.
- `ccache` (optional but recommended).
- `pkg-config`, `flex`, `bison`, `make`.

## Build flow

```sh
# 1. Get the Wine source and overlay this repo on top.
git clone --branch proton_11.0 --depth 1 https://github.com/ValveSoftware/wine.git wine-src
cd wine-src

# Drop patches/, build-scripts/, android/ from this repo into the Wine tree.

# 2. Build host tools (once):
bash build-scripts/build-step0.sh

# 3. arm64ec build:
bash build-scripts/build-step-arm64ec.sh --build-sysvshm --configure --build --install
bash build-scripts/build-step-arm64ec.sh --package-wcp
```

`--build-sysvshm` builds the small `libandroid-sysvshm.so` shim (SysV
`shmget/shmat` on Bionic). Run it once before `--configure` so the patched
fsync.c can find the helper at link time.

## Output

After `--install` and `--package-wcp`:

- `$HOME/compiled-files-aarch64/` — installed wine tree (bin/, lib/, share/).
- `proton-11.0-arm64ec.wcp` — GameNative/Winlator drop-in package.

The `.wcp` is a zstd-compressed tar. The contained `prefixPack.txz` is
**generated on every build** by `generate_prefix_pack` in
`build-scripts/build-step-arm64ec.sh` (no external download). It is a minimal
skeleton: `drive_c` folders plus header-only `system.reg` / `user.reg` /
`userdef.reg`, and deliberately no `.update-timestamp`. On first launch Wine
runs `wineboot`, which applies this build's `wine.inf` and rebuilds the
registry, so it always matches the compiled Wine.

Existing containers keep their old registry (wineboot only merges `wine.inf`
into it when the file's timestamp changes), so create a **new container** to
get a clean one.

Set `WCP_PREFIX_PACK=/path/x.txz` to override with a ready-made pack.

## Sync patch details

The ESYNC patches add `dlls/ntdll/unix/esync.{c,h}` (eventfd-based sync
primitives on the ntdll side) and `server/esync.{c,h}` (server-side
bookkeeping), and wire `do_esync()` checks into `dlls/ntdll/unix/sync.c`,
`server/inproc_sync.c`, and `server/thread.c` next to the existing
`do_fsync()` checks.

The FSYNC patches add a small `shm_utils.h` shim that backs fsync's
shared-memory indices with Android's `android_sysvshm` shim.

## OpenGL32 wow64 Vulkan buffer-storage path

On this Android fork, the Vulkan buffer-storage path in
`dlls/opengl32/unix_wgl.c::initialize_vk_device` is **always
disabled** (no env var, no toggle). The patch
`patches/common/dlls_opengl32_unix_wgl_c_vk_buffer_storage_fallback.patch`
unconditionally early-returns FALSE at the top of
`initialize_vk_device`, before any Vulkan buffer-storage init runs.

Without this, on stacks where the Vulkan driver advertises
`VK_EXT_map_memory_placed` but does not honor `pPlacedAddress`
(e.g. Zink-over-a-Vulkan-wrapper on Termux-X11 with Turnip Adreno),
`wow64_map_buffer()` hits:

```
assertion "buffer->host_ptr == buffer->vm_ptr" failed
```

the first time a 32-bit app persistently maps a buffer via
`glBufferStorage` + `glMapBuffer` (e.g. wined3d's D3D7 vertex buffer
pool — observed as the Direct3D 7 test 32-bit crash, 64-bit version
unaffected). Returning FALSE here makes `make_context_current()` fall
back to `GL_AMD_pinned_memory` (if available) or disable
`GL_ARB_buffer_storage` entirely, so 32-bit apps use the regular
`glBufferData` + `glMapBuffer` copy path. 64-bit contexts are
unaffected (the Vulkan buffer-storage branch is only entered under
`is_wow64()`).

The Vulkan path is a perf optimization; losing it on this Android
fork is acceptable in exchange for 32-bit stability.

## License

LGPL-2.1-or-later (same as Wine). See `LICENSE` and `COPYING.LIB`.
