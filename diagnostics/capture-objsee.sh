#!/bin/sh
# Run on the iPhone, in NewTerm or an interactive SSH session.
# No preference writes, binary patches, or automatic SpringBoard restart.
set -u
umask 077

mango_mode=${1:-}
case "$mango_mode" in
    media|orientation|logs) ;;
    *) printf 'Usage: sh capture-objsee.sh media|orientation|logs\n' >&2; exit 2 ;;
esac
if [ "$#" -ne 1 ]; then
    printf 'Use exactly one mode: media, orientation, or logs.\n' >&2
    exit 2
fi

mango_run() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo -- "$@"
    fi
}

if [ "$(id -u)" -ne 0 ]; then
    if ! command -v sudo >/dev/null 2>&1; then
        printf 'sudo is unavailable. Run from a root shell on the iPhone.\n' >&2
        exit 1
    fi
    sudo -v || exit 1
fi

mango_objsee_bin=$(command -v objsee 2>/dev/null || :)
if [ "$mango_mode" != logs ]; then
    if [ -z "$mango_objsee_bin" ]; then
        printf 'objsee is unavailable. Use mode logs to collect existing logs.\n' >&2
        exit 1
    fi
fi

mango_base=/var/mobile/Documents/MangoSuiteDiagnostics
mkdir -p "$mango_base" || exit 1
mango_dir=$(mktemp -d "$mango_base/$mango_mode-$(date +%Y%m%d-%H%M%S)-XXXXXX") || exit 1
mango_finished=0
mango_interrupted=0

mango_copy() {
    mango_stage=$1
    mango_label=$2
    mango_source=$3
    if mango_run test -f "$mango_source"; then
        if mango_run cat "$mango_source" > "$mango_dir/$mango_stage-$mango_label.log"; then
            printf '%s %s: copied from %s\n' "$mango_stage" "$mango_label" "$mango_source" >> "$mango_dir/metadata.txt"
        else
            printf '%s %s: read failed (%s)\n' "$mango_stage" "$mango_label" "$mango_source" >> "$mango_dir/metadata.txt"
        fi
    else
        printf '%s %s: absent (%s)\n' "$mango_stage" "$mango_label" "$mango_source" >> "$mango_dir/metadata.txt"
    fi
}

mango_collect() {
    # RootHide's shell and a tweak may resolve /var/mobile differently.
    # Keep both candidates distinct; do not infer the active path from existence.
    mango_copy "$1" idle-shell /var/mobile/Library/Logs/MangoIdleIsland/Status.log
    mango_copy "$1" idle-rootfs /rootfs/var/mobile/Library/Logs/MangoIdleIsland/Status.log
    mango_copy "$1" world-shell /var/mobile/Library/Logs/MangoUpsideDownWorld.log
    mango_copy "$1" world-rootfs /rootfs/var/mobile/Library/Logs/MangoUpsideDownWorld.log
}

mango_finish() {
    if [ "$mango_finished" -eq 1 ]; then return; fi
    mango_finished=1
    # A second Ctrl-C must not interrupt the final log copy.
    trap '' INT
    printf 'END=%s\nINTERRUPTED=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$mango_interrupted" >> "$mango_dir/metadata.txt"
    mango_collect after
    printf '\nSaved: %s\n' "$mango_dir"
    if command -v tar >/dev/null 2>&1; then
        if tar -czf "$mango_dir.tar.gz" -C "$mango_base" "${mango_dir##*/}"; then
            printf 'Archive: %s.tar.gz\n' "$mango_dir"
        else
            printf 'Archive failed; the directory above still contains the logs.\n' >&2
        fi
    fi
    if [ "$mango_mode" != logs ]; then
        printf 'After saving these files, respring before another objsee capture.\n'
        printf 'Stopping the collector does not instantly unload the injected tracer.\n'
    fi
}

trap 'mango_interrupted=1' INT
trap mango_finish 0

{
    printf 'SCRIPT_REVISION=2\nMODE=%s\nSTART=%s\n' "$mango_mode" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    uname -sr
    if command -v dpkg-query >/dev/null 2>&1; then
        dpkg-query -W -f='${Package}\t${Version}\n' \
            com.go.mango com.chenxun.mangosuite com.chenxun.mangosuite.helper 2>&1
    fi
    if [ -n "$mango_objsee_bin" ]; then
        printf 'OBJSEE=%s\n' "$mango_objsee_bin"
        "$mango_objsee_bin" -v 2>&1
    fi
} > "$mango_dir/metadata.txt"

cat > "$mango_dir/notes.txt" <<'NOTES'
Fill in after reproduction (Chinese is fine):
Player used, if media capture:
Approximate seconds from capture start when the problem occurred:
Actions immediately before the problem:
Launcher upright while Home/Lock Screen remained upside down: yes/no/not observed
Island up-swipe result after the problem:
Island down-swipe result after the problem:
Problem reproduced during this capture: yes/no
Matching screen recording filename, if available:
NOTES

mango_collect before
if [ "$mango_mode" = logs ]; then
    exit 0
fi

# Older objsee CLIs emit one OR filter per -c/-m/-i argument; newer CLIs merge
# adjacent fields. Use only class filters so both parsers keep a bounded scope.
# Relevant selectors are selected from the collected class trace afterwards.
set -- -p SpringBoard --nocolor -A0
case "$mango_mode" in
    orientation)
        set -- "$@" \
            -c ViewController \
            -c MangoPillManager \
            -c DecoratedAppSceneView \
            -c DecoratedFloatingView \
            -c SBSystemApertureWindow \
            -c SBSystemApertureViewController
        ;;
    media)
        set -- "$@" \
            -c SBSystemApertureContainerView \
            -c _SBSystemApertureContainerViewContentView \
            -c 'SAUI*' \
            -c MGLiveBackdropView
        ;;
esac

printf 'Starting objsee attachment for %s. Startup errors are saved below.\n' "$mango_mode"
printf 'If the collector stays running, reproduce once, then press Ctrl-C.\n'
printf 'If it does not reproduce within about 60 seconds, stop anyway.\n'
printf 'Trace file: %s/objsee.log\n' "$mango_dir"
printf 'TRACE_START=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$mango_dir/metadata.txt"
mango_run "$mango_objsee_bin" "$@" > "$mango_dir/objsee.log" 2>&1
mango_status=$?
printf 'OBJSEE_EXIT=%s\n' "$mango_status" >> "$mango_dir/metadata.txt"
if [ "$mango_status" -ne 0 ] && [ "$mango_interrupted" -eq 0 ]; then
    printf 'objsee exited early. Send this archive; do not repeat attachment yet.\n' >&2
fi
exit "$mango_status"
