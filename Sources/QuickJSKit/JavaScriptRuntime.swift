/// An isolated JavaScript engine and its associated object heap.
///
/// `JavaScriptRuntime` is an actor because QuickJS does not permit concurrent
/// access to a runtime. Actor isolation serializes every engine operation and
/// makes the public API safe to use from concurrent Swift tasks.
///
/// Create a runtime, then call its methods with `await` from outside the actor:
///
/// ```swift
/// let runtime = try JavaScriptRuntime()
/// let value = try await runtime.evaluate("21 * 2")
/// ```
///
/// The runtime owns all JavaScript state created inside it. Values currently
/// returned by ``evaluate(_:sourceURL:)`` are detached Swift primitives and may
/// safely cross isolation boundaries. Live JavaScript object handles will stay
/// bound to their originating runtime in future releases.
public actor JavaScriptRuntime {
    /// Resource limits applied when a runtime is created.
    ///
    /// Limits are expressed in bytes and are enforced by QuickJS. A `nil`
    /// value uses the engine default. Configuration has value semantics and is
    /// safe to share between tasks.
    public struct Configuration: Sendable, Hashable {
        /// The maximum number of bytes the JavaScript heap may allocate.
        public var memoryLimit: UInt64?

        /// The maximum number of bytes available to the JavaScript stack.
        public var maximumStackSize: UInt64?

        /// Creates a runtime configuration.
        ///
        /// - Parameters:
        ///   - memoryLimit: Maximum heap allocation in bytes, or `nil` for the
        ///     engine default.
        ///   - maximumStackSize: Maximum JavaScript stack size in bytes, or
        ///     `nil` for the engine default.
        public init(
            memoryLimit: UInt64? = nil,
            maximumStackSize: UInt64? = nil
        ) {
            self.memoryLimit = memoryLimit
            self.maximumStackSize = maximumStackSize
        }
    }

    /// The immutable configuration used to create this runtime.
    public nonisolated let configuration: Configuration

    private let engine: QuickJSEngine

    /// Creates an isolated JavaScript runtime.
    ///
    /// Runtime creation performs a small fixed amount of allocation. No worker
    /// thread is created; work runs on the actor's current Swift executor.
    ///
    /// - Parameter configuration: Resource limits for the new runtime.
    /// - Throws: ``JavaScriptError`` when a limit cannot be represented on the
    ///   current platform or QuickJS cannot allocate its runtime or context.
    public init(configuration: Configuration = Configuration()) throws {
        self.configuration = configuration
        self.engine = try QuickJSEngine(configuration: configuration)
    }

    /// Evaluates a JavaScript script in this runtime's global context.
    ///
    /// Evaluation is synchronous while isolated to the actor. Calling it from
    /// another isolation domain therefore requires `await`, but it does not
    /// create an unstructured task or dispatch to a hidden thread.
    ///
    /// Phase 1 supports detached primitive results: `undefined`, `null`,
    /// booleans, numbers, and strings. Returning another JavaScript value kind
    /// currently produces a conversion error.
    ///
    /// - Parameters:
    ///   - source: UTF-8 JavaScript source code.
    ///   - sourceURL: A diagnostic filename shown in JavaScript stack traces.
    /// - Returns: A detached, concurrency-safe Swift representation.
    /// - Throws: ``JavaScriptError`` for syntax errors, thrown JavaScript
    ///   exceptions, allocation failures, or unsupported result kinds.
    public func evaluate(
        _ source: String,
        sourceURL: String = "<eval>"
    ) throws -> JavaScriptValue {
        try engine.evaluate(source, sourceURL: sourceURL)
    }
}
