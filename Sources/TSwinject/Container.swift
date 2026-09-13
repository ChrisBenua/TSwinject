//
//  Portions derived from Swinject (https://github.com/Swinject/Swinject)
//  Copyright © 2019 Swinject Contributors. All rights reserved.
//  Licensed under the MIT License — see NOTICE.
//
//  ``Container`` resolves services by wrapping every registered instance in
//  ``DiEntryConcrete``/``DiEntryWeak``. Resolution casts `Any` to those concrete
//  generic classes — which is cheap — instead of casting to a protocol
//  existential, which forces Swift to walk every protocol conformance
//  descriptor in the image.
//

import Foundation

public final class Container: @unchecked Sendable {
    let services = ThreadSafeDictionary<ServiceKey, ServiceEntry>()
    /// The container consulted when a lookup misses here, or `nil` for a root container.
    public let parent: Container?
    let defaultObjectScope: ObjectScope

    /// Maximum resolution nesting depth before a circular dependency is assumed
    /// and `fatalError` is raised. Defaults to 200 (Swinject's fixed value); a
    /// child container inherits its parent's value unless overridden at init.
    public let maxResolutionDepth: Int
    let lock: RecursiveLock
    let synchronized: Bool
    var behaviors = [Behavior]()

    var resolutionDepth = 0
    var currentObjectGraph: GraphIdentifier?
    var graphInstancesInFlight = [ServiceEntry]()

    /// Sink installed by the Swinject interop module. Consulted only when
    /// `routeAllToSink` is `true`: every `register`/`registerWeak` (and
    /// `removeAll`/`resetObjectScope`/`hasAnyRegistration`) is routed to it
    /// instead of the native storage.
    public var takeoverSink: (any TakeoverSink)?

    /// Fallback resolver installed by the Swinject interop module. Consulted
    /// after all native lookups (including parent chain) fail.
    public var fallbackResolver: Resolver?

    /// Per-container tracker. When set, receives every top-level resolve event
    /// in addition to `_factoryTracker` (if any). Both sinks receive the same
    /// event; neither overrides the other.
    public var resolveTracker: (any ResolveTracker)?

    /// Tracker produced by calling `ResolveTracking.factory` once during
    /// `init`. `nil` when no factory is installed or the factory returned `nil`.
    let _factoryTracker: (any ResolveTracker)?

    /// When `true`, all `register*` calls skip the native `installEntry` and
    /// go only to `takeoverSink`; all `resolve*` calls skip native lookups and
    /// go only to `fallbackResolver`. Set via `activateTakeover` (the core hook
    /// behind `attachSwinjectBridge`).
    ///
    /// The setter is `internal`, so external code cannot flip this flag
    /// directly — the only public way to enable routing is `activateTakeover`,
    /// which enforces "configure before any native registration." This makes the
    /// "frozen for the container's lifetime" contract real rather than advisory.
    public internal(set) var routeAllToSink: Bool = false

    init(
        parent: Container?,
        defaultObjectScope: ObjectScope,
        synchronized: Bool,
        maxResolutionDepth: Int? = nil
    ) {
        self.parent = parent
        self.defaultObjectScope = defaultObjectScope
        self.synchronized = synchronized
        self.maxResolutionDepth = maxResolutionDepth ?? parent?.maxResolutionDepth ?? 200
        self.lock = parent?.lock ?? RecursiveLock()
        self._factoryTracker = ResolveTracking.makeTracker()
    }

