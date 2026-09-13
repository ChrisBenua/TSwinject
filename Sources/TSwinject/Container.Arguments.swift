//
//  Portions derived from Swinject (https://github.com/Swinject/Swinject)
//  Copyright © 2019 Swinject Contributors. All rights reserved.
//  Licensed under the MIT License — see NOTICE.
//
//  Adds 1..9-arg variants of `register` / `registerWeak` / `resolve` that
//  wrap into DiEntry the same way the zero-arg path does. Each arity stores
//  its factory as `Any` keyed by the factory's function type, so resolves
//  can't collide across arities.
//

import Foundation

/// `register` / `registerWeak` / `resolve` for factories taking 1 to 9 runtime
/// arguments — values supplied at resolve time rather than pulled from the
/// container.
///
/// The nine arities are written out rather than generated from a parameter pack.
/// Packs were tried and reverted: with a defaulted `name:`, a zero-element pack
/// greedily matched the 0-argument call sites and broke Swinject-compatible
/// ergonomics. Nine is therefore the ceiling, matching Swinject's.
public extension Container {

    // MARK: - 1-argument

    /// Registers a factory taking 1 runtime argument, supplied at resolve time.
    ///
    /// ```swift
    /// container.register(Report.self) { (_, id: UUID) in Report(id: id) }
    /// let report = container.resolve(Report.self, argument: someID)
    /// ```
    ///
    /// Arity and argument types are part of the registration's identity, so this
    /// does not collide with a zero-argument registration of the same type: both
    /// can coexist, and a resolve picks whichever matches the arguments it passes.
    /// The corollary is that a resolve whose argument types do not match any
    /// registration returns `nil` rather than falling back to another arity.
    ///
    /// Argument *values* are not part of the cache key. Under a sharing scope such
    /// as ``ObjectScope/container``, the first resolve builds the instance and
    /// later resolves return it — with different arguments silently ignored. If
    /// each argument value should produce its own instance, register as
    /// ``ObjectScope/transient``.
    ///
    /// - Parameters:
    ///   - serviceType: The type to register.
    ///   - name: Distinguishes several registrations of the same type and arity.
    ///   - scope: Lifetime of the resolved instance; `nil` uses the container's
    ///     default. See the note above on arguments and sharing scopes.
    ///   - factory: Builds the instance from a ``Resolver`` and the argument.
    ///   - initCompleted: Runs after the instance is built and stored; use it to
    ///     break circular dependencies.
    func register<Service, Arg1>(
        _ serviceType: Service.Type,
        name: String? = nil,
        scope: ObjectScope? = nil,
        factory: @escaping (Resolver, Arg1) -> Service,
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

        let strongFactory: (Resolver, Arg1) -> Any = { r, arg1 in
            DiEntryConcrete(value: factory(r, arg1))
        }
        let strongInitCompleted: ((Resolver, Any) -> Void)? = initCompleted.map { cb in
            { r, any in
                if let w = any as? DiEntryConcrete<Service> { cb(r, w.value) }
            }
        }
        installEntry(
            serviceType: DiEntryConcrete<Service>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1) -> Service).self,
            name: name,
            factory: strongFactory,
            scope: scope,
            storageFactory: scope.makeStorage,
            initCompleted: strongInitCompleted
        )
        let optFactory: (Resolver, Arg1) -> Any = { r, arg1 in
            let value: Service? = r.resolve(Service.self, name: name, argument: arg1)
            return DiEntryConcrete<Service?>(value: value)
        }
        installEntry(
            serviceType: DiEntryConcrete<Service?>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1) -> Service?).self,
            name: name,
            factory: optFactory,
            scope: ObjectScope.transient,
            storageFactory: TransientStorage.init,
            initCompleted: nil
        )
        notifyBehaviors(didRegisterType: Service.self, name: name)
    }

    /// Registers a factory taking 1 runtime argument whose instance is shared only
    /// while someone else holds it.
    ///
    /// Combines the argument semantics of
    /// ``register(_:name:scope:factory:initCompleted:)-(_,_,ObjectScope?,(Resolver,Arg1)->Service,_)``
    /// with the weak-reference behaviour of `registerWeak`: the factory returns a
    /// `(value, () -> value?)` pair — see ``weakInstance(_:)`` — and the container
    /// retains only the wrapper. Once the value deallocates, the next resolve
    /// rebuilds it, re-invoking the factory with whatever argument that resolve
    /// passes.
    ///
    /// - Parameters:
    ///   - serviceType: The type to register.
    ///   - name: Distinguishes several registrations of the same type and arity.
    ///   - scope: Where the wrapper is stored; the default is almost always right.
    ///   - factory: Returns the value and a closure reading it weakly.
    ///   - initCompleted: Runs after the instance is built.
    func registerWeak<Service, Arg1>(
        _ serviceType: Service.Type,
        name: String? = nil,
        scope: WeakObjectScopeProtocol = WeakScope.shared,
        factory: @escaping (Resolver, Arg1) -> (Service, () -> Service?),
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

        let weakFactory: (Resolver, Arg1) -> Any = { _, arg1 in
            DiEntryWeak<Service>(factory: { r in
                let pair = factory(r, arg1)
                initCompleted?(r, pair.0)
                return pair
            })
        }
        installEntry(
            serviceType: DiEntryWeak<Service>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1) -> Service).self,
            name: name,
            factory: weakFactory,
            scope: scope,
            storageFactory: scope.makeStorage,
            initCompleted: nil
        )
        let optFactory: (Resolver, Arg1) -> Any = { r, arg1 in
            let value: Service? = r.resolve(Service.self, name: name, argument: arg1)
            return DiEntryConcrete<Service?>(value: value)
        }
        installEntry(
            serviceType: DiEntryConcrete<Service?>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1) -> Service?).self,
            name: name,
            factory: optFactory,
            scope: ObjectScope.transient,
            storageFactory: TransientStorage.init,
            initCompleted: nil
        )
        notifyBehaviors(didRegisterType: Service.self, name: name)
    }

    /// Resolves a service registered with 1 runtime argument.
    ///
    /// Equivalent to `resolve(serviceType, name: nil, argument:)`.
    ///
    /// - Parameters:
    ///   - serviceType: The registered type to resolve.
    ///   - arg1: The argument passed to the registered factory.
    /// - Returns: The resolved instance, or `nil` if no registration matches this
    ///   type *and* argument type.
    func resolve<Service, Arg1>(
        _ serviceType: Service.Type,
        argument arg1: Arg1
    ) -> Service? {
        resolve(serviceType, name: nil, argument: arg1)
    }

    /// Resolves a named service registered with 1 runtime argument.
    ///
    /// Searches this container and then its parent chain. Matching is on the
    /// argument's *type*, not its value, so the value reaches the factory only
    /// when the factory actually runs — under a sharing scope a cached instance
    /// is returned and the argument is ignored.
    ///
    /// - Parameters:
    ///   - serviceType: The registered type to resolve.
    ///   - name: The registration name; `nil` matches unnamed registrations.
    ///   - arg1: The argument passed to the registered factory.
    /// - Returns: The resolved instance, or `nil` if nothing matches.
    func resolve<Service, Arg1>(
        _ serviceType: Service.Type,
        name: String?,
        argument arg1: Arg1
    ) -> Service? {
        if hasTracker {
            return _resolveTracked(serviceType, name: name) {
                self._resolveUntracked1(serviceType, name: name, argument: arg1)
            }
        }
        return _resolveUntracked1(serviceType, name: name, argument: arg1)
    }

    private func _resolveUntracked1<Service, Arg1>(
        _ serviceType: Service.Type,
        name: String?,
        argument arg1: Arg1
    ) -> Service? {
        syncIfEnabled {
            // Slow-path: skip native lookups, go straight to Swinject.
            if routeAllToSink {
                return fallbackResolver?.resolve(serviceType, name: name, argument: arg1)
            }
            let argsType: Any.Type = ((Resolver, Arg1) -> Service).self
            let concreteKey = ServiceKey(
                serviceType: DiEntryConcrete<Service>.self,
                argumentsType: argsType,
                name: name
            )
            if let (entry, owner) = getEntry(for: concreteKey),
               let wrapper: DiEntryConcrete<Service> = resolveEntry(entry, owner: owner, invoker: {
                   ($0 as! (Resolver, Arg1) -> Any)(self, arg1)
               }) {
                return wrapper.value
            }
            let weakKey = ServiceKey(
                serviceType: DiEntryWeak<Service>.self,
                argumentsType: argsType,
                name: name
            )
            if let (entry, owner) = getEntry(for: weakKey),
               let wrapper: DiEntryWeak<Service> = resolveEntry(entry, owner: owner, invoker: {
                   ($0 as! (Resolver, Arg1) -> Any)(self, arg1)
               }) {
                return wrapper.value(self)
            }
            if let value = parent?.resolve(serviceType, name: name, argument: arg1) { return value }
            return fallbackResolver?.resolve(serviceType, name: name, argument: arg1)
        }
    }

    // MARK: - 2-argument

    /// Registers a factory taking 2 runtime arguments.
    ///
    /// Same semantics as the 1-argument overload — see it for how arity and
    /// argument types key a registration, and why argument values do not affect
    /// a shared instance.
    func register<Service, Arg1, Arg2>(
        _ serviceType: Service.Type,
        name: String? = nil,
        scope: ObjectScope? = nil,
        factory: @escaping (Resolver, Arg1, Arg2) -> Service,
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

        let strongFactory: (Resolver, Arg1, Arg2) -> Any = { r, arg1, arg2 in
            DiEntryConcrete(value: factory(r, arg1, arg2))
        }
        let strongInitCompleted: ((Resolver, Any) -> Void)? = initCompleted.map { cb in
            { r, any in
                if let w = any as? DiEntryConcrete<Service> { cb(r, w.value) }
            }
        }
        installEntry(
            serviceType: DiEntryConcrete<Service>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1, Arg2) -> Service).self,
            name: name,
            factory: strongFactory,
            scope: scope,
            storageFactory: scope.makeStorage,
            initCompleted: strongInitCompleted
        )
        let optFactory: (Resolver, Arg1, Arg2) -> Any = { r, arg1, arg2 in
            let value: Service? = r.resolve(Service.self, name: name, arguments: arg1, arg2)
            return DiEntryConcrete<Service?>(value: value)
        }
        installEntry(
            serviceType: DiEntryConcrete<Service?>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1, Arg2) -> Service?).self,
            name: name,
            factory: optFactory,
            scope: ObjectScope.transient,
            storageFactory: TransientStorage.init,
            initCompleted: nil
        )
        notifyBehaviors(didRegisterType: Service.self, name: name)
    }

    /// Registers a weakly-shared factory taking 2 runtime arguments.
    ///
    /// Same semantics as the 1-argument `registerWeak` overload.
    func registerWeak<Service, Arg1, Arg2>(
        _ serviceType: Service.Type,
        name: String? = nil,
        scope: WeakObjectScopeProtocol = WeakScope.shared,
        factory: @escaping (Resolver, Arg1, Arg2) -> (Service, () -> Service?),
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

        let weakFactory: (Resolver, Arg1, Arg2) -> Any = { _, arg1, arg2 in
            DiEntryWeak<Service>(factory: { r in
                let pair = factory(r, arg1, arg2)
                initCompleted?(r, pair.0)
                return pair
            })
        }
        installEntry(
            serviceType: DiEntryWeak<Service>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1, Arg2) -> Service).self,
            name: name,
            factory: weakFactory,
            scope: scope,
            storageFactory: scope.makeStorage,
            initCompleted: nil
        )
        let optFactory: (Resolver, Arg1, Arg2) -> Any = { r, arg1, arg2 in
            let value: Service? = r.resolve(Service.self, name: name, arguments: arg1, arg2)
            return DiEntryConcrete<Service?>(value: value)
        }
        installEntry(
            serviceType: DiEntryConcrete<Service?>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1, Arg2) -> Service?).self,
            name: name,
            factory: optFactory,
            scope: ObjectScope.transient,
            storageFactory: TransientStorage.init,
            initCompleted: nil
        )
        notifyBehaviors(didRegisterType: Service.self, name: name)
    }

    /// Resolves a service registered with 2 runtime arguments.
    ///
    /// Equivalent to the `name: nil` overload below.
    func resolve<Service, Arg1, Arg2>(
        _ serviceType: Service.Type,
        arguments arg1: Arg1, _ arg2: Arg2
    ) -> Service? {
        resolve(serviceType, name: nil, arguments: arg1, arg2)
    }

    /// Resolves a named service registered with 2 runtime arguments.
    ///
    /// Returns `nil` unless a registration matches the type, name, and argument
    /// types exactly.
    func resolve<Service, Arg1, Arg2>(
        _ serviceType: Service.Type,
        name: String?,
        arguments arg1: Arg1, _ arg2: Arg2
    ) -> Service? {
        if hasTracker {
            return _resolveTracked(serviceType, name: name) {
                self._resolveUntracked2(serviceType, name: name, arguments: arg1, arg2)
            }
        }
        return _resolveUntracked2(serviceType, name: name, arguments: arg1, arg2)
    }

    private func _resolveUntracked2<Service, Arg1, Arg2>(
        _ serviceType: Service.Type,
        name: String?,
        arguments arg1: Arg1, _ arg2: Arg2
    ) -> Service? {
        syncIfEnabled {
            // Slow-path: skip native lookups, go straight to Swinject.
            if routeAllToSink {
                return fallbackResolver?.resolve(serviceType, name: name, arguments: arg1, arg2)
            }
            let argsType: Any.Type = ((Resolver, Arg1, Arg2) -> Service).self
            let concreteKey = ServiceKey(
                serviceType: DiEntryConcrete<Service>.self,
                argumentsType: argsType,
                name: name
            )
            if let (entry, owner) = getEntry(for: concreteKey),
               let wrapper: DiEntryConcrete<Service> = resolveEntry(entry, owner: owner, invoker: {
                   ($0 as! (Resolver, Arg1, Arg2) -> Any)(self, arg1, arg2)
               }) {
                return wrapper.value
            }
            let weakKey = ServiceKey(
                serviceType: DiEntryWeak<Service>.self,
                argumentsType: argsType,
                name: name
            )
            if let (entry, owner) = getEntry(for: weakKey),
               let wrapper: DiEntryWeak<Service> = resolveEntry(entry, owner: owner, invoker: {
                   ($0 as! (Resolver, Arg1, Arg2) -> Any)(self, arg1, arg2)
               }) {
                return wrapper.value(self)
            }
            if let value = parent?.resolve(serviceType, name: name, arguments: arg1, arg2) { return value }
            return fallbackResolver?.resolve(serviceType, name: name, arguments: arg1, arg2)
        }
    }

    // MARK: - 3-argument

    /// Registers a factory taking 3 runtime arguments.
    ///
    /// Same semantics as the 1-argument overload — see it for how arity and
    /// argument types key a registration, and why argument values do not affect
    /// a shared instance.
    func register<Service, Arg1, Arg2, Arg3>(
        _ serviceType: Service.Type,
        name: String? = nil,
        scope: ObjectScope? = nil,
        factory: @escaping (Resolver, Arg1, Arg2, Arg3) -> Service,
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

        let strongFactory: (Resolver, Arg1, Arg2, Arg3) -> Any = { r, arg1, arg2, arg3 in
            DiEntryConcrete(value: factory(r, arg1, arg2, arg3))
        }
        let strongInitCompleted: ((Resolver, Any) -> Void)? = initCompleted.map { cb in
            { r, any in
                if let w = any as? DiEntryConcrete<Service> { cb(r, w.value) }
            }
        }
        installEntry(
            serviceType: DiEntryConcrete<Service>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1, Arg2, Arg3) -> Service).self,
            name: name,
            factory: strongFactory,
            scope: scope,
            storageFactory: scope.makeStorage,
            initCompleted: strongInitCompleted
        )
        let optFactory: (Resolver, Arg1, Arg2, Arg3) -> Any = { r, arg1, arg2, arg3 in
            let value: Service? = r.resolve(Service.self, name: name, arguments: arg1, arg2, arg3)
            return DiEntryConcrete<Service?>(value: value)
        }
        installEntry(
            serviceType: DiEntryConcrete<Service?>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1, Arg2, Arg3) -> Service?).self,
            name: name,
            factory: optFactory,
            scope: ObjectScope.transient,
            storageFactory: TransientStorage.init,
            initCompleted: nil
        )
        notifyBehaviors(didRegisterType: Service.self, name: name)
    }

    /// Registers a weakly-shared factory taking 3 runtime arguments.
    ///
    /// Same semantics as the 1-argument `registerWeak` overload.
    func registerWeak<Service, Arg1, Arg2, Arg3>(
        _ serviceType: Service.Type,
        name: String? = nil,
        scope: WeakObjectScopeProtocol = WeakScope.shared,
        factory: @escaping (Resolver, Arg1, Arg2, Arg3) -> (Service, () -> Service?),
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

        let weakFactory: (Resolver, Arg1, Arg2, Arg3) -> Any = { _, arg1, arg2, arg3 in
            DiEntryWeak<Service>(factory: { r in
                let pair = factory(r, arg1, arg2, arg3)
                initCompleted?(r, pair.0)
                return pair
            })
        }
        installEntry(
            serviceType: DiEntryWeak<Service>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1, Arg2, Arg3) -> Service).self,
            name: name,
            factory: weakFactory,
            scope: scope,
            storageFactory: scope.makeStorage,
            initCompleted: nil
        )
        let optFactory: (Resolver, Arg1, Arg2, Arg3) -> Any = { r, arg1, arg2, arg3 in
            let value: Service? = r.resolve(Service.self, name: name, arguments: arg1, arg2, arg3)
            return DiEntryConcrete<Service?>(value: value)
        }
        installEntry(
            serviceType: DiEntryConcrete<Service?>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1, Arg2, Arg3) -> Service?).self,
            name: name,
            factory: optFactory,
            scope: ObjectScope.transient,
            storageFactory: TransientStorage.init,
            initCompleted: nil
        )
        notifyBehaviors(didRegisterType: Service.self, name: name)
    }

    /// Resolves a service registered with 3 runtime arguments.
    ///
    /// Equivalent to the `name: nil` overload below.
    func resolve<Service, Arg1, Arg2, Arg3>(
        _ serviceType: Service.Type,
        arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3
    ) -> Service? {
        resolve(serviceType, name: nil, arguments: arg1, arg2, arg3)
    }

    /// Resolves a named service registered with 3 runtime arguments.
    ///
    /// Returns `nil` unless a registration matches the type, name, and argument
    /// types exactly.
    func resolve<Service, Arg1, Arg2, Arg3>(
        _ serviceType: Service.Type,
        name: String?,
        arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3
    ) -> Service? {
        if hasTracker {
            return _resolveTracked(serviceType, name: name) {
                self._resolveUntracked3(serviceType, name: name, arguments: arg1, arg2, arg3)
            }
        }
        return _resolveUntracked3(serviceType, name: name, arguments: arg1, arg2, arg3)
    }

    private func _resolveUntracked3<Service, Arg1, Arg2, Arg3>(
        _ serviceType: Service.Type,
        name: String?,
        arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3
    ) -> Service? {
        syncIfEnabled {
            // Slow-path: skip native lookups, go straight to Swinject.
            if routeAllToSink {
                return fallbackResolver?.resolve(serviceType, name: name, arguments: arg1, arg2, arg3)
            }
            let argsType: Any.Type = ((Resolver, Arg1, Arg2, Arg3) -> Service).self
            let concreteKey = ServiceKey(
                serviceType: DiEntryConcrete<Service>.self,
                argumentsType: argsType,
                name: name
            )
            if let (entry, owner) = getEntry(for: concreteKey),
               let wrapper: DiEntryConcrete<Service> = resolveEntry(entry, owner: owner, invoker: {
                   ($0 as! (Resolver, Arg1, Arg2, Arg3) -> Any)(self, arg1, arg2, arg3)
               }) {
                return wrapper.value
            }
            let weakKey = ServiceKey(
                serviceType: DiEntryWeak<Service>.self,
                argumentsType: argsType,
                name: name
            )
            if let (entry, owner) = getEntry(for: weakKey),
               let wrapper: DiEntryWeak<Service> = resolveEntry(entry, owner: owner, invoker: {
                   ($0 as! (Resolver, Arg1, Arg2, Arg3) -> Any)(self, arg1, arg2, arg3)
               }) {
                return wrapper.value(self)
            }
            if let value = parent?.resolve(serviceType, name: name, arguments: arg1, arg2, arg3) { return value }
            return fallbackResolver?.resolve(serviceType, name: name, arguments: arg1, arg2, arg3)
        }
    }

    // MARK: - 4-argument

    /// Registers a factory taking 4 runtime arguments.
    ///
    /// Same semantics as the 1-argument overload — see it for how arity and
    /// argument types key a registration, and why argument values do not affect
    /// a shared instance.
    func register<Service, Arg1, Arg2, Arg3, Arg4>(
        _ serviceType: Service.Type,
        name: String? = nil,
        scope: ObjectScope? = nil,
        factory: @escaping (Resolver, Arg1, Arg2, Arg3, Arg4) -> Service,
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

        let strongFactory: (Resolver, Arg1, Arg2, Arg3, Arg4) -> Any = { r, arg1, arg2, arg3, arg4 in
            DiEntryConcrete(value: factory(r, arg1, arg2, arg3, arg4))
        }
        let strongInitCompleted: ((Resolver, Any) -> Void)? = initCompleted.map { cb in
            { r, any in
                if let w = any as? DiEntryConcrete<Service> { cb(r, w.value) }
            }
        }
        installEntry(
            serviceType: DiEntryConcrete<Service>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1, Arg2, Arg3, Arg4) -> Service).self,
            name: name,
            factory: strongFactory,
            scope: scope,
            storageFactory: scope.makeStorage,
            initCompleted: strongInitCompleted
        )
        let optFactory: (Resolver, Arg1, Arg2, Arg3, Arg4) -> Any = { r, arg1, arg2, arg3, arg4 in
            let value: Service? = r.resolve(Service.self, name: name, arguments: arg1, arg2, arg3, arg4)
            return DiEntryConcrete<Service?>(value: value)
        }
        installEntry(
            serviceType: DiEntryConcrete<Service?>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1, Arg2, Arg3, Arg4) -> Service?).self,
            name: name,
            factory: optFactory,
            scope: ObjectScope.transient,
            storageFactory: TransientStorage.init,
            initCompleted: nil
        )
        notifyBehaviors(didRegisterType: Service.self, name: name)
    }

    /// Registers a weakly-shared factory taking 4 runtime arguments.
    ///
    /// Same semantics as the 1-argument `registerWeak` overload.
    func registerWeak<Service, Arg1, Arg2, Arg3, Arg4>(
        _ serviceType: Service.Type,
        name: String? = nil,
        scope: WeakObjectScopeProtocol = WeakScope.shared,
        factory: @escaping (Resolver, Arg1, Arg2, Arg3, Arg4) -> (Service, () -> Service?),
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

        let weakFactory: (Resolver, Arg1, Arg2, Arg3, Arg4) -> Any = { _, arg1, arg2, arg3, arg4 in
            DiEntryWeak<Service>(factory: { r in
                let pair = factory(r, arg1, arg2, arg3, arg4)
                initCompleted?(r, pair.0)
                return pair
            })
        }
        installEntry(
            serviceType: DiEntryWeak<Service>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1, Arg2, Arg3, Arg4) -> Service).self,
            name: name,
            factory: weakFactory,
            scope: scope,
            storageFactory: scope.makeStorage,
            initCompleted: nil
        )
        let optFactory: (Resolver, Arg1, Arg2, Arg3, Arg4) -> Any = { r, arg1, arg2, arg3, arg4 in
            let value: Service? = r.resolve(Service.self, name: name, arguments: arg1, arg2, arg3, arg4)
            return DiEntryConcrete<Service?>(value: value)
        }
        installEntry(
            serviceType: DiEntryConcrete<Service?>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1, Arg2, Arg3, Arg4) -> Service?).self,
            name: name,
            factory: optFactory,
            scope: ObjectScope.transient,
            storageFactory: TransientStorage.init,
            initCompleted: nil
        )
        notifyBehaviors(didRegisterType: Service.self, name: name)
    }

    /// Resolves a service registered with 4 runtime arguments.
    ///
    /// Equivalent to the `name: nil` overload below.
    func resolve<Service, Arg1, Arg2, Arg3, Arg4>(
        _ serviceType: Service.Type,
        arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4
    ) -> Service? {
        resolve(serviceType, name: nil, arguments: arg1, arg2, arg3, arg4)
    }

    /// Resolves a named service registered with 4 runtime arguments.
    ///
    /// Returns `nil` unless a registration matches the type, name, and argument
    /// types exactly.
    func resolve<Service, Arg1, Arg2, Arg3, Arg4>(
        _ serviceType: Service.Type,
        name: String?,
        arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4
    ) -> Service? {
        if hasTracker {
            return _resolveTracked(serviceType, name: name) {
                self._resolveUntracked4(serviceType, name: name, arguments: arg1, arg2, arg3, arg4)
            }
        }
        return _resolveUntracked4(serviceType, name: name, arguments: arg1, arg2, arg3, arg4)
    }

    private func _resolveUntracked4<Service, Arg1, Arg2, Arg3, Arg4>(
        _ serviceType: Service.Type,
        name: String?,
        arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4
    ) -> Service? {
        syncIfEnabled {
            // Slow-path: skip native lookups, go straight to Swinject.
            if routeAllToSink {
                return fallbackResolver?.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4)
            }
            let argsType: Any.Type = ((Resolver, Arg1, Arg2, Arg3, Arg4) -> Service).self
            let concreteKey = ServiceKey(
                serviceType: DiEntryConcrete<Service>.self,
                argumentsType: argsType,
                name: name
            )
            if let (entry, owner) = getEntry(for: concreteKey),
               let wrapper: DiEntryConcrete<Service> = resolveEntry(entry, owner: owner, invoker: {
                   ($0 as! (Resolver, Arg1, Arg2, Arg3, Arg4) -> Any)(self, arg1, arg2, arg3, arg4)
               }) {
                return wrapper.value
            }
            let weakKey = ServiceKey(
                serviceType: DiEntryWeak<Service>.self,
                argumentsType: argsType,
                name: name
            )
            if let (entry, owner) = getEntry(for: weakKey),
               let wrapper: DiEntryWeak<Service> = resolveEntry(entry, owner: owner, invoker: {
                   ($0 as! (Resolver, Arg1, Arg2, Arg3, Arg4) -> Any)(self, arg1, arg2, arg3, arg4)
               }) {
                return wrapper.value(self)
            }
            if let value = parent?.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4) { return value }
            return fallbackResolver?.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4)
        }
    }

    // MARK: - 5-argument

    /// Registers a factory taking 5 runtime arguments.
    ///
    /// Same semantics as the 1-argument overload — see it for how arity and
    /// argument types key a registration, and why argument values do not affect
    /// a shared instance.
    func register<Service, Arg1, Arg2, Arg3, Arg4, Arg5>(
        _ serviceType: Service.Type,
        name: String? = nil,
        scope: ObjectScope? = nil,
        factory: @escaping (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5) -> Service,
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

        let strongFactory: (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5) -> Any = { r, arg1, arg2, arg3, arg4, arg5 in
            DiEntryConcrete(value: factory(r, arg1, arg2, arg3, arg4, arg5))
        }
        let strongInitCompleted: ((Resolver, Any) -> Void)? = initCompleted.map { cb in
            { r, any in
                if let w = any as? DiEntryConcrete<Service> { cb(r, w.value) }
            }
        }
        installEntry(
            serviceType: DiEntryConcrete<Service>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1, Arg2, Arg3, Arg4, Arg5) -> Service).self,
            name: name,
            factory: strongFactory,
            scope: scope,
            storageFactory: scope.makeStorage,
            initCompleted: strongInitCompleted
        )
        let optFactory: (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5) -> Any = { r, arg1, arg2, arg3, arg4, arg5 in
            let value: Service? = r.resolve(Service.self, name: name, arguments: arg1, arg2, arg3, arg4, arg5)
            return DiEntryConcrete<Service?>(value: value)
        }
        installEntry(
            serviceType: DiEntryConcrete<Service?>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1, Arg2, Arg3, Arg4, Arg5) -> Service?).self,
            name: name,
            factory: optFactory,
            scope: ObjectScope.transient,
            storageFactory: TransientStorage.init,
            initCompleted: nil
        )
        notifyBehaviors(didRegisterType: Service.self, name: name)
    }

    /// Registers a weakly-shared factory taking 5 runtime arguments.
    ///
    /// Same semantics as the 1-argument `registerWeak` overload.
    func registerWeak<Service, Arg1, Arg2, Arg3, Arg4, Arg5>(
        _ serviceType: Service.Type,
        name: String? = nil,
        scope: WeakObjectScopeProtocol = WeakScope.shared,
        factory: @escaping (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5) -> (Service, () -> Service?),
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

        let weakFactory: (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5) -> Any = { _, arg1, arg2, arg3, arg4, arg5 in
            DiEntryWeak<Service>(factory: { r in
                let pair = factory(r, arg1, arg2, arg3, arg4, arg5)
                initCompleted?(r, pair.0)
                return pair
            })
        }
        installEntry(
            serviceType: DiEntryWeak<Service>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1, Arg2, Arg3, Arg4, Arg5) -> Service).self,
            name: name,
            factory: weakFactory,
            scope: scope,
            storageFactory: scope.makeStorage,
            initCompleted: nil
        )
        let optFactory: (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5) -> Any = { r, arg1, arg2, arg3, arg4, arg5 in
            let value: Service? = r.resolve(Service.self, name: name, arguments: arg1, arg2, arg3, arg4, arg5)
            return DiEntryConcrete<Service?>(value: value)
        }
        installEntry(
            serviceType: DiEntryConcrete<Service?>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1, Arg2, Arg3, Arg4, Arg5) -> Service?).self,
            name: name,
            factory: optFactory,
            scope: ObjectScope.transient,
            storageFactory: TransientStorage.init,
            initCompleted: nil
        )
        notifyBehaviors(didRegisterType: Service.self, name: name)
    }

    /// Resolves a service registered with 5 runtime arguments.
    ///
    /// Equivalent to the `name: nil` overload below.
    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5>(
        _ serviceType: Service.Type,
        arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5
    ) -> Service? {
        resolve(serviceType, name: nil, arguments: arg1, arg2, arg3, arg4, arg5)
    }

    /// Resolves a named service registered with 5 runtime arguments.
    ///
    /// Returns `nil` unless a registration matches the type, name, and argument
    /// types exactly.
    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5>(
        _ serviceType: Service.Type,
        name: String?,
        arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5
    ) -> Service? {
        if hasTracker {
            return _resolveTracked(serviceType, name: name) {
                self._resolveUntracked5(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5)
            }
        }
        return _resolveUntracked5(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5)
    }

    private func _resolveUntracked5<Service, Arg1, Arg2, Arg3, Arg4, Arg5>(
        _ serviceType: Service.Type,
        name: String?,
        arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5
    ) -> Service? {
        syncIfEnabled {
            // Slow-path: skip native lookups, go straight to Swinject.
            if routeAllToSink {
                return fallbackResolver?.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5)
            }
            let argsType: Any.Type = ((Resolver, Arg1, Arg2, Arg3, Arg4, Arg5) -> Service).self
            let concreteKey = ServiceKey(
                serviceType: DiEntryConcrete<Service>.self,
                argumentsType: argsType,
                name: name
            )
            if let (entry, owner) = getEntry(for: concreteKey),
               let wrapper: DiEntryConcrete<Service> = resolveEntry(entry, owner: owner, invoker: {
                   ($0 as! (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5) -> Any)(self, arg1, arg2, arg3, arg4, arg5)
               }) {
                return wrapper.value
            }
            let weakKey = ServiceKey(
                serviceType: DiEntryWeak<Service>.self,
                argumentsType: argsType,
                name: name
            )
            if let (entry, owner) = getEntry(for: weakKey),
               let wrapper: DiEntryWeak<Service> = resolveEntry(entry, owner: owner, invoker: {
                   ($0 as! (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5) -> Any)(self, arg1, arg2, arg3, arg4, arg5)
               }) {
                return wrapper.value(self)
            }
            if let value = parent?.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5) { return value }
            return fallbackResolver?.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5)
        }
    }

    // MARK: - 6-argument

    /// Registers a factory taking 6 runtime arguments.
    ///
    /// Same semantics as the 1-argument overload — see it for how arity and
    /// argument types key a registration, and why argument values do not affect
    /// a shared instance.
    func register<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6>(
        _ serviceType: Service.Type,
        name: String? = nil,
        scope: ObjectScope? = nil,
        factory: @escaping (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6) -> Service,
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

        let strongFactory: (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6) -> Any = { r, arg1, arg2, arg3, arg4, arg5, arg6 in
            DiEntryConcrete(value: factory(r, arg1, arg2, arg3, arg4, arg5, arg6))
        }
        let strongInitCompleted: ((Resolver, Any) -> Void)? = initCompleted.map { cb in
            { r, any in
                if let w = any as? DiEntryConcrete<Service> { cb(r, w.value) }
            }
        }
        installEntry(
            serviceType: DiEntryConcrete<Service>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6) -> Service).self,
            name: name,
            factory: strongFactory,
            scope: scope,
            storageFactory: scope.makeStorage,
            initCompleted: strongInitCompleted
        )
        let optFactory: (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6) -> Any = { r, arg1, arg2, arg3, arg4, arg5, arg6 in
            let value: Service? = r.resolve(Service.self, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6)
            return DiEntryConcrete<Service?>(value: value)
        }
        installEntry(
            serviceType: DiEntryConcrete<Service?>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6) -> Service?).self,
            name: name,
            factory: optFactory,
            scope: ObjectScope.transient,
            storageFactory: TransientStorage.init,
            initCompleted: nil
        )
        notifyBehaviors(didRegisterType: Service.self, name: name)
    }

    /// Registers a weakly-shared factory taking 6 runtime arguments.
    ///
    /// Same semantics as the 1-argument `registerWeak` overload.
    func registerWeak<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6>(
        _ serviceType: Service.Type,
        name: String? = nil,
        scope: WeakObjectScopeProtocol = WeakScope.shared,
        factory: @escaping (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6) -> (Service, () -> Service?),
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

        let weakFactory: (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6) -> Any = { _, arg1, arg2, arg3, arg4, arg5, arg6 in
            DiEntryWeak<Service>(factory: { r in
                let pair = factory(r, arg1, arg2, arg3, arg4, arg5, arg6)
                initCompleted?(r, pair.0)
                return pair
            })
        }
        installEntry(
            serviceType: DiEntryWeak<Service>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6) -> Service).self,
            name: name,
            factory: weakFactory,
            scope: scope,
            storageFactory: scope.makeStorage,
            initCompleted: nil
        )
        let optFactory: (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6) -> Any = { r, arg1, arg2, arg3, arg4, arg5, arg6 in
            let value: Service? = r.resolve(Service.self, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6)
            return DiEntryConcrete<Service?>(value: value)
        }
        installEntry(
            serviceType: DiEntryConcrete<Service?>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6) -> Service?).self,
            name: name,
            factory: optFactory,
            scope: ObjectScope.transient,
            storageFactory: TransientStorage.init,
            initCompleted: nil
        )
        notifyBehaviors(didRegisterType: Service.self, name: name)
    }

    /// Resolves a service registered with 6 runtime arguments.
    ///
    /// Equivalent to the `name: nil` overload below.
    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6>(
        _ serviceType: Service.Type,
        arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5, _ arg6: Arg6
    ) -> Service? {
        resolve(serviceType, name: nil, arguments: arg1, arg2, arg3, arg4, arg5, arg6)
    }

    /// Resolves a named service registered with 6 runtime arguments.
    ///
    /// Returns `nil` unless a registration matches the type, name, and argument
    /// types exactly.
    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6>(
        _ serviceType: Service.Type,
        name: String?,
        arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5, _ arg6: Arg6
    ) -> Service? {
        if hasTracker {
            return _resolveTracked(serviceType, name: name) {
                self._resolveUntracked6(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6)
            }
        }
        return _resolveUntracked6(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6)
    }

    private func _resolveUntracked6<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6>(
        _ serviceType: Service.Type,
        name: String?,
        arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5, _ arg6: Arg6
    ) -> Service? {
        syncIfEnabled {
            // Slow-path: skip native lookups, go straight to Swinject.
            if routeAllToSink {
                return fallbackResolver?.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6)
            }
            let argsType: Any.Type = ((Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6) -> Service).self
            let concreteKey = ServiceKey(
                serviceType: DiEntryConcrete<Service>.self,
                argumentsType: argsType,
                name: name
            )
            if let (entry, owner) = getEntry(for: concreteKey),
               let wrapper: DiEntryConcrete<Service> = resolveEntry(entry, owner: owner, invoker: {
                   ($0 as! (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6) -> Any)(self, arg1, arg2, arg3, arg4, arg5, arg6)
               }) {
                return wrapper.value
            }
            let weakKey = ServiceKey(
                serviceType: DiEntryWeak<Service>.self,
                argumentsType: argsType,
                name: name
            )
            if let (entry, owner) = getEntry(for: weakKey),
               let wrapper: DiEntryWeak<Service> = resolveEntry(entry, owner: owner, invoker: {
                   ($0 as! (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6) -> Any)(self, arg1, arg2, arg3, arg4, arg5, arg6)
               }) {
                return wrapper.value(self)
            }
            if let value = parent?.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6) { return value }
            return fallbackResolver?.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6)
        }
    }

    // MARK: - 7-argument

    /// Registers a factory taking 7 runtime arguments.
    ///
    /// Same semantics as the 1-argument overload — see it for how arity and
    /// argument types key a registration, and why argument values do not affect
    /// a shared instance.
    func register<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7>(
        _ serviceType: Service.Type,
        name: String? = nil,
        scope: ObjectScope? = nil,
        factory: @escaping (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7) -> Service,
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

        let strongFactory: (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7) -> Any = { r, arg1, arg2, arg3, arg4, arg5, arg6, arg7 in
            DiEntryConcrete(value: factory(r, arg1, arg2, arg3, arg4, arg5, arg6, arg7))
        }
        let strongInitCompleted: ((Resolver, Any) -> Void)? = initCompleted.map { cb in
            { r, any in
                if let w = any as? DiEntryConcrete<Service> { cb(r, w.value) }
            }
        }
        installEntry(
            serviceType: DiEntryConcrete<Service>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7) -> Service).self,
            name: name,
            factory: strongFactory,
            scope: scope,
            storageFactory: scope.makeStorage,
            initCompleted: strongInitCompleted
        )
        let optFactory: (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7) -> Any = { r, arg1, arg2, arg3, arg4, arg5, arg6, arg7 in
            let value: Service? = r.resolve(Service.self, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7)
            return DiEntryConcrete<Service?>(value: value)
        }
        installEntry(
            serviceType: DiEntryConcrete<Service?>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7) -> Service?).self,
            name: name,
            factory: optFactory,
            scope: ObjectScope.transient,
            storageFactory: TransientStorage.init,
            initCompleted: nil
        )
        notifyBehaviors(didRegisterType: Service.self, name: name)
    }

    /// Registers a weakly-shared factory taking 7 runtime arguments.
    ///
    /// Same semantics as the 1-argument `registerWeak` overload.
    func registerWeak<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7>(
        _ serviceType: Service.Type,
        name: String? = nil,
        scope: WeakObjectScopeProtocol = WeakScope.shared,
        factory: @escaping (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7) -> (Service, () -> Service?),
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

        let weakFactory: (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7) -> Any = { _, arg1, arg2, arg3, arg4, arg5, arg6, arg7 in
            DiEntryWeak<Service>(factory: { r in
                let pair = factory(r, arg1, arg2, arg3, arg4, arg5, arg6, arg7)
                initCompleted?(r, pair.0)
                return pair
            })
        }
        installEntry(
            serviceType: DiEntryWeak<Service>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7) -> Service).self,
            name: name,
            factory: weakFactory,
            scope: scope,
            storageFactory: scope.makeStorage,
            initCompleted: nil
        )
        let optFactory: (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7) -> Any = { r, arg1, arg2, arg3, arg4, arg5, arg6, arg7 in
            let value: Service? = r.resolve(Service.self, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7)
            return DiEntryConcrete<Service?>(value: value)
        }
        installEntry(
            serviceType: DiEntryConcrete<Service?>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7) -> Service?).self,
            name: name,
            factory: optFactory,
            scope: ObjectScope.transient,
            storageFactory: TransientStorage.init,
            initCompleted: nil
        )
        notifyBehaviors(didRegisterType: Service.self, name: name)
    }

    /// Resolves a service registered with 7 runtime arguments.
    ///
    /// Equivalent to the `name: nil` overload below.
    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7>(
        _ serviceType: Service.Type,
        arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5, _ arg6: Arg6, _ arg7: Arg7
    ) -> Service? {
        resolve(serviceType, name: nil, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7)
    }

    /// Resolves a named service registered with 7 runtime arguments.
    ///
    /// Returns `nil` unless a registration matches the type, name, and argument
    /// types exactly.
    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7>(
        _ serviceType: Service.Type,
        name: String?,
        arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5, _ arg6: Arg6, _ arg7: Arg7
    ) -> Service? {
        if hasTracker {
            return _resolveTracked(serviceType, name: name) {
                self._resolveUntracked7(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7)
            }
        }
        return _resolveUntracked7(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7)
    }

    private func _resolveUntracked7<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7>(
        _ serviceType: Service.Type,
        name: String?,
        arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5, _ arg6: Arg6, _ arg7: Arg7
    ) -> Service? {
        syncIfEnabled {
            // Slow-path: skip native lookups, go straight to Swinject.
            if routeAllToSink {
                return fallbackResolver?.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7)
            }
            let argsType: Any.Type = ((Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7) -> Service).self
            let concreteKey = ServiceKey(
                serviceType: DiEntryConcrete<Service>.self,
                argumentsType: argsType,
                name: name
            )
            if let (entry, owner) = getEntry(for: concreteKey),
               let wrapper: DiEntryConcrete<Service> = resolveEntry(entry, owner: owner, invoker: {
                   ($0 as! (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7) -> Any)(self, arg1, arg2, arg3, arg4, arg5, arg6, arg7)
               }) {
                return wrapper.value
            }
            let weakKey = ServiceKey(
                serviceType: DiEntryWeak<Service>.self,
                argumentsType: argsType,
                name: name
            )
            if let (entry, owner) = getEntry(for: weakKey),
               let wrapper: DiEntryWeak<Service> = resolveEntry(entry, owner: owner, invoker: {
                   ($0 as! (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7) -> Any)(self, arg1, arg2, arg3, arg4, arg5, arg6, arg7)
               }) {
                return wrapper.value(self)
            }
            if let value = parent?.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7) { return value }
            return fallbackResolver?.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7)
        }
    }

    // MARK: - 8-argument

    /// Registers a factory taking 8 runtime arguments.
    ///
    /// Same semantics as the 1-argument overload — see it for how arity and
    /// argument types key a registration, and why argument values do not affect
    /// a shared instance.
    func register<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8>(
        _ serviceType: Service.Type,
        name: String? = nil,
        scope: ObjectScope? = nil,
        factory: @escaping (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8) -> Service,
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

        let strongFactory: (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8) -> Any = { r, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8 in
            DiEntryConcrete(value: factory(r, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8))
        }
        let strongInitCompleted: ((Resolver, Any) -> Void)? = initCompleted.map { cb in
            { r, any in
                if let w = any as? DiEntryConcrete<Service> { cb(r, w.value) }
            }
        }
        installEntry(
            serviceType: DiEntryConcrete<Service>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8) -> Service).self,
            name: name,
            factory: strongFactory,
            scope: scope,
            storageFactory: scope.makeStorage,
            initCompleted: strongInitCompleted
        )
        let optFactory: (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8) -> Any = { r, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8 in
            let value: Service? = r.resolve(Service.self, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8)
            return DiEntryConcrete<Service?>(value: value)
        }
        installEntry(
            serviceType: DiEntryConcrete<Service?>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8) -> Service?).self,
            name: name,
            factory: optFactory,
            scope: ObjectScope.transient,
            storageFactory: TransientStorage.init,
            initCompleted: nil
        )
        notifyBehaviors(didRegisterType: Service.self, name: name)
    }

    /// Registers a weakly-shared factory taking 8 runtime arguments.
    ///
    /// Same semantics as the 1-argument `registerWeak` overload.
    func registerWeak<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8>(
        _ serviceType: Service.Type,
        name: String? = nil,
        scope: WeakObjectScopeProtocol = WeakScope.shared,
        factory: @escaping (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8) -> (Service, () -> Service?),
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

        let weakFactory: (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8) -> Any = { _, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8 in
            DiEntryWeak<Service>(factory: { r in
                let pair = factory(r, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8)
                initCompleted?(r, pair.0)
                return pair
            })
        }
        installEntry(
            serviceType: DiEntryWeak<Service>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8) -> Service).self,
            name: name,
            factory: weakFactory,
            scope: scope,
            storageFactory: scope.makeStorage,
            initCompleted: nil
        )
        let optFactory: (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8) -> Any = { r, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8 in
            let value: Service? = r.resolve(Service.self, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8)
            return DiEntryConcrete<Service?>(value: value)
        }
        installEntry(
            serviceType: DiEntryConcrete<Service?>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8) -> Service?).self,
            name: name,
            factory: optFactory,
            scope: ObjectScope.transient,
            storageFactory: TransientStorage.init,
            initCompleted: nil
        )
        notifyBehaviors(didRegisterType: Service.self, name: name)
    }

    /// Resolves a service registered with 8 runtime arguments.
    ///
    /// Equivalent to the `name: nil` overload below.
    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8>(
        _ serviceType: Service.Type,
        arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5, _ arg6: Arg6, _ arg7: Arg7, _ arg8: Arg8
    ) -> Service? {
        resolve(serviceType, name: nil, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8)
    }

    /// Resolves a named service registered with 8 runtime arguments.
    ///
    /// Returns `nil` unless a registration matches the type, name, and argument
    /// types exactly.
    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8>(
        _ serviceType: Service.Type,
        name: String?,
        arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5, _ arg6: Arg6, _ arg7: Arg7, _ arg8: Arg8
    ) -> Service? {
        if hasTracker {
            return _resolveTracked(serviceType, name: name) {
                self._resolveUntracked8(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8)
            }
        }
        return _resolveUntracked8(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8)
    }

    private func _resolveUntracked8<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8>(
        _ serviceType: Service.Type,
        name: String?,
        arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5, _ arg6: Arg6, _ arg7: Arg7, _ arg8: Arg8
    ) -> Service? {
        syncIfEnabled {
            // Slow-path: skip native lookups, go straight to Swinject.
            if routeAllToSink {
                return fallbackResolver?.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8)
            }
            let argsType: Any.Type = ((Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8) -> Service).self
            let concreteKey = ServiceKey(
                serviceType: DiEntryConcrete<Service>.self,
                argumentsType: argsType,
                name: name
            )
            if let (entry, owner) = getEntry(for: concreteKey),
               let wrapper: DiEntryConcrete<Service> = resolveEntry(entry, owner: owner, invoker: {
                   ($0 as! (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8) -> Any)(self, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8)
               }) {
                return wrapper.value
            }
            let weakKey = ServiceKey(
                serviceType: DiEntryWeak<Service>.self,
                argumentsType: argsType,
                name: name
            )
            if let (entry, owner) = getEntry(for: weakKey),
               let wrapper: DiEntryWeak<Service> = resolveEntry(entry, owner: owner, invoker: {
                   ($0 as! (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8) -> Any)(self, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8)
               }) {
                return wrapper.value(self)
            }
            if let value = parent?.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8) { return value }
            return fallbackResolver?.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8)
        }
    }

    // MARK: - 9-argument

    /// Registers a factory taking 9 runtime arguments.
    ///
    /// Same semantics as the 1-argument overload — see it for how arity and
    /// argument types key a registration, and why argument values do not affect
    /// a shared instance.
    func register<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8, Arg9>(
        _ serviceType: Service.Type,
        name: String? = nil,
        scope: ObjectScope? = nil,
        factory: @escaping (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8, Arg9) -> Service,
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

        let strongFactory: (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8, Arg9) -> Any = { r, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9 in
            DiEntryConcrete(value: factory(r, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9))
        }
        let strongInitCompleted: ((Resolver, Any) -> Void)? = initCompleted.map { cb in
            { r, any in
                if let w = any as? DiEntryConcrete<Service> { cb(r, w.value) }
            }
        }
        installEntry(
            serviceType: DiEntryConcrete<Service>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8, Arg9) -> Service).self,
            name: name,
            factory: strongFactory,
            scope: scope,
            storageFactory: scope.makeStorage,
            initCompleted: strongInitCompleted
        )
        let optFactory: (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8, Arg9) -> Any = { r, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9 in
            let value: Service? = r.resolve(Service.self, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
            return DiEntryConcrete<Service?>(value: value)
        }
        installEntry(
            serviceType: DiEntryConcrete<Service?>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8, Arg9) -> Service?).self,
            name: name,
            factory: optFactory,
            scope: ObjectScope.transient,
            storageFactory: TransientStorage.init,
            initCompleted: nil
        )
        notifyBehaviors(didRegisterType: Service.self, name: name)
    }

    /// Registers a weakly-shared factory taking 9 runtime arguments.
    ///
    /// Same semantics as the 1-argument `registerWeak` overload.
    func registerWeak<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8, Arg9>(
        _ serviceType: Service.Type,
        name: String? = nil,
        scope: WeakObjectScopeProtocol = WeakScope.shared,
        factory: @escaping (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8, Arg9) -> (Service, () -> Service?),
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

        let weakFactory: (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8, Arg9) -> Any = { _, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9 in
            DiEntryWeak<Service>(factory: { r in
                let pair = factory(r, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
                initCompleted?(r, pair.0)
                return pair
            })
        }
        installEntry(
            serviceType: DiEntryWeak<Service>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8, Arg9) -> Service).self,
            name: name,
            factory: weakFactory,
            scope: scope,
            storageFactory: scope.makeStorage,
            initCompleted: nil
        )
        let optFactory: (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8, Arg9) -> Any = { r, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9 in
            let value: Service? = r.resolve(Service.self, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
            return DiEntryConcrete<Service?>(value: value)
        }
        installEntry(
            serviceType: DiEntryConcrete<Service?>.self,
            registeredServiceType: Service.self,
            argumentsType: ((Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8, Arg9) -> Service?).self,
            name: name,
            factory: optFactory,
            scope: ObjectScope.transient,
            storageFactory: TransientStorage.init,
            initCompleted: nil
        )
        notifyBehaviors(didRegisterType: Service.self, name: name)
    }

    /// Resolves a service registered with 9 runtime arguments.
    ///
    /// Equivalent to the `name: nil` overload below.
    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8, Arg9>(
        _ serviceType: Service.Type,
        arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5, _ arg6: Arg6, _ arg7: Arg7, _ arg8: Arg8, _ arg9: Arg9
    ) -> Service? {
        resolve(serviceType, name: nil, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
    }

    /// Resolves a named service registered with 9 runtime arguments.
    ///
    /// Returns `nil` unless a registration matches the type, name, and argument
    /// types exactly.
    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8, Arg9>(
        _ serviceType: Service.Type,
        name: String?,
        arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5, _ arg6: Arg6, _ arg7: Arg7, _ arg8: Arg8, _ arg9: Arg9
    ) -> Service? {
        if hasTracker {
            return _resolveTracked(serviceType, name: name) {
                self._resolveUntracked9(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
            }
        }
        return _resolveUntracked9(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
    }

    private func _resolveUntracked9<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8, Arg9>(
        _ serviceType: Service.Type,
        name: String?,
        arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5, _ arg6: Arg6, _ arg7: Arg7, _ arg8: Arg8, _ arg9: Arg9
    ) -> Service? {
        syncIfEnabled {
            // Slow-path: skip native lookups, go straight to Swinject.
            if routeAllToSink {
                return fallbackResolver?.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
            }
            let argsType: Any.Type = ((Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8, Arg9) -> Service).self
            let concreteKey = ServiceKey(
                serviceType: DiEntryConcrete<Service>.self,
                argumentsType: argsType,
                name: name
            )
            if let (entry, owner) = getEntry(for: concreteKey),
               let wrapper: DiEntryConcrete<Service> = resolveEntry(entry, owner: owner, invoker: {
                   ($0 as! (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8, Arg9) -> Any)(self, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
               }) {
                return wrapper.value
            }
            let weakKey = ServiceKey(
                serviceType: DiEntryWeak<Service>.self,
                argumentsType: argsType,
                name: name
            )
            if let (entry, owner) = getEntry(for: weakKey),
               let wrapper: DiEntryWeak<Service> = resolveEntry(entry, owner: owner, invoker: {
                   ($0 as! (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8, Arg9) -> Any)(self, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
               }) {
                return wrapper.value(self)
            }
            if let value = parent?.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9) { return value }
            return fallbackResolver?.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
        }
    }
}
