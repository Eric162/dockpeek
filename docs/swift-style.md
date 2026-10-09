# Swift style

DockPeek follows the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
for API design and [Google's Swift Style Guide](https://google.github.io/swift/)
for source organization and coding conventions. The project decisions below take
precedence where they differ. Review changes against both guides, including rules
that automated checks cannot assess.

## Automated enforcement

Run `make format`, then `make check`. The pinned swift-format configuration in
[.swift-format](../.swift-format) owns layout and syntax style. SwiftLint's explicit
rule list in [.swiftlint.yml](../.swiftlint.yml) owns semantic and complexity checks;
`make analyze` also checks unused imports using compiler information. Git hooks and
CI run these gates. Compiler warnings are errors in every Swift target.

| Convention | Enforcement |
| --- | --- |
| Two-space indentation, 100-column wrapping, trailing collection commas, ordered imports | swift-format layout and `OrderedImports` |
| Capitalized type names, lower camel case members, access control instead of leading underscores | `TypeNamesShouldBeCapitalized`, `AlwaysUseLowerCamelCase`, `NoLeadingUnderscores` |
| One declaration per line, no semicolons or parenthesized conditions | swift-format syntax rules |
| Early exits and loop filters | `UseEarlyExits`, `UseWhereClausesInForLoops` |
| Optional binding and throwing operations for fallible work | Force unwrap/try/IUO formatter rules and SwiftLint force-cast rules |
| Documentation syntax and summaries | `UseTripleSlashForDocumentationComments`, `BeginDocumentationCommentWithOneLineSummary`, `ValidateDocumentationComments` |
| Unused imports, concurrency mistakes, excessive complexity | SwiftLint lint/analyzer rules and Swift 6 compiler checking |

A passing formatter or linter does not establish full style-guide compliance.

## Review requirements

Choose names that explain the domain and make call sites clear. Check argument
labels, units, side effects, and optional/error semantics when adding APIs.

Name files after their primary abstraction, group related helpers intentionally,
and keep related overloads adjacent. Order members so a reader can follow the
lifecycle or responsibilities. Use `// MARK:` when it helps navigation.

Document contracts that callers cannot infer from the declaration, including
failure behavior, cancellation, ownership, coordinate systems, and time units.
Keep comments accurate when behavior changes.

Preserve the target boundaries described in CONTRIBUTING.md. AppKit and SwiftUI
state belongs on the main actor; subprocess ownership belongs in DockPeekRuntime;
pure decisions belong in DockPeekCore. Review concurrency escape annotations and
resource cleanup explicitly.

## Project exceptions

- Public declarations used only to cross this application's target boundaries do
  not require comments that repeat obvious names. `AllPublicDeclarationsHaveDocumentation`
  stays disabled. Document non-obvious contracts during review; a published library
  API would require a separate documentation review.
- The pinned formatter decides wrapping, compact declarations, and attribute
  placement. Hand formatting from upstream examples does not override its output.
  Explicit returns remain allowed for clarity.
- Executable entry points use `main.swift`. Small related helper types and test
  suites may share a descriptive file.
- Identifiers are ASCII. User-facing strings may contain Unicode.
- Force unwraps, force casts, force try, and implicitly unwrapped optionals are
  prohibited by the automated gates, including tests and experiments.

For a new exception, explain the specific constraint here and next to any affected
rule configuration. Use the smallest scope and run the existing checks before
changing policy.
