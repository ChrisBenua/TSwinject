//
//  Portions derived from Swinject (https://github.com/Swinject/Swinject)
//  Copyright © 2019 Swinject Contributors. All rights reserved.
//  Licensed under the MIT License — see NOTICE.
//
//  Single mode: the TSwinject container becomes a typed façade over a real
//  Swinject container. Every register/resolve (and removeAll / resetObjectScope
//  / hasAnyRegistration) routes to Swinject.
//
//  Entry point: `attachSwinjectBridge(legacy)` — point the façade at the
//  *legacy* Swinject container so there is a single shared registry: services
//  registered through the façade are visible to unmigrated Swinject-side
//  consumers and vice-versa, with one engine upholding graph/scope identity,
//  circularity (initCompleted), and synchronization.
//

import Foundation
import Swinject
import TSwinject

/// Maps a TSwinject scope onto the Swinject scope used for a routed
/// registration. Consulted for every strong registration; weak registrations
/// always map to Swinject's `.weak`.
public typealias SwinjectScopeMap = @Sendable (TSwinject.ObjectScope) -> Swinject.ObjectScope

/// Turns a TSwinject container into a façade over a real Swinject container, so
/// a codebase can migrate one assembly at a time against a single shared registry.
public extension TSwinject.Container {
    /// The default scope mapping. Built-in scopes map 1:1; custom scopes are
    /// recognised by their *backing storage*, not their name: any scope whose
    /// `makeStorage()` produces a `PermanentStorage` maps to Swinject's
    /// `.container` rather than silently degrading to `.graph`.
    static let defaultSwinjectScopeMap: SwinjectScopeMap = { scope in
        switch scope.description {
        case "transient": return .transient
        case "container": return .container
        case "graph": return .graph
        default:
            return scope.makeStorage() is TSwinject.PermanentStorage ? .container : .graph
        }
    }

    /// Routes this container entirely to `swinjectContainer` (takeover): every
    /// `register*` goes only to Swinject; every `resolve*` goes only to Swinject.
    /// The TSwinject container becomes a thin typed façade.
    ///
    /// Must be called **before** any `register*` call on this container — this is
    /// enforced: `activateTakeover` traps with a precondition failure if the
    /// container already holds native registrations, rather than silently
    /// orphaning them.
    ///
    /// For migration, pass the *legacy* Swinject container itself — a single
    /// registry means a service registered through this façade is found by
    /// unmigrated Swinject-side consumers, and a service registered directly in
    /// Swinject is found through the façade. Neither direction can silently miss.
    func attachSwinjectBridge(
        _ swinjectContainer: Swinject.Container,
        scopeMap: @escaping SwinjectScopeMap = TSwinject.Container.defaultSwinjectScopeMap
    ) {
        activateTakeover(
            sink: SwinjectTakeoverSink(target: swinjectContainer, scopeMap: scopeMap),
            fallbackResolver: SwinjectResolverAdapter(swinjectContainer)
        )
    }
}

// MARK: - SwinjectTakeoverSink

private final class SwinjectTakeoverSink: TakeoverSink {
    let target: Swinject.Container
    let scopeMap: SwinjectScopeMap

    init(target: Swinject.Container, scopeMap: @escaping SwinjectScopeMap) {
        self.target = target
        self.scopeMap = scopeMap
    }

    /// Re-runs the TSwinject `initCompleted` callback on the Swinject entry,
    /// presenting the Swinject resolver through the TSwinject façade type.
    private func applyInitCompleted<Service>(
        _ entry: Swinject.ServiceEntry<Service>,
        _ initCompleted: ((TSwinject.Resolver, Service) -> Void)?
    ) {
        guard let initCompleted else { return }
        entry.initCompleted { r, service in
            initCompleted(TSwinjectResolverAdapter(r), service)
        }
    }

    // MARK: 0-argument

    func mirrorRegister<Service>(
        _ serviceType: Service.Type,
        name: String?,
        scope: TSwinject.ObjectScope,
        factory: @escaping (TSwinject.Resolver) -> Service,
        initCompleted: ((TSwinject.Resolver, Service) -> Void)?
    ) {
        let entry = target.register(serviceType, name: name) { (r: Swinject.Resolver) in
            factory(TSwinjectResolverAdapter(r))
        }
        entry.inObjectScope(scopeMap(scope))
        applyInitCompleted(entry, initCompleted)
    }

