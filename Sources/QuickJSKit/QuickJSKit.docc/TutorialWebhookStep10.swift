import Foundation
import QuickJSKit

func writeWebhookWorkspace(
    for environment: JavaScriptRuntimeTemplate
) throws {
    let workspace = try environment.environmentDescription().typeScriptWorkspace(
        options: .init(
            sourceGlobs: ["Rules/**/*.js"],
            checkJavaScript: true,
            includePackageJSON: true
        )
    )
    try workspace.write(
        to: FileManager.default.temporaryDirectory
            .appendingPathComponent("TenantWebhookWorkspace")
    )
}
