/// Declares bindings and values on the JavaScript global object.
public struct Globals: Sendable {
    internal let component: JavaScriptRuntimeTemplate.Component

    /// Creates a global declaration group.
    public init(
        @JavaScriptRuntimeTemplate.ExportBuilder _ content: @Sendable () -> JavaScriptRuntimeTemplate.Export
    ) {
        component = .globals(content)
    }
}

/// Declares a shared Swift object exported to every created runtime.
public struct SharedObject<Root: AnyObject & Sendable>: Sendable {
    internal let component: JavaScriptRuntimeTemplate.Component

    /// Creates a shared object export.
    public init(
        _ root: Root,
        as name: String,
        documentation: TypeScriptDocumentation? = nil,
        @JavaScriptRuntimeTemplate.ExportBuilder _ content: @Sendable (Root) -> JavaScriptRuntimeTemplate.Export
    ) {
        component = .export(
            root,
            as: name,
            documentation: documentation,
            content
        )
    }

    /// Creates a shared object from a macro-generated export definition.
    public init(
        _ root: Root,
        as name: String,
        documentation: TypeScriptDocumentation? = nil
    ) where Root: JavaScriptExportProviding {
        component = .instance(factory: { root }) {
            JavaScriptRuntimeTemplate.Instance<Root>.export(
                as: name,
                documentation: documentation ?? Root.javaScriptExportDocumentation
            ) {
                Root.javaScriptExportDefinition
            }
        }
    }
}

/// Declares a Swift-defined ES module in a runtime template.
public struct SwiftModule: Sendable {
    internal let component: JavaScriptRuntimeTemplate.Component

    /// Creates a Swift module declaration.
    public init(
        _ specifier: String,
        documentation: TypeScriptDocumentation? = nil,
        @JavaScriptRuntimeTemplate.ExportBuilder _ content: @Sendable () -> JavaScriptRuntimeTemplate.Export
    ) {
        component = .module(
            specifier,
            documentation: documentation,
            content
        )
    }
}

/// Declares canonical JavaScript source for an ES module.
public struct SourceModule: Sendable {
    internal let component: JavaScriptRuntimeTemplate.Component

    /// Creates a source-module declaration.
    public init(
        _ source: String,
        as specifier: String,
        sourceURL: String? = nil,
        documentation: TypeScriptDocumentation? = nil,
        declarations: TypeScriptModuleDeclarations? = nil
    ) {
        component = .sourceModule(
            source,
            as: specifier,
            sourceURL: sourceURL,
            documentation: documentation,
            declarations: declarations
        )
    }
}

/// Declares the resolver and asynchronous loader used by created runtimes.
public struct ModuleLoader: Sendable {
    internal let component: JavaScriptRuntimeTemplate.Component

    /// Creates a module-loader declaration.
    public init(_ loader: JavaScriptModuleLoader) {
        component = .moduleLoader(loader)
    }
}

/// Declares independently created Swift state for each runtime.
public struct RuntimeInstance<Root: AnyObject>: Sendable {
    internal let component: JavaScriptRuntimeTemplate.Component

    /// Creates a per-runtime factory group.
    public init(
        factory: @escaping @Sendable () async throws -> sending Root,
        @JavaScriptRuntimeTemplate.InstanceBuilder<Root> _ content: @Sendable () -> JavaScriptRuntimeTemplate.Instance<Root>
    ) {
        component = .instance(factory: factory, content)
    }
}

/// Declares a program compiled into every runtime without executing it.
public struct Prepare: Sendable {
    internal let component: JavaScriptRuntimeTemplate.Component

    /// Creates a prepared-program declaration.
    public init(_ program: JavaScriptProgram) {
        component = .prepare(program)
    }
}

/// Groups ordered actions executed after template installation.
public struct Startup: Sendable {
    internal let component: JavaScriptRuntimeTemplate.Component

    /// Creates a startup action group.
    public init(
        @JavaScriptRuntimeTemplate.StartupBuilder _ content: @Sendable () -> JavaScriptRuntimeTemplate.Startup
    ) {
        component = .startup(content)
    }
}