    /// Creates a container, optionally as a child of an existing one.
    ///
    /// A child container sees its parent's registrations: a lookup that misses
    /// locally walks up the parent chain. Registrations made on the child are not
    /// visible to the parent. Parent and child share one lock, so a child is no
    /// more concurrency-safe than its parent.
    ///
    /// - Parameters:
    ///   - parent: The container consulted when a lookup misses here.
    ///   - defaultObjectScope: Scope applied to registrations that do not pass
    ///     one of their own. Defaults to ``ObjectScope/graph``, matching Swinject.
    ///   - behaviors: Behaviors attached before `registeringClosure` runs, so
    ///     they observe the registrations it makes.
    ///   - maxResolutionDepth: Nesting depth at which a circular dependency is
    ///     assumed. Inherited from `parent` when `nil`, otherwise 200.
    ///   - registeringClosure: Runs against the new container, for registering
    ///     inline at the construction site.
    public convenience init(
        parent: Container? = nil,
        defaultObjectScope: ObjectScope = .graph,
        behaviors: [Behavior] = [],
        maxResolutionDepth: Int? = nil,
        registeringClosure: (Container) -> Void = { _ in }
    ) {
        self.init(parent: parent, defaultObjectScope: defaultObjectScope, synchronized: false, maxResolutionDepth: maxResolutionDepth)
        behaviors.forEach(addBehavior)
        registeringClosure(self)
    }

    // MARK: - Takeover activation

    /// Installs the Swinject-takeover routing: `sink` becomes the write path,
    /// `fallbackResolver` the read path, and `routeAllToSink` is frozen on. This
    /// is the core hook behind the interop module's `attachSwinjectBridge`.
    ///
    /// Because `routeAllToSink`'s setter is `internal`, this is the only way
    /// external code can enable routing — and it enforces the "configure before
    /// use" contract: it is a programmer error to activate takeover after any
    /// native `register*` has run, because those registrations would become
    /// permanently unreachable once resolution starts skipping native lookups.
    ///
    /// - Precondition: no native registration has been installed on this
    ///   container yet (`services` is empty).
    public func activateTakeover(sink: any TakeoverSink, fallbackResolver: Resolver) {
        precondition(
            services.isEmpty,
            "attachSwinjectBridge must be called before any register"
        )
        takeoverSink = sink
        self.fallbackResolver = fallbackResolver
        routeAllToSink = true
    }

    // MARK: - Registration

    /// Registers a factory for `serviceType`, to be resolved with no arguments.
    ///
    /// ```swift
    /// container.register(Logger.self, scope: .container) { _ in ConsoleLogger() }
    /// ```
    ///
    /// Registering the same `(type, name, arity)` twice replaces the earlier
    /// entry rather than erroring — the last registration wins, which is what
    /// makes overriding a production assembly in tests work.
    ///
    /// Two entries are installed: the service itself, and a companion entry for
    /// `Optional<Service>` so `resolve(Service?.self)` works. The companion is
    /// always transient and defers to the real entry, so it costs nothing in
    /// terms of lifetime.
    ///
    /// - Note: This is the Swinject-compatible spelling, except that the scope is
    ///   a parameter here rather than an `.inObjectScope(_:)` call on a returned
    ///   entry. Nothing is returned to chain onto.
    ///
    /// - Parameters:
    ///   - serviceType: The type to register. To avoid the protocol-existential
    ///     cast this library exists to eliminate, prefer registering the concrete
    ///     type and forwarding protocols to it — see the `#implements` macro.
    ///   - name: Distinguishes several registrations of the same type. Resolves
    ///     must pass the same name.
    ///   - scope: Lifetime of the resolved instance. `nil` uses the container's
    ///     `defaultObjectScope` (``ObjectScope/graph`` unless configured).
    ///   - factory: Builds the instance. Receives a ``Resolver`` — not the
    ///     container — so dependencies can be pulled but nothing registered.
    ///   - initCompleted: Runs after the instance is built and stored. Use it to
    ///     break circular dependencies: at this point the instance is already in
    ///     the graph, so resolving back to it will not recurse.
    public func register<Service>(
        _ serviceType: Service.Type,
        name: String? = nil,
        scope: ObjectScope? = nil,
        factory: @escaping (Resolver) -> Service,
        initCompleted: ((Resolver, Service) -> Void)? = nil
    ) {
        let scope = scope ?? defaultObjectScope

        // Slow-path: route everything to the attached Swinject container.
        if routeAllToSink {
            takeoverSink?.mirrorRegister(
                Service.self, name: name, scope: scope, factory: factory, initCompleted: initCompleted
            )
            notifyBehaviors(didRegisterType: Service.self, name: name)
            return
        }

        let strongFactory: (Resolver) -> Any = { resolver in
            DiEntryConcrete(value: factory(resolver))
        }
        let strongInitCompleted: ((Resolver, Any) -> Void)? = initCompleted.map { cb in
            { resolver, any in
                if let wrapper = any as? DiEntryConcrete<Service> {
                    cb(resolver, wrapper.value)
                }
            }
        }
        installEntry(
            serviceType: DiEntryConcrete<Service>.self,
            registeredServiceType: Service.self,
            name: name,
            factory: strongFactory,
            scope: scope,
            storageFactory: scope.makeStorage,
            initCompleted: strongInitCompleted
        )

        let optFactory: (Resolver) -> Any = { r in
            let value: Service? = r.resolve(Service.self, name: name)
            return DiEntryConcrete<Service?>(value: value)
        }
        installEntry(
            serviceType: DiEntryConcrete<Service?>.self,
            registeredServiceType: Service.self,
            name: name,
            factory: optFactory,
            scope: ObjectScope.transient,
            storageFactory: TransientStorage.init,
            initCompleted: nil
        )

        notifyBehaviors(didRegisterType: Service.self, name: name)
    }

