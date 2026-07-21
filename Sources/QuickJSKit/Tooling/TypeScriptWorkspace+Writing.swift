public import struct Foundation.URL

extension TypeScriptWorkspace {
    /// Writes this artifact using a manifest that protects user modifications.
    ///
    /// All generated files are staged before replacement. Managed-path
    /// symlinks and path traversal are rejected. If a replacement fails,
    /// existing managed files are restored to their previous contents.
    ///
    /// - Parameters:
    ///   - directory: Destination workspace directory.
    ///   - policy: How modified files from an earlier generation are handled.
    /// - Throws: ``TypeScriptToolingError`` or an underlying filesystem error.
    public func write(
        to directory: URL,
        policy: WritePolicy = .updateGenerated
    ) throws {
        try WorkspaceWriter(workspace: self).write(to: directory, policy: policy)
    }
}
