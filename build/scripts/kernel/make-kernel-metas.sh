#!/bin/bash
# Create the linux-image-rt-amd64 / linux-headers-rt-amd64 meta packages for a
# custom kernel, so packages that depend on Debian's meta names (nexus-dkms:
# "linux-headers-rt-amd64 | ...") are satisfied by it instead of apt pulling
# Debian's own RT kernel in alongside.
#
# Usage: make-kernel-metas.sh OUTDIR RELEASE   (e.g. 7.2.9-vos-rt)
set -euo pipefail
OUTDIR=$(realpath "$1"); REL=$2
VER=${REL%%-*}+vos1
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
for kind in image headers; do
    pkg=linux-$kind-rt-amd64
    mkdir -p "$WORK/$pkg/DEBIAN"
    cat > "$WORK/$pkg/DEBIAN/control" <<CTL
Package: $pkg
Version: $VER
Architecture: amd64
Maintainer: Vitruvian <noreply@localhost>
Depends: linux-$kind-$REL
Section: kernel
Priority: optional
Description: Vitruvian custom kernel meta package ($kind)
 Depends on linux-$kind-$REL and stands in for Debian's $pkg.
CTL
    dpkg-deb --root-owner-group --build "$WORK/$pkg" "$OUTDIR/${pkg}_${VER}_amd64.deb" >/dev/null
done
echo ">> Meta packages for $REL written to $OUTDIR"
