# TSwinject

**Swinject without the casts.** A dependency-injection container whose public API
mirrors [Swinject](https://github.com/Swinject/Swinject)'s, so most call sites
migrate by swapping the `import` — but which never casts to a protocol
existential. In steady state that is ~1.3× faster; on the first resolve of each
service in a protocol-heavy binary — an app launch, in other words — it is
[73× faster](#10-000-unique-types-cold-and-warm).

```swift
import TSwinject

let container = Container()
container.register(Logger.self, scope: .container) { _ in ConsoleLogger() }
container.register(Service.self) { r in
    RealService(logger: r.resolve(Logger.self)!)
}

let service = container.resolve(Service.self)
```

## Why it's faster

Swinject stores each registered instance as `Any` and casts back to the service
type on every resolve. When the service type is a protocol, that cast is not a
pointer comparison — the Swift runtime walks the protocol conformance descriptors
in the image looking for a match. The more protocols your binary defines, the
more it walks.

TSwinject boxes every instance in a generic class — `DiEntryConcrete<T>` or
`DiEntryWeak<T>` — and keys the registry on `ObjectIdentifier(DiEntryConcrete<Service>.self)`
rather than on `Service` itself. The cast back to the box is guaranteed correct by
construction, so it is O(1), and reading the value afterwards is a stored-property
load.

That single choice is the entire library. Everything else is API compatibility.

## Benchmarks

All numbers: Apple M2 Max, macOS 26.6.2, Swift 6.3.3, release build. Debug
numbers are meaningless — the release build is what removes the boxing overhead.

### 10 000 unique types, cold and warm

10 000 distinct protocols, each with one conforming class, registered in the
default scope and then resolved twice. Best of 5 runs, each in a fresh process:

| phase | Swinject 2.10.0 | TSwinject | |
|---|---|---|---|
| register | 1.45 µs | 2.73 µs | 0.53× — TSwinject is *slower* |
| resolve #1 (cold) | 174.67 µs | 2.37 µs | **73.6× faster** |
| resolve #2 (warm) | 2.42 µs | 1.22 µs | **2.0× faster** |

The cold first resolve is the one that matters at launch. Swinject's
`instance as? Service` has to locate a conformance the runtime has never been
asked for, which means walking the image's conformance records — 175 µs per
resolve here, 1.75 s to build the whole graph. TSwinject casts to
`DiEntryConcrete<Service>` instead, never consults the conformance tables, and
does not care how many protocols the binary contains.

Registration is the honest trade: keying the registry on
`DiEntryConcrete<Service>.self` forces one generic metadata instantiation per
service, costing ~13 ms across all 10 000. Paid once, at startup.

```sh
cd Benchmarks/UniqueTypes && ./run.sh
```

See [`Benchmarks/UniqueTypes/README.md`](Benchmarks/UniqueTypes/README.md) for
the methodology — why two executables, and why every sample is a fresh process.

### 5 services, steady state

5 protocol-typed services, `.container` scope, 200 000 iterations × 5 resolves —
the warmest possible case, and so the smallest honest gap:

| | ns/resolve | resolves/s |
|---|---|---|
| Swinject 2.10.0 | 909 | 1 100 238 |
| **TSwinject** | **677** | **1 477 371** |
| | **1.34× faster** | |

`XCTClockMetric` over 5 runs agrees (0.894 s vs 0.663 s, relative standard
deviation under 1%).

```sh
swift test -c release --filter ContainerBenchmarkTests
```

## Installation

### Swift Package Manager

```swift
.package(url: "https://github.com/ChrisBenua/TSwinject.git", from: "1.0.0")
```

Then depend on whichever products you need:

```swift
.product(name: "TSwinject", package: "TSwinject")                  // the container
.product(name: "TSwinjectMacro", package: "TSwinject")             // #implements
.product(name: "TSwinjectSwinjectInterop", package: "TSwinject")   // migration bridge
```

> **Note on dependencies.** The package declares `swift-syntax` (for the macro)
> and `Swinject` (for the bridge). SwiftPM checks both out for anyone depending on
> this package — about 13 MB — and they will appear in your `Package.resolved`.
> Neither is *compiled* unless you depend on the product that needs it; a
> `TSwinject`-only consumer builds nothing but the core.
> `Tests/Fixtures/verify-isolation.sh` enforces that.

### CocoaPods

```ruby
pod 'TSwinject', '~> 1.0'
pod 'TSwinjectMacro', '~> 1.0'              # optional, #implements
pod 'TSwinjectSwinjectInterop', '~> 1.0'    # optional, migration bridge
```

Requires iOS 16 / macOS 13 and Swift 6.

## Registering and resolving

Scopes control how long an instance lives:

| Scope | Lifetime |
|---|---|
| `.transient` | A new instance on every resolve. |
| `.graph` | Shared within a single top-level `resolve`. **Default.** |
| `.container` | Shared for the life of the container and its children. |

```swift
container.register(Cache.self, scope: .container) { _ in Cache() }
```

Unlike Swinject there is no `.inObjectScope(_:)` to chain — the scope is a
parameter, because `register` returns nothing.

**Runtime arguments** (1 to 9), where the argument type is part of the
registration's identity:

```swift
container.register(Report.self) { (_, id: UUID) in Report(id: id) }
let report = container.resolve(Report.self, argument: someID)
```

**Weak registrations**, shared while someone holds the instance and rebuilt after
it deallocates:

```swift
container.registerWeak(Session.self) { _ in weakInstance(Session()) }
```

**Circular dependencies** are broken with `initCompleted`, which runs after the
instance is in the graph:

```swift
container.register(Parent.self) { r in
    Parent(child: r.resolve(Child.self)!)
}
container.register(
    Child.self,
    factory: { _ in Child() },
    initCompleted: { r, child in
        // Runs after `child` is in the graph, so this does not recurse.
        child.parent = r.resolve(Parent.self)
    }
)
```

**Concurrency.** Registration is thread-safe. Resolving from several threads is
not — use `container.synchronize()` and hand the returned `Resolver` to other
threads.

## `#implements` — protocol forwarding without casts

Registering a concrete type under a protocol reintroduces exactly the existential
cast this library avoids. Register the concrete type, then forward the protocols
to it:

```swift
import TSwinjectMacro

container.register(CredentialsService.self, scope: .container) { _ in
    CredentialsService()
}
#implements(
    container,
    CredentialsService.self,
    CredentialsReading.self,
    TokenProviding.self
)
```

Each protocol becomes a `.transient` registration resolving the base type, so the
base registration's scope still governs the instance's lifetime.

> **CocoaPods users:** CocoaPods does not propagate the compiler's plugin flag to
> your targets. Any target that *writes* `#implements(...)` must add this to its
> own `OTHER_SWIFT_FLAGS`:
>
> ```
> -load-plugin-executable $(PODS_ROOT)/TSwinjectMacro/bin/TSwinjectMacroPlugin#TSwinjectMacroPlugin
> ```
>
> The plugin is compiled during `pod install` — budget about three minutes on a
> cold install, since swift-syntax is built in release. SwiftPM users need none of
> this.

## Migrating from Swinject

`TSwinjectSwinjectInterop` lets a codebase move one assembly at a time against a
single shared registry:

```swift
import TSwinjectSwinjectInterop

let modern = TSwinject.Container()
modern.attachSwinjectBridge(legacy)   // before any register on `modern`
```

`modern` becomes a typed façade over the legacy Swinject container. Everything
registered through it lands in `legacy`, and everything it resolves comes from
`legacy` — one registry, one engine upholding scopes, graphs and circularity, so
neither side can miss the other's registrations. Keep the attach behind a runtime
flag as a rollback switch, then delete it and the Swinject dependency when the
port is done.

See [docs/MIGRATION.md](docs/MIGRATION.md) for the full playbook and a
Swinject → TSwinject API mapping table.

## Known limitations

- **9 runtime arguments maximum**, matching Swinject. Parameter packs were tried
  and reverted: with a defaulted `name:`, a zero-element pack greedily matched the
  zero-argument call sites and broke Swinject-compatible ergonomics.
- **`synchronize()`** returns a child container flagged as synchronized rather
  than a dedicated `SynchronizedResolver` type. Functionally equivalent.
- **Swinject's own test suites** (Circularity, CustomScope, GraphCaching, Speed)
  have not been ported, though the bundled suite covers roughly 95% of source
  lines.
- **Argument values are not part of the cache key.** Under a sharing scope the
  first resolve wins and later arguments are ignored — register as `.transient`
  if each argument should build its own instance.

## License

MIT — see [LICENSE](LICENSE).

TSwinject is derived in part from [Swinject](https://github.com/Swinject/Swinject),
also MIT. The derived files carry the upstream copyright notice, and
[NOTICE](NOTICE) lists them alongside Swinject's full license text.
