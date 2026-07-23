#!/usr/bin/env sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output_directory=${1:-"$repository_root/.build/symbol-graphs"}

swift package \
    --package-path "$repository_root" \
    dump-symbol-graph \
    --minimum-access-level public

core_graph=$(find "$repository_root/.build" \
    -type f -name 'QuickJSKit.symbols.json' -print | head -n 1)
macro_graph=$(find "$repository_root/.build" \
    -type f -name 'QuickJSKitMacros.symbols.json' -print | head -n 1)

if [ -z "$core_graph" ] || [ -z "$macro_graph" ]; then
    echo "SwiftPM did not produce both public product symbol graphs." >&2
    exit 1
fi

mkdir -p "$output_directory"
cp "$core_graph" "$output_directory/QuickJSKit.symbols.json"
cp "$macro_graph" "$output_directory/QuickJSKitMacros.symbols.json"

if grep -R -E \
    '"(CQuickJS|JSRuntime|JSContext|JSValue|JSAtom|OpaquePointer)"' \
    "$output_directory"
then
    echo "A CQuickJS declaration leaked into a public symbol graph." >&2
    exit 1
fi

if command -v jq >/dev/null 2>&1; then
    undocumented=$(jq -r '
        .symbols[]
        | select(.accessLevel == "public")
        | select(.docComment == null)
        | select(.identifier.precise | contains("::SYNTHESIZED::") | not)
        | .names.title
    ' "$output_directory/QuickJSKit.symbols.json" \
        "$output_directory/QuickJSKitMacros.symbols.json")
    if [ -n "$undocumented" ]; then
        echo "Undocumented public symbols:" >&2
        echo "$undocumented" >&2
        exit 1
    fi
fi

echo "Public symbol graphs contain no QuickJS C declarations."
