/// A hand-written TypeScript declaration body for a JavaScript source module.
///
/// Supply the declarations that belong inside the module's ambient
/// `declare module` block. QuickJSKit owns the canonical module specifier and
/// wraps this body when rendering the complete environment.
public struct TypeScriptModuleDeclarations: Sendable, Hashable {
    /// The declaration body, normally containing `export` declarations.
    public let body: String

    /// Creates companion declarations for a source module.
    public init(_ body: String) {
        self.body = body
    }
}
