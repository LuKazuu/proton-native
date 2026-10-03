#!/bin/sh
# Build the wine-tools tree (host-side helper tools used during cross builds).
# Must be run once before any --configure step.

set -e

mkdir -p wine-tools
cd wine-tools
../configure --without-x --without-gstreamer --without-vulkan --without-wayland
make -j"$(nproc)" __tooldeps__ nls/all