/// Declares a typed Swift function in a global, object, or module export.
public struct Function: Sendable {
    internal let export: JavaScriptRuntimeTemplate.Export

    /// Creates a synchronous typed function declaration.
    public init<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) -> Result
    ) where repeat each Argument: Decodable & Sendable,
            Result: Encodable & Sendable {
        export = .function(name, options: options, body)
    }

    /// Creates a throwing synchronous typed function declaration.
    public init<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) throws -> Result
    ) where repeat each Argument: Decodable & Sendable,
            Result: Encodable & Sendable {
        export = .function(name, options: options, body)
    }

    /// Creates an asynchronous typed function declaration.
    public init<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) async -> Result
    ) where repeat each Argument: Decodable & Sendable,
            Result: Encodable & Sendable {
        export = .function(name, options: options, body)
    }

    /// Creates an asynchronous throwing typed function declaration.
    public init<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) async throws -> Result
    ) where repeat each Argument: Decodable & Sendable,
            Result: Encodable & Sendable {
        export = .function(name, options: options, body)
    }

    /// Creates a synchronous function returning JavaScript `undefined`.
    public init<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) -> Void
    ) where repeat each Argument: Decodable & Sendable {
        export = .function(name, options: options, body)
    }

    /// Creates a throwing synchronous function returning `undefined`.
    public init<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) throws -> Void
    ) where repeat each Argument: Decodable & Sendable {
        export = .function(name, options: options, body)
    }

    /// Creates an asynchronous function fulfilling with `undefined`.
    public init<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) async -> Void
    ) where repeat each Argument: Decodable & Sendable {
        export = .function(name, options: options, body)
    }

    /// Creates an asynchronous throwing function fulfilling with `undefined`.
    public init<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) async throws -> Void
    ) where repeat each Argument: Decodable & Sendable {
        export = .function(name, options: options, body)
    }
}

/// Declares an Encodable snapshot value in a template export.
public struct Value: Sendable {
    internal let export: JavaScriptRuntimeTemplate.Export

    /// Creates a snapshot value declaration.
    public init<Snapshot: Encodable & Sendable>(
        _ value: Snapshot,
        as name: String,
        documentation: TypeScriptDocumentation? = nil
    ) {
        export = .value(value, as: name, documentation: documentation)
    }
}

/// Publishes a Swift type as a JavaScript constructor, enum validator, or live
/// host type.
public struct JavaScriptType: Sendable {
    internal let export: JavaScriptRuntimeTemplate.Export

    /// Creates a JavaScript value type from a macro-generated struct or enum
    /// definition.
    public init<Value>(_ type: Value.Type)
    where Value: JavaScriptValueTypeProviding {
        let definition = Value.javaScriptValueTypeDefinition.erase(
            schema: collectedTypeScriptSchema(from: Value.self)
        )
        export = JavaScriptRuntimeTemplate.Export(types: [definition])
    }

    /// Creates a live JavaScript host type from a macro-generated final class
    /// or actor definition.
    public init<Root>(_ type: Root.Type)
    where Root: JavaScriptHostTypeProviding {
        let definition = Root.javaScriptHostTypeDefinition
        export = JavaScriptRuntimeTemplate.Export(
            types: [.host(definition.erase())]
        )
    }
}

/// Declares a live property in a shared object or global export.
public struct Property: Sendable {
    internal let export: JavaScriptRuntimeTemplate.Export

    /// Creates a read-only live property.
    public init<Value: Encodable & Sendable>(
        _ name: String,
        documentation: TypeScriptDocumentation? = nil,
        get: @escaping @Sendable () -> Value
    ) {
        var builder = JavaScriptExportBuilder()
        builder.property(name, documentation: documentation, get: get)
        export = JavaScriptRuntimeTemplate.Export(members: builder.members)
    }

    /// Creates a readable and writable live property.
    public init<Value: Codable & Sendable>(
        _ name: String,
        documentation: TypeScriptDocumentation? = nil,
        get: @escaping @Sendable () -> Value,
        set: @escaping @Sendable (Value) -> Void
    ) {
        var builder = JavaScriptExportBuilder()
        builder.property(
            name,
            documentation: documentation,
            get: get,
            set: set
        )
        export = JavaScriptRuntimeTemplate.Export(members: builder.members)
    }
}

