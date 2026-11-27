#!/bin/sh
# Installs the Ferry .deb in a clean Ubuntu container, with only the packages it depends on,
# and checks that ferryctl starts: a shared library it links but the .deb doesn't depend on fails here.
#   scripts/check-deb.sh <Ferry .deb>
set -eu
deb=$(realpath "$1")
docker run --rm -v "$deb:/ferry.deb:ro" ubuntu:24.04 sh -c '
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq >/dev/null
  apt-get install -y -qq --no-install-recommends /ferry.deb >/dev/null
  ferryctl --version'
