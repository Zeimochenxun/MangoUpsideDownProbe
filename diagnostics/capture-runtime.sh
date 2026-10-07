#!/bin/sh
# Immediate snapshot only. No injection, preference writes, or process control.
set -u
umask 077

if [ "$#" -ne 0 ]; then
    printf 'Usage: sh capture-runtime.sh\n' >&2
    exit 2
fi

for mango_command in date uname mkdir mktemp tail tar rm; do
    if ! command -v "$mango_command" >/dev/null 2>&1; then
        printf 'Required command unavailable: %s\n' "$mango_command" >&2
        exit 1
    fi
done

mango_base=/var/mobile/Documents/MangoSuiteDiagnostics
if ! mkdir -p "$mango_base"; then
    printf 'Cannot create output directory: %s\n' "$mango_base" >&2
    exit 1
fi
mango_dir=$(mktemp -d "$mango_base/runtime-$(date +%Y%m%d-%H%M%S)-XXXXXX") || exit 1
mango_metadata=$mango_dir/metadata.txt
mango_limit=1048576

{
    printf 'SCRIPT_REVISION=2\nDIAGNOSTIC_VERSION=1.2.0~beta9.1\nMODE=immediate-snapshot\n'
    printf 'START_UTC=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'CAPTURE_LIMIT_BYTES_PER_FILE=%s\nLOGGER_TTL_SECONDS=1200\nLOGGER_LIMIT_BYTES_PER_FILE=262144\n' "$mango_limit"
    printf 'PATH_POLICY=shell and rootfs are separate candidates; existence does not establish current-process provenance\n'
    printf 'LEGACY_POLICY=legacy files are supplementary history, never evidence from this diagnostic build\n'
    printf 'PRIVILEGE_POLICY=current user only; no sudo or root escalation\n'
    printf 'UNAME='; uname -sr
    if command -v id >/dev/null 2>&1; then printf 'UID=%s\n' "$(id -u)"; fi
    if command -v dpkg-query >/dev/null 2>&1; then
        printf 'INSTALLED_PACKAGES_BEGIN\n'
        dpkg-query -W -f='${Package}\t${Version}\n' \
            com.go.mango com.chenxun.mangosuite com.chenxun.mangosuite.helper 2>&1
        printf 'DPKG_QUERY_EXIT=%s\nINSTALLED_PACKAGES_END\n' "$?"
    else
        printf 'DPKG_QUERY=unavailable\n'
    fi
} > "$mango_metadata"

mango_interrupt() {
    trap '' INT HUP TERM
    printf 'INTERRUPTED=1\nEND_UTC=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$mango_metadata"
    printf 'Snapshot interrupted; partial directory: %s\n' "$mango_dir" >&2
    printf '%s\n' "$mango_dir"
    exit 130
}
trap mango_interrupt INT HUP TERM

mango_copy() {
    mango_label=$1
    mango_source=$2
    mango_target=$mango_dir/$mango_label.log
    # test -f follows symlinks; explicitly reject those before reading.
    if [ -L "$mango_source" ]; then
        printf '%s: rejected-symlink source=%s\n' "$mango_label" "$mango_source" >> "$mango_metadata"
        return
    fi
    if [ ! -e "$mango_source" ]; then
        printf '%s: absent-or-inaccessible source=%s\n' "$mango_label" "$mango_source" >> "$mango_metadata"
        return
    fi
    if [ ! -f "$mango_source" ]; then
        printf '%s: rejected-nonregular source=%s\n' "$mango_label" "$mango_source" >> "$mango_metadata"
        return
    fi
    if [ ! -r "$mango_source" ]; then
        printf '%s: permission-denied source=%s\n' "$mango_label" "$mango_source" >> "$mango_metadata"
        return
    fi
    mango_file_info=unavailable
    if command -v stat >/dev/null 2>&1; then
        mango_file_info=$(stat -f 'size=%z mtime_epoch=%m' "$mango_source" 2>/dev/null) || \
            mango_file_info=$(stat -c 'size=%s mtime_epoch=%Y' "$mango_source" 2>/dev/null) || \
            mango_file_info=unavailable
    fi
    # At most the last 1 MiB is copied, even for older unbounded legacy logs.
    if tail -c "$mango_limit" "$mango_source" > "$mango_target" 2>/dev/null; then
        printf '%s: copied-bounded-tail source=%s %s\n' "$mango_label" "$mango_source" "$mango_file_info" >> "$mango_metadata"
    else
        rm -f "$mango_target"
        printf '%s: read-failed source=%s\n' "$mango_label" "$mango_source" >> "$mango_metadata"
    fi
}

# RootHide's shell and tweak can resolve /var/mobile to different roots.
# Do not merge these candidates, and do not call an old rootfs file current.
mango_copy diagnostic-idle-shell /var/mobile/Library/Logs/MangoSuiteDiagnostics/Idle.log
mango_copy diagnostic-world-shell /var/mobile/Library/Logs/MangoSuiteDiagnostics/World.log
mango_copy diagnostic-split-shell /var/mobile/Library/Logs/MangoSuiteDiagnostics/Split.log
mango_copy diagnostic-idle-rootfs /rootfs/var/mobile/Library/Logs/MangoSuiteDiagnostics/Idle.log
mango_copy diagnostic-world-rootfs /rootfs/var/mobile/Library/Logs/MangoSuiteDiagnostics/World.log
mango_copy diagnostic-split-rootfs /rootfs/var/mobile/Library/Logs/MangoSuiteDiagnostics/Split.log
mango_copy legacy-idle-shell /var/mobile/Library/Logs/MangoIdleIsland/Status.log
mango_copy legacy-idle-rootfs /rootfs/var/mobile/Library/Logs/MangoIdleIsland/Status.log
mango_copy legacy-world-shell /var/mobile/Library/Logs/MangoUpsideDownWorld.log
mango_copy legacy-world-rootfs /rootfs/var/mobile/Library/Logs/MangoUpsideDownWorld.log

printf 'END_UTC=%s\nINTERRUPTED=0\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$mango_metadata"
mango_archive=$mango_dir.tar.gz
if tar -czf "$mango_archive" -C "$mango_base" "${mango_dir##*/}"; then
    printf '%s\n' "$mango_archive"
else
    rm -f "$mango_archive"
    printf 'Archive failed; snapshot directory: %s\n' "$mango_dir" >&2
    printf '%s\n' "$mango_dir"
    exit 1
fi