    func mirrorRegisterWeak<Service>(
        _ serviceType: Service.Type,
        name: String?,
        scope: TSwinject.WeakObjectScopeProtocol,
        factory: @escaping (TSwinject.Resolver) -> (Service, () -> Service?),
        initCompleted: ((TSwinject.Resolver, Service) -> Void)?
    ) {
        let entry = target.register(serviceType, name: name) { (r: Swinject.Resolver) -> Service in
            factory(TSwinjectResolverAdapter(r)).0
        }
        entry.inObjectScope(.weak)
        applyInitCompleted(entry, initCompleted)
    }

    // MARK: 1-argument

    func mirrorRegister<Service, Arg1>(
        _ serviceType: Service.Type,
        name: String?,
        scope: TSwinject.ObjectScope,
        factory: @escaping (TSwinject.Resolver, Arg1) -> Service,
        initCompleted: ((TSwinject.Resolver, Service) -> Void)?
    ) {
        let entry = target.register(serviceType, name: name) { (r: Swinject.Resolver, arg1: Arg1) in
            factory(TSwinjectResolverAdapter(r), arg1)
        }
        entry.inObjectScope(scopeMap(scope))
        applyInitCompleted(entry, initCompleted)
    }

    func mirrorRegisterWeak<Service, Arg1>(
        _ serviceType: Service.Type,
        name: String?,
        scope: TSwinject.WeakObjectScopeProtocol,
        factory: @escaping (TSwinject.Resolver, Arg1) -> (Service, () -> Service?),
        initCompleted: ((TSwinject.Resolver, Service) -> Void)?
    ) {
        let entry = target.register(serviceType, name: name) { (r: Swinject.Resolver, arg1: Arg1) -> Service in
            factory(TSwinjectResolverAdapter(r), arg1).0
        }
        entry.inObjectScope(.weak)
        applyInitCompleted(entry, initCompleted)
    }

    // MARK: 2-argument

    func mirrorRegister<Service, Arg1, Arg2>(
        _ serviceType: Service.Type,
        name: String?,
        scope: TSwinject.ObjectScope,
        factory: @escaping (TSwinject.Resolver, Arg1, Arg2) -> Service,
        initCompleted: ((TSwinject.Resolver, Service) -> Void)?
    ) {
        let entry = target.register(serviceType, name: name) { (r: Swinject.Resolver, arg1: Arg1, arg2: Arg2) in
            factory(TSwinjectResolverAdapter(r), arg1, arg2)
        }
        entry.inObjectScope(scopeMap(scope))
        applyInitCompleted(entry, initCompleted)
    }

    func mirrorRegisterWeak<Service, Arg1, Arg2>(
        _ serviceType: Service.Type,
        name: String?,
        scope: TSwinject.WeakObjectScopeProtocol,
        factory: @escaping (TSwinject.Resolver, Arg1, Arg2) -> (Service, () -> Service?),
        initCompleted: ((TSwinject.Resolver, Service) -> Void)?
    ) {
        let entry = target.register(serviceType, name: name) { (r: Swinject.Resolver, arg1: Arg1, arg2: Arg2) -> Service in
            factory(TSwinjectResolverAdapter(r), arg1, arg2).0
        }
        entry.inObjectScope(.weak)
        applyInitCompleted(entry, initCompleted)
    }

    // MARK: 3-argument

    func mirrorRegister<Service, Arg1, Arg2, Arg3>(
        _ serviceType: Service.Type,
        name: String?,
        scope: TSwinject.ObjectScope,
        factory: @escaping (TSwinject.Resolver, Arg1, Arg2, Arg3) -> Service,
        initCompleted: ((TSwinject.Resolver, Service) -> Void)?
    ) {
        let entry = target.register(serviceType, name: name) { (r: Swinject.Resolver, arg1: Arg1, arg2: Arg2, arg3: Arg3) in
            factory(TSwinjectResolverAdapter(r), arg1, arg2, arg3)
        }
        entry.inObjectScope(scopeMap(scope))
        applyInitCompleted(entry, initCompleted)
    }

