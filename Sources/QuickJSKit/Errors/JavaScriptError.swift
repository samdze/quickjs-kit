/// A structured failure produced while embedding or executing JavaScript.
///
/// The error contains only owned Swift data, so it can cross concurrency
/// boundaries safely. When QuickJS supplies a JavaScript error object, its name,
/// message, and stack trace are copied before the engine value is released.
public struct JavaScriptError: Error, Sendable, Equatable, CustomStringConvertible {
    /// A stable category for a JavaScript integration failure.
    public enum Kind: String, Sendable, Hashable {
        /// JavaScript source could not be parsed.
        case syntax

        /// The host runtime could not complete an engine operation.
        case runtime

        /// JavaScript execution threw a value.
        case exception

        /// Execution exceeded a configured deadline.
        case timeout

        /// Swift task cancellation interrupted execution.
        case cancelled

        /// Module resolution, loading, or linking failed.
        case module

        /// A host-provided interrupt handler stopped execution.
        case interrupted

        /// A synchronous operation encountered work that must suspend.
        case wouldSuspend

        /// A Swift or JavaScript value could not be converted.
        case conversion

        /// A configured memory, stack, or other resource limit was reached.
        case resourceLimit

        /// An invariant failed inside QuickJSKit.
        case internalFailure
    }

    /// The broad failure category.
    public let kind: Kind

    /// The JavaScript error constructor name, such as `TypeError`, when known.
    public let name: String?

    /// A human-readable explanation of the failure.
    public let message: String

    /// The JavaScript stack trace, when supplied by the engine.
    public let stack: String?

    /// The diagnostic source name associated with evaluation, when known.
    public let sourceURL: String?

    internal init(
        kind: Kind,
        name: String? = nil,
        message: String,
        stack: String? = nil,
        sourceURL: String? = nil
    ) {
        self.kind = kind
        self.name = name
        self.message = message
        self.stack = stack
        self.sourceURL = sourceURL
    }

    /// A concise description that includes the JavaScript error name when one
    /// is available.
    public var description: String {
        if let name {
            return "\(name): \(message)"
        }
        return message
    }

    internal func withSourceURL(_ sourceURL: String?) -> JavaScriptError {
        JavaScriptError(
            kind: kind,
            name: name,
            message: message,
            stack: stack,
            sourceURL: sourceURL ?? self.sourceURL
        )
    }
}
