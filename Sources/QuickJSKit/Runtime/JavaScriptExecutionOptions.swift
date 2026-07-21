/// Controls one contiguous period of JavaScript execution.
///
/// Time spent suspended in Swift asynchronous work is not part of an execution
/// timeout. Use Swift task cancellation when an end-to-end deadline is needed.
public struct JavaScriptExecutionOptions: Sendable, Hashable {
    /// Selects the timeout applied to an operation.
    public enum Timeout: Sendable, Hashable {
        /// Uses the default configured by the runtime.
        case runtimeDefault

        /// Disables the runtime default for this operation.
        case disabled

        /// Interrupts active JavaScript after the supplied duration.
        ///
        /// A non-positive duration interrupts immediately.
        case after(Duration)
    }

    /// The timeout policy for this operation.
    public var timeout: Timeout

    /// Creates execution options.
    public init(timeout: Timeout = .runtimeDefault) {
        self.timeout = timeout
    }
}
