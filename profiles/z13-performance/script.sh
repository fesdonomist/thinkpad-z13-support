#!/bin/sh
Z13_TUNED_PROFILE=z13-performance
export Z13_TUNED_PROFILE

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec "$SCRIPT_DIR/../z13-balanced/script.sh" "$@"
