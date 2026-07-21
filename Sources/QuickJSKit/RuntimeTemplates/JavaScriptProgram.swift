/// An immutable JavaScript script that can be compiled once and reused.
///
/// A program keeps canonical source and diagnostic identity, never QuickJS
/// heap state. Preparing it in a runtime installs an independent compiled
/// function in that runtime's heap. Copies of the same program value preserve
/// identity and share the corresponding runtime-local compilation entry.
public struct JavaScriptProgram: Sendable {
    /// The canonical JavaScript source.
    public let source: String

    /// The filename used in JavaScript diagnostics and stack traces.
    public let sourceURL: String

    internal let identity: JavaScriptProgramIdentity

    /// Creates a reusable JavaScript program.
    ///
    /// Construction does not parse or execute source. A runtime or runtime
    /// template performs compilation when the program is prepared.
    ///
    /// - Parameters:
    ///   - source: JavaScript source evaluated as a global script.
    ///   - sourceURL: The filename preserved in diagnostics and stack traces.
    public init(
        _ source: String,
        sourceURL: String = "<program>"
    ) {
        self.source = source
        self.sourceURL = sourceURL
        self.identity = JavaScriptProgramIdentity()
    }
}

internal final class JavaScriptProgramIdentity: Sendable {}
