/// A runtime-bound decoder that reads native JavaScript values directly.
public struct JavaScriptDecoder: Sendable {
    /// The default maximum number of nested containers.
    public static let defaultMaximumNestingDepth = 64

    internal let runtime: JavaScriptRuntime

    /// The maximum number of nested keyed or unkeyed containers.
    ///
    /// Values below one are rejected with `DecodingError` when decoding begins.
    public var maximumNestingDepth: Int

    internal init(runtime: JavaScriptRuntime) {
        self.runtime = runtime
        self.maximumNestingDepth = Self.defaultMaximumNestingDepth
    }

    /// Decodes a JavaScript value directly into a Swift type.
    public func decode<T: Decodable & Sendable>(
        _ type: T.Type,
        from value: JavaScriptValue
    ) async throws -> T {
        try await runtime.decode(
            type,
            from: value,
            maximumNestingDepth: maximumNestingDepth
        )
    }
}
