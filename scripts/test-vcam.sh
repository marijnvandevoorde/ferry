#!/bin/bash
# Runs ferryctl against every model the vcam emulator knows (Fuji, and Canon over PTP/IP) and checks that downloads are byte-identical.
#
# Needs Docker and a vcam image (see README): VCAM_IMAGE=vcam-fuji scripts/test-vcam.sh [model...]
set -euo pipefail

IMAGE=${VCAM_IMAGE:-vcam-fuji}
MODELS=("$@")
[ ${#MODELS[@]} -eq 0 ] && MODELS=(fuji_x_a2 fuji_x30 fuji_x_f10 fuji_x_t2 fuji_x_t4 fuji_x_t20 fuji_x_t30 fuji_x_s10 fuji_x_h1 fuji_gfx100_ii
    fuji_gfx100_ii+bluetooth
    canon_r canon_90d canon_5d3 canon_200d canon_g7x3)
# vcam's Nikon and Sony models only support USB so far.
# "+bluetooth" connects as after a Bluetooth hand-off, which puts newer cameras in the XApp gallery.

cd "$(dirname "$0")/.."
swift build -q --product ferryctl
FUJICTL=$(swift build --show-bin-path)/ferryctl

WORK=$(mktemp -d)
trap 'docker rm -f fujikit-vcam >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT

# A card with files of different sizes, including some that need several 1 MB chunks.
CARD=$WORK/card/DCIM/100_FUJI
mkdir -p "$CARD"
head -c 2500000 /dev/urandom > "$CARD/DSCF0001.JPG"
head -c 9353 /dev/urandom > "$CARD/DSCF0002.JPG"
head -c 1048576 /dev/urandom > "$CARD/DSCF0003.JPG"
head -c 1000 /dev/urandom > "$CARD/DSCF0004.JPG"
FILES=$(ls "$CARD" | wc -l)

start_vcam() {
    docker rm -f fujikit-vcam >/dev/null 2>&1 || true
    # Publish only the model's own port: Docker accepts connections on published ports even when nothing
    # listens behind them, which would hide the "connection refused" that protocol detection relies on.
    local port=15740 ports=15740:15740
    [[ $1 == fuji_* ]] && port=55740 ports=55740-55742:55740-55742
    docker run -d --name fujikit-vcam -p $ports -v "$WORK/card:/card" "$IMAGE" \
        stdbuf -oL build/vcam "$1" tcp --local-ip --fs /card "${@:2}" >/dev/null
    for _ in $(seq 50); do
        # vcam's PTP/IP server accepts a single connection, so don't probe it; wait for its log line.
        if [[ $1 == fuji_* ]]; then
            nc -z 127.0.0.1 $port 2>/dev/null && return 0
        else
            docker logs fujikit-vcam 2>&1 | grep -q "listening on port" && sleep 0.3 && return 0
        fi
        sleep 0.2
    done
    echo "vcam did not start"; docker logs fujikit-vcam | tail -20; return 1
}

failed=()
for model in "${MODELS[@]}"; do
    printf '%-26s ' "$model"
    extra=()
    [[ $model == *+bluetooth ]] && extra=(--bluetooth)
    start_vcam "${model%+bluetooth}"
    out=$WORK/out-$model
    if ! "$FUJICTL" --host 127.0.0.1 --quiet ${extra[@]+"${extra[@]}"} download "$out" > "$WORK/$model.log" 2>&1; then
        echo "FAIL (ferryctl)"; tail -5 "$WORK/$model.log"; failed+=("$model"); continue
    fi
    ok=1
    # vcam's Fuji mode lists folders as objects but leaves one entry out of the count, so one file is never listed.
    EXPECTED=$FILES
    # The XApp gallery lists every file.
    [[ $model == fuji_* && $model != *+bluetooth ]] && EXPECTED=$((FILES - 1))
    got=$(ls "$out" | wc -l)
    [ "$got" -eq "$EXPECTED" ] || { ok=0; echo "FAIL (downloaded $got files, expected $EXPECTED)"; }
    for f in "$out"/*; do
        cmp -s "$f" "$CARD/$(basename "$f")" || { ok=0; echo "FAIL ($(basename "$f") differs)"; }
    done
    if [ $ok = 1 ]; then echo "ok"; else failed+=("$model"); fi
done

if [ ${#failed[@]} -gt 0 ]; then
    echo "Failed: ${failed[*]}"
    exit 1
fi
