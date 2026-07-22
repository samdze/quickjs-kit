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
public struct RuntimeInstance<Root: AnyObject & Sendable>: Sendable {
    internal let component: JavaScriptRuntimeTemplate.Component

    /// Creates a per-runtime factory group.
    public init(
        factory: @escaping @Sendable () async throws -> Root,
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

/// Declares root-backed bindings on the JavaScript global object.
public struct RuntimeGlobals<Root: AnyObject & Sendable>: Sendable {
    internal let instance: JavaScriptRuntimeTemplate.Instance<Root>

    /// Creates a per-runtime global declaration group.
    public init(
        @JavaScriptRuntimeTemplate.InstanceExportBuilder<Root> _ content: @Sendable () -> JavaScriptRuntimeTemplate.InstanceExport<Root>
    ) {
        instance = .globals(content)
    }
}

/// Declares a named object backed by per-runtime Swift state.
public struct RuntimeObject<Root: AnyObject & Sendable>: Sendable {
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
}

/// Declares a Swift module backed by per-runtime Swift state.
public struct RuntimeModule<Root: AnyObject & Sendable>: Sendable {
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
}

/// Declares a function receiving a per-runtime Swift root as its first argument.
public struct InstanceFunction<Root: AnyObject & Sendable>: Sendable {
    internal let export: JavaScriptRuntimeTemplate.InstanceExport<Root>

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
            Result: Encodable & Sendable {
        export = .function(name, options: options, body)
    }

    /// Creates an asynchronous throwing root-backed function declaration.
    public init<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (Root, repeat each Argument) async throws -> Result
    ) where repeat each Argument: Decodable & Sendable,
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
    ) where repeat each Argument: Decodable & Sendable {
        export = .function(name, options: options, body)
    }

    /// Creates an asynchronous throwing root-backed function fulfilling with `undefined`.
    public init<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (Root, repeat each Argument) async throws -> Void
    ) where repeat each Argument: Decodable & Sendable {
        export = .function(name, options: options, body)
    }
}

/// Declares a snapshot value produced from per-runtime Swift state.
public struct InstanceValue<Root: AnyObject & Sendable>: Sendable {
    internal let export: JavaScriptRuntimeTemplate.InstanceExport<Root>

    /// Creates a per-runtime snapshot value declaration.
    public init<Snapshot: Encodable & Sendable>(
        as name: String,
        documentation: TypeScriptDocumentation? = nil,
        _ produce: @escaping @Sendable (Root) async throws -> Snapshot
    ) {
        export = .value(
            as: name,
            documentation: documentation,
            produce
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
    ) -> JavaScriptRuntimeTemplate.Component where Root: AnyObject & Sendable {
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
    ) -> JavaScriptRuntimeTemplate.Component where Root: AnyObject & Sendable {
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
