#!/usr/bin/env sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

swift build --package-path "$repository_root/Examples"
swift build --package-path "$repository_root/IntegrationTests/PlatformSmoke"

if [ "${RUN_EXAMPLES:-0}" = "1" ]; then
    for product in \
        TypedEvaluation \
        AsyncHostAPI \
        ModuleEmbedding \
        RuntimeTemplates \
        TypeScriptWorkspace
    do
        swift run --package-path "$repository_root/Examples" "$product"
    done

    swift run \
        --package-path "$repository_root/IntegrationTests/PlatformSmoke" \
        QuickJSKitPlatformSmoke
fi
