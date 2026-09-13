# Migrating from Swinject to TSwinject

A **phased migration strategy** for large codebases, using a feature flag and the
interop bridge so the switch is reversible at every step.

---

## Strategy TL;DR

| Phase | Mechanism | What runs |
|---|---|---|
| **1. Single-registry porting** | `attachSwinjectBridge(legacyContainer)` — the TSwinject container is a typed façade over the *legacy* Swinject container | Swinject engine, one registry |
| **2. The flip** | Stop attaching the bridge | TSwinject native engine |
| **3. Kill-switch window** | Re-attach behind a runtime flag | Either, chosen at startup |
| **4. Cleanup** | Delete the flag, the interop product, and the Swinject dependency | TSwinject only |

The defining property of phase 1: **there is only one registry.** Ported
assemblies register *through* the façade *into* the legacy container; unported
assemblies register into it directly. A service registered through TSwinject is
found by unmigrated Swinject-side consumers, and a service registered in
Swinject is found through the façade — **neither direction can silently miss.**
One engine upholds graph identity, scope identity, circular-dependency
resolution (`initCompleted`), and synchronization for everything, the whole
time. Porting is a pure type-level refactor with no runtime behavior change.

(Earlier designs — a bidirectional `.both` mirror and a dual-container setup
with a read-through seam — were evaluated and rejected: both allow
configurations where the two sides silently disagree about instances. See
DESIGN_REVIEW_V2.md §5–§6 for the analysis.)

## 1. Single-registry porting

### 1.1 Wire the façade (composition root)

```swift
import Swinject
import TSwinject
import TSwinjectSwinjectInterop

// The legacy container — unchanged, still owns every registration.
let legacy = Swinject.Container()
let legacyAssembler = Swinject.Assembler(
    [CoreAssembly(), FeatureAAssembly(), FeatureBAssembly()],
    container: legacy
)

// The façade. MUST be attached before any register call on it.
let modern = TSwinject.Container()
modern.attachSwinjectBridge(legacy)
let modernAssembler = TSwinject.Assembler(container: modern)
```

From here on, `modern.register…` lands in `legacy`, and `modern.resolve…` reads
from `legacy` (through Swinject's own synchronized view, so it composes with any
`legacy.synchronize()` resolver the app already uses).

### 1.2 Port assemblies in any order

Pick an assembly, port it, move it from the legacy assembler to the modern one,
switch its call sites from `Swinject.Resolver` to `TSwinject.Resolver`. Repeat.

- **No ordering constraints.** Dependencies and consumers can be ported in any
  order because everything lives in one registry. A ported factory's dependency
  on an unported service resolves; an unported consumer of a ported service
  resolves; same instances either way.
- **The compiler tracks the frontier.** `Swinject.Resolver` and
  `TSwinject.Resolver` are distinct types, so an unported call site receiving
  the new resolver (or vice versa) is a type error, not a runtime surprise.
- **`initCompleted` works**, including circular dependencies — the bridge passes
  it through to the Swinject entry.
- **Bulk operations work**: `removeAll()`, `resetObjectScope(_:)`, and
  `resetObjectScope(_:serviceType:)` on the façade act on the shared registry;
  `hasAnyRegistration` answers for everything in the shared registry — both
  façade-routed registrations and ones made directly on the legacy container
  (it delegates to Swinject's own `hasAnyRegistration`).

Per-assembly checklist:

- [ ] Change `import Swinject` → `import TSwinject` in the assembly file.
- [ ] Convert registration style (see §2 recipes).
- [ ] Register on the *modern* assembler; remove from the legacy list.
- [ ] Switch the feature's call sites to `TSwinject.Resolver` (the compiler
      finds them all).
- [ ] Run the app/tests — behavior must be identical, because the engine and
      registry didn't change.

### 1.3 Multiple containers

If the app builds several TSwinject containers (e.g. one per child assembler),
attach each to the appropriate Swinject container manually — before any
`register` call on that container. Mirror the Swinject container hierarchy in
your TSwinject hierarchy: resolution ignores the TSwinject parent chain once a
container is bridged, so Swinject's own parent walk is what handles
cross-container lookups.

> **There is no façade hierarchy under a single shared registry.** With multiple
> façades all pointing at one `legacy`, `child.register(X)` and
> `parent.register(X)` both write to `legacy` — last-write-wins, not
> child-shadows-parent. For real migrations that is fine: the container hierarchy
> lives in the Swinject containers, not the façades. Each TSwinject façade should
> be bridged to its *own* Swinject container, with those Swinject containers
> forming the hierarchy.

## 2. Porting recipes

TSwinject deliberately does not return a `ServiceEntry` from `register` (see
§3), so Swinject's chaining style converts to parameters:

