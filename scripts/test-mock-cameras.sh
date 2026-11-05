#!/bin/bash
# Imports from mock Olympus, Ricoh, GoPro and DLNA (Sony/Panasonic) cameras (scripts/mock-cameras) and checks the files are byte-identical.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -q --product ferryctl
FUJICTL=$(swift build --show-bin-path)/ferryctl
WORK=$(mktemp -d)
PIDS=()
trap 'kill "${PIDS[@]}" 2>/dev/null || true; rm -rf "$WORK"' EXIT

for kind in olympus ricoh gopro dlna; do
    folder=100OLYMP; [ $kind = ricoh ] && folder=100RICOH; [ $kind = dlna ] && folder=100MSDCF; [ $kind = gopro ] && folder=100GOPRO
    CARD=$WORK/$kind/DCIM/$folder
    mkdir -p "$CARD"
    head -c 2500000 /dev/urandom > "$CARD/P0000001.JPG"
    head -c 9353 /dev/urandom > "$CARD/P0000002.JPG"
    if [ $kind = gopro ]; then for i in 1 2 3; do head -c 40000 /dev/urandom > "$CARD/G001000$i.JPG"; done; fi
    port=$((18000 + RANDOM % 1000))
    python3 -I scripts/mock-cameras/server.py $kind $port "$WORK/$kind" & PIDS+=($!); disown
    sleep 1
    host=127.0.0.1:$port; [ $kind = dlna ] && host=http://127.0.0.1:$port/DmsDesc.xml
    "$FUJICTL" --host $host --protocol $kind --quiet --history "$WORK/$kind.json" --folders "" import "$WORK/out-$kind" > /dev/null
    for f in "$CARD"/*; do cmp -s "$f" "$WORK/out-$kind/$(basename "$f")" || { echo "$kind: $(basename "$f") differs"; exit 1; }; done
    echo "$kind: ok"
done