/// Declares root-backed bindings on the JavaScript global object.
public struct RuntimeGlobals<Root: AnyObject>: Sendable {
    internal let instance: JavaScriptRuntimeTemplate.Instance<Root>

    /// Creates a per-runtime global declaration group.
    public init(
        @JavaScriptRuntimeTemplate.InstanceExportBuilder<Root> _ content: @Sendable () -> JavaScriptRuntimeTemplate.InstanceExport<Root>
    ) {
        instance = .globals(content)
    }

    /// Creates global bindings from a macro-generated export definition.
    public init() where Root: JavaScriptExportProviding {
        let definition = Root.javaScriptExportDefinition
        instance = .globals { definition }
    }
}

/// Declares a named object backed by per-runtime Swift state.
public struct RuntimeObject<Root: AnyObject>: Sendable {
    internal let instance: JavaScriptRuntimeTemplate.Instance<Root>

    /// Creates a per-runtime object export.
    public init(
        as name: String,
        documentation: TypeScriptDocumentation? = nil,
        @JavaScriptRuntimeTemplate.InstanceExportBuilder<Root> _ content: @Sendable () -> JavaScriptRuntimeTemplate.InstanceExport<Root>
    ) {
        instance = .export(
            as: name,
            documentation: documentation,
            content
        )
    }

    /// Creates an object from a macro-generated export definition.
    public init(
        as name: String,
        documentation: TypeScriptDocumentation? = nil
    ) where Root: JavaScriptExportProviding {
        let definition = Root.javaScriptExportDefinition
        instance = .export(
            as: name,
            documentation: documentation ?? Root.javaScriptExportDocumentation
        ) {
            definition
        }
    }
}

/// Declares a Swift module backed by per-runtime Swift state.
public struct RuntimeModule<Root: AnyObject>: Sendable {
    internal let instance: JavaScriptRuntimeTemplate.Instance<Root>

    /// Creates a per-runtime Swift module declaration.
    public init(
        _ specifier: String,
        documentation: TypeScriptDocumentation? = nil,
        @JavaScriptRuntimeTemplate.InstanceExportBuilder<Root> _ content: @Sendable () -> JavaScriptRuntimeTemplate.InstanceExport<Root>
    ) {
        instance = .module(
            specifier,
            documentation: documentation,
            content
        )
    }

    /// Creates a method-only module from a macro-generated export definition.
    public init(
        _ specifier: String,
        documentation: TypeScriptDocumentation? = nil
    ) where Root: JavaScriptExportProviding {
        let definition = Root.javaScriptExportDefinition
        instance = .module(
            specifier,
            documentation: documentation ?? Root.javaScriptExportDocumentation
        ) {
            definition
        }
    }
}

/// Declares a function receiving a per-runtime Swift root as its first argument.
public struct InstanceFunction<Root: AnyObject>: Sendable {
    internal let export: JavaScriptRuntimeTemplate.InstanceExport<Root>

