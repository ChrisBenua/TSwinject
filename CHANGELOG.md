# Changelog

## 1.0.0

First public release.

### TSwinject

- `Container` with a Swinject-compatible API: `register` / `registerWeak` /
  `resolve` for 0 to 9 runtime arguments, named registrations, parent and child
  containers, `removeAll`, `resetObjectScope`, `hasAnyRegistration`,
  `synchronize`, `addBehavior`, and `Assembly` / `Assembler`.
- Object scopes `.transient`, `.graph` (default) and `.container`; weak
  registrations via `registerWeak` and `weakInstance(_:)`.
- `Optional<Service>` resolution from a single registration.
- Opt-in per-resolve timing through `ResolveTracking`.
- Resolution avoids protocol-existential casts by boxing instances in
  `DiEntryConcrete<T>` / `DiEntryWeak<T>` — 1.34× faster than Swinject 2.10.0 on
  the bundled benchmark.

### TSwinjectMacro

- `#implements(container, Base.self, Protocol.self, ...)` expands to one
  `.transient` forwarding registration per protocol, so a concrete type can be
  exposed under several protocols without reintroducing existential casts.

### TSwinjectSwinjectInterop

- `Container.attachSwinjectBridge(_:scopeMap:)` turns a TSwinject container into a
  typed façade over a real Swinject container, giving a single shared registry for
  incremental migration.