    func mirrorRegisterWeak<Service, Arg1, Arg2, Arg3>(
        _ serviceType: Service.Type,
        name: String?,
        scope: TSwinject.WeakObjectScopeProtocol,
        factory: @escaping (TSwinject.Resolver, Arg1, Arg2, Arg3) -> (Service, () -> Service?),
        initCompleted: ((TSwinject.Resolver, Service) -> Void)?
    ) {
        let entry = target.register(serviceType, name: name) { (r: Swinject.Resolver, arg1: Arg1, arg2: Arg2, arg3: Arg3) -> Service in
            factory(TSwinjectResolverAdapter(r), arg1, arg2, arg3).0
        }
        entry.inObjectScope(.weak)
        applyInitCompleted(entry, initCompleted)
    }

    // MARK: 4-argument

    func mirrorRegister<Service, Arg1, Arg2, Arg3, Arg4>(
        _ serviceType: Service.Type,
        name: String?,
        scope: TSwinject.ObjectScope,
        factory: @escaping (TSwinject.Resolver, Arg1, Arg2, Arg3, Arg4) -> Service,
        initCompleted: ((TSwinject.Resolver, Service) -> Void)?
    ) {
        let entry = target.register(serviceType, name: name) { (r: Swinject.Resolver, arg1: Arg1, arg2: Arg2, arg3: Arg3, arg4: Arg4) in
            factory(TSwinjectResolverAdapter(r), arg1, arg2, arg3, arg4)
        }
        entry.inObjectScope(scopeMap(scope))
        applyInitCompleted(entry, initCompleted)
    }

    func mirrorRegisterWeak<Service, Arg1, Arg2, Arg3, Arg4>(
        _ serviceType: Service.Type,
        name: String?,
        scope: TSwinject.WeakObjectScopeProtocol,
        factory: @escaping (TSwinject.Resolver, Arg1, Arg2, Arg3, Arg4) -> (Service, () -> Service?),
        initCompleted: ((TSwinject.Resolver, Service) -> Void)?
    ) {
        let entry = target.register(serviceType, name: name) { (r: Swinject.Resolver, arg1: Arg1, arg2: Arg2, arg3: Arg3, arg4: Arg4) -> Service in
            factory(TSwinjectResolverAdapter(r), arg1, arg2, arg3, arg4).0
        }
        entry.inObjectScope(.weak)
        applyInitCompleted(entry, initCompleted)
    }

    // MARK: 5-argument

    func mirrorRegister<Service, Arg1, Arg2, Arg3, Arg4, Arg5>(
        _ serviceType: Service.Type,
        name: String?,
        scope: TSwinject.ObjectScope,
        factory: @escaping (TSwinject.Resolver, Arg1, Arg2, Arg3, Arg4, Arg5) -> Service,
        initCompleted: ((TSwinject.Resolver, Service) -> Void)?
    ) {
        let entry = target.register(serviceType, name: name) { (r: Swinject.Resolver, arg1: Arg1, arg2: Arg2, arg3: Arg3, arg4: Arg4, arg5: Arg5) in
            factory(TSwinjectResolverAdapter(r), arg1, arg2, arg3, arg4, arg5)
        }
        entry.inObjectScope(scopeMap(scope))
        applyInitCompleted(entry, initCompleted)
    }

    func mirrorRegisterWeak<Service, Arg1, Arg2, Arg3, Arg4, Arg5>(
        _ serviceType: Service.Type,
        name: String?,
        scope: TSwinject.WeakObjectScopeProtocol,
        factory: @escaping (TSwinject.Resolver, Arg1, Arg2, Arg3, Arg4, Arg5) -> (Service, () -> Service?),
        initCompleted: ((TSwinject.Resolver, Service) -> Void)?
    ) {
        let entry = target.register(serviceType, name: name) { (r: Swinject.Resolver, arg1: Arg1, arg2: Arg2, arg3: Arg3, arg4: Arg4, arg5: Arg5) -> Service in
            factory(TSwinjectResolverAdapter(r), arg1, arg2, arg3, arg4, arg5).0
        }
        entry.inObjectScope(.weak)
        applyInitCompleted(entry, initCompleted)
    }

