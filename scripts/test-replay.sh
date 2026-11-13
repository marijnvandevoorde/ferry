#!/bin/bash
# Records a diagnostics file (ferryctl --trace) from each emulated camera, replays it with scripts/mock-cameras/replay.py,
# and checks that importing from the replay gives the same file names and sizes.
#
# Fujifilm and Canon (PTP/IP) need Docker and the vcam image (VCAM_IMAGE, default vcam-fuji); skipped without Docker.
# Olympus, Ricoh, GoPro and DLNA use the mock cameras in scripts/mock-cameras.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -q --product ferryctl
FERRYCTL=$(swift build --show-bin-path)/ferryctl
IMAGE=${VCAM_IMAGE:-vcam-fuji}
WORK=$(mktemp -d)
PIDS=()
cleanup() {
    kill "${PIDS[@]}" 2>/dev/null || true
    docker rm -f fujikit-vcam >/dev/null 2>&1 || true
    rm -rf "$WORK"
}
trap cleanup EXIT

# Same file names and sizes in both folders.
same() {
    diff <(cd "$1" && find . -type f | sort | xargs -I{} sh -c 'echo "{} $(wc -c < "{}")"') \
         <(cd "$2" && find . -type f | sort | xargs -I{} sh -c 'echo "{} $(wc -c < "{}")"')
}

card() {
    mkdir -p "$1"
    head -c 2500000 /dev/urandom > "$1/P0000001.JPG"
    head -c 9353 /dev/urandom > "$1/P0000002.JPG"
}

for kind in olympus ricoh gopro dlna; do
    card "$WORK/$kind/DCIM/100CARD"
    port=$((18000 + RANDOM % 1000))
    python3 -I scripts/mock-cameras/server.py $kind $port "$WORK/$kind" & PID=$!; PIDS+=($PID); disown
    sleep 1
    host=127.0.0.1:$port; [ $kind = dlna ] && host=http://127.0.0.1:$port/DmsDesc.xml
    "$FERRYCTL" --host "$host" --protocol $kind --quiet --trace "$WORK/$kind.json" --history "$WORK/$kind-1.json" \
        --folders "" import "$WORK/$kind-recorded" > /dev/null 2>&1
    kill $PID
    sleep 0.3
    python3 -I scripts/mock-cameras/replay.py "$WORK/$kind.json" --port $port > "$WORK/$kind-replay.log" 2>&1 & PID=$!; PIDS+=($PID); disown
    sleep 1
    "$FERRYCTL" --host "$host" --protocol $kind --quiet --history "$WORK/$kind-2.json" \
        --folders "" import "$WORK/$kind-replayed" > "$WORK/$kind-replayed.log" 2>&1 || { echo "$kind: replay import failed"; cat "$WORK/$kind-replayed.log"; exit 1; }
    kill $PID
    same "$WORK/$kind-recorded" "$WORK/$kind-replayed" || { echo "$kind: replay differs"; exit 1; }
    echo "$kind: ok ($(ls "$WORK/$kind-replayed" | wc -l | tr -d ' ') files)"
done

if ! docker image inspect "$IMAGE" > /dev/null 2>&1; then
    echo "fuji, ptpip: skipped (no Docker image $IMAGE)"
    exit 0
fi

for model in fuji_x_t20 canon_r; do
    proto=fuji ports=55740-55742:55740-55742
    [[ $model == canon_* ]] && proto=ptpip ports=15740:15740
    card "$WORK/$model/DCIM/100CARD"
    docker rm -f fujikit-vcam > /dev/null 2>&1 || true
    docker run -d --name fujikit-vcam -p $ports -v "$WORK/$model:/card" "$IMAGE" \
        stdbuf -oL build/vcam $model tcp --local-ip --fs /card > /dev/null
    for _ in $(seq 50); do docker logs fujikit-vcam 2>&1 | grep -q "listening on port" && break; sleep 0.2; done
    sleep 0.5
    "$FERRYCTL" --host 127.0.0.1 --protocol $proto --quiet --trace "$WORK/$model.json" --history "$WORK/$model-1.json" \
        --folders "" import "$WORK/$model-recorded" > /dev/null 2>&1
    docker rm -f fujikit-vcam > /dev/null
    python3 -I scripts/mock-cameras/replay.py "$WORK/$model.json" > "$WORK/$model-replay.log" 2>&1 & PID=$!; PIDS+=($PID); disown
    sleep 1
    "$FERRYCTL" --host 127.0.0.1 --protocol $proto --quiet --history "$WORK/$model-2.json" \
        --folders "" import "$WORK/$model-replayed" > "$WORK/$model-replayed.log" 2>&1 || { echo "$model: replay import failed"; cat "$WORK/$model-replayed.log"; exit 1; }
    kill $PID
    [ -n "$(ls "$WORK/$model-recorded")" ] || { echo "$model: nothing recorded"; exit 1; }
    same "$WORK/$model-recorded" "$WORK/$model-replayed" || { echo "$model: replay differs"; exit 1; }
    echo "$model: ok ($(ls "$WORK/$model-replayed" | wc -l | tr -d ' ') files)"
done
