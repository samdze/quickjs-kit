internal import CQuickJS

internal final class RegisteredSwiftModule {
    internal let specifier: String
    internal let exports: [String: ManagedQuickJSValue]
    internal let bindingIdentifiers: [UInt64]

    internal init(
        specifier: String,
        exports: [String: ManagedQuickJSValue],
        bindingIdentifiers: [UInt64]
    ) {
        self.specifier = specifier
        self.exports = exports
        self.bindingIdentifiers = bindingIdentifiers
    }
}

internal enum EngineModuleDiscovery {
    case ready
    case missing(JavaScriptModuleRequest)
}

extension QuickJSEngine {
    internal func registerSwiftModule(
        specifier: String,
        members: [JavaScriptExportMemberDefinition],
        settle: @escaping BindingSettlement
    ) throws {
        try validateModuleSpecifier(specifier)
        guard !hasModuleSource(specifier) else {
            throw JavaScriptError(
                kind: .module,
                message: "A module is already registered as '\(specifier)'."
            )
        }
        guard !BindingValidation.hasDuplicateNames(members.map(\.name)) else {
            throw JavaScriptError(
                kind: .conversion,
                message: "A module cannot contain duplicate export names."
            )
        }

        var exports: [String: ManagedQuickJSValue] = [:]
        var bindingIdentifiers: [UInt64] = []
        do {
            for (order, member) in members.enumerated() {
                if let message = member.validationMessage {
                    throw JavaScriptError(kind: .conversion, message: message)
                }
                switch member.storage {
                case let .value(_, encode):
                    exports[member.name] = try encode(self)
                case let .liveValue(_, value):
                    exports[member.name] = try materialize(value)
                case let .function(definition):
                    let identifier = try allocateBindingIdentifier()
                    let boundFunction = definition.bind(
                        location: .module(specifier: specifier),
                        order: UInt64(order),
                        settle: settle
                    )
                    let binding = RegisteredBinding(
                        identifier: identifier,
                        name: member.name,
                        function: boundFunction
                    )
                    swiftBindings[identifier] = binding
                    bindingIdentifiers.append(identifier)
                    let rawFunction = try makeBoundFunction(
                        bindingIdentifier: identifier,
                        name: member.name,
                        length: boundFunction.description.parameters.count
                    )
                    binding.exposedValue = ManagedQuickJSValue(
                        JS_DupValue(context, rawFunction.raw),
                        in: context
                    )
                    exports[member.name] = rawFunction
                }
            }

            guard let module = specifier.withCString({
                JS_NewCModule(context, $0, quickJSKitSwiftModuleInitializer)
            }) else {
                throw extractException()
            }
            for name in members.map(\.name) {
                let status = name.withCString { JS_AddModuleExport(context, module, $0) }
                guard status >= 0 else {
                    JS_FreeValue(context, quickJSModuleValue(module))
                    throw extractException()
                }
            }
            swiftModules[UInt(bitPattern: module)] = RegisteredSwiftModule(
                specifier: specifier,
                exports: exports,
                bindingIdentifiers: bindingIdentifiers
            )
            nativeModuleSpecifiers.insert(specifier)
            environmentModules[specifier] = .swift(
                specifier: specifier,
                members: members.map(\.environmentDescription)
            )
        } catch {
            for identifier in bindingIdentifiers {
                swiftBindings.removeValue(forKey: identifier)
            }
            throw error
        }
    }

    internal func initializeSwiftModule(_ module: OpaquePointer) -> Int32 {
        guard let record = swiftModules[UInt(bitPattern: module)] else {
            _ = throwJavaScriptError(
                name: "ModuleError",
                message: "The Swift module registration is no longer available."
            )
            return -1
        }
        for (name, value) in record.exports {
            let status = name.withCString {
                JS_SetModuleExport(context, module, $0, JS_DupValue(context, value.raw))
            }
            if status < 0 { return -1 }
        }
        return 0
    }

    internal func configureModuleResolver(
        _ resolver: (@Sendable (JavaScriptModuleRequest) throws -> String)?
    ) throws {
        guard !moduleCompilationStarted else {
            throw JavaScriptError(
                kind: .module,
                message: "The module loader cannot change after module compilation begins."
            )
        }
        moduleResolver = resolver
    }

    internal func registerModuleSource(
        _ source: String,
        specifier: String,
        sourceURL: String,
        typeScriptDeclarations: TypeScriptModuleDeclarations? = nil,
        isEnvironmentModule: Bool = true
    ) throws {
        try validateModuleSpecifier(specifier)
        guard moduleSources[specifier] == nil,
              !nativeModuleSpecifiers.contains(specifier) else {
            throw JavaScriptError(
                kind: .module,
                message: "A module is already registered as '\(specifier)'.",
                sourceURL: sourceURL
            )
        }
        moduleSources[specifier] = EngineModuleSource(
            source: source,
            sourceURL: sourceURL
        )
        if isEnvironmentModule {
            environmentModules[specifier] = .source(
                specifier: specifier,
                declarations: typeScriptDeclarations
            )
        }
    }

