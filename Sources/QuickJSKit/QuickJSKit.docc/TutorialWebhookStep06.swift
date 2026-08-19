import Foundation
import QuickJSKit

enum TenantRuleError: Error {
    case unknownSpecifier(String)
}

func makeTenantRuleLoader(rulesURL: URL) -> JavaScriptModuleLoader {
    let allowedRules = ["rules:acme": rulesURL.appendingPathComponent("acme.js")]
    return JavaScriptModuleLoader(
        resolve: { request in
            // The template already owns this application module.
            if request.specifier == "app:webhook-workflow" {
                return request.specifier
            }
            // Every other allowed specifier is an explicit tenant rule.
            guard allowedRules[request.specifier] != nil else {
                throw TenantRuleError.unknownSpecifier(request.specifier)
            }
            return request.specifier
        },
        load: { request in
            guard let ruleURL = allowedRules[request.specifier] else {
                throw TenantRuleError.unknownSpecifier(request.specifier)
            }
            return JavaScriptModuleSource(
                source: try String(contentsOf: ruleURL, encoding: .utf8),
                sourceURL: ruleURL.absoluteString
            )
        }
    )
}