    // MARK: 6-argument

    func mirrorRegister<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6>(
        _ serviceType: Service.Type,
        name: String?,
        scope: TSwinject.ObjectScope,
        factory: @escaping (TSwinject.Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6) -> Service,
        initCompleted: ((TSwinject.Resolver, Service) -> Void)?
    ) {
        let entry = target.register(serviceType, name: name) { (r: Swinject.Resolver, arg1: Arg1, arg2: Arg2, arg3: Arg3, arg4: Arg4, arg5: Arg5, arg6: Arg6) in
            factory(TSwinjectResolverAdapter(r), arg1, arg2, arg3, arg4, arg5, arg6)
        }
        entry.inObjectScope(scopeMap(scope))
        applyInitCompleted(entry, initCompleted)
    }

    func mirrorRegisterWeak<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6>(
        _ serviceType: Service.Type,
        name: String?,
        scope: TSwinject.WeakObjectScopeProtocol,
        factory: @escaping (TSwinject.Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6) -> (Service, () -> Service?),
        initCompleted: ((TSwinject.Resolver, Service) -> Void)?
    ) {
        let entry = target.register(serviceType, name: name) { (r: Swinject.Resolver, arg1: Arg1, arg2: Arg2, arg3: Arg3, arg4: Arg4, arg5: Arg5, arg6: Arg6) -> Service in
            factory(TSwinjectResolverAdapter(r), arg1, arg2, arg3, arg4, arg5, arg6).0
        }
        entry.inObjectScope(.weak)
        applyInitCompleted(entry, initCompleted)
    }

    // MARK: 7-argument

    func mirrorRegister<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7>(
        _ serviceType: Service.Type,
        name: String?,
        scope: TSwinject.ObjectScope,
        factory: @escaping (TSwinject.Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7) -> Service,
        initCompleted: ((TSwinject.Resolver, Service) -> Void)?
    ) {
        let entry = target.register(serviceType, name: name) { (r: Swinject.Resolver, arg1: Arg1, arg2: Arg2, arg3: Arg3, arg4: Arg4, arg5: Arg5, arg6: Arg6, arg7: Arg7) in
            factory(TSwinjectResolverAdapter(r), arg1, arg2, arg3, arg4, arg5, arg6, arg7)
        }
        entry.inObjectScope(scopeMap(scope))
        applyInitCompleted(entry, initCompleted)
    }

    func mirrorRegisterWeak<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7>(
        _ serviceType: Service.Type,
        name: String?,
        scope: TSwinject.WeakObjectScopeProtocol,
        factory: @escaping (TSwinject.Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7) -> (Service, () -> Service?),
        initCompleted: ((TSwinject.Resolver, Service) -> Void)?
    ) {
        let entry = target.register(serviceType, name: name) { (r: Swinject.Resolver, arg1: Arg1, arg2: Arg2, arg3: Arg3, arg4: Arg4, arg5: Arg5, arg6: Arg6, arg7: Arg7) -> Service in
            factory(TSwinjectResolverAdapter(r), arg1, arg2, arg3, arg4, arg5, arg6, arg7).0
        }
        entry.inObjectScope(.weak)
        applyInitCompleted(entry, initCompleted)
    }

    // MARK: 8-argument

    func mirrorRegister<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8>(
        _ serviceType: Service.Type,
        name: String?,
        scope: TSwinject.ObjectScope,
        factory: @escaping (TSwinject.Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8) -> Service,
        initCompleted: ((TSwinject.Resolver, Service) -> Void)?
    ) {
        let entry = target.register(serviceType, name: name) { (r: Swinject.Resolver, arg1: Arg1, arg2: Arg2, arg3: Arg3, arg4: Arg4, arg5: Arg5, arg6: Arg6, arg7: Arg7, arg8: Arg8) in
            factory(TSwinjectResolverAdapter(r), arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8)
        }
        entry.inObjectScope(scopeMap(scope))
        applyInitCompleted(entry, initCompleted)
    }