    /// Creates a synchronous function returning a live Swift host object.
    public init<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (Root, repeat each Argument) -> Result
    ) where repeat each Argument: Decodable & Sendable,
            Result: JavaScriptHostTypeProviding & Sendable {
        export = .hostFunction(name, options: options, body)
    }

    /// Creates a synchronous function returning an optional host object.
    public init<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (Root, repeat each Argument) -> Result?
    ) where repeat each Argument: Decodable & Sendable,
            Result: JavaScriptHostTypeProviding & Sendable {
        export = .optionalHostFunction(
            name,
            options: options,
            isThrowing: false,
            body
        )
    }

    /// Creates a throwing synchronous function returning an optional host object.
    public init<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (Root, repeat each Argument) throws -> Result?
    ) where repeat each Argument: Decodable & Sendable,
            Result: JavaScriptHostTypeProviding & Sendable {
        export = .optionalHostFunction(
            name,
            options: options,
            isThrowing: true,
            body
        )
    }

    /// Creates an actor-confined async function returning a host object.
    public init<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        runtimeIsolated body: @escaping @Sendable (
            isolated JavaScriptRuntime,
            Root,
            repeat each Argument
        ) async -> Result
    ) where repeat each Argument: Decodable & Sendable,
            Result: JavaScriptHostTypeProviding {
        export = .runtimeIsolatedHostResultFunction(
            name,
            options: options,
            isThrowing: false,
            body
        )
    }

    /// Creates an actor-confined throwing async function returning a host object.
    public init<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        runtimeIsolated body: @escaping @Sendable (
            isolated JavaScriptRuntime,
            Root,
            repeat each Argument
        ) async throws -> Result
    ) where repeat each Argument: Decodable & Sendable,
            Result: JavaScriptHostTypeProviding {
        export = .runtimeIsolatedHostResultFunction(
            name,
            options: options,
            isThrowing: true,
            body
        )
    }

    /// Creates an actor-confined async function returning an optional host object.
    public init<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        runtimeIsolated body: @escaping @Sendable (
            isolated JavaScriptRuntime,
            Root,
            repeat each Argument
        ) async -> Result?
    ) where repeat each Argument: Decodable & Sendable,
            Result: JavaScriptHostTypeProviding {
        export = .runtimeIsolatedHostResultFunction(
            name,
            options: options,
            optional: true,
            isThrowing: false,
            body
        )
    }

    /// Creates an actor-confined throwing async function returning an optional host object.
    public init<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        runtimeIsolated body: @escaping @Sendable (
            isolated JavaScriptRuntime,
            Root,
            repeat each Argument
        ) async throws -> Result?
    ) where repeat each Argument: Decodable & Sendable,
            Result: JavaScriptHostTypeProviding {
        export = .runtimeIsolatedHostResultFunction(
            name,
            options: options,
            optional: true,
            isThrowing: true,
            body
        )
    }

    /// Creates a synchronous function accepting one exact host reference.
    public init<Argument: JavaScriptHostTypeProviding, Result: Encodable & Sendable>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (Root, Argument) -> Result
    ) {
        export = .hostArgumentFunction(
            name,
            options: options,
            isThrowing: false,
            { root, argument in body(root, argument!) }
        )
    }

    /// Creates an actor-confined async Void function accepting one host reference.
    public init<Argument: JavaScriptHostTypeProviding>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        runtimeIsolated body: @escaping @Sendable (
            isolated JavaScriptRuntime,
            Root,
            Argument
        ) async -> Void
    ) {
        export = .runtimeIsolatedHostArgumentFunction(
            name,
            options: options,
            isThrowing: false,
            resultShape: .void,
            { runtime, root, argument in
                await body(runtime, root, argument!)
            },
            encode: { _ in
                BindingResult { engine in
                    ManagedQuickJSValue(quickJSUndefined(), in: engine.context)
                }
            }
        )
    }

    /// Creates an actor-confined throwing async Void function accepting one host reference.
    public init<Argument: JavaScriptHostTypeProviding>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        runtimeIsolated body: @escaping @Sendable (
            isolated JavaScriptRuntime,
            Root,
            Argument
        ) async throws -> Void
    ) {
        export = .runtimeIsolatedHostArgumentFunction(
            name,
            options: options,
            isThrowing: true,
            resultShape: .void,
            { runtime, root, argument in
                try await body(runtime, root, argument!)
            },
            encode: { _ in
                BindingResult { engine in
                    ManagedQuickJSValue(quickJSUndefined(), in: engine.context)
                }
            }
        )
    }

    /// Creates an actor-confined async Void function accepting an optional host reference.
    public init<Argument: JavaScriptHostTypeProviding>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        runtimeIsolated body: @escaping @Sendable (
            isolated JavaScriptRuntime,
            Root,
            Argument?
        ) async -> Void
    ) {
        export = .runtimeIsolatedHostArgumentFunction(
            name,
            options: options,
            optional: true,
            isThrowing: false,
            resultShape: .void,
            body,
            encode: { _ in
                BindingResult { engine in
                    ManagedQuickJSValue(quickJSUndefined(), in: engine.context)
                }
            }
        )
    }

    /// Creates an actor-confined throwing async Void function accepting an optional host reference.
    public init<Argument: JavaScriptHostTypeProviding>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        runtimeIsolated body: @escaping @Sendable (
            isolated JavaScriptRuntime,
            Root,
            Argument?
        ) async throws -> Void
    ) {
        export = .runtimeIsolatedHostArgumentFunction(
            name,
            options: options,
            optional: true,
            isThrowing: true,
            resultShape: .void,
            body,
            encode: { _ in
                BindingResult { engine in
                    ManagedQuickJSValue(quickJSUndefined(), in: engine.context)
                }
            }
        )
    }

    /// Creates an actor-confined async function accepting one host reference.
    public init<Argument: JavaScriptHostTypeProviding, Result: Encodable & Sendable>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        runtimeIsolated body: @escaping @Sendable (
            isolated JavaScriptRuntime,
            Root,
            Argument
        ) async -> Result
    ) {
        export = .runtimeIsolatedHostArgumentFunction(
            name,
            options: options,
            isThrowing: false,
            resultShape: bindingTypeShape(for: Result.self),
            { runtime, root, argument in
                await body(runtime, root, argument!)
            },
            encode: { result in
                BindingResult { engine in
                    try engine.encode(
                        result,
                        maximumNestingDepth:
                            JavaScriptEncoder.defaultMaximumNestingDepth
                    )
                }
            }
        )
    }

    /// Creates an actor-confined throwing async function accepting one host reference.
    public init<Argument: JavaScriptHostTypeProviding, Result: Encodable & Sendable>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        runtimeIsolated body: @escaping @Sendable (
            isolated JavaScriptRuntime,
            Root,
            Argument
        ) async throws -> Result
    ) {
        export = .runtimeIsolatedHostArgumentFunction(
            name,
            options: options,
            isThrowing: true,
            resultShape: bindingTypeShape(for: Result.self),
            { runtime, root, argument in
                try await body(runtime, root, argument!)
            },
            encode: { result in
                BindingResult { engine in
                    try engine.encode(
                        result,
                        maximumNestingDepth:
                            JavaScriptEncoder.defaultMaximumNestingDepth
                    )
                }
            }
        )
    }

    /// Creates an actor-confined async function accepting an optional host reference.
    public init<Argument: JavaScriptHostTypeProviding, Result: Encodable & Sendable>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        runtimeIsolated body: @escaping @Sendable (
            isolated JavaScriptRuntime,
            Root,
            Argument?
        ) async -> Result
    ) {
        export = .runtimeIsolatedHostArgumentFunction(
            name,
            options: options,
            optional: true,
            isThrowing: false,
            resultShape: bindingTypeShape(for: Result.self),
            body,
            encode: { result in
                BindingResult { engine in
                    try engine.encode(
                        result,
                        maximumNestingDepth:
                            JavaScriptEncoder.defaultMaximumNestingDepth
                    )
                }
            }
        )
    }

    /// Creates an actor-confined throwing async function accepting an optional host reference.
    public init<Argument: JavaScriptHostTypeProviding, Result: Encodable & Sendable>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        runtimeIsolated body: @escaping @Sendable (
            isolated JavaScriptRuntime,
            Root,
            Argument?
        ) async throws -> Result
    ) {
        export = .runtimeIsolatedHostArgumentFunction(
            name,
            options: options,
            optional: true,
            isThrowing: true,
            resultShape: bindingTypeShape(for: Result.self),
            body,
            encode: { result in
                BindingResult { engine in
                    try engine.encode(
                        result,
                        maximumNestingDepth:
                            JavaScriptEncoder.defaultMaximumNestingDepth
                    )
                }
            }
        )
    }

    /// Creates a throwing function accepting one exact host reference.
    public init<Argument: JavaScriptHostTypeProviding, Result: Encodable & Sendable>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (Root, Argument) throws -> Result
    ) {
        export = .hostArgumentFunction(
            name,
            options: options,
            isThrowing: true,
            { root, argument in try body(root, argument!) }
        )
    }

    /// Creates a synchronous function accepting an optional host reference.
    public init<Argument: JavaScriptHostTypeProviding, Result: Encodable & Sendable>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (Root, Argument?) -> Result
    ) {
        export = .hostArgumentFunction(
            name,
            options: options,
            optional: true,
            isThrowing: false,
            body
        )
    }

    /// Creates a throwing synchronous function returning a live Swift host object.
    public init<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (Root, repeat each Argument) throws -> Result
    ) where repeat each Argument: Decodable & Sendable,
            Result: JavaScriptHostTypeProviding & Sendable {
        export = .hostFunction(name, options: options, body)
    }

    /// Creates a synchronous root-backed function declaration.
    public init<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (Root, repeat each Argument) -> Result
    ) where repeat each Argument: Decodable & Sendable,
            Result: Encodable & Sendable {
        export = .function(name, options: options, body)
    }

    /// Creates a throwing synchronous root-backed function declaration.
    public init<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (Root, repeat each Argument) throws -> Result
    ) where repeat each Argument: Decodable & Sendable,
            Result: Encodable & Sendable {
        export = .function(name, options: options, body)
    }

    /// Creates an asynchronous root-backed function declaration.
    public init<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (Root, repeat each Argument) async -> Result
    ) where repeat each Argument: Decodable & Sendable,
            Root: Sendable,
            Result: Encodable & Sendable {
        export = .function(name, options: options, body)
    }

    /// Creates an asynchronous throwing root-backed function declaration.
    public init<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (Root, repeat each Argument) async throws -> Result
    ) where repeat each Argument: Decodable & Sendable,
            Root: Sendable,
            Result: Encodable & Sendable {
        export = .function(name, options: options, body)
    }

    /// Creates a synchronous root-backed function returning `undefined`.
    public init<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (Root, repeat each Argument) -> Void
    ) where repeat each Argument: Decodable & Sendable {
        export = .function(name, options: options, body)
    }

    /// Creates a throwing root-backed function returning `undefined`.
    public init<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (Root, repeat each Argument) throws -> Void
    ) where repeat each Argument: Decodable & Sendable {
        export = .function(name, options: options, body)
    }

    /// Creates an asynchronous root-backed function fulfilling with `undefined`.
    public init<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (Root, repeat each Argument) async -> Void
    ) where repeat each Argument: Decodable & Sendable,
            Root: Sendable {
        export = .function(name, options: options, body)
    }

    /// Creates an asynchronous throwing root-backed function fulfilling with `undefined`.
    public init<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (Root, repeat each Argument) async throws -> Void
    ) where repeat each Argument: Decodable & Sendable,
            Root: Sendable {
        export = .function(name, options: options, body)
    }

    /// Creates an actor-confined asynchronous root-backed function.
    ///
    /// The runtime parameter is Swift-only and lets the compiler prove that a
    /// non-`Sendable` root remains on its owning runtime actor.
    public init<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        runtimeIsolated body: @escaping @Sendable (
            isolated JavaScriptRuntime,
            Root,
            repeat each Argument
        ) async -> Result
    ) where repeat each Argument: Decodable & Sendable,
            Result: Encodable & Sendable {
        export = .function(
            name,
            options: options,
            runtimeIsolated: body
        )
    }

    /// Creates an actor-confined asynchronous throwing root-backed function.
    public init<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        runtimeIsolated body: @escaping @Sendable (
            isolated JavaScriptRuntime,
            Root,
            repeat each Argument
        ) async throws -> Result
    ) where repeat each Argument: Decodable & Sendable,
            Result: Encodable & Sendable {
        export = .function(
            name,
            options: options,
            runtimeIsolated: body
        )
    }

    /// Creates an actor-confined asynchronous root-backed function returning `undefined`.
    public init<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        runtimeIsolated body: @escaping @Sendable (
            isolated JavaScriptRuntime,
            Root,
            repeat each Argument
        ) async -> Void
    ) where repeat each Argument: Decodable & Sendable {
        export = .function(
            name,
            options: options,
            runtimeIsolated: body
        )
    }

    /// Creates an actor-confined asynchronous throwing root-backed function returning `undefined`.
    public init<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        runtimeIsolated body: @escaping @Sendable (
            isolated JavaScriptRuntime,
            Root,
            repeat each Argument
        ) async throws -> Void
    ) where repeat each Argument: Decodable & Sendable {
        export = .function(
            name,
            options: options,
            runtimeIsolated: body
        )
    }
}

