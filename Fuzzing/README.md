# QuickJSKit Fuzzing

This standalone package provides a coverage-guided libFuzzer boundary for:

- JavaScript parsing and evaluation;
- ES module compilation and static dependency discovery;
- direct Codable decoding and nesting limits;
- TypeScript and TSDoc escaping.

Run a short AddressSanitizer campaign with:

```sh
Scripts/run-fuzzing.sh 60
```

The argument is the maximum campaign duration in seconds. Input rejection is
expected; crashes, traps, leaks, hangs, and sanitizer findings are failures.
Minimize every finding and commit it as a deterministic regression test or seed
before closing the issue.

The fuzzer uses a tightly restricted runtime and does not access the network,
filesystem modules, credentials, or application capabilities.
