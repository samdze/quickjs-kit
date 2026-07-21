internal import CQuickJS

extension QuickJSEngine {
    internal func prepareProgram(_ program: JavaScriptProgram) throws {
        let identifier = ObjectIdentifier(program.identity)
        guard compiledProgramValues[identifier] == nil else { return }
        compiledProgramValues[identifier] = try compileProgram(program)
        preparedProgramCompilationCountForTesting += 1
    }

    internal func compileProgramArtifact(
        _ program: JavaScriptProgram
    ) throws -> [UInt8]? {
        let compiled = try compileProgram(program)
        var byteCount = 0
        // JS_WriteObject returns a context-allocated buffer. Copy it into
        // detached Swift storage before the temporary compiler is destroyed.
        guard let bytes = JS_WriteObject(
            context,
            &byteCount,
            compiled.raw,
            Int32(JS_WRITE_OBJ_BYTECODE)
        ) else {
            clearPendingException()
            return nil
        }
        defer { js_free(context, bytes) }
        return Array(UnsafeBufferPointer(start: bytes, count: byteCount))
    }

    internal func installCompiledProgramArtifact(
        _ bytes: [UInt8],
        for program: JavaScriptProgram
    ) throws {
        guard !bytes.isEmpty else { throw RuntimeTemplateArtifactReadError() }
        let raw = bytes.withUnsafeBufferPointer { buffer in
            JS_ReadObject(
                context,
                buffer.baseAddress,
                buffer.count,
                Int32(JS_READ_OBJ_BYTECODE)
            )
        }
        guard JS_IsException(raw) == 0 else {
            clearPendingException()
            throw RuntimeTemplateArtifactReadError()
        }
        let compiled = ManagedQuickJSValue(raw, in: context)
        guard quickJSValueTag(compiled.raw) == Int32(JS_TAG_FUNCTION_BYTECODE) else {
            throw RuntimeTemplateArtifactReadError()
        }
        compiledProgramValues[ObjectIdentifier(program.identity)] = compiled
        cachedProgramReadCountForTesting += 1
    }

    internal func evaluatePreparedProgram(
        _ program: JavaScriptProgram
    ) throws -> ManagedQuickJSValue {
        try prepareProgram(program)
        let identifier = ObjectIdentifier(program.identity)
        guard let compiled = compiledProgramValues[identifier] else {
            throw JavaScriptError(
                kind: .internalFailure,
                message: "A prepared JavaScript program was not retained."
            )
        }

        // JS_EvalFunction consumes its +1 argument. Duplicate the retained
        // compiled function so the program remains reusable.
        let raw = JS_EvalFunction(context, JS_DupValue(context, compiled.raw))
        let result = ManagedQuickJSValue(raw, in: context)
        if JS_IsException(raw) != 0 {
            throw extractException(sourceURL: program.sourceURL)
        }
        return result
    }

    private func compileProgram(
        _ program: JavaScriptProgram
    ) throws -> ManagedQuickJSValue {
        let sourceByteCount = program.source.utf8.count
        let raw = program.source.withCString { sourcePointer in
            program.sourceURL.withCString { sourceURLPointer in
                JS_Eval(
                    context,
                    sourcePointer,
                    sourceByteCount,
                    sourceURLPointer,
                    Int32(JS_EVAL_TYPE_GLOBAL | JS_EVAL_FLAG_COMPILE_ONLY)
                )
            }
        }
        let compiled = ManagedQuickJSValue(raw, in: context)
        if JS_IsException(raw) != 0 {
            throw extractException(sourceURL: program.sourceURL)
        }
        guard quickJSValueTag(compiled.raw) == Int32(JS_TAG_FUNCTION_BYTECODE) else {
            throw JavaScriptError(
                kind: .internalFailure,
                message: "Compile-only program evaluation did not produce a function.",
                sourceURL: program.sourceURL
            )
        }
        return compiled
    }
}
