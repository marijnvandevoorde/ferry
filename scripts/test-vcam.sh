#!/bin/bash
# Runs fujictl against every Fuji model the vcam emulator knows and checks that downloads are byte-identical.
#
# Needs Docker and a vcam image (see README): VCAM_IMAGE=vcam-fuji scripts/test-vcam.sh [model...]
set -euo pipefail

IMAGE=${VCAM_IMAGE:-vcam-fuji}
MODELS=("$@")
[ ${#MODELS[@]} -eq 0 ] && MODELS=(fuji_x_a2 fuji_x30 fuji_x_f10 fuji_x_t2 fuji_x_t4 fuji_x_t20 fuji_x_t30 fuji_x_s10 fuji_x_h1 fuji_gfx100_ii)

cd "$(dirname "$0")/.."
swift build -q --product fujictl
FUJICTL=$(swift build --show-bin-path)/fujictl

WORK=$(mktemp -d)
trap 'docker rm -f fujikit-vcam >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT

# A card with files of different sizes, including some that need several 1 MB chunks.
CARD=$WORK/card/DCIM/100_FUJI
mkdir -p "$CARD"
head -c 2500000 /dev/urandom > "$CARD/DSCF0001.JPG"
head -c 9353 /dev/urandom > "$CARD/DSCF0002.JPG"
head -c 1048576 /dev/urandom > "$CARD/DSCF0003.JPG"
head -c 1000 /dev/urandom > "$CARD/DSCF0004.JPG"
# vcam lists folders as objects but leaves one entry out of the object count, so one file is never listed.
EXPECTED=$(( $(ls "$CARD" | wc -l) - 1 ))

start_vcam() {
    docker rm -f fujikit-vcam >/dev/null 2>&1 || true
    docker run -d --name fujikit-vcam -p 55740-55742:55740-55742 -v "$WORK/card:/card" "$IMAGE" \
        build/vcam "$1" tcp --local-ip --fs /card "${@:2}" >/dev/null
    for _ in $(seq 50); do
        nc -z 127.0.0.1 55740 2>/dev/null && return 0
        sleep 0.2
    done
    echo "vcam did not start"; docker logs fujikit-vcam | tail -20; return 1
}

failed=()
for model in "${MODELS[@]}"; do
    printf '%-16s ' "$model"
    start_vcam "$model"
    out=$WORK/out-$model
    if ! "$FUJICTL" --host 127.0.0.1 --quiet download "$out" > "$WORK/$model.log" 2>&1; then
        echo "FAIL (fujictl)"; tail -5 "$WORK/$model.log"; failed+=("$model"); continue
    fi
    ok=1
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