/// Declares a snapshot value produced from per-runtime Swift state.
public struct InstanceValue<Root: AnyObject>: Sendable {
    internal let export: JavaScriptRuntimeTemplate.InstanceExport<Root>

    /// Creates a per-runtime snapshot value declaration.
    public init<Snapshot: Encodable & Sendable>(
        as name: String,
        documentation: TypeScriptDocumentation? = nil,
        _ produce: @escaping @Sendable (Root) async throws -> Snapshot
    ) where Root: Sendable {
        export = .value(
            as: name,
            documentation: documentation,
            produce
        )
    }

    /// Creates a snapshot while isolated to the destination runtime actor.
    public init<Snapshot: Encodable & Sendable>(
        as name: String,
        documentation: TypeScriptDocumentation? = nil,
        runtimeIsolated produce: @escaping @Sendable (
            isolated JavaScriptRuntime,
            Root
        ) async throws -> Snapshot
    ) {
        export = .value(
            as: name,
            documentation: documentation,
            runtimeIsolated: produce
        )
    }
}

/// Declares a live property backed by one runtime-local Swift root.
public struct InstanceProperty<Root: AnyObject>: Sendable {
    internal let export: JavaScriptRuntimeTemplate.InstanceExport<Root>

    /// Creates a read-only runtime-local property.
    public init<Value: Encodable & Sendable>(
        _ name: String,
        documentation: TypeScriptDocumentation? = nil,
        sourceLocation: TypeScriptSourceLocation? = nil,
        get: @escaping @Sendable (Root) -> Value
    ) {
        export = .property(
            name,
            documentation: documentation,
            sourceLocation: sourceLocation,
            get: get
        )
    }