    internal func registerLoadedModuleSource(
        _ source: JavaScriptModuleSource,
        specifier: String
    ) throws {
        if moduleSources[specifier] != nil { return }
        try registerModuleSource(
            source.source,
            specifier: specifier,
            sourceURL: source.sourceURL,
            typeScriptDeclarations: source.typeScriptDeclarations
        )
    }

    internal func hasModuleSource(_ specifier: String) -> Bool {
        moduleSources[specifier] != nil || nativeModuleSpecifiers.contains(specifier)
    }

    internal func resolveModuleSpecifier(
        _ specifier: String,
        referrer: String?
    ) throws -> String {
        try validateModuleSpecifier(specifier)
        let request = JavaScriptModuleRequest(specifier: specifier, referrer: referrer)
        let result = try moduleResolver?(request) ?? defaultResolveModule(
            specifier,
            referrer: referrer
        )
        try validateModuleSpecifier(result)
        return result
    }

    internal func discoverModule(_ specifier: String) throws -> EngineModuleDiscovery {
        if nativeModuleSpecifiers.contains(specifier) { return .ready }
        guard let source = moduleSources[specifier] else {
            return .missing(JavaScriptModuleRequest(specifier: specifier, referrer: nil))
        }
        moduleCompilationStarted = true
        missingModuleRequest = nil
        let raw = compileModuleSource(source, specifier: specifier)
        if JS_IsException(raw) != 0 {
            if let missing = missingModuleRequest {
                missingModuleRequest = nil
                clearPendingException()
                return .missing(missing)
            }
            let error = extractException(sourceURL: source.sourceURL)
            if error.kind == .syntax { throw error }
            throw JavaScriptError(
                kind: .module,
                name: error.name,
                message: error.message,
                stack: error.stack,
                sourceURL: error.sourceURL
            )
        }
        let compiled = ManagedQuickJSValue(raw, in: context)
        if let module = quickJSModulePointer(compiled.raw) {
            setImportMetaURL(source.sourceURL, on: module)
        }
        return .ready
    }

    internal func loadModule(_ specifier: String) throws -> ManagedQuickJSValue {
        moduleCompilationStarted = true
        let raw = specifier.withCString { pointer in
            JS_LoadModule(context, "<QuickJSKit import>", pointer)
        }
        let result = ManagedQuickJSValue(raw, in: context)
        if JS_IsException(raw) != 0 {
            let error = extractException(sourceURL: moduleSources[specifier]?.sourceURL)
            throw JavaScriptError(
                kind: error.kind == .syntax ? .syntax : .module,
                name: error.name,
                message: error.message,
                stack: error.stack,
                sourceURL: error.sourceURL
            )
        }
        return result
    }

    internal func allocateTransientModuleSpecifier() -> String {
        defer { nextTransientModuleIdentifier &+= 1 }
        return "quickjskit:eval:\(nextTransientModuleIdentifier)"
    }

    internal func normalizeModule(base: String, requested: String) -> String? {
        do {
            if base == "<QuickJSKit import>", hasModuleSource(requested) {
                return requested
            }
            let referrer = base.isEmpty ? nil : base
            let normalized = try resolveModuleSpecifier(requested, referrer: referrer)
            normalizedModuleRequests[normalized] = JavaScriptModuleRequest(
                specifier: normalized,
                referrer: referrer
            )
            return normalized
        } catch {
            _ = throwJavaScriptError(
                name: "ModuleError",
                message: String(describing: error)
            )
            return nil
        }
    }

    internal func compileModuleForLoader(_ specifier: String) -> OpaquePointer? {
        moduleCompilationStarted = true
        guard let source = moduleSources[specifier] else {
            missingModuleRequest = normalizedModuleRequests[specifier] ?? JavaScriptModuleRequest(
                specifier: specifier,
                referrer: nil
            )
            _ = throwJavaScriptError(
                name: "ModuleError",
                message: "No source is registered for module '\(specifier)'."
            )
            return nil
        }
        let raw = compileModuleSource(source, specifier: specifier)
        guard JS_IsException(raw) == 0,
              let module = quickJSModulePointer(raw) else {
            return nil
        }
        setImportMetaURL(source.sourceURL, on: module)
        // Compiled modules are already retained by the context's loaded-module
        // list. Balance the compile-only JSValue before returning the borrowed
        // module definition to QuickJS's loader.
        JS_FreeValue(context, raw)
        return module
    }

