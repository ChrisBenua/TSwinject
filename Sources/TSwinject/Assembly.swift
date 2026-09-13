//
//  Portions derived from Swinject (https://github.com/Swinject/Swinject)
//  Copyright © 2019 Swinject Contributors. All rights reserved.
//  Licensed under the MIT License — see NOTICE.
//

/// The ``Assembly`` provides a means to organize your `Service` registration in logic groups which allows
/// the user to swap out different implementations of `Services` by providing different ``Assembly`` instances
/// to the ``Assembler``
public protocol Assembly {
    /// Provide hook for ``Assembler`` to load Services into the provided container
    ///
    /// - parameter container: the container provided by the ``Assembler``
    ///
    func assemble(container: Container)

    /// Provides a hook to the ``Assembly`` that will be called once the ``Assembler`` has loaded all ``Assembly``
    /// instances into the container.
    ///
    /// - parameter resolver: the resolver that can resolve instances from the built container
    ///
    func loaded(resolver: Resolver)
}

/// Makes ``Assembly/loaded(resolver:)`` optional, so an assembly that only
/// registers services does not have to implement it.
public extension Assembly {
    /// No-op default, so `loaded(resolver:)` is opt-in.
    func loaded(resolver _: Resolver) {
        // no-op
    }
}