    func mirrorRegisterWeak<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8>(
        _ serviceType: Service.Type,
        name: String?,
        scope: TSwinject.WeakObjectScopeProtocol,
        factory: @escaping (TSwinject.Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8) -> (Service, () -> Service?),
        initCompleted: ((TSwinject.Resolver, Service) -> Void)?
    ) {
        let entry = target.register(serviceType, name: name) { (r: Swinject.Resolver, arg1: Arg1, arg2: Arg2, arg3: Arg3, arg4: Arg4, arg5: Arg5, arg6: Arg6, arg7: Arg7, arg8: Arg8) -> Service in
            factory(TSwinjectResolverAdapter(r), arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8).0
        }
        entry.inObjectScope(.weak)
        applyInitCompleted(entry, initCompleted)
    }

    // MARK: 9-argument

    func mirrorRegister<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8, Arg9>(
        _ serviceType: Service.Type,
        name: String?,
        scope: TSwinject.ObjectScope,
        factory: @escaping (TSwinject.Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8, Arg9) -> Service,
        initCompleted: ((TSwinject.Resolver, Service) -> Void)?
    ) {
        let entry = target.register(serviceType, name: name) { (r: Swinject.Resolver, arg1: Arg1, arg2: Arg2, arg3: Arg3, arg4: Arg4, arg5: Arg5, arg6: Arg6, arg7: Arg7, arg8: Arg8, arg9: Arg9) in
            factory(TSwinjectResolverAdapter(r), arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
        }
        entry.inObjectScope(scopeMap(scope))
        applyInitCompleted(entry, initCompleted)
    }

    func mirrorRegisterWeak<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8, Arg9>(
        _ serviceType: Service.Type,
        name: String?,
        scope: TSwinject.WeakObjectScopeProtocol,
        factory: @escaping (TSwinject.Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8, Arg9) -> (Service, () -> Service?),
        initCompleted: ((TSwinject.Resolver, Service) -> Void)?
    ) {
        let entry = target.register(serviceType, name: name) { (r: Swinject.Resolver, arg1: Arg1, arg2: Arg2, arg3: Arg3, arg4: Arg4, arg5: Arg5, arg6: Arg6, arg7: Arg7, arg8: Arg8, arg9: Arg9) -> Service in
            factory(TSwinjectResolverAdapter(r), arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9).0
        }
        entry.inObjectScope(.weak)
        applyInitCompleted(entry, initCompleted)
    }

    // MARK: Bulk operations

    func mirrorRemoveAll() {
        target.removeAll()
    }

    func mirrorResetObjectScope(_ scope: TSwinject.ObjectScope) {
        target.resetObjectScope(scopeMap(scope))
    }

    #if SWINJECT_2_10_AVAILABLE
        func mirrorResetObjectScope(_ scope: TSwinject.ObjectScope, serviceType: Any.Type) {
            target.resetObjectScope(scopeMap(scope), serviceType: serviceType)
        }
    #endif

    func mirrorResetWeakObjectScope() {
        target.resetObjectScope(.weak)
    }

    #if SWINJECT_2_10_AVAILABLE
        func mirrorResetWeakObjectScope(serviceType: Any.Type) {
            target.resetObjectScope(.weak, serviceType: serviceType)
        }
    #endif

    func mirrorHasRegistration<Service>(_ serviceType: Service.Type, name: String?) -> Bool {
        target.hasAnyRegistration(of: serviceType, name: name)
    }
}

// MARK: - TSwinjectResolverAdapter

/// Wraps a `Swinject.Resolver` so TSwinject-typed factories can pull
/// dependencies from the Swinject engine during takeover.
private final class TSwinjectResolverAdapter: TSwinject.Resolver, @unchecked Sendable {
    let inner: Swinject.Resolver
    init(_ inner: Swinject.Resolver) { self.inner = inner }

    func resolve<Service>(_ serviceType: Service.Type, name: String?) -> Service? {
        inner.resolve(serviceType, name: name)
    }

    func resolve<Service, Arg1>(_ serviceType: Service.Type, name: String?, argument arg1: Arg1) -> Service? {
        inner.resolve(serviceType, name: name, argument: arg1)
    }

