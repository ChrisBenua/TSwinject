# TSwinject

A casting-free Swinject alternative. The whole library is structured around one
observation: in Swift, casting `Any → SomeConcreteGenericClass<T>` is O(1), while
`Any → SomeProtocol` walks every protocol-conformance descriptor in the binary.
Swinject does the latter on every resolve; TSwinject does the former.

The public API mirrors Swinject's so call sites only swap `import Swinject` for
`import TSwinject`.

## The load-bearing trick

Every registered service is boxed in a generic class:

- `DiEntryConcrete<T>` — strong reference, holds `var value: T`
- `DiEntryWeak<T>` — weak reference, lazily produced via a `(T, () -> T?)` pair

Containers store these as `Any` in a `ThreadSafeDictionary<ServiceKey, ServiceEntry>`
(an rwlock-guarded dictionary, same design Swinject uses). The key is built from
`ObjectIdentifier(DiEntryConcrete<Service>.self)` (not `Service` directly), so the
cast back to the wrapper is guaranteed by construction — the runtime never has to
scan conformances. After the cast, `.value` is a plain stored property read.

**Do not "simplify" this by storing `Service` directly as `Any` and casting
`any as? Service`.** That is the exact slow path the library exists to avoid. The
header comment in `Container.swift` exists to flag this for future readers.

## Module layout

- `Sources/TSwinject/` — core library. No external dependencies. Keep it that way;
  `Tests/Fixtures/verify-isolation.sh` fails the build if Swinject or swift-syntax
  ever get compiled into a core-only consumer.
- `Sources/TSwinjectSwinjectInterop/` — optional migration bridge. Depends on
  Swinject. Single mode: **takeover** — the TSwinject container becomes a typed
  façade over a real Swinject container (every register/resolve, plus
  `removeAll`/`resetObjectScope`/`hasAnyRegistration` and `initCompleted`, routes
  to Swinject). Entry point: `Container.attachSwinjectBridge(_:scopeMap:)` — point
  the façade at the *legacy* container for a **single shared registry**, so
  neither side can miss the other's registrations and one engine upholds
  graph/scope/circularity invariants (see `docs/MIGRATION.md`).
  A bidirectional `.both` mirror mode existed and was deliberately removed — two
  engines cannot share graph identity or in-flight circularity state; do not
  reintroduce it (see `docs/DESIGN.md`).
- `Sources/TSwinjectMacro/` + `Sources/TSwinjectMacroPlugin/` — the `#implements`
  freestanding macro and its swift-syntax plugin.
- `Tests/TSwinjectTests/` — Core, Advanced (graph/initCompleted/reset), Arguments
  (1..9-arg), Assembler, ResolveTracking suites.
- `Tests/TSwinjectInteropTests/` — bridge tests against a real Swinject container.
- `Tests/TSwinjectMacroTests/` — `MacroExpansionTests` asserts the expanded source;
  `MacroRuntimeTests` exercises `#implements` against a real `Container` and is the
  executable specification of what it generates.
- `Tests/TSwinjectBenchmarks/` — the benchmark the README quotes. The library's
  reason to exist lives or dies by this number, so don't regress it silently.

## Source file map (what to look at when)

- `Container.swift` — central type. 0-arg `register` / `registerWeak`,
  `installEntry`, `resolveEntry`, scope/graph lifecycle, parent chain,
  `synchronize()`, behavior dispatch. Conforms to `Resolver`.
- `Container.Arguments.swift` — 1..9-arg variants. ~1500 lines of intentional
  boilerplate, one block per arity. Parameter packs were tried and reverted (see
  "Deferred" below).
- `DiEntry.swift` — the two wrapper classes. Tiny but performance-critical. Both
  types + their `value` / `factory` / inits are `@usableFromInline` so the
  resolution path can be made `@inlinable` across the module boundary.
- `ServiceEntry.swift` — internal registration record. Keep it `internal` — the
  `Behavior` protocol deliberately does not expose it (unlike Swinject).
- `ServiceKey.swift` — `(serviceType, argumentsType, name)` triple, hashed via
  `ObjectIdentifier`. The `argumentsType` field is what keeps different arities
  from colliding on the same `Service.Type`.
- `Resolver.swift` — protocol with 0..9-arg `resolve` overloads. The unnamed
  defaults forward to `name: nil`; the **named defaults return `nil`**, which is
  the trap for anyone conforming a test stub. `Container` overrides every variant.
- `ObjectScope.swift` — `.transient`, `.graph` (default), `.container`.
  `ObjectScope` is a final class whose `description` is used as identity by the
  interop bridge's scope mapping — `InteropTests.testBuiltInScopeDescriptions_areStableBridgeKeys`
  pins those strings, because renaming one would silently degrade every custom
  scope to `.graph` via the `default:` branch with no compile error.
- `WeakObjectScope.swift` — separate protocol from `ObjectScopeProtocol` because
  the semantics differ: the `DiEntryWeak` *wrapper* is held permanently; only the
  *wrapped value* is weak.