    /// Creates a readable and writable runtime-local property.
    public init<Value: Codable & Sendable>(
        _ name: String,
        documentation: TypeScriptDocumentation? = nil,
        sourceLocation: TypeScriptSourceLocation? = nil,
        get: @escaping @Sendable (Root) -> Value,
        set: @escaping @Sendable (Root, Value) -> Void
    ) {
        export = .property(
            name,
            documentation: documentation,
            sourceLocation: sourceLocation,
            get: get,
            set: set
        )
    }

    /// Creates a Promise-valued read-only runtime-local property.
    public init<Value: Encodable & Sendable>(
        _ name: String,
        documentation: TypeScriptDocumentation? = nil,
        sourceLocation: TypeScriptSourceLocation? = nil,
        runtimeIsolatedGet get: @escaping @Sendable (
            isolated JavaScriptRuntime,
            Root
        ) async -> Value
    ) {
        export = .property(
            name,
            documentation: documentation,
            sourceLocation: sourceLocation,
            runtimeIsolatedGet: get
        )
    }
}

/// Runs a prepared program during runtime creation.
public struct Run: Sendable {
    internal let startup: JavaScriptRuntimeTemplate.Startup

    /// Creates a startup program action.
    public init(
        _ program: JavaScriptProgram,
        options: JavaScriptExecutionOptions = .init()
    ) {
        startup = .run(program, options: options)
    }
}

