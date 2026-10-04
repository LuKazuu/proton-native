# Proton Wine Build Workflow

`build-proton.yml` builds Proton Wine 11.0 for `aarch64` (ARM64EC) on GitHub Actions.

The repo is treated as a **patch overlay**:

1. Checks out **this repo** (patches + build-scripts + android helpers).
2. Checks out the upstream Wine 11.0 source (`ValveSoftware/wine`
   `proton_11.0` branch).
3. Overlays `patches/`, `build-scripts/`, `android/` from this repo on top.
4. Runs the standard build sequence: `autogen.sh` → `build-step0.sh`
   (host tools) → `--build-sysvshm` → `--configure` →
   `--build` → `--install` → `--package-wcp`.

## Triggers

- Push to `main` or `master`
- Pull request against `main` or `master`
- Manual `workflow_dispatch`

The release job runs only on push to `main` / `master` (or manual dispatch);
PR runs only produce artifacts.

## Sync backend

ESYNC + FSYNC only.

## Output

A single `.wcp` artifact:

- `proton-11.0-arm64ec.wcp`

The `.wcp` is a zstd-compressed tar. The contained `prefixPack.txz` is generated
during `--package-wcp` (minimal skeleton, registry rebuilt by `wineboot` from
this build's `wine.inf` on first launch). No `bionic-prefix-files` download.

## Caching

| Cache             | Key                                        | Purpose                              |
|-------------------|--------------------------------------------|--------------------------------------|
| Android NDK r27d  | `android-ndk-r27d`                         | Skip the ~1GB NDK download+unzip    |
| LLVM MinGW        | `bylaws-llvm-mingw-20250920`              | Skip the ~200MB mingw download+extract |
| wine-tools        | `wine-tools-esync-{hash(configure.ac)}`   | Skip the host-tools build (~3 min)  |
| ccache (per-arch) | `ccache-p11-esync-{arch}-{sha}`            | Skip recompiling unchanged objects   |

## Local reproduction

```sh
# 1. Clone this repo and the upstream Wine source side by side.
git clone https://github.com/<your-fork>/proton-wine-p11.git
git clone --branch proton_11.0 --depth 1 https://github.com/ValveSoftware/wine.git wine-src

# 2. Overlay the patches onto the Wine source.
cp -r proton-wine-p11/patches        wine-src/
cp -r proton-wine-p11/build-scripts   wine-src/
cp -r proton-wine-p11/android         wine-src/

# 3. From inside wine-src/, run the build.
cd wine-src
bash autogen.sh
bash build-scripts/build-step0.sh
bash build-scripts/build-step-arm64ec.sh --build-sysvshm --configure --build --install --package-wcp
```

You need the Android NDK r27d, LLVM MinGW 2025-09-20 ucrt, and the
GameNative `termuxfs-aarch64.tar` (see
https://github.com/GameNative/termux-on-gha/releases) extracted to
`$HOME/termuxfs/aarch64/`. See the main `README.md` for full prerequisites.
