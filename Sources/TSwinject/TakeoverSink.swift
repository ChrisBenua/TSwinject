/// Sink that receives *all* registrations and bulk operations of a container
/// whose `routeAllToSink` flag is set (the Swinject-takeover mode used during
/// migration and as an A/B kill-switch). Implemented by the interop product.
///
/// The native registration path never calls the sink — when `routeAllToSink`
/// is `false` the container ignores it entirely.
public protocol TakeoverSink: AnyObject {
    // MARK: - 0-argument

    func mirrorRegister<Service>(
        _ serviceType: Service.Type,
        name: String?,
        scope: ObjectScope,
        factory: @escaping (Resolver) -> Service,
        initCompleted: ((Resolver, Service) -> Void)?
    )

    func mirrorRegisterWeak<Service>(
        _ serviceType: Service.Type,
        name: String?,
        scope: WeakObjectScopeProtocol,
        factory: @escaping (Resolver) -> (Service, () -> Service?),
        initCompleted: ((Resolver, Service) -> Void)?
    )

    // MARK: - 1-argument

    func mirrorRegister<Service, Arg1>(
        _ serviceType: Service.Type,
        name: String?,
        scope: ObjectScope,
        factory: @escaping (Resolver, Arg1) -> Service,
        initCompleted: ((Resolver, Service) -> Void)?
    )

    func mirrorRegisterWeak<Service, Arg1>(
        _ serviceType: Service.Type,
        name: String?,
        scope: WeakObjectScopeProtocol,
        factory: @escaping (Resolver, Arg1) -> (Service, () -> Service?),
        initCompleted: ((Resolver, Service) -> Void)?
    )

    // MARK: - 2-argument

    func mirrorRegister<Service, Arg1, Arg2>(
        _ serviceType: Service.Type,
        name: String?,
        scope: ObjectScope,
        factory: @escaping (Resolver, Arg1, Arg2) -> Service,
        initCompleted: ((Resolver, Service) -> Void)?
    )

    func mirrorRegisterWeak<Service, Arg1, Arg2>(
        _ serviceType: Service.Type,
        name: String?,
        scope: WeakObjectScopeProtocol,
        factory: @escaping (Resolver, Arg1, Arg2) -> (Service, () -> Service?),
        initCompleted: ((Resolver, Service) -> Void)?
    )

    // MARK: - 3-argument

    func mirrorRegister<Service, Arg1, Arg2, Arg3>(
        _ serviceType: Service.Type,
        name: String?,
        scope: ObjectScope,
        factory: @escaping (Resolver, Arg1, Arg2, Arg3) -> Service,
        initCompleted: ((Resolver, Service) -> Void)?
    )

    func mirrorRegisterWeak<Service, Arg1, Arg2, Arg3>(
        _ serviceType: Service.Type,
        name: String?,
        scope: WeakObjectScopeProtocol,
        factory: @escaping (Resolver, Arg1, Arg2, Arg3) -> (Service, () -> Service?),
        initCompleted: ((Resolver, Service) -> Void)?
    )

    // MARK: - 4-argument

    func mirrorRegister<Service, Arg1, Arg2, Arg3, Arg4>(
        _ serviceType: Service.Type,
        name: String?,
        scope: ObjectScope,
        factory: @escaping (Resolver, Arg1, Arg2, Arg3, Arg4) -> Service,
        initCompleted: ((Resolver, Service) -> Void)?
    )

    func mirrorRegisterWeak<Service, Arg1, Arg2, Arg3, Arg4>(
        _ serviceType: Service.Type,
        name: String?,
        scope: WeakObjectScopeProtocol,
        factory: @escaping (Resolver, Arg1, Arg2, Arg3, Arg4) -> (Service, () -> Service?),
        initCompleted: ((Resolver, Service) -> Void)?
    )

    // MARK: - 5-argument

    func mirrorRegister<Service, Arg1, Arg2, Arg3, Arg4, Arg5>(
        _ serviceType: Service.Type,
        name: String?,
        scope: ObjectScope,
        factory: @escaping (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5) -> Service,
        initCompleted: ((Resolver, Service) -> Void)?
    )