/// Links a module graph during runtime creation without evaluating it.
public struct PreloadModule: Sendable {
    internal let startup: JavaScriptRuntimeTemplate.Startup

    /// Creates a startup module-preload action.
    public init(_ specifier: String) {
        startup = .preloadModule(specifier)
    }
}

/// Imports and evaluates a module during runtime creation.
public struct ImportModule: Sendable {
    internal let startup: JavaScriptRuntimeTemplate.Startup

    /// Creates a startup module-import action.
    public init(
        _ specifier: String,
        options: JavaScriptExecutionOptions = .init()
    ) {
        startup = .importModule(specifier, options: options)
    }
}

extension JavaScriptRuntimeTemplate.ContentBuilder {
    /// Accepts a global declaration group.
    public static func buildExpression(
        _ expression: Globals
    ) -> JavaScriptRuntimeTemplate.Component {
        expression.component
    }

    /// Accepts a shared object export.
    public static func buildExpression<Root>(
        _ expression: SharedObject<Root>
    ) -> JavaScriptRuntimeTemplate.Component where Root: AnyObject {
        expression.component
    }

    /// Accepts a Swift-defined module.
    public static func buildExpression(
        _ expression: SwiftModule
    ) -> JavaScriptRuntimeTemplate.Component {
        expression.component
    }

