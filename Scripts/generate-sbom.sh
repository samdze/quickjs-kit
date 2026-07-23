#!/usr/bin/env sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output=${1:-"$repository_root/.build/quickjskit.spdx"}
revision=$(git -C "$repository_root" rev-parse HEAD)
created=$(git -C "$repository_root" show -s --format=%cI HEAD)
quickjs_version=$(tr -d '\r\n' < "$repository_root/Sources/CQuickJS/VERSION")
quickjs_checksum=$(sed -n \
    's/.*"archiveSHA256": "\([^"]*\)".*/\1/p' \
    "$repository_root/Sources/CQuickJS/UPSTREAM.json")
swift_syntax_version=$(sed -n \
    '/"identity" : "swift-syntax"/,/}/s/.*"version" : "\([^"]*\)".*/\1/p' \
    "$repository_root/Package.resolved")

mkdir -p "$(dirname -- "$output")"

{
    printf '%s\n' 'SPDXVersion: SPDX-2.3'
    printf '%s\n' 'DataLicense: CC0-1.0'
    printf '%s\n' 'SPDXID: SPDXRef-DOCUMENT'
    printf '%s\n' 'DocumentName: QuickJSKit'
    printf 'DocumentNamespace: https://github.com/samdze/quickjs-kit/spdx/%s\n' "$revision"
    printf '%s\n' 'Creator: Tool: QuickJSKit-generate-sbom'
    printf 'Created: %s\n\n' "$created"

    printf '%s\n' 'PackageName: QuickJSKit'
    printf '%s\n' 'SPDXID: SPDXRef-Package-QuickJSKit'
    printf '%s\n' 'PackageVersion: pre-release'
    printf '%s\n' 'PackageDownloadLocation: NOASSERTION'
    printf '%s\n' 'FilesAnalyzed: false'
    printf '%s\n\n' 'PackageLicenseDeclared: MIT'

    printf '%s\n' 'PackageName: QuickJS'
    printf '%s\n' 'SPDXID: SPDXRef-Package-QuickJS'
    printf 'PackageVersion: %s\n' "$quickjs_version"
    printf '%s\n' 'PackageDownloadLocation: https://bellard.org/quickjs/'
    printf '%s\n' 'FilesAnalyzed: false'
    printf '%s\n' 'PackageLicenseDeclared: MIT'
    printf 'PackageChecksum: SHA256: %s\n\n' "$quickjs_checksum"

    printf '%s\n' 'PackageName: SwiftSyntax'
    printf '%s\n' 'SPDXID: SPDXRef-Package-SwiftSyntax'
    printf 'PackageVersion: %s\n' "$swift_syntax_version"
    printf '%s\n' 'PackageDownloadLocation: https://github.com/swiftlang/swift-syntax'
    printf '%s\n' 'FilesAnalyzed: false'
    printf '%s\n\n' 'PackageLicenseDeclared: Apache-2.0'

    printf '%s\n' 'Relationship: SPDXRef-DOCUMENT DESCRIBES SPDXRef-Package-QuickJSKit'
    printf '%s\n' 'Relationship: SPDXRef-Package-QuickJSKit DEPENDS_ON SPDXRef-Package-QuickJS'
    printf '%s\n' 'Relationship: SPDXRef-Package-QuickJSKit DEPENDS_ON SPDXRef-Package-SwiftSyntax'
} > "$output"

echo "Wrote SPDX SBOM to $output"
