# The vcam camera emulator (LGPL, github.com/petabyt/vcam), used only for testing.
# docker build -t vcam-fuji scripts/vcam
FROM debian:13-slim
ARG VCAM_COMMIT=c25376ed6f7b19a2dd430897f8008837f5e1962c
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates git cmake ninja-build gcc g++ \
        pkg-config libusb-1.0-0-dev libexif-dev iproute2 && rm -rf /var/lib/apt/lists/*
RUN git clone https://github.com/petabyt/vcam /vcam && cd /vcam && git checkout $VCAM_COMMIT
WORKDIR /vcam
RUN cmake -G Ninja -B build && cmake --build build