    /// Accepts a source module.
    public static func buildExpression(
        _ expression: SourceModule
    ) -> JavaScriptRuntimeTemplate.Component {
        expression.component
    }

    /// Accepts a module loader.
    public static func buildExpression(
        _ expression: ModuleLoader
    ) -> JavaScriptRuntimeTemplate.Component {
        expression.component
    }

    /// Accepts a per-runtime factory group.
    public static func buildExpression<Root>(
        _ expression: RuntimeInstance<Root>
    ) -> JavaScriptRuntimeTemplate.Component where Root: AnyObject {
        expression.component
    }

    /// Accepts a prepared program.
    public static func buildExpression(
        _ expression: Prepare
    ) -> JavaScriptRuntimeTemplate.Component {
        expression.component
    }

    /// Accepts a startup action group.
    public static func buildExpression(
        _ expression: Startup
    ) -> JavaScriptRuntimeTemplate.Component {
        expression.component
    }
}

extension JavaScriptRuntimeTemplate.ExportBuilder {
    /// Accepts a typed function declaration.
    public static func buildExpression(
        _ expression: Function
    ) -> JavaScriptRuntimeTemplate.Export {
        expression.export
    }

    /// Accepts a snapshot value declaration.
    public static func buildExpression(
        _ expression: Value
    ) -> JavaScriptRuntimeTemplate.Export {
        expression.export
    }

    /// Accepts a live property declaration.
    public static func buildExpression(
        _ expression: Property
    ) -> JavaScriptRuntimeTemplate.Export {
        expression.export
    }
}

extension JavaScriptRuntimeTemplate.InstanceBuilder {
    /// Accepts root-backed global declarations.
    public static func buildExpression(
        _ expression: RuntimeGlobals<Root>
    ) -> JavaScriptRuntimeTemplate.Instance<Root> {
        expression.instance
    }

    /// Accepts a root-backed object export.
    public static func buildExpression(
        _ expression: RuntimeObject<Root>
    ) -> JavaScriptRuntimeTemplate.Instance<Root> {
        expression.instance
    }

    /// Accepts a root-backed Swift module.
    public static func buildExpression(
        _ expression: RuntimeModule<Root>
    ) -> JavaScriptRuntimeTemplate.Instance<Root> {
        expression.instance
    }
}

extension JavaScriptRuntimeTemplate.InstanceExportBuilder {
    /// Accepts a root-backed function declaration.
    public static func buildExpression(
        _ expression: InstanceFunction<Root>
    ) -> JavaScriptRuntimeTemplate.InstanceExport<Root> {
        expression.export
    }

    /// Accepts a root-produced snapshot value.
    public static func buildExpression(
        _ expression: InstanceValue<Root>
    ) -> JavaScriptRuntimeTemplate.InstanceExport<Root> {
        expression.export
    }

    /// Accepts a runtime-local live property declaration.
    public static func buildExpression(
        _ expression: InstanceProperty<Root>
    ) -> JavaScriptRuntimeTemplate.InstanceExport<Root> {
        expression.export
    }
}

extension JavaScriptRuntimeTemplate.StartupBuilder {
    /// Accepts a prepared program action.
    public static func buildExpression(
        _ expression: Run
    ) -> JavaScriptRuntimeTemplate.Startup {
        expression.startup
    }

    /// Accepts a module-preload action.
    public static func buildExpression(
        _ expression: PreloadModule
    ) -> JavaScriptRuntimeTemplate.Startup {
        expression.startup
    }

    /// Accepts a module-import action.
    public static func buildExpression(
        _ expression: ImportModule
    ) -> JavaScriptRuntimeTemplate.Startup {
        expression.startup
    }
}
