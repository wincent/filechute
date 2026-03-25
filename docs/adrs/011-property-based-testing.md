# ADR 011: Property-Based Testing

## Status

Proposed

## Context

The existing test suite (~380 tests across 20 suites) relies entirely on
example-based tests: hand-picked inputs with hand-written expected outputs.
This approach is effective for documenting known edge cases and verifying
specific behaviors, but it has a structural blind spot -- it only covers
inputs the author thought to try.

Several components in `FilechuteCore` are pure functions over broad input
domains where the interesting failures come from inputs a human is unlikely
to write by hand:

- **FTS5 query sanitization** transforms arbitrary user input into a safe
  FTS5 query string. The input space includes FTS5 operators (`NEAR`, `AND`,
  `OR`, `NOT`), quoting characters, Unicode, empty strings, and
  pathological whitespace. A missed edge case here can crash the search
  query or silently drop search terms.

- **UTF-8 truncation** cuts extracted text to a byte budget. The invariant
  (output is always valid UTF-8 and within the byte limit) must hold for
  every possible Unicode string and byte limit, including strings composed
  entirely of multi-byte characters and limits that fall mid-character.

- **ContentHash** must be deterministic: the same bytes must always produce
  the same hash regardless of whether they arrive via `Data` or via a file
  URL. This is foundational to the content-addressed store -- a violation
  would silently create duplicate objects or return the wrong file.

- **BulkTagState** computes `.all` / `.some` / `.none` from a mapping of
  object IDs to tag names and a set of selected object IDs. The logic is
  simple, but the input space (variable selection sizes, case-insensitive
  matching, objects missing from the mapping) has combinatorial breadth that
  a handful of examples cannot cover.

- **TableInteraction** is a pure state machine mapping `(KeyInput,
  InteractionContext)` to `InteractionEffect`. The context has boolean
  fields (editing, textFieldFocused, quickLookVisible, gridMode, trashView)
  and an optional column count, producing a large state space. Example
  tests cover key paths through it, but entire regions of the space are
  untested.

Property-based testing addresses this by generating random inputs,
asserting that properties (invariants) hold for all of them, and -- when a
failure is found -- shrinking the input to a minimal reproducing case.

The Swift ecosystem has a few property-based testing libraries (SwiftCheck,
Fox, Genything), but none are actively maintained. Adding a third-party
dependency for a testing utility introduces supply-chain risk and
maintenance burden disproportionate to the scope of what is needed. The
core machinery of property-based testing is small enough to implement
in-house.

## Decision

### Build a minimal property-based testing library in the test target

The implementation lives entirely in `Tests/`, adding no code to the
production target and no third-party dependencies.

### Core components

**`Gen<T>`**: A composable random value generator.

```swift
struct Gen<T> {
    let generate: (inout any RandomNumberGenerator) -> T
}
```

`Gen` supports `map` and `flatMap` for composition, plus static factory
methods for common types:

```swift
extension Gen where T == Int {
    static func int(in range: ClosedRange<Int>) -> Gen<Int> { ... }
}

extension Gen where T == String {
    static func string(
        count: Gen<Int> = .int(in: 0...100),
        alphabet: Gen<Character> = .character(in: .asciiPrintable)
    ) -> Gen<String> { ... }

    static func unicodeString(count: Gen<Int> = .int(in: 0...100)) -> Gen<String> { ... }
}

extension Gen where T == Data {
    static func data(count: Gen<Int> = .int(in: 0...1024)) -> Gen<Data> { ... }
}

extension Gen {
    static func element<C: Collection>(of collection: C) -> Gen<C.Element>
        where T == C.Element { ... }

    static func array<U>(of element: Gen<U>, count: Gen<Int> = .int(in: 0...20)) -> Gen<[U]>
        where T == [U] { ... }
}
```

Generators for domain types (`KeyInput`, `InteractionContext`,
`BulkTagState` inputs) are defined alongside their respective test suites
rather than in the shared infrastructure.

**`forAll`**: Runs a property assertion over many random inputs.

