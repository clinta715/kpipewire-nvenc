#!/bin/sh
# Build KPipeWire with the NVENC patch and optionally install the library.
# Usage: ./build-install.sh [--install]
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ver=6.8.3
work="$here/releases/$ver/work"
stage="$here/releases/$ver/stage"
dest="$HOME/.local/lib/krdp-nvenc/$ver"

rm -rf "$work" "$stage"
mkdir -p "$work" "$stage"

tar -xJf "$here/kpipewire-$ver.tar.xz" -C "$work"
cd "$work/kpipewire-$ver"
patch -p1 < "$here/nvenc-$ver.patch"

# BUILD_TESTING pulls in PlasmaWaylandProtocols, which is not needed for the library.
cmake -B build -S . -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_TESTING=OFF
cmake --build build -j"$(nproc)"
DESTDIR="$stage" cmake --install build

lib="$stage/usr/lib/libKPipeWireRecord.so.$ver"
strings "$lib" | grep -q H264NvencEncoder || { echo "FAIL: NVENC encoder missing from $lib" >&2; exit 1; }
echo "built $lib"

if [ "${1:-}" = "--install" ]; then
    mkdir -p "$dest"
    install -m 644 "$lib" "$dest/libKPipeWireRecord.so.6"
    echo "installed $dest/libKPipeWireRecord.so.6"
fi
