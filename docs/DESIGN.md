# Design notes

Why TSwinject is built the way it is, and which apparent simplifications would
break it. Distilled from the internal design reviews that preceded the 1.0 release.

## The cast trick

Casting `Any → SomeConcreteGenericClass<T>` is O(1). Casting `Any → SomeProtocol`
makes the Swift runtime walk the protocol-conformance descriptors in the image
looking for a match, and the cost scales with how many conformances the binary
contains. Swinject stores instances as `Any` and casts back to the service type on
every resolve, so registering against a protocol puts that walk on the hot path.

TSwinject boxes every instance in `DiEntryConcrete<T>` or `DiEntryWeak<T>` and
keys the registry on `ObjectIdentifier(DiEntryConcrete<Service>.self)` rather than
on `Service`. The cast back to the box is correct by construction, so it is a
pointer comparison, and reading `.value` afterwards is a stored-property load.

Everything else in the library exists to preserve Swinject's API on top of that.

**The failure mode to watch for:** any refactor that stores `Service` directly as
`Any` and casts with `any as? Service` has silently reintroduced the slow path
while leaving every test green. Only the benchmark catches it.

## Accepted trade-offs

These look like defects in review and are not.

### The doubled registry

Every `register` installs a second, transient `DiEntryConcrete<Service?>` companion
entry, so one registration answers both `resolve(T)` and `resolve(T?)`.

The cost is two entries in `services` and two locked writes per registration. The
alternative — Swinject's `InstanceWrapper` / `resolveAsWrapper` machinery — would
reintroduce dynamic protocol-conformance work on the resolve path, which is the
one thing this library exists to avoid. The doubled registry is the cheaper side of
that trade.

### Nine unfolded arities

`Container.Arguments.swift` repeats nearly identical code nine times. Parameter
packs were prototyped and reverted: with a defaulted `name:` and a zero-element
pack, the pack overload greedily matched arity-0 and arity-1..9 call sites and
broke Swinject-compatible ergonomics. A future attempt would have to force a
non-empty pack (`FirstArg` + `repeat each RestArg`) and prove by test that 0..9
still bind to the concrete overloads.

### Strong/weak re-registration shadowing

Re-registering a service under the *other* flavour (`register` after
`registerWeak`, or the reverse) does not replace the first entry — the two live
under distinct wrapper keys, `DiEntryConcrete<S>` and `DiEntryWeak<S>` — while the
shared `DiEntryConcrete<S?>` optional-mirror key *is* overwritten. Afterwards
`resolve(S.self)` and `resolve(S?.self)` can disagree. This is rare misuse and is
accepted rather than defended against.

### Argument values are not cache keys

A registration's identity includes its argument *types*, not the values passed at
resolve time. Under a sharing scope the first resolve builds the instance and
later resolves return it, ignoring their arguments. Registering `.transient` is
the correct answer when each argument value should produce its own instance.

## Why the Swinject bridge has only one mode

`TSwinjectSwinjectInterop` offers exactly one mode: **takeover**, where the
TSwinject container becomes a typed façade and one Swinject container performs
every construction.

A bidirectional `.both` mirror mode — registering into both engines and resolving
from whichever had the entry — existed during development and was deliberately
removed. It cannot be made correct:

- **Graph identity is per-engine.** `ObjectScope.graph` shares an instance within
  one top-level resolve, keyed by a `GraphIdentifier` minted by the engine running
  the resolve. Two engines mint two identifiers, so a dependency resolved through
  one and then the other is built twice within what the caller believes is a single
  graph.
- **In-flight circularity state is per-engine.** `initCompleted` breaks cycles by
  publishing the instance into the graph before its dependencies resolve back to
  it. The second engine cannot see the first engine's in-flight instance, so a
  cycle that terminates under one engine recurses to the depth limit under the other.
- **Scope identity is per-engine.** Two `.container`-scoped registries mean two
  "singletons" for the same type, and which one a caller gets depends on which
  engine answered.

Takeover avoids all three by having a single engine own construction, graph
identity, scope identity, and the lock domain. There is no second engine to
disagree with. Do not reintroduce mirroring.

**Known limit of takeover:** pointing several façades at one legacy container
flattens the façade hierarchy — `child.register(X)` and `parent.register(X)` both
write to the same registry, so it is last-write-wins rather than child-shadows-parent.
When a migration needs hierarchy, put it in the Swinject containers and bridge each
façade to its own.

## Scope descriptions are load-bearing

`ObjectScope.description` is a label everywhere except the bridge, where the scope
mapping matches the built-in descriptions `"transient"`, `"graph"` and `"container"`
to pick the corresponding Swinject scope. Custom scopes are mapped by their backing
storage instead, so their descriptions are free-form.

Renaming a built-in description would send every scope down the mapping's
`default:` branch and silently degrade custom scopes to `.graph`, with no compile
error. `InteropTests.testBuiltInScopeDescriptions_areStableBridgeKeys` pins them.

## Thread safety

Registration is thread-safe: `services` is an rwlock-guarded `ThreadSafeDictionary`,
the same design Swinject uses. Concurrent *resolution* is not — it mutates graph
state — and requires `synchronize()`.

Two details worth knowing before relying on the model:

- `register` is not locked as a unit. Each `installEntry` takes the lock, and the
  concrete entry and its optional companion are separate critical sections, so a
  concurrent resolve can observe one without the other. `notifyBehaviors` fires
  unlocked.
- `Container` is `@unchecked Sendable`. That is a claim about the registry, not a
  promise that concurrent resolution is safe.

## Resolve tracking fidelity

`ResolveTracking` emits one event per *top-level* resolve, gated by a thread-local
re-entrancy guard rather than by `Container.resolutionDepth` — the latter is
maintained on the entry's owner, not on the resolver, so it is the wrong object
once a child or synchronized resolver is involved.

The event's `durationNanoseconds` covers the whole cascade — optional-mirror
lookup, parent walk, fallback resolver, lock acquisition — attributed to the leaf
service type. `ResolveThreadKind` collapses every QoS class to `.background`.
Treat the numbers as indicative, not as a profiler.
