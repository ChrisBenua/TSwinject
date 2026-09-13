//
//  Portions derived from Swinject (https://github.com/Swinject/Swinject)
//  Copyright © 2019 Swinject Contributors. All rights reserved.
//  Licensed under the MIT License — see NOTICE.
//

/// Protocol for adding functionality to the container.
///
/// Unlike Swinject's `Behavior`, the callback does not receive a `ServiceEntry`
/// (TSwinject keeps registration records private).
public protocol Behavior {
    /// Called after each registration on a container the behavior is attached to.
    ///
    /// Attach with `Container.addBehavior(_:)`. Only registrations made *after*
    /// the behavior is added are reported, so add behaviors before assemblies run.
    ///
    /// - Parameters:
    ///   - container: The container that received the registration.
    ///   - type: The service type that was registered.
    ///   - name: The registration's name, or `nil` if it was unnamed.
    func container<Service>(
        _ container: Container,
        didRegisterType type: Service.Type,
        withName name: String?
    )
}
