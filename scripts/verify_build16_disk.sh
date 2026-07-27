#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERIFY_TMP="$(mktemp -d /tmp/aimac-build16-disk.XXXXXX)"
IMAGE="$VERIFY_TMP/fixture.sparseimage"
MOUNT="$VERIFY_TMP/volume"

cleanup() {
    hdiutil detach "$MOUNT" -quiet >/dev/null 2>&1 || true
    rm -rf "$VERIFY_TMP"
}
trap cleanup EXIT

mkdir -p "$MOUNT"
hdiutil create -size 1g -fs APFS -volname AIMacBuild16Verify -type SPARSE -quiet "$IMAGE"
hdiutil attach -nobrowse -mountpoint "$MOUNT" -quiet "$IMAGE"

dd if=/dev/urandom of="$MOUNT/regular-32mb.bin" bs=1m count=32 status=none
mkfile -n 512m "$MOUNT/sparse-512mb.bin"
sync

swiftc \
    "$PROJECT_DIR/AIMacOptimizer/Sources/Services/DiskSize.swift" \
    "$PROJECT_DIR/scripts/Build16DiskVerifier.swift" \
    -o "$VERIFY_TMP/Build16DiskVerifier"

"$VERIFY_TMP/Build16DiskVerifier" "$MOUNT"
