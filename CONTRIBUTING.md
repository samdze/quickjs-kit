# Contributing to QuickJSKit

Read `AGENTS.md`, `Documentation/Architecture.md`, and the relevant architectural
decision records before changing the package. Discuss new public abstractions,
ownership changes, or concurrency changes before implementing a large surface.

Contributions should:

- keep C and unsafe state behind the internal runtime boundary;
- preserve one actor as the synchronization boundary for each QuickJS heap;
- include public executable examples and internal invariant tests as needed;
- document every public symbol with DocC;
- update architecture, migration notes, and the changelog when contracts change;
- use English Conventional Commit messages;
- keep vendored QuickJS upgrades isolated from wrapper changes.

Before opening a pull request, run:

```sh
swift test
swift test -c release -Xswiftc -warnings-as-errors
Scripts/verify-vendored-quickjs.sh
```

Also build the standalone examples and platform smoke consumer. CI adds C
warnings-as-errors, TypeScript/TSDoc fixtures, DocC, symbol graphs, sanitizer
runs, platform qualification, and repeated concurrency tests.

Security vulnerabilities must follow `SECURITY.md`, not the public issue tracker.
