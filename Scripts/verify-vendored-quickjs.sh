#!/usr/bin/env sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
vendor_directory="$repository_root/Sources/CQuickJS"

cd "$vendor_directory"

if command -v sha256sum >/dev/null 2>&1; then
    sha256sum --check CHECKSUMS.sha256
elif command -v shasum >/dev/null 2>&1; then
    shasum --algorithm 256 --check CHECKSUMS.sha256
else
    echo "No SHA-256 verification tool is available." >&2
    exit 1
fi

expected_version=$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' UPSTREAM.json)
actual_version=$(tr -d '\r\n' < VERSION)

if [ "$actual_version" != "$expected_version" ]; then
    echo "QuickJS version does not match UPSTREAM.json." >&2
    exit 1
fi

echo "Vendored QuickJS $actual_version verified."