    /// Registers a factory whose instance is shared only while someone else
    /// holds it, and rebuilt once it deallocates.
    ///
    /// ```swift
    /// container.registerWeak(Session.self) { _ in weakInstance(Session()) }
    /// ```
    ///
    /// The factory returns a `(value, () -> value?)` pair: a strong reference to
    /// hand back from this resolve, and a closure that reads the same object
    /// weakly on later resolves. ``weakInstance(_:)`` builds that pair for you;
    /// writing it by hand means retaining the value somewhere, or it deallocates
    /// before it is ever returned.
    ///
    /// The container permanently retains the small wrapper, never the value. Once
    /// the last external strong reference goes, the next resolve runs the factory
    /// again.
    ///
    /// - Important: Takes a ``WeakObjectScopeProtocol``, not an ``ObjectScope`` —
    ///   the two are separate types on purpose, so the scopes cannot be swapped.
    ///
    /// - Parameters:
    ///   - serviceType: The type to register.
    ///   - name: Distinguishes several registrations of the same type.
    ///   - scope: Where the wrapper is stored. The default is almost always right.
    ///   - factory: Returns the value and a closure reading it weakly.
    ///   - initCompleted: Runs after the instance is built, as in ``register(_:name:scope:factory:initCompleted:)``.
    public func registerWeak<Service>(
        _ serviceType: Service.Type,
        name: String? = nil,
        scope: WeakObjectScopeProtocol = WeakScope.shared,
        factory: @escaping (Resolver) -> (Service, () -> Service?),
        initCompleted: ((Resolver, Service) -> Void)? = nil
    ) {
        // Slow-path: route everything to the attached Swinject container.
        if routeAllToSink {
            takeoverSink?.mirrorRegisterWeak(
                Service.self, name: name, scope: scope, factory: factory, initCompleted: initCompleted
            )
            notifyBehaviors(didRegisterType: Service.self, name: name)
            return
        }

        // The wrapper must not capture a resolver — it lives in PermanentStorage
        // inside this container, so a captured container would never deallocate
        // (N3). The resolver is supplied per (re)build via `value(_:)`.
        let weakFactory: (Resolver) -> Any = { _ in
            DiEntryWeak<Service>(factory: { resolver in
                let pair = factory(resolver)
                initCompleted?(resolver, pair.0)
                return pair
            })
        }
        installEntry(
            serviceType: DiEntryWeak<Service>.self,
            registeredServiceType: Service.self,
            name: name,
            factory: weakFactory,
            scope: scope,
            storageFactory: scope.makeStorage,
            initCompleted: nil
        )

        let optFactory: (Resolver) -> Any = { r in
            let value: Service? = r.resolve(Service.self, name: name)
            return DiEntryConcrete<Service?>(value: value)
        }
        installEntry(
            serviceType: DiEntryConcrete<Service?>.self,
            registeredServiceType: Service.self,
            name: name,
            factory: optFactory,
            scope: ObjectScope.transient,
            storageFactory: TransientStorage.init,
            initCompleted: nil
        )

        notifyBehaviors(didRegisterType: Service.self, name: name)
    }

