internal import CQuickJS

/// Swift equivalents for QuickJS macros that Clang cannot import when JSValue
/// uses its struct representation.
internal func quickJSNull() -> JSValue {
#if arch(i386) || arch(arm) || arch(arm64_32) || arch(wasm32)
    UInt64(UInt32(bitPattern: Int32(JS_TAG_NULL))) << 32
#else
    var storage = JSValueUnion()
    storage.uint64 = 0
    return JSValue(u: storage, tag: Int64(JS_TAG_NULL))
#endif
}

internal func quickJSUndefined() -> JSValue {
#if arch(i386) || arch(arm) || arch(arm64_32) || arch(wasm32)
    UInt64(UInt32(bitPattern: Int32(JS_TAG_UNDEFINED))) << 32
#else
    var storage = JSValueUnion()
    storage.uint64 = 0
    return JSValue(u: storage, tag: Int64(JS_TAG_UNDEFINED))
#endif
}

internal func quickJSObjectAddress(_ value: JSValue) -> UInt {
#if arch(i386) || arch(arm) || arch(arm64_32) || arch(wasm32)
    UInt(truncatingIfNeeded: value)
#else
    UInt(bitPattern: value.u.ptr)
#endif
}
