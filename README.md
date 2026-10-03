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
├── common/         # applied for both x86_64 and arm64ec builds
├── arm64ec/        # applied only for the arm64ec build
└── x86_64/         # applied only for the x86_64 build
```

The full ordered list per architecture lives in the `PATCHES=(...)` block
inside `build-scripts/build-step-{arm64ec,x86_64}.sh` under `--configure`.

## CI / GitHub Actions

`.github/workflows/build-proton.yml` checks out upstream `ValveSoftware/wine` `proton_11.0`,
overlays this repo's patches on top, and builds both arches in a matrix.
On push to `main` / `master` (or manual dispatch) it publishes a
date-tagged GitHub Release with both `.wcp` artifacts.

See `.github/workflows/README.md` for details.

## Build prerequisites

- Wine 11.0 source tree (`ValveSoftware/wine` `proton_11.0` branch).
- Android NDK r27d or newer (SDK 28 target).
- `llvm-mingw` toolchain (2025-09-20 ucrt build verified).
- Termux filesystem at `$HOME/termuxfs/{aarch64,x86_64}/` with dev headers for
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

# 3a. x86_64 build:
bash build-scripts/build-step-x86_64.sh --build-sysvshm --configure --build --install
bash build-scripts/build-step-x86_64.sh --package-wcp

# 3b. arm64ec build:
bash build-scripts/build-step-arm64ec.sh --build-sysvshm --configure --build --install
bash build-scripts/build-step-arm64ec.sh --package-wcp
```

`--build-sysvshm` builds the small `libandroid-sysvshm.so` shim (SysV
`shmget/shmat` on Bionic). Run it once before `--configure` so the patched
fsync.c can find the helper at link time.

## Output

After `--install` and `--package-wcp`:

- `$HOME/compiled-files-{aarch64,x86_64}/` — installed wine tree (bin/, lib/, share/).
- `proton-11.0-{arm64ec,x86_64}.wcp` — GameNative/Winlator drop-in package.

The `.wcp` is an uncompressed tar. The contained `prefixPack.txz` is
xz-compressed (pre-built payload from `GameNative/bionic-prefix-files`).

## Sync patch details

The ESYNC patches add `dlls/ntdll/unix/esync.{c,h}` (eventfd-based sync
primitives on the ntdll side) and `server/esync.{c,h}` (server-side
bookkeeping), and wire `do_esync()` checks into `dlls/ntdll/unix/sync.c`,
`server/inproc_sync.c`, and `server/thread.c` next to the existing
`do_fsync()` checks.

The FSYNC patches add a small `shm_utils.h` shim that backs fsync's
shared-memory indices with Android's `android_sysvshm` shim.

## License

LGPL-2.1-or-later (same as Wine). See `LICENSE` and `COPYING.LIB`.
