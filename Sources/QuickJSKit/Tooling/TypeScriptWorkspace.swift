internal import Foundation

extension JavaScriptEnvironmentDescription {
    /// Generates a detached IDE workspace artifact.
    ///
    /// - Parameter options: Workspace layout and declaration options.
    /// - Returns: Files that can be inspected or written later.
    /// - Throws: ``TypeScriptToolingError`` for invalid or incomplete metadata.
    public func typeScriptWorkspace(
        options: TypeScriptWorkspaceOptions = .init()
    ) throws -> TypeScriptWorkspace {
        try TypeScriptWorkspace(environment: self, options: options)
    }
}

/// Options for generating a TypeScript-aware editor workspace.
public struct TypeScriptWorkspaceOptions: Sendable, Hashable {
    /// Source patterns included by the generated TypeScript project.
    public var sourceGlobs: [String]

    /// Whether TypeScript checks JavaScript files as well as TypeScript files.
    public var checkJavaScript: Bool

    /// Whether to generate a minimal private ESM `package.json`.
    public var includePackageJSON: Bool

    /// Options for the generated ambient declaration file.
    public var declarationOptions: TypeScriptDeclarationOptions

    /// Source-map options, or `nil` to omit declaration maps.
    public var sourceMapOptions: TypeScriptSourceMapOptions?

    /// Creates workspace options.
    public init(
        sourceGlobs: [String] = [
            "**/*.js",
            "**/*.mjs",
            "**/*.ts",
            "**/*.mts",
        ],
        checkJavaScript: Bool = true,
        includePackageJSON: Bool = false,
        declarationOptions: TypeScriptDeclarationOptions = .init(),
        sourceMapOptions: TypeScriptSourceMapOptions? = .init()
    ) {
        self.sourceGlobs = sourceGlobs
        self.checkJavaScript = checkJavaScript
        self.includePackageJSON = includePackageJSON
        self.declarationOptions = declarationOptions
        self.sourceMapOptions = sourceMapOptions
    }
}

/// A detached collection of generated TypeScript workspace files.
public struct TypeScriptWorkspace: Sendable, Hashable {
    /// One UTF-8 text file in the generated workspace.
    public struct File: Sendable, Hashable {
        /// A validated path relative to the workspace directory.
        public let path: String

        /// The complete UTF-8 file contents.
        public let contents: String

        /// Creates a generated workspace file.
        public init(path: String, contents: String) {
            self.path = path
            self.contents = contents
        }
    }

    /// Controls replacement of files previously owned by QuickJSKit.
    public enum WritePolicy: Sendable, Hashable {
        /// Update only generated files unchanged since the previous write.
        case updateGenerated
        /// Replace modified generated files while preserving unrelated files.
        case overwriteGenerated
    }

    /// Generated files in deterministic path order.
    public let files: [File]

    internal init(
        environment: JavaScriptEnvironmentDescription,
        options: TypeScriptWorkspaceOptions
    ) throws {
        for glob in options.sourceGlobs {
            try Self.validateRelativePath(glob, role: "source glob", permitsGlob: true)
        }
        let declarations: String
        var files: [File]
        if let sourceMapOptions = options.sourceMapOptions {
            let bundle = try environment.typeScriptDeclarationBundle(
                options: options.declarationOptions,
                sourceMapOptions: sourceMapOptions
            )
            declarations = bundle.declarations
            files = [
                File(
                    path: "quickjskit.generated.d.ts.map",
                    contents: bundle.sourceMap
                ),
            ]
        } else {
            declarations = try environment.typeScriptDeclarations(
                options: options.declarationOptions
            )
            files = []
        }
        files.append(
            File(path: "quickjskit.generated.d.ts", contents: declarations)
        )
        files.append(File(path: "tsconfig.json", contents: Self.tsconfig(options: options)))
        if options.includePackageJSON {
            files.append(
                File(
                    path: "package.json",
                    contents: "{\n  \"private\": true,\n  \"type\": \"module\"\n}\n"
                )
            )
        }
        self.files = files.sorted { $0.path < $1.path }
    }

    private static func tsconfig(options: TypeScriptWorkspaceOptions) -> String {
        let include = (["quickjskit.generated.d.ts"] + options.sourceGlobs)
            .map { "    \(quotedJSONString($0))" }
            .joined(separator: ",\n")
        return """
        {
          "compilerOptions": {
            "allowJs": true,
            "checkJs": \(options.checkJavaScript),
            "module": "ESNext",
            "moduleResolution": "Bundler",
            "noEmit": true,
            "strict": true,
            "target": "ES2024"
          },
          "include": [
        \(include)
          ]
        }
        """ + "\n"
    }

    fileprivate static func validateRelativePath(
        _ path: String,
        role: String,
        permitsGlob: Bool = false
    ) throws {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("\\") else {
            throw TypeScriptToolingError("The \(role) '\(path)' must be relative.")
        }
        let forbidden = permitsGlob ? CharacterSet(charactersIn: "\0") : CharacterSet(charactersIn: "\0*?")
        guard path.rangeOfCharacter(from: forbidden) == nil,
              !path.split(separator: "/", omittingEmptySubsequences: false).contains(".."),
              !path.split(separator: "\\", omittingEmptySubsequences: false).contains("..") else {
            throw TypeScriptToolingError("The \(role) '\(path)' is not safe.")
        }
    }
}

