#!/usr/bin/env sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output_directory=${1:-"$repository_root/.build/symbol-graphs"}
scratch_directory=$(mktemp -d "${TMPDIR:-/tmp}/quickjskit-symbolgraph.XXXXXX")
symbol_graph_log=$(mktemp "${TMPDIR:-/tmp}/quickjskit-symbolgraph.XXXXXX.log")

cleanup() {
    rm -rf "$scratch_directory" "$symbol_graph_log"
}

trap cleanup EXIT

symbol_graph_failed=false
if ! swift package \
    --package-path "$repository_root" \
    --scratch-path "$scratch_directory" \
    dump-symbol-graph \
    --minimum-access-level public >"$symbol_graph_log" 2>&1
then
    symbol_graph_failed=true
fi

core_graph=$(find "$scratch_directory" \
    -type f -name 'QuickJSKit.symbols.json' -print -quit)
macro_graph=$(find "$scratch_directory" \
    -type f -name 'QuickJSKitMacros.symbols.json' -print -quit)

if [ -z "$core_graph" ] || [ -z "$macro_graph" ]; then
    cat "$symbol_graph_log" >&2
    echo "SwiftPM did not produce both public product symbol graphs." >&2
    exit 1
fi

if [ "$symbol_graph_failed" = true ]; then
    echo "SwiftPM reported a non-public symbol graph failure; validating the public product graphs." >&2
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