    func mirrorRegisterWeak<Service, Arg1, Arg2, Arg3, Arg4, Arg5>(
        _ serviceType: Service.Type,
        name: String?,
        scope: WeakObjectScopeProtocol,
        factory: @escaping (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5) -> (Service, () -> Service?),
        initCompleted: ((Resolver, Service) -> Void)?
    )

    // MARK: - 6-argument

    func mirrorRegister<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6>(
        _ serviceType: Service.Type,
        name: String?,
        scope: ObjectScope,
        factory: @escaping (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6) -> Service,
        initCompleted: ((Resolver, Service) -> Void)?
    )

    func mirrorRegisterWeak<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6>(
        _ serviceType: Service.Type,
        name: String?,
        scope: WeakObjectScopeProtocol,
        factory: @escaping (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6) -> (Service, () -> Service?),
        initCompleted: ((Resolver, Service) -> Void)?
    )

    // MARK: - 7-argument

    func mirrorRegister<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7>(
        _ serviceType: Service.Type,
        name: String?,
        scope: ObjectScope,
        factory: @escaping (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7) -> Service,
        initCompleted: ((Resolver, Service) -> Void)?
    )

    func mirrorRegisterWeak<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7>(
        _ serviceType: Service.Type,
        name: String?,
        scope: WeakObjectScopeProtocol,
        factory: @escaping (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7) -> (Service, () -> Service?),
        initCompleted: ((Resolver, Service) -> Void)?
    )

    // MARK: - 8-argument

    func mirrorRegister<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8>(
        _ serviceType: Service.Type,
        name: String?,
        scope: ObjectScope,
        factory: @escaping (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8) -> Service,
        initCompleted: ((Resolver, Service) -> Void)?
    )

    func mirrorRegisterWeak<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8>(
        _ serviceType: Service.Type,
        name: String?,
        scope: WeakObjectScopeProtocol,
        factory: @escaping (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8) -> (Service, () -> Service?),
        initCompleted: ((Resolver, Service) -> Void)?
    )

    // MARK: - 9-argument

    func mirrorRegister<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8, Arg9>(
        _ serviceType: Service.Type,
        name: String?,
        scope: ObjectScope,
        factory: @escaping (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8, Arg9) -> Service,
        initCompleted: ((Resolver, Service) -> Void)?
    )

    func mirrorRegisterWeak<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8, Arg9>(
        _ serviceType: Service.Type,
        name: String?,
        scope: WeakObjectScopeProtocol,
        factory: @escaping (Resolver, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8, Arg9) -> (Service, () -> Service?),
        initCompleted: ((Resolver, Service) -> Void)?
    )

    // MARK: - Bulk operations

    /// Mirrors `Container.removeAll()` — clears every registration on the
    /// takeover side (the shared registry).
    func mirrorRemoveAll()

    /// Mirrors `Container.resetObjectScope(_:)` for a concrete `ObjectScope`.
    func mirrorResetObjectScope(_ scope: ObjectScope)

    #if SWINJECT_2_10_AVAILABLE
        /// Mirrors `Container.resetObjectScope(_:serviceType:)` for a concrete
        /// `ObjectScope`.
        func mirrorResetObjectScope(_ scope: ObjectScope, serviceType: Any.Type)
    #endif

    /// Mirrors `Container.resetObjectScope(_:)` for a *weak* scope. All weak
    /// registrations collapse to the target's `.weak` scope under takeover, so
    /// this resets every weak registration (not one scope instance).
    func mirrorResetWeakObjectScope()

    #if SWINJECT_2_10_AVAILABLE
        /// Mirrors `Container.resetObjectScope(_:serviceType:)` for a *weak* scope —
        /// resets the target's `.weak` scope for one service type.
        func mirrorResetWeakObjectScope(serviceType: Any.Type)
    #endif

    /// Answers `Container.hasAnyRegistration(of:name:)` from the takeover side by
    /// delegating to the target container's own registration probe, so it sees
    /// registrations made directly on the target as well as ones routed here.
    func mirrorHasRegistration<Service>(_ serviceType: Service.Type, name: String?) -> Bool
}