```swift
func forAll<T>(
    _ name: String = "",
    gen: Gen<T>,
    iterations: Int = 100,
    file: StaticString = #filePath,
    line: UInt = #line,
    property: (T) throws -> Bool
) {
    var rng: any RandomNumberGenerator = SeededRandomNumberGenerator(seed: stableSeed())
    for i in 0..<iterations {
        let value = gen.generate(&rng)
        XCTAssertTrue(
            try property(value),
            "\(name) failed on iteration \(i) with: \(value)",
            file: file,
            line: line
        )
    }
}
```

Overloads for two and three generators (`forAll(gen1, gen2, property:)`)
avoid forcing callers to tuple-compose manually.

**`SeededRandomNumberGenerator`**: A deterministic PRNG seeded from a
stable value (e.g., the test file name and current date). This makes
property test failures reproducible: re-running the same test on the same
day produces the same sequence. The seed is logged on failure so it can be
pinned for debugging.

```swift
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    // SplitMix64 or similar simple PRNG with known-good statistical properties.
    private var state: UInt64

    init(seed: UInt64) { self.state = seed }

    mutating func next() -> UInt64 { ... }
}
```

### Shrinking

Shrinking (reducing a failing input to a minimal reproducing case) is
valuable but adds significant implementation complexity. The initial
implementation omits automatic shrinking. Instead, the `forAll` function
logs the failing input and the seed, making it straightforward to
reproduce and manually minimize.

If experience shows that failing inputs are frequently large and hard to
interpret without shrinking, it can be added later by extending `Gen<T>`
with a `shrink: (T) -> [T]` function. This is an additive change that does
not require modifying existing property definitions.

### Target properties

Properties are organized as extensions to existing test suites, not as a
separate suite, so they run as part of `make test` alongside existing
example-based tests.

#### FTS5 query sanitization

| Property                  | Description                                                                                                                                                                         |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| No FTS5 syntax errors     | For any input string, passing the sanitized output to `sqlite3_prepare_v2` with a `MATCH` clause does not return `SQLITE_ERROR`. (Requires a live FTS5 table in the test database.) |
| Roundtrip preservation    | For any input consisting only of alphanumeric words separated by spaces, every word appears as a prefix-match term in the sanitized output.                                         |
| No raw special characters | The sanitized output never contains unescaped `"`, `*`, `(`, `)`, or `:` outside of the quoting structure the sanitizer itself produces.                                            |

Generator: `Gen.unicodeString()` biased toward strings containing FTS5
operator keywords (`NEAR`, `AND`, `OR`, `NOT`) and special characters
(`"`, `*`, `(`, `)`, `:`, `^`).

#### UTF-8 truncation

| Property            | Description                                                                                                                                    |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Valid UTF-8         | `String(data: result.data(using: .utf8)!, encoding: .utf8) != nil` for all inputs. Equivalently: the result's `utf8.count` is its byte length. |
| Respects byte limit | `result.utf8.count <= maxBytes` for all `(string, maxBytes)` pairs.                                                                            |
| Idempotent          | `truncate(truncate(s, to: n), to: n) == truncate(s, to: n)`.                                                                                   |
| Short passthrough   | If `s.utf8.count <= maxBytes`, the result equals the original string.                                                                          |

Generator: `Gen.unicodeString()` paired with `Gen.int(in: 0...200)` for
the byte limit. The string generator should be biased toward multi-byte
characters (CJK, emoji, combining marks) since those are where boundary
errors occur.

#### ContentHash determinism

| Property                | Description                                                                                                             |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Deterministic           | `ContentHash.compute(from: data) == ContentHash.compute(from: data)` for all `Data`.                                    |
| File-data agreement     | For any `Data`, writing it to a temp file and calling `compute(fromFileAt:)` returns the same hash as `compute(from:)`. |
| Prefix/suffix partition | `hash.prefix + hash.suffix == hash.value` and `hash.prefix.count == 2`.                                                 |

Generator: `Gen.data(count: .int(in: 0...10_000))`.

#### BulkTagState

| Property           | Description                                                                                        |
| ------------------ | -------------------------------------------------------------------------------------------------- |
| Consistency        | If every selected object has the tag, state is `.all`. If none do, `.none`. Otherwise `.some`.     |
| Empty selection    | `compute` returns `.none` for an empty selection regardless of the mapping.                        |
| Case insensitivity | Adding the same tag name in a different case to all objects does not change the state from `.all`. |