- `InstanceStorage.swift` — `GraphStorage` / `PermanentStorage` / `TransientStorage`
  / `CompositeStorage`. The storage type *is* the lifetime policy.
- `Assembly.swift` + `Assembler.swift` — Swinject-compatible assembly composition.
  The deprecated throwing initializers were removed (this is a fresh library — no
  v1→v2 migration shims).
- `Behavior.swift` — simpler than Swinject's; the callback does not receive a
  `ServiceEntry`.
- `GraphIdentifier.swift` — `UUID` on Apple platforms, `UInt.random` elsewhere
  (Linux has no universal `UUID`).
- `RecursiveLock.swift` — pthread recursive mutex on Apple platforms
  (`os_unfair_lock_recursive` is private API), `NSRecursiveLock` elsewhere.
- `ThreadSafeDictionary.swift` + `ReadWriteLock.swift` — rwlock-guarded backing
  store for `services` (ported from Swinject's own design); registration is always
  thread-safe, concurrent *resolution* still requires `synchronize()`.
- `TakeoverSink.swift` — protocol the core routes everything through when
  `routeAllToSink` is set, without depending on Swinject. The interop module
  implements it.
- `ResolveTracking.swift` — opt-in per-resolve timing events: process-wide
  `ResolveTracking.factory` + per-container `resolveTracker`, gated by a
  thread-local re-entrancy guard so only top-level resolves emit.
- `weakify.swift` — `weakInstance(MyService())` returns `(value, () -> T?)` for
  `registerWeak`. Note the function is `weakInstance`, not `weakify`; the filename
  predates the rename.

## Conventions

- **No deprecated methods, no compatibility shims.** This is a new library that
  happens to look like Swinject's API. Do not port over Swinject's
  `UnavailableItems.swift`-style migration stubs.
- **No `Foundation` import in files that don't need it.** Most pure-Swift files
  don't.
- **Public API surface = Swinject's surface.** When in doubt, match Swinject's
  method signatures, parameter labels, and defaults so consumers can swap the
  import and walk away. The interop module is the escape valve for the
  genuinely-different cases.
- **Arity boilerplate stays unfolded.** `Container.Arguments.swift` repeats nearly
  identical code 9 times. Don't macro/generic this away — parameter packs were
  tried (see below) and broke the call-site experience.
- **Tests use `@testable import TSwinject`** and define their fixtures (`Animal`,
  `Cat`, `Owner`, …) `private` per file. Don't share fixtures across test files.
- **`@usableFromInline` is the inlining contract.** If you add a member that the
  resolution hot path touches, annotate it. Don't make the whole type `public` to
  work around access control.
- **Attribution is not optional.** Files derived from Swinject carry a
  `Portions derived from Swinject` header and are listed in `NOTICE`. Swinject is
  MIT, which requires its copyright notice be retained. If you port more code from
  upstream, add the header and update `NOTICE` in the same commit.

## Build / test / bench

```sh
swift build
swift test --skip TSwinjectBenchmarks     # 135 tests, fast
swiftlint --strict                        # missing_docs is enabled on Sources/
```

Benchmarks — **must be release**, debug numbers are noise:

```sh
swift test -c release --filter ContainerBenchmarkTests
```

`test_rawComparison_printOnly` prints the ns/resolve and speedup quoted in the
README. Re-measure and update the README table if you touch `Container.swift`,
`Container.Arguments.swift`, or `DiEntry.swift`.

Dependency isolation (runs in CI, and should be run after any manifest change):

```sh
./Tests/Fixtures/verify-isolation.sh
```

Platform: iOS 16 / macOS 13. Swift 6, language mode 6.

## Deferred / known limits

- **10+ argument overloads.** Parameter-pack variants were prototyped and dropped:
  with a defaulted `name:` and a zero-element pack they greedily matched arity-0
  and arity-1..9 call sites, breaking Swinject-style ergonomics. A future attempt
  would have to force a non-empty pack (e.g. `FirstArg` + `repeat each RestArg`)
  and prove via tests that 0..9 still hit the concrete overloads.
- **`synchronize()`** currently returns a child container with `synchronized: true`
  rather than a dedicated `SynchronizedResolver` wrapper class. Functionally
  equivalent for now.
- **Test coverage.** `TSwinjectTests` covers ~95% of source lines but the broader
  Swinject suites (Circularity / CustomScope / GraphCaching / Speed) have not been
  ported.
- **The macro's CocoaPods path** builds the plugin from source during
  `pod install` (~3 minutes cold, swift-syntax in release). It is host-native by
  construction, so no universal binary is needed — but note that `swift build
  --arch x86_64` is silently ignored by SwiftPM, and passing two `--arch` flags
  routes to the Xcode build system, which does not emit the plugin executable at
  all. Don't "fix" the prepare_command by adding `--arch`.

## When in doubt

The cast pattern is the product. If a change makes the resolution path "cleaner"
by removing the `DiEntryConcrete` indirection, it has almost certainly
reintroduced the slow path. Run the benchmark before and after any change to
`Container.swift`, `Container.Arguments.swift`, or `DiEntry.swift`.
