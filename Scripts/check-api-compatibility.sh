#!/usr/bin/env sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
baseline_file="$repository_root/.github/api-baseline"

if [ ! -s "$baseline_file" ]; then
    echo "No API baseline has been recorded." >&2
    exit 1
fi

baseline=$(tr -d '[:space:]' < "$baseline_file")
swift package \
    --package-path "$repository_root" \
    diagnose-api-breaking-changes "$baseline"