    func installEntry(
        serviceType: Any.Type,
        registeredServiceType: Any.Type,
        argumentsType: Any.Type = Resolver.self,
        name: String?,
        factory: Any,
        scope: AnyObject,
        storageFactory: @escaping () -> InstanceStorage,
        initCompleted: ((Resolver, Any) -> Void)?
    ) {
        syncIfEnabled {
            let key = ServiceKey(serviceType: serviceType, argumentsType: argumentsType, name: name)
            let entry = ServiceEntry(
                serviceType: serviceType,
                registeredServiceType: registeredServiceType,
                argumentsType: argumentsType,
                factory: factory,
                objectScope: scope,
                storageFactory: storageFactory,
                initCompleted: initCompleted
            )
            services[key] = entry
        }
    }

    func notifyBehaviors<Service>(didRegisterType: Service.Type, name: String?) {
        behaviors.forEach { $0.container(self, didRegisterType: Service.self, withName: name) }
    }

    // MARK: - Misc

    /// Removes every registration from this container.
    ///
    /// Affects this container only — a parent's registrations survive and remain
    /// reachable through the parent chain. Cached instances go with their
    /// registrations; to drop cached instances but keep the registrations, use
    /// ``resetObjectScope(_:)-(ObjectScope)``.
    public func removeAll() {
        syncIfEnabled {
            services.removeAll()
            if routeAllToSink {
                takeoverSink?.mirrorRemoveAll()
            }
        }
    }

    /// Discards instances cached by every registration in `scope`, keeping the
    /// registrations themselves, so the next resolve rebuilds.
    ///
    /// Propagates up the parent chain, so resetting `.container` on a child also
    /// clears the parent's `.container` instances.
    ///
    /// - Parameter scope: The scope whose cached instances are dropped.
    public func resetObjectScope(_ scope: ObjectScopeProtocol) {
        syncIfEnabled {
            for entry in services.values where entry.objectScope === scope {
                entry.storage = entry.storageFactory()
            }
            if routeAllToSink, let concrete = scope as? ObjectScope {
                takeoverSink?.mirrorResetObjectScope(concrete)
            }
            parent?.resetObjectScope(scope)
        }
    }

    /// Concrete-typed overload of ``resetObjectScope(_:)-(ObjectScopeProtocol)``,
    /// so `container.resetObjectScope(.container)` resolves without a cast.
    public func resetObjectScope(_ scope: ObjectScope) {
        resetObjectScope(scope as ObjectScopeProtocol)
    }

    /// Discards cached instances for a single service type within `scope`,
    /// leaving every other registration in that scope untouched.
    ///
    /// - Parameters:
    ///   - scope: The scope to look in.
    ///   - serviceType: The registered service type whose cache is cleared.
    public func resetObjectScope(_ scope: ObjectScopeProtocol, serviceType: Any.Type) {
        syncIfEnabled {
            for entry in services.values
                where entry.objectScope === scope && entry.registeredServiceType == serviceType {
                entry.storage = entry.storageFactory()
            }
            if routeAllToSink, let concrete = scope as? ObjectScope {
                #if SWINJECT_2_10_AVAILABLE
                    takeoverSink?.mirrorResetObjectScope(concrete, serviceType: serviceType)
                #endif
            }
            parent?.resetObjectScope(scope, serviceType: serviceType)
        }
    }

    /// Concrete-typed overload of
    /// ``resetObjectScope(_:serviceType:)-(ObjectScopeProtocol,_)``.
    public func resetObjectScope(_ scope: ObjectScope, serviceType: Any.Type) {
        resetObjectScope(scope as ObjectScopeProtocol, serviceType: serviceType)
    }

