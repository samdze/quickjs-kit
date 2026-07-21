/// A transactional collection of exports for a Swift-defined ES module.
///
/// Functions use the same typed conversion and native Promise behavior as
/// global Swift bindings. Values are immutable snapshots.
public struct JavaScriptModuleBuilder {
    internal var builder: JavaScriptExportBuilder

    internal init(runtime: JavaScriptRuntime) {
        self.builder = JavaScriptExportBuilder(runtime: runtime)
    }

    /// Adds a synchronous typed function export.
    public mutating func function<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) -> Result
    ) where repeat each Argument: Decodable & Sendable,
            Result: Encodable & Sendable {
        builder.function(name, options: options, body)
    }

    /// Adds a throwing synchronous typed function export.
    public mutating func function<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) throws -> Result
    ) where repeat each Argument: Decodable & Sendable,
            Result: Encodable & Sendable {
        builder.function(name, options: options, body)
    }

    /// Adds an asynchronous typed function export.
    public mutating func function<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) async -> Result
    ) where repeat each Argument: Decodable & Sendable,
            Result: Encodable & Sendable {
        builder.function(name, options: options, body)
    }

    /// Adds an asynchronous throwing typed function export.
    public mutating func function<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) async throws -> Result
    ) where repeat each Argument: Decodable & Sendable,
            Result: Encodable & Sendable {
        builder.function(name, options: options, body)
    }

    /// Adds a synchronous function export returning JavaScript `undefined`.
    public mutating func function<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) -> Void
    ) where repeat each Argument: Decodable & Sendable {
        builder.function(name, options: options, body)
    }

    /// Adds a throwing function export returning JavaScript `undefined`.
    public mutating func function<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) throws -> Void
    ) where repeat each Argument: Decodable & Sendable {
        builder.function(name, options: options, body)
    }

    /// Adds an asynchronous function export fulfilling with `undefined`.
    public mutating func function<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) async -> Void
    ) where repeat each Argument: Decodable & Sendable {
        builder.function(name, options: options, body)
    }

    /// Adds an asynchronous throwing function export fulfilling with
    /// JavaScript `undefined`.
    public mutating func function<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) async throws -> Void
    ) where repeat each Argument: Decodable & Sendable {
        builder.function(name, options: options, body)
    }

    /// Adds a read-only Codable snapshot export.
    public mutating func value<Value: Encodable & Sendable>(
        _ value: Value,
        as name: String,
        documentation: String? = nil
    ) {
        builder.value(value, as: name, documentation: documentation)
    }

    /// Adds a read-only same-runtime live-value export.
    public mutating func value(
        _ value: JavaScriptValue,
        as name: String,
        documentation: String? = nil
    ) {
        builder.value(value, as: name, documentation: documentation)
    }
}

extension JavaScriptRuntime {
    /// Defines a runtime-lifetime ES module backed by Swift values and
    /// functions.
    ///
    /// Definition is transactional: validation and value encoding finish
    /// before the module becomes importable.
    public func defineModule(
        _ specifier: String,
        _ configure: @Sendable (inout JavaScriptModuleBuilder) -> Void
    ) throws {
        var module = JavaScriptModuleBuilder(runtime: self)
        configure(&module)
        try engine.withExecution(options: .init()) {
            try engine.registerSwiftModule(
                specifier: specifier,
                members: module.builder.members
            )
        }
    }
}