| Swinject | TSwinject |
|---|---|
| `c.register(X.self) { … }.inObjectScope(.container)` | `c.register(X.self, scope: .container) { … }` |
| `c.register(X.self) { … }.initCompleted { r, x in … }` | `c.register(X.self, factory: { … }, initCompleted: { r, x in … })` |
| `c.register(X.self, name: "n") { … }` | unchanged |
| `c.register(X.self) { r, arg in … }` + `resolve(X.self, argument:)` | unchanged (0–9 args) |
| `c.register(X.self) { … }.inObjectScope(.weak)` | `c.registerWeak(X.self) { _ in weakInstance(X()) }` |
| `.implements(Y.self)` / `c.forward(Y.self, to: entry)` | forward-by-factory — see §3 |

These conversions are regexable; the only judgment calls are
`implements`/`forward` (below) and custom scopes
(`ObjectScope(storageFactory:description:)` exists with the same shape — give
custom scopes unique, stable `description`s; the bridge maps them by name and
by backing storage).

## 3. Type forwarding without casts (`implements` replacement)

Swinject's `.implements(Y.self)` stores one entry resolvable under several types
and performs an `as?` cast to the forwarded type on every resolve — when `Y` is
a protocol, that is the protocol-conformance walk TSwinject exists to avoid. A
chainable `entry.implements(...)` is therefore **deliberately not offered**: in
generic code Swift cannot prove `Service: Y`, so any such API degenerates to a
runtime cast on the resolve path.

The casting-free pattern — register the forwarded type explicitly with a
transient factory that delegates to the concrete entry:

```swift
container.register(Cat.self, scope: .container) { _ in Cat() }

// "Cat implements Animal":
container.register(Animal.self, scope: .transient) { r in
    r.resolve(Cat.self)!   // upcast Cat → Animal is static, at this closure
}
```

- The `Animal` entry is transient, so it never caches anything itself — identity
  always follows the `Cat` entry's scope (`.container` here → same instance
  under both types; `.graph` → shared within a graph, exactly like Swinject
  forwarding).
- The `Cat → Animal` conversion is checked by the compiler at the closure; the
  resolve path stays on concrete-generic-class casts.
- One line per forwarded protocol, instead of one `.implements` call — the
  ergonomic cost of keeping the hot path cast-free.

## 4. The flip and the kill-switch

When the last assembly is ported and no production code resolves the Swinject
container directly, flip to the native engine — same registrations, different
wiring:

```swift
let modern = TSwinject.Container()
if RemoteConfig.useLegacyDIEngine {
    modern.attachSwinjectBridge(Swinject.Container())   // B arm: Swinject engine
}
// A arm: nothing to attach — native TSwinject fast path.
// …run the (fully ported) assemblies as usual.
```

- Rollback = flip the flag; nothing ships.
- Compare arms with `ResolveTracking.factory` — one event per top-level resolve
  with duration and thread.
- The flip is per-process-launch. Never change the wiring mid-flight; the
  routing flag is frozen after the first register/resolve.

Once the experiment is over: delete the flag, the `TSwinjectSwinjectInterop`
product, and the Swinject dependency.

## 5. Known limits of the bridge (B arm / phase 1)

- **`registerWeak`'s custom weak closure** (the second element of the
  `weakInstance` pair) is ignored under the bridge; Swinject's `.weak` scope
  semantics apply. For standard `weakInstance(...)` usage these are equivalent.
- **Custom scopes** map onto Swinject scopes via `scopeMap`, keyed on the
  scope's `description` (built-ins) or its backing storage
  (`PermanentStorage`-backed customs → `.container`; everything else →
  `.graph`). Supply your own `scopeMap` for anything fancier.

## 6. FAQ

**Why not migrate with two live containers and a read-through?** Because it
reintroduces an ordering constraint (a service must not be ported before its
last Swinject-side consumer) whose violation fails *silently* — a resolve
returns `nil` or, worse, a second instance. The single registry makes that
class of error unrepresentable. The cost — no native-engine speedup until the
flip — buys a migration where every intermediate state is exactly as correct as
the starting state.

**What if assemblies A and B depend on each other?** Port them in any order —
even one at a time. Cross-assembly dependencies, cycles included, run on the
one Swinject engine throughout phase 1.

**Do I lose live singleton instances when I port an assembly?** No — porting is
a code change between releases, not a runtime handoff. Within any process run
there is one composition; instances are created by whichever side owns the
registration in that build, in the one shared registry.

**Can I keep `Swinject.Resolver` in public APIs during migration?** Yes, but
every API converted to `TSwinject.Resolver` becomes compiler-verified migrated
surface — convert aggressively; the type system is the migration tracker.
