/// A live JavaScript function bound to its originating runtime.
public struct JavaScriptFunction: Sendable, Hashable {
    internal let reference: JavaScriptReference

    internal init(reference: JavaScriptReference) {
        self.reference = reference
    }

    /// The general JavaScript value representing this function.
    public var value: JavaScriptValue { JavaScriptValue(reference: reference) }

    /// This function viewed as a JavaScript object.
    public var object: JavaScriptObject { JavaScriptObject(reference: reference) }

    /// Calls the function with heterogeneous encodable arguments.
    public func call<each Argument>(
        _ arguments: repeat each Argument,
        options: JavaScriptExecutionOptions = .init()
    ) async throws -> JavaScriptValue
    where repeat each Argument: Encodable,
          repeat each Argument: Sendable {
        try await reference.runtime.call(
            reference,
            arguments: repeat each arguments,
            options: options
        )
    }

    /// Calls the function and directly decodes its result.
    public func call<each Argument, Result>(
        _ arguments: repeat each Argument,
        as type: Result.Type = Result.self,
        options: JavaScriptExecutionOptions = .init()
    ) async throws -> Result
    where repeat each Argument: Encodable,
          repeat each Argument: Sendable,
          Result: Decodable & Sendable {
        try await reference.runtime.call(
            reference,
            arguments: repeat each arguments,
            as: type,
            options: options
        )
    }

    /// Calls the function with an explicit JavaScript `this` receiver.
    public func call<each Argument, Result>(
        on receiver: JavaScriptObject,
        _ arguments: repeat each Argument,
        as type: Result.Type = Result.self,
        options: JavaScriptExecutionOptions = .init()
    ) async throws -> Result
    where repeat each Argument: Encodable,
          repeat each Argument: Sendable,
          Result: Decodable & Sendable {
        try await reference.runtime.call(
            reference,
            on: receiver.reference,
            arguments: repeat each arguments,
            as: type,
            options: options
        )
    }

    /// Calls the function with existing JavaScript values.
    public func call(
        arguments: [JavaScriptValue],
        this receiver: JavaScriptObject? = nil,
        options: JavaScriptExecutionOptions = .init()
    ) async throws -> JavaScriptValue {
        try await reference.runtime.call(
            reference,
            arguments: arguments,
            receiver: receiver?.reference,
            options: options
        )
    }
}