    private func compileModuleSource(
        _ source: EngineModuleSource,
        specifier: String
    ) -> JSValue {
        source.source.withCString { sourcePointer in
            specifier.withCString { specifierPointer in
                JS_Eval(
                    context,
                    sourcePointer,
                    source.source.utf8.count,
                    specifierPointer,
                    Int32(JS_EVAL_TYPE_MODULE | JS_EVAL_FLAG_COMPILE_ONLY)
                )
            }
        }
    }

    private func setImportMetaURL(_ sourceURL: String, on module: OpaquePointer) {
        let meta = ManagedQuickJSValue(JS_GetImportMeta(context, module), in: context)
        guard JS_IsException(meta.raw) == 0 else {
            clearPendingException()
            return
        }
        let url = newString(sourceURL)
        try? defineProperty(
            "url",
            on: meta.raw,
            value: url.raw,
            flags: Int32(JS_PROP_CONFIGURABLE | JS_PROP_WRITABLE | JS_PROP_ENUMERABLE)
        )
    }

    private func validateModuleSpecifier(_ specifier: String) throws {
        guard !specifier.isEmpty, !specifier.contains("\0") else {
            throw JavaScriptError(
                kind: .module,
                message: "Module specifiers must be non-empty and contain no NUL characters."
            )
        }
    }

    private func defaultResolveModule(_ requested: String, referrer: String?) -> String {
        guard requested == "." || requested == ".." ||
                requested.hasPrefix("./") || requested.hasPrefix("../"),
              let referrer else {
            return requested
        }

        let base = moduleSources[referrer]?.sourceURL ?? referrer
        let prefix: String
        if let slash = base.lastIndex(of: "/") {
            prefix = String(base[...slash])
        } else {
            prefix = ""
        }
        return normalizePath(prefix + requested)
    }

    private func normalizePath(_ path: String) -> String {
        let schemeRange = path.range(of: "://")
        var schemePrefix: String
        let remainder: Substring
        if let schemeRange {
            schemePrefix = String(path[..<schemeRange.upperBound])
            if path[schemeRange.upperBound...].hasPrefix("/") {
                schemePrefix += "/"
                remainder = path[path.index(after: schemeRange.upperBound)...]
            } else {
                remainder = path[schemeRange.upperBound...]
            }
        } else {
            schemePrefix = path.hasPrefix("/") ? "/" : ""
            let start = path.hasPrefix("/")
                ? path.index(after: path.startIndex)
                : path.startIndex
            remainder = path[start...]
        }

        var components: [Substring] = []
        for component in remainder.split(separator: "/", omittingEmptySubsequences: true) {
            if component == "." { continue }
            if component == ".." {
                if !components.isEmpty, components.last != ".." {
                    components.removeLast()
                } else if schemePrefix.isEmpty {
                    components.append(component)
                }
            } else {
                components.append(component)
            }
        }
        return schemePrefix + components.joined(separator: "/")
    }
}

internal let quickJSKitModuleNormalizer: @convention(c) (
    OpaquePointer?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    UnsafeMutableRawPointer?
) -> UnsafeMutablePointer<CChar>? = { context, base, requested, opaque in
    guard let context, let requested, let opaque else { return nil }
    let bridge = Unmanaged<QuickJSRuntimeBridge>.fromOpaque(opaque).takeUnretainedValue()
    guard let engine = bridge.engine,
          let normalized = engine.normalizeModule(
            base: base.map(String.init(cString:)) ?? "",
            requested: String(cString: requested)
          ) else {
        return nil
    }

    let bytes = Array(normalized.utf8) + [0]
    guard let allocation = js_malloc(context, bytes.count) else { return nil }
    bytes.withUnsafeBytes { source in
        allocation.copyMemory(from: source.baseAddress!, byteCount: bytes.count)
    }
    return allocation.assumingMemoryBound(to: CChar.self)
}

internal let quickJSKitModuleLoader: @convention(c) (
    OpaquePointer?,
    UnsafePointer<CChar>?,
    UnsafeMutableRawPointer?
) -> OpaquePointer? = { _, name, opaque in
    guard let name, let opaque else { return nil }
    let bridge = Unmanaged<QuickJSRuntimeBridge>.fromOpaque(opaque).takeUnretainedValue()
    return bridge.engine?.compileModuleForLoader(String(cString: name))
}

internal let quickJSKitSwiftModuleInitializer: @convention(c) (
    OpaquePointer?,
    OpaquePointer?
) -> Int32 = { context, module in
    guard let context, let module,
          let runtime = JS_GetRuntime(context),
          let opaque = JS_GetRuntimeOpaque(runtime) else {
        return -1
    }
    let bridge = Unmanaged<QuickJSRuntimeBridge>.fromOpaque(opaque).takeUnretainedValue()
    return bridge.engine?.initializeSwiftModule(module) ?? -1
}
