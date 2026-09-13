//
//  Portions derived from Swinject (https://github.com/Swinject/Swinject)
//  Copyright © 2019 Swinject Contributors. All rights reserved.
//  Licensed under the MIT License — see NOTICE.
//

/// Internal registration record. Not part of the public API surface.
final class ServiceEntry {
    let serviceType: Any.Type
    let registeredServiceType: Any.Type
    let argumentsType: Any.Type
    let factory: Any // typed per-arity, e.g. `(Resolver) -> Any` or `(Resolver, Arg1) -> Any`
    let objectScope: AnyObject?
    lazy var storage: InstanceStorage = storageFactory()
    let storageFactory: () -> InstanceStorage
    var initCompleted: ((Resolver, Any) -> Void)?

    init(
        serviceType: Any.Type,
        registeredServiceType: Any.Type,
        argumentsType: Any.Type,
        factory: Any,
        objectScope: AnyObject?,
        storageFactory: @escaping () -> InstanceStorage,
        initCompleted: ((Resolver, Any) -> Void)? = nil
    ) {
        self.serviceType = serviceType
        self.registeredServiceType = registeredServiceType
        self.argumentsType = argumentsType
        self.factory = factory
        self.objectScope = objectScope
        self.storageFactory = storageFactory
        self.initCompleted = initCompleted
    }
}