internal struct WorkspaceWriter {
    private static let manifestPath = ".quickjskit-manifest.json"
    private let workspace: TypeScriptWorkspace
    private let fileManager = FileManager.default

    internal init(workspace: TypeScriptWorkspace) {
        self.workspace = workspace
    }

    internal func write(
        to directory: URL,
        policy: TypeScriptWorkspace.WritePolicy
    ) throws {
        try ensureDirectory(directory)
        try rejectSymlink(directory, role: "workspace directory")
        let oldManifest = try readManifest(in: directory)
        let newContents = Dictionary(uniqueKeysWithValues: workspace.files.map {
            ($0.path, Data($0.contents.utf8))
        })
        for path in newContents.keys {
            try TypeScriptWorkspace.validateRelativePath(path, role: "generated path")
            try rejectSymlinkComponents(in: directory, path: path)
            try checkDestination(
                directory.appendingPathComponent(path),
                path: path,
                oldManifest: oldManifest,
                policy: policy
            )
        }

        let obsolete = Set(oldManifest.keys).subtracting(newContents.keys)
        let removableObsolete = try obsolete.filter { path in
            let url = directory.appendingPathComponent(path)
            guard fileManager.fileExists(atPath: url.path) else { return false }
            try rejectSymlinkComponents(in: directory, path: path)
            return try hash(Data(contentsOf: url)) == oldManifest[path]
        }

        let staging = directory.appendingPathComponent(
            ".quickjskit-staging-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: staging) }

        for (path, contents) in newContents {
            let staged = staging.appendingPathComponent(path)
            try fileManager.createDirectory(
                at: staged.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: staged)
        }
        let manifest = manifestData(
            Dictionary(uniqueKeysWithValues: newContents.map { ($0.key, hash($0.value)) })
        )
        try manifest.write(to: staging.appendingPathComponent(Self.manifestPath))

        let affected = Set(newContents.keys)
            .union(removableObsolete)
            .union([Self.manifestPath])
        var backup: [String: Data?] = [:]
        for path in affected {
            let destination = directory.appendingPathComponent(path)
            if fileManager.fileExists(atPath: destination.path) {
                backup[path] = .some(try Data(contentsOf: destination))
            } else {
                backup[path] = .some(nil)
            }
        }

        do {
            for path in removableObsolete {
                try fileManager.removeItem(at: directory.appendingPathComponent(path))
            }
            for path in newContents.keys.sorted() + [Self.manifestPath] {
                let destination = directory.appendingPathComponent(path)
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let staged = staging.appendingPathComponent(path)
                let data = try Data(contentsOf: staged)
                try data.write(to: destination, options: .atomic)
            }
        } catch {
            for (path, contents) in backup {
                let destination = directory.appendingPathComponent(path)
                if let contents {
                    try? contents.write(to: destination, options: .atomic)
                } else if fileManager.fileExists(atPath: destination.path) {
                    try? fileManager.removeItem(at: destination)
                }
            }
            throw error
        }
    }

    private func ensureDirectory(_ directory: URL) throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw TypeScriptToolingError("The workspace destination is not a directory.")
            }
        } else {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func checkDestination(
        _ url: URL,
        path: String,
        oldManifest: [String: String],
        policy: TypeScriptWorkspace.WritePolicy
    ) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try rejectSymlink(url, role: "managed file")
        guard let expected = oldManifest[path] else {
            throw TypeScriptToolingError(
                "QuickJSKit will not replace unrelated file '\(path)'."
            )
        }
        if policy == .updateGenerated,
           try hash(Data(contentsOf: url)) != expected {
            throw TypeScriptToolingError(
                "Generated file '\(path)' was modified; use overwriteGenerated to replace it."
            )
        }
    }

    private func readManifest(in directory: URL) throws -> [String: String] {
        let url = directory.appendingPathComponent(Self.manifestPath)
        guard fileManager.fileExists(atPath: url.path) else { return [:] }
        try rejectSymlink(url, role: "ownership manifest")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        guard let root = object as? [String: Any],
              let version = root["version"] as? Int,
              version == 1,
              let files = root["files"] as? [String: String] else {
            throw TypeScriptToolingError("The QuickJSKit ownership manifest is invalid.")
        }
        for path in files.keys {
            try TypeScriptWorkspace.validateRelativePath(path, role: "manifest path")
        }
        return files
    }

    private func manifestData(_ hashes: [String: String]) -> Data {
        let entries = hashes.keys.sorted().map {
            "    \(quotedJSONString($0)): \(quotedJSONString(hashes[$0] ?? ""))"
        }.joined(separator: ",\n")
        return Data("{\n  \"version\": 1,\n  \"files\": {\n\(entries)\n  }\n}\n".utf8)
    }

    private func rejectSymlink(_ url: URL, role: String) throws {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
        if values.isSymbolicLink == true {
            throw TypeScriptToolingError("The \(role) '\(url.lastPathComponent)' cannot be a symlink.")
        }
    }

    private func rejectSymlinkComponents(in directory: URL, path: String) throws {
        var current = directory
        for component in path.split(separator: "/") {
            current.appendPathComponent(String(component))
            guard fileManager.fileExists(atPath: current.path) else { continue }
            try rejectSymlink(current, role: "managed path")
        }
    }

    private func hash(_ data: Data) -> String {
        var value: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            value ^= UInt64(byte)
            value &*= 1_099_511_628_211
        }
        return String(value, radix: 16)
    }
}
