#!/usr/bin/env sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
duration=${1:-60}
artifact_directory="$repository_root/Fuzzing/.build"

swift build \
    --package-path "$repository_root/Fuzzing" \
    --configuration release \
    --scratch-path "$artifact_directory" \
    -Xswiftc -sanitize=fuzzer,address

binary=$(swift build \
    --package-path "$repository_root/Fuzzing" \
    --configuration release \
    --scratch-path "$artifact_directory" \
    --show-bin-path)

"$binary/QuickJSKitFuzzer" \
    "$repository_root/Fuzzing/Corpus/evaluation" \
    "$repository_root/Fuzzing/Corpus/modules" \
    "$repository_root/Fuzzing/Corpus/declarations" \
    -max_total_time="$duration" \
    -timeout=10