    /// Discards cached instances registered under a *weak* scope, forcing a fresh
    /// `DiEntryWeak` wrapper (and thus a fresh weakly-held value) on the next
    /// resolve. Weak scopes are a distinct protocol from `ObjectScopeProtocol`,
    /// so they need their own overload.
    public func resetObjectScope(_ scope: WeakObjectScopeProtocol) {
        syncIfEnabled {
            for entry in services.values where entry.objectScope === scope {
                entry.storage = entry.storageFactory()
            }
            if routeAllToSink {
                takeoverSink?.mirrorResetWeakObjectScope()
            }
            parent?.resetObjectScope(scope)
        }
    }

    /// Per-type variant of the weak `resetObjectScope` — discards only the weak
    /// entry registered for `serviceType` under `scope`.
    public func resetObjectScope(_ scope: WeakObjectScopeProtocol, serviceType: Any.Type) {
        syncIfEnabled {
            for entry in services.values
                where entry.objectScope === scope && entry.registeredServiceType == serviceType {
                entry.storage = entry.storageFactory()
            }
            #if SWINJECT_2_10_AVAILABLE
                if routeAllToSink {
                    takeoverSink?.mirrorResetWeakObjectScope(serviceType: serviceType)
                }
            #endif
            parent?.resetObjectScope(scope, serviceType: serviceType)
        }
    }

    /// Reports whether `serviceType` is registered here or anywhere up the parent
    /// chain, at any arity.
    ///
    /// A 3-argument registration counts, so this answers "can this be resolved at
    /// all", not "can this be resolved with no arguments". It does not build
    /// anything.
    ///
    /// - Parameters:
    ///   - serviceType: The type to look for.
    ///   - name: Only registrations under this name are considered; `nil` matches
    ///     unnamed registrations.
    /// - Returns: `true` if a matching registration exists.
    public func hasAnyRegistration<Service>(of serviceType: Service.Type, name: String? = nil) -> Bool {
        syncIfEnabled {
            // Takeover mode: native storage is empty by design — answer from the
            // takeover side's own registration probe, which sees every
            // registration in the shared registry (both directions).
            if routeAllToSink {
                return takeoverSink?.mirrorHasRegistration(serviceType, name: name) ?? false
            }
            // Match on the *registered* service type across every wrapper key,
            // ignoring `argumentsType`, so 1..9-arg registrations are reported too
            // (Swinject parity — `Swinject/Container.swift:229-238`). Probing the
            // 0-arg wrapper keys directly would miss arg-based registrations.
            let found = services.contains { key, entry in
                entry.registeredServiceType == serviceType && key.name == name
            }
            if found { return true }
            return parent?.hasAnyRegistration(of: serviceType, name: name) ?? false
        }
    }

    /// Returns a resolver that serialises access, for resolving from several
    /// threads.
    ///
    /// A plain `Container` is safe to register into concurrently but not to
    /// resolve from concurrently; resolution mutates graph state. Hand this
    /// resolver to code on other threads and keep the container itself on one.
    ///
    /// The returned value reads the same registrations, including any added after
    /// this call, and shares the container's lock.
    ///
    /// - Returns: A ``Resolver`` view over this container that locks around
    ///   resolution.
    public func synchronize() -> Resolver {
        let child = Container(parent: self, defaultObjectScope: defaultObjectScope, synchronized: true)
        // Propagate bridge: the synchronized child is an implementation-detail wrapper,
        // not an independent container. It must share our Swinject bridge so that
        // resolves through it see the same registrations as the parent.
        if routeAllToSink {
            child.routeAllToSink = true
            child.takeoverSink = takeoverSink
            child.fallbackResolver = fallbackResolver
        }
        // Propagate property-only tracker so resolves through the synchronized
        // resolver still emit events. (_factoryTracker is set independently via
        // ResolveTracking.makeTracker() during init.)
        child.resolveTracker = resolveTracker
        return child
    }

