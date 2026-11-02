#!/bin/bash
# Tests PC AutoSave registration and import against vcam. Needs Docker Desktop and the vcam image (see README).
set -euo pipefail
cd "$(dirname "$0")/.."
docker build -q -t vcam-fuji-autosave --build-arg VCAM_IMAGE="${VCAM_IMAGE:-vcam-fuji}" scripts/vcam-autosave >/dev/null
swift build -q --product fujictl
FUJICTL=$(swift build --show-bin-path)/fujictl

WORK=$(mktemp -d)
trap 'docker rm -f fujikit-vcam >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT
CARD=$WORK/card/DCIM/100_FUJI
mkdir -p "$CARD"
head -c 2500000 /dev/urandom > "$CARD/DSCF0001.JPG"
head -c 9353 /dev/urandom > "$CARD/DSCF0002.JPG"
head -c 1000 /dev/urandom > "$CARD/DSCF0003.JPG"

run() {
    docker rm -f fujikit-vcam >/dev/null 2>&1 || true
    # Ports of a container that was just removed can take a moment to be released.
    for _ in $(seq 10); do
        docker run -d --name fujikit-vcam --cap-add NET_ADMIN -e MODE="$1" -p 51540:51540 -p 55740-55742:55740-55742 \
            -v "$WORK/card:/card" vcam-fuji-autosave >/dev/null 2>&1 && break
        docker rm -f fujikit-vcam >/dev/null 2>&1 || true
        sleep 1
    done
    sleep 3
}

run --register
"$FUJICTL" --host 127.0.0.1 --quiet autosave register | grep -q "Registered with VCAM" && echo "register: ok"

run --discovery
"$FUJICTL" --host 127.0.0.1 --quiet --history "$WORK/history.json" --folders "" autosave "$WORK/out" > /dev/null
for f in "$WORK/out"/*; do cmp -s "$f" "$CARD/$(basename "$f")" || { echo "import: $(basename "$f") differs"; exit 1; }; done
echo "import: ok ($(ls "$WORK/out" | wc -l | tr -d ' ') files)"
