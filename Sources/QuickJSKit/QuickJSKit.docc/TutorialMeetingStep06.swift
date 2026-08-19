import QuickJSKit
import QuickJSKitMacros

// The macro derives the JavaScript and TypeScript shape from this Swift model.
@JavaScriptExport
struct ProjectLead: Codable, Sendable {
    let id: String
    let name: String
}
