#!/bin/bash
# Build the latest stable Linux kernel with CachyOS patches and PREEMPT_RT,
# as Debian packages (linux-image / linux-headers) for Vitruvian images.
#
# Mirrors CachyOS's own "rt-bore" variant (linux-cachyos PKGBUILD,
# _cpusched=rt-bore): BORE scheduler for the fair class + PREEMPT_RT.
#
# Usage: build-cachyos-rt.sh [-o OUTDIR] [-v MAJOR.MINOR.PATCH] [-t TAGREL]
#   -v  kernel version (default: latest stable 7.x from CachyOS/linux-cachyos)
#   -t  CachyOS/linux release suffix (default: read from the PKGBUILD)
#   -o  output directory for the .debs (default: ./kernel-debs)
# Environment:
#   VOS_KERNEL_MARCH   generic_v1..v4 | native (default: generic_v3, so the
#                      image runs on any x86-64-v3 CPU, i.e. Haswell/Zen1+)
#   JOBS               make parallelism (default: nproc)
#   VOS_KERNEL_CONFIG_ONLY=1  fetch, patch and configure, then stop (no build)
set -euo pipefail

OUTDIR="$PWD/kernel-debs"
KVER="" TAGREL=""
while getopts "o:v:t:" o; do
    case $o in
        o) OUTDIR=$(realpath -m "$OPTARG") ;;
        v) KVER=$OPTARG ;;
        t) TAGREL=$OPTARG ;;
        *) sed -n 2,16p "$0"; exit 1 ;;
    esac
done
MARCH=${VOS_KERNEL_MARCH:-generic_v3}
JOBS=${JOBS:-$(nproc)}

RAW=https://raw.githubusercontent.com/CachyOS
PKGBUILD=$(curl -fsSL "$RAW/linux-cachyos/master/linux-cachyos/PKGBUILD")
pb() { sed -n "s/^$1=\(.*\)/\1/p" <<<"$PKGBUILD" | head -1; }

if [ -z "$KVER" ]; then
    KVER="$(pb _major).$(pb _minor)"
fi
[ -n "$TAGREL" ] || TAGREL=$(pb _tagrel)
MAJOR=${KVER%.*}
SRC=cachyos-$KVER-$TAGREL
PATCHES=$RAW/kernel-patches/master/$MAJOR

WORK=$(mktemp -d "${TMPDIR:-/tmp}/vos-kernel.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

echo ">> Fetching $SRC"
curl -fsSL "https://github.com/CachyOS/linux/releases/download/$SRC/$SRC.tar.gz" | tar xz
curl -fsSL "$RAW/linux-cachyos/master/linux-cachyos/config" -o config
for p in sched/0001-bore-cachy.patch misc/0001-rt-i915.patch; do
    curl -fsSL "$PATCHES/$p" -o "$(basename "$p")"
done

cd "$SRC"
for p in 0001-bore-cachy.patch 0001-rt-i915.patch; do
    echo ">> Applying $p"
    patch -Np1 < "../$p"
done

cp ../config .config
echo -vos-rt > localversion.20-pkgname

# Same knob settings as the PKGBUILD's rt-bore defaults, plus x86-64 level.
case $MARCH in
    generic_v[1-4]) scripts/config -e GENERIC_CPU -d MZEN4 -d X86_NATIVE_CPU \
                        --set-val X86_64_VERSION "${MARCH#generic_v}" ;;
    native)         scripts/config -d GENERIC_CPU -d MZEN4 -e X86_NATIVE_CPU ;;
    *) echo "bad VOS_KERNEL_MARCH: $MARCH" >&2; exit 1 ;;
esac
scripts/config -e CACHY -e SCHED_BORE -e PREEMPT_RT
scripts/config -d HZ_300 -e HZ_1000 --set-val HZ 1000
scripts/config -d HZ_PERIODIC -d NO_HZ_IDLE -e NO_HZ_FULL_NODEF -e NO_HZ_FULL \
               -e NO_HZ -e NO_HZ_COMMON -e CONTEXT_TRACKING
scripts/config -d CC_OPTIMIZE_FOR_PERFORMANCE -e CC_OPTIMIZE_FOR_PERFORMANCE_O3
scripts/config -d TRANSPARENT_HUGEPAGE_MADVISE -e TRANSPARENT_HUGEPAGE_ALWAYS
# GCC build (Debian chroot): no Clang LTO. No debug info keeps the debs small.
scripts/config -d LTO_CLANG_THIN -d LTO_CLANG_FULL -e LTO_NONE \
               -d DEBUG_INFO -d DEBUG_INFO_BTF -e DEBUG_INFO_NONE
# Debian build-env: don't trust Arch's cert/key paths.
scripts/config --set-str SYSTEM_TRUSTED_KEYS "" --set-str SYSTEM_REVOCATION_KEYS ""

make olddefconfig
for c in PREEMPT_RT SCHED_BORE; do
    grep -q "^CONFIG_$c=y" .config || { echo "CONFIG_$c did not stick" >&2; exit 1; }
done

if [ "${VOS_KERNEL_CONFIG_ONLY:-0}" = 1 ]; then
    echo ">> Config OK: $KVER-vos-rt ($MARCH), PREEMPT_RT=y SCHED_BORE=y"
    exit 0
fi

echo ">> Building $KVER-vos-rt ($MARCH) with $JOBS jobs"
make -j"$JOBS" bindeb-pkg KBUILD_BUILD_USER=vitruvian KBUILD_BUILD_HOST=vitruvian

mkdir -p "$OUTDIR"
# Skip the -dbg package (~1.4GB of vmlinux debug symbols): not needed in images.
for d in ../linux-image-*.deb ../linux-headers-*.deb ../linux-libc-dev_*.deb; do
    case $d in *-dbg_*) continue ;; esac
    cp "$d" "$OUTDIR"/
done
"$(dirname "$0")/make-kernel-metas.sh" "$OUTDIR" "$KVER-vos-rt"
echo ">> Done: $(ls "$OUTDIR" | tr '\n' ' ')"