    /// Attaches a behavior notified of every subsequent registration.
    ///
    /// Only registrations made after this call are reported, so add behaviors
    /// before running assemblies.
    ///
    /// - Parameter behavior: The observer to attach. It is retained by the container.
    public func addBehavior(_ behavior: Behavior) {
        syncIfEnabled { behaviors.append(behavior) }
    }

    // MARK: - Tracking helpers

    /// `true` when at least one tracker (per-container or factory-produced) is
    /// installed. Two property loads + a nil check — no lock, no allocation.
    @inline(__always) var hasTracker: Bool {
        resolveTracker != nil || _factoryTracker != nil
    }

    /// Shared tracked-path dispatcher used by every public `resolve` overload.
    ///
    /// Only fires for the **outermost** resolve on the current thread. Nested
    /// resolves invoked from inside a factory — including those routed through a
    /// child / synchronized resolver or a parent-chain fallthrough — fall through
    /// to `work()` directly, gated by the thread-local `TrackingReentrancy` rather
    /// than `resolutionDepth` (which is maintained on the entry's *owner*, not the
    /// resolver, and so is the wrong object for a child resolver).
    ///
    /// Note: a resolve initiated inside `withObjectGraph(_:)` is treated as
    /// top-level and emits one event — `withObjectGraph` bumps `resolutionDepth`,
    /// not the thread-local guard.
    ///
    /// The `work` closure is only allocated on the tracked path; callers with
    /// no tracker installed never reach this method.
    func _resolveTracked<Service>(
        _ serviceType: Service.Type,
        name: String?,
        work: () -> Service?
    ) -> Service? {
        guard TrackingReentrancy.depth == 0 else { return work() }
        TrackingReentrancy.depth += 1
        defer { TrackingReentrancy.depth -= 1 }
        let start = DispatchTime.now().uptimeNanoseconds
        let result = work()
        let elapsed = DispatchTime.now().uptimeNanoseconds &- start
        let event = ResolveEvent(
            serviceType: serviceType,
            name: name,
            durationNanoseconds: elapsed,
            thread: Thread.isMainThread ? .main : .background
        )
        // Fan-out: both trackers receive the same event when set.
        resolveTracker?.didResolve(event)
        _factoryTracker?.didResolve(event)
        return result
    }

    // MARK: - Internal helpers

    @inline(__always)
    @discardableResult
    func syncIfEnabled<T>(_ action: () throws -> T) rethrows -> T {
        try synchronized ? lock.sync(action) : action()
    }

    func incrementResolutionDepth() {
        parent?.incrementResolutionDepth()
        if resolutionDepth == 0, currentObjectGraph == nil {
            currentObjectGraph = GraphIdentifier()
        }
        guard resolutionDepth < maxResolutionDepth else {
            fatalError(
                """
                Infinite recursive call for circular dependency has been detected.
                To avoid the infinite call, 'initCompleted' handler should be used to inject circular dependency.
                """,
                file: "",
                line: 0
            )
        }
        resolutionDepth += 1
    }

    func decrementResolutionDepth() {
        parent?.decrementResolutionDepth()
        assert(resolutionDepth > 0, "The depth cannot be negative.")
        resolutionDepth -= 1
        if resolutionDepth == 0 { graphResolutionCompleted() }
    }

    private func graphResolutionCompleted() {
        graphInstancesInFlight.forEach { $0.storage.graphResolutionCompleted() }
        graphInstancesInFlight.removeAll(keepingCapacity: true)
        currentObjectGraph = nil
    }

    func getEntry(for key: ServiceKey) -> (entry: ServiceEntry, owner: Container)? {
        if let entry = services[key] { return (entry, self) }
        return parent?.getEntry(for: key)
    }
}

// MARK: - Resolver conformance

protocol _ResolveBridge {
    func resolveDiConcrete<Service>(name: String?) -> Service?
    func resolveDiWeak<Service>(name: String?) -> Service?
}

