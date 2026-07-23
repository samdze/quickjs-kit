#!/usr/bin/env sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture="$repository_root/Tests/TypeScriptIntegration"

cd "$fixture"
npm ci --ignore-scripts
npm exec -- tsc --project tsconfig.json
node validate-tsdoc.mjs