    func resolve<Service, Arg1, Arg2>(_ serviceType: Service.Type, name: String?, arguments arg1: Arg1, _ arg2: Arg2) -> Service? {
        inner.resolve(serviceType, name: name, arguments: arg1, arg2)
    }

    func resolve<Service, Arg1, Arg2, Arg3>(_ serviceType: Service.Type, name: String?, arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3) -> Service? {
        inner.resolve(serviceType, name: name, arguments: arg1, arg2, arg3)
    }

    func resolve<Service, Arg1, Arg2, Arg3, Arg4>(_ serviceType: Service.Type, name: String?, arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4) -> Service? {
        inner.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4)
    }

    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5>(_ serviceType: Service.Type, name: String?, arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5) -> Service? {
        inner.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5)
    }

    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6>(_ serviceType: Service.Type, name: String?, arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5, _ arg6: Arg6) -> Service? {
        inner.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6)
    }

    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7>(_ serviceType: Service.Type, name: String?, arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5, _ arg6: Arg6, _ arg7: Arg7) -> Service? {
        inner.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7)
    }

    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8>(_ serviceType: Service.Type, name: String?, arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5, _ arg6: Arg6, _ arg7: Arg7, _ arg8: Arg8) -> Service? {
        inner.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8)
    }

    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8, Arg9>(_ serviceType: Service.Type, name: String?, arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5, _ arg6: Arg6, _ arg7: Arg7, _ arg8: Arg8, _ arg9: Arg9) -> Service? {
        inner.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
    }
}

// MARK: - SwinjectResolverAdapter

/// Used as the TSwinject `fallbackResolver` — answers all façade resolves from
/// Swinject. Resolution goes through Swinject's own synchronized view so façade
/// resolves share Swinject's lock with any synchronized resolver the host
/// already uses on the same container.
private final class SwinjectResolverAdapter: TSwinject.Resolver, @unchecked Sendable {
    let inner: Swinject.Container
    private let synchronizedInner: Swinject.Resolver

    init(_ inner: Swinject.Container) {
        self.inner = inner
        self.synchronizedInner = inner.synchronize()
    }

    func resolve<Service>(_ serviceType: Service.Type, name: String?) -> Service? {
        synchronizedInner.resolve(serviceType, name: name)
    }

    func resolve<Service, Arg1>(_ serviceType: Service.Type, name: String?, argument arg1: Arg1) -> Service? {
        synchronizedInner.resolve(serviceType, name: name, argument: arg1)
    }

    func resolve<Service, Arg1, Arg2>(_ serviceType: Service.Type, name: String?, arguments arg1: Arg1, _ arg2: Arg2) -> Service? {
        synchronizedInner.resolve(serviceType, name: name, arguments: arg1, arg2)
    }

    func resolve<Service, Arg1, Arg2, Arg3>(_ serviceType: Service.Type, name: String?, arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3) -> Service? {
        synchronizedInner.resolve(serviceType, name: name, arguments: arg1, arg2, arg3)
    }

    func resolve<Service, Arg1, Arg2, Arg3, Arg4>(_ serviceType: Service.Type, name: String?, arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4) -> Service? {
        synchronizedInner.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4)
    }

    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5>(_ serviceType: Service.Type, name: String?, arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5) -> Service? {
        synchronizedInner.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5)
    }

    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6>(_ serviceType: Service.Type, name: String?, arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5, _ arg6: Arg6) -> Service? {
        synchronizedInner.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6)
    }

    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7>(_ serviceType: Service.Type, name: String?, arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5, _ arg6: Arg6, _ arg7: Arg7) -> Service? {
        synchronizedInner.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7)
    }

    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8>(_ serviceType: Service.Type, name: String?, arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5, _ arg6: Arg6, _ arg7: Arg7, _ arg8: Arg8) -> Service? {
        synchronizedInner.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8)
    }

    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8, Arg9>(_ serviceType: Service.Type, name: String?, arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5, _ arg6: Arg6, _ arg7: Arg7, _ arg8: Arg8, _ arg9: Arg9) -> Service? {
        synchronizedInner.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
    }
}
