/// A request to resolve or load an ES module.
public struct JavaScriptModuleRequest: Sendable, Hashable {
    /// The requested or canonical module specifier.
    public let specifier: String

    /// The canonical importing module, or `nil` for a root import.
    public let referrer: String?

    /// Creates a module request.
    public init(specifier: String, referrer: String?) {
        self.specifier = specifier
        self.referrer = referrer
    }
}

/// JavaScript source returned by a custom module loader.
public struct JavaScriptModuleSource: Sendable, Hashable {
    /// The ES module source text.
    public let source: String

    /// The diagnostic and `import.meta.url` location for the source.
    public let sourceURL: String

    /// Creates loaded module source.
    public init(source: String, sourceURL: String) {
        self.source = source
        self.sourceURL = sourceURL
    }
}

/// A runtime-local resolver and asynchronous ES module source loader.
public struct JavaScriptModuleLoader: Sendable {
    internal let resolveClosure: (@Sendable (JavaScriptModuleRequest) throws -> String)?
    internal let loadClosure: @Sendable (JavaScriptModuleRequest) async throws -> JavaScriptModuleSource

    /// Creates a module loader.
    ///
    /// When `resolve` is `nil`, QuickJSKit applies its portable lexical
    /// resolver. Loading never occurs from inside a QuickJS C callback.
    public init(
        resolve: (@Sendable (JavaScriptModuleRequest) throws -> String)? = nil,
        load: @escaping @Sendable (
            JavaScriptModuleRequest
        ) async throws -> JavaScriptModuleSource
    ) {
        self.resolveClosure = resolve
        self.loadClosure = load
    }
}