Generator: random `[Int64: [String]]` mapping and `Set<Int64>` selection,
with tag names drawn from a small alphabet to encourage collisions.

#### TableInteraction

| Property                          | Description                                                                                                         |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| Totality                          | Every `(KeyInput, InteractionContext)` pair produces a valid `InteractionEffect` (no traps, no undefined behavior). |
| Editing blocks shortcuts          | When `context.isEditing` is true, the result is always `.passthrough` for non-escape keys.                          |
| Text field focus blocks shortcuts | When `context.textFieldIsFocused` is true, the result is always `.passthrough`.                                     |

Generator: `Gen.element(of: KeyInput.allCases)` combined with a
`Gen<InteractionContext>` that randomizes each boolean field and the column
count.

### File organization

```
Tests/
  FilechuteCoreTests/
    PropertyTesting/
      Gen.swift                          -- Gen<T>, combinators, common generators
      SeededRandomNumberGenerator.swift  -- deterministic PRNG
      ForAll.swift                       -- forAll function and overloads
    DatabasePropertyTests.swift          -- FTS5 sanitization properties
    TextExtractorPropertyTests.swift     -- UTF-8 truncation properties
    ContentHashPropertyTests.swift       -- hash determinism properties
    BulkTagStatePropertyTests.swift      -- tag state properties
    TableInteractionPropertyTests.swift  -- state machine properties
```

### Iteration count

Default 100 iterations per property. This is conservative -- enough to
catch most off-by-one and boundary errors without meaningfully slowing
`make test`. Individual properties that cover especially large input spaces
(FTS5 sanitization, TableInteraction) can override to 500 or more if the
per-iteration cost is low.

## Consequences

- Five components gain coverage over their full input domain rather than
  just hand-picked examples. The FTS5 sanitizer and UTF-8 truncation
  properties are the most likely to surface real bugs, given their
  adversarial input spaces.
- No third-party dependencies are added. The property testing
  infrastructure is ~150 lines of Swift in the test target.
- `make test` time increases slightly. At 100 iterations across 5 suites
  with ~15 total properties, the added time is on the order of seconds
  (dominated by the FTS5 property, which requires database round-trips).
- The deterministic seed makes failures reproducible without needing to
  save the failing input. This is less ergonomic than automatic shrinking
  but adequate for the input sizes involved.
- The `Gen` / `forAll` infrastructure is reusable for any future component
  that has testable invariants.

## Alternatives Considered

- **SwiftCheck**: The most established Swift property-based testing
  library, modeled after Haskell's QuickCheck. Provides automatic
  shrinking, `Arbitrary` protocol conformances for standard types, and
  rich combinators. However, it has not been actively maintained since
  2022, has open issues with Swift concurrency compatibility, and pulls
  in a non-trivial dependency graph. The subset of functionality needed
  here (generators, `forAll`, deterministic replay) does not justify the
  dependency.
- **Fox**: An Objective-C/Swift library inspired by Clojure's test.check.
  Also unmaintained. Its Objective-C core makes it awkward to use with
  Swift value types and actors.
- **Genything**: A newer library from Just Eat Takeaway with composable
  generators. More active than the above but with a small community and
  uncertain long-term maintenance. Adds dependency risk for marginal
  benefit over a hand-rolled solution.
- **Swift Testing parameterized tests**: Apple's `@Test(arguments:)` runs
  a test over an explicit collection of inputs. This covers some of the
  same ground for enumerable input sets (e.g., `KeyInput.allCases`) but
  does not provide random generation, so it cannot explore the large input
  spaces that make property-based testing valuable. Parameterized tests
  complement property-based tests but do not replace them.
- **Implementing automatic shrinking from the start**: Shrinking is the
  most complex part of a property-based testing library, typically
  doubling the implementation size. For the input sizes and types involved
  here (short strings, small integers, booleans, small arrays), failing
  inputs are already small enough to interpret directly. Deferring
  shrinking avoids upfront complexity while leaving the door open.
- **Using `SystemRandomNumberGenerator` directly**: Simpler, but makes
  failures non-reproducible. A test that fails in CI but passes locally
  is far harder to debug than one where the seed can be pinned.