extension Container: _ResolveBridge {
    func resolveDiConcrete<Service>(name: String?) -> Service? {
        let key = ServiceKey(serviceType: DiEntryConcrete<Service>.self, argumentsType: Resolver.self, name: name)
        guard let (entry, owner) = getEntry(for: key),
              let wrapper: DiEntryConcrete<Service> = resolveEntry(entry, owner: owner, invoker: {
                  ($0 as! (Resolver) -> Any)(self)
              }) else {
            return nil
        }
        return wrapper.value
    }

    func resolveDiWeak<Service>(name: String?) -> Service? {
        let key = ServiceKey(serviceType: DiEntryWeak<Service>.self, argumentsType: Resolver.self, name: name)
        guard let (entry, owner) = getEntry(for: key),
              let wrapper: DiEntryWeak<Service> = resolveEntry(entry, owner: owner, invoker: {
                  ($0 as! (Resolver) -> Any)(self)
              }) else {
            return nil
        }
        return wrapper.value(self)
    }
}

extension Container: Resolver {
    /// Resolves a service registered with no arguments, searching this container
    /// and then its parent chain.
    ///
    /// ```swift
    /// let logger = container.resolve(Logger.self)
    /// ```
    ///
    /// Returns `nil` when nothing is registered for `(serviceType, name)` at this
    /// arity — a missing registration is not a crash. A *circular* dependency is
    /// different: it exceeds `maxResolutionDepth` and traps. Break cycles with the
    /// `initCompleted` parameter of ``register(_:name:scope:factory:initCompleted:)``.
    ///
    /// This call opens an object graph if one is not already open, which is what
    /// gives ``ObjectScope/graph`` registrations their shared lifetime; the graph
    /// closes when this call returns.
    ///
    /// - Parameters:
    ///   - serviceType: The registered type to resolve.
    ///   - name: The registration name; `nil` matches unnamed registrations.
    /// - Returns: The resolved instance, or `nil` if nothing matches.
    public func resolve<Service>(_ serviceType: Service.Type, name: String?) -> Service? {
        if hasTracker {
            return _resolveTracked(serviceType, name: name) { self._resolveUntracked(serviceType, name: name) }
        }
        return _resolveUntracked(serviceType, name: name)
    }

    private func _resolveUntracked<Service>(_ serviceType: Service.Type, name: String?) -> Service? {
        return syncIfEnabled {
            // Slow-path: skip all native lookups and parent chain, go straight to Swinject.
            if routeAllToSink {
                return fallbackResolver?.resolve(serviceType, name: name)
            }
            // 1. DiEntryConcrete<Service>
            if let value: Service = resolveDiConcrete(name: name) { return value }
            // 2. DiEntryWeak<Service>
            if let value: Service = resolveDiWeak(name: name) { return value }
            // 3. Parent
            if let value = parent?.resolve(serviceType, name: name) { return value }
            // 4. Interop fallback
            return fallbackResolver?.resolve(serviceType, name: name)
        }
    }

    func resolveEntry<Wrapper>(
        _ entry: ServiceEntry,
        owner: Container,
        invoker: (Any) -> Any
    ) -> Wrapper? {
        owner.incrementResolutionDepth()
        defer { owner.decrementResolutionDepth() }

        guard let graph = owner.currentObjectGraph else {
            fatalError(
                "If accessing container from multiple threads, make sure to use a synchronized resolver.",
                file: "",
                line: 0
            )
        }

        if let cached = entry.storage.instance(inGraph: graph), let typed = cached as? Wrapper {
            return typed
        }

        let resolved = invoker(entry.factory)
        // factory invocation may have set the instance already (circular init).
        if let cached = entry.storage.instance(inGraph: graph), let typed = cached as? Wrapper {
            return typed
        }
        entry.storage.setInstance(resolved, inGraph: graph)
        owner.graphInstancesInFlight.append(entry)

        if let initCompleted = entry.initCompleted {
            initCompleted(self, resolved)
        }

        return resolved as? Wrapper
    }
}
