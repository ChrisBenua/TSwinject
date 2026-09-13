//
//  Portions derived from Swinject (https://github.com/Swinject/Swinject)
//  Copyright © 2019 Swinject Contributors. All rights reserved.
//  Licensed under the MIT License — see NOTICE.
//

/// The read side of a container: everything needed to resolve a registered
/// service, and nothing that can register one.
///
/// Factory closures receive a `Resolver` rather than the `Container` itself, so
/// a factory can pull its dependencies but cannot mutate the registry while an
/// object graph is being built.
///
/// The overload set mirrors Swinject's: `resolve` for 0 through 9 runtime
/// arguments, each with and without a `name:`. Arity and argument types are part
/// of a registration's identity, so `resolve(Foo.self)` and
/// `resolve(Foo.self, argument: 1)` look up two independent registrations.
///
/// - Important: Conforming your own type — a test double, say — gets default
///   implementations for every requirement, and the defaults for the named
///   variants return `nil`. See the extension below.
public protocol Resolver: Sendable {
    /// Resolves an unnamed service. Equivalent to `resolve(serviceType, name: nil)`.
    func resolve<Service>(_ serviceType: Service.Type) -> Service?

    /// Resolves a service registered under `name`, or `nil` if nothing matches.
    func resolve<Service>(_ serviceType: Service.Type, name: String?) -> Service?

    /// Resolves an unnamed service whose factory takes 1 runtime argument.
    func resolve<Service, Arg1>(_ serviceType: Service.Type, argument: Arg1) -> Service?
    /// Resolves a named service whose factory takes 1 runtime argument.
    func resolve<Service, Arg1>(_ serviceType: Service.Type, name: String?, argument: Arg1) -> Service?

    /// Resolves an unnamed service whose factory takes 2 runtime arguments.
    func resolve<Service, Arg1, Arg2>(_ serviceType: Service.Type, arguments arg1: Arg1, _ arg2: Arg2) -> Service?
    /// Resolves a named service whose factory takes 2 runtime arguments.
    func resolve<Service, Arg1, Arg2>(_ serviceType: Service.Type, name: String?, arguments arg1: Arg1, _ arg2: Arg2) -> Service?

    /// Resolves an unnamed service whose factory takes 3 runtime arguments.
    func resolve<Service, Arg1, Arg2, Arg3>(_ serviceType: Service.Type, arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3) -> Service?
    /// Resolves a named service whose factory takes 3 runtime arguments.
    func resolve<Service, Arg1, Arg2, Arg3>(_ serviceType: Service.Type, name: String?, arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3) -> Service?

    /// Resolves an unnamed service whose factory takes 4 runtime arguments.
    func resolve<Service, Arg1, Arg2, Arg3, Arg4>(_ serviceType: Service.Type, arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4) -> Service?
    /// Resolves a named service whose factory takes 4 runtime arguments.
    func resolve<Service, Arg1, Arg2, Arg3, Arg4>(_ serviceType: Service.Type, name: String?, arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4) -> Service?

    /// Resolves an unnamed service whose factory takes 5 runtime arguments.
    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5>(_ serviceType: Service.Type, arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5) -> Service?
    /// Resolves a named service whose factory takes 5 runtime arguments.
    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5>(_ serviceType: Service.Type, name: String?, arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5) -> Service?

    /// Resolves an unnamed service whose factory takes 6 runtime arguments.
    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6>(_ serviceType: Service.Type, arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5, _ arg6: Arg6) -> Service?
    /// Resolves a named service whose factory takes 6 runtime arguments.
    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6>(_ serviceType: Service.Type, name: String?, arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5, _ arg6: Arg6) -> Service?

    /// Resolves an unnamed service whose factory takes 7 runtime arguments.
    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7>(_ serviceType: Service.Type, arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5, _ arg6: Arg6, _ arg7: Arg7) -> Service?
    /// Resolves a named service whose factory takes 7 runtime arguments.
    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7>(_ serviceType: Service.Type, name: String?, arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5, _ arg6: Arg6, _ arg7: Arg7) -> Service?

    /// Resolves an unnamed service whose factory takes 8 runtime arguments.
    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8>(_ serviceType: Service.Type, arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5, _ arg6: Arg6, _ arg7: Arg7, _ arg8: Arg8) -> Service?
    /// Resolves a named service whose factory takes 8 runtime arguments.
    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8>(_ serviceType: Service.Type, name: String?, arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5, _ arg6: Arg6, _ arg7: Arg7, _ arg8: Arg8) -> Service?

    /// Resolves an unnamed service whose factory takes 9 runtime arguments.
    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8, Arg9>(_ serviceType: Service.Type, arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5, _ arg6: Arg6, _ arg7: Arg7, _ arg8: Arg8, _ arg9: Arg9) -> Service?
    /// Resolves a named service whose factory takes 9 runtime arguments.
    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8, Arg9>(_ serviceType: Service.Type, name: String?, arguments arg1: Arg1, _ arg2: Arg2, _ arg3: Arg3, _ arg4: Arg4, _ arg5: Arg5, _ arg6: Arg6, _ arg7: Arg7, _ arg8: Arg8, _ arg9: Arg9) -> Service?
}

/// Default implementations, so a conformer only has to override what it uses.
///
/// The two halves behave differently, and the difference matters:
///
/// - The **unnamed** variants forward to their `name: nil` counterpart. Override
///   the named variant and the unnamed one works for free.
/// - The **named** variants return `nil`. They are placeholders, not lookups.
///
/// So a hand-written `Resolver` stub silently returns `nil` for every arity it
/// did not override. If a test fails because a dependency came back `nil`, this
/// is the first thing to check. ``Container`` overrides every variant and is
/// unaffected.
public extension Resolver {
    /// Forwards to `resolve(_:name:)` with no name.
    func resolve<Service>(_ serviceType: Service.Type) -> Service? {
        resolve(serviceType, name: nil)
    }

    /// Forwards to the 1-argument named variant with no name.
    func resolve<Service, Arg1>(_ serviceType: Service.Type, argument: Arg1) -> Service? {
        resolve(serviceType, name: nil, argument: argument)
    }

    /// Placeholder returning `nil`; override to resolve 1-argument registrations.
    func resolve<Service, Arg1>(_: Service.Type, name _: String?, argument _: Arg1) -> Service? { nil }

    /// Forwards to the 2-argument named variant with no name.
    func resolve<Service, A1, A2>(_ s: Service.Type, arguments a1: A1, _ a2: A2) -> Service? {
        resolve(s, name: nil, arguments: a1, a2)
    }

    /// Placeholder returning `nil`; override to resolve 2-argument registrations.
    func resolve<Service, A1, A2>(_: Service.Type, name _: String?, arguments _: A1, _: A2) -> Service? { nil }

    /// Forwards to the 3-argument named variant with no name.
    func resolve<Service, A1, A2, A3>(_ s: Service.Type, arguments a1: A1, _ a2: A2, _ a3: A3) -> Service? {
        resolve(s, name: nil, arguments: a1, a2, a3)
    }

    /// Placeholder returning `nil`; override to resolve 3-argument registrations.
    func resolve<Service, A1, A2, A3>(_: Service.Type, name _: String?, arguments _: A1, _: A2, _: A3) -> Service? { nil }

    /// Forwards to the 4-argument named variant with no name.
    func resolve<Service, A1, A2, A3, A4>(_ s: Service.Type, arguments a1: A1, _ a2: A2, _ a3: A3, _ a4: A4) -> Service? {
        resolve(s, name: nil, arguments: a1, a2, a3, a4)
    }

    /// Placeholder returning `nil`; override to resolve 4-argument registrations.
    func resolve<Service, A1, A2, A3, A4>(_: Service.Type, name _: String?, arguments _: A1, _: A2, _: A3, _: A4) -> Service? { nil }

    /// Forwards to the 5-argument named variant with no name.
    func resolve<Service, A1, A2, A3, A4, A5>(_ s: Service.Type, arguments a1: A1, _ a2: A2, _ a3: A3, _ a4: A4, _ a5: A5) -> Service? {
        resolve(s, name: nil, arguments: a1, a2, a3, a4, a5)
    }

    /// Placeholder returning `nil`; override to resolve 5-argument registrations.
    func resolve<Service, A1, A2, A3, A4, A5>(_: Service.Type, name _: String?, arguments _: A1, _: A2, _: A3, _: A4, _: A5) -> Service? { nil }

    /// Forwards to the 6-argument named variant with no name.
    func resolve<Service, A1, A2, A3, A4, A5, A6>(_ s: Service.Type, arguments a1: A1, _ a2: A2, _ a3: A3, _ a4: A4, _ a5: A5, _ a6: A6) -> Service? {
        resolve(s, name: nil, arguments: a1, a2, a3, a4, a5, a6)
    }

    /// Placeholder returning `nil`; override to resolve 6-argument registrations.
    func resolve<Service, A1, A2, A3, A4, A5, A6>(_: Service.Type, name _: String?, arguments _: A1, _: A2, _: A3, _: A4, _: A5, _: A6) -> Service? { nil }

    /// Forwards to the 7-argument named variant with no name.
    func resolve<Service, A1, A2, A3, A4, A5, A6, A7>(_ s: Service.Type, arguments a1: A1, _ a2: A2, _ a3: A3, _ a4: A4, _ a5: A5, _ a6: A6, _ a7: A7) -> Service? {
        resolve(s, name: nil, arguments: a1, a2, a3, a4, a5, a6, a7)
    }

    /// Placeholder returning `nil`; override to resolve 7-argument registrations.
    func resolve<Service, A1, A2, A3, A4, A5, A6, A7>(_: Service.Type, name _: String?, arguments _: A1, _: A2, _: A3, _: A4, _: A5, _: A6, _: A7) -> Service? { nil }

    /// Forwards to the 8-argument named variant with no name.
    func resolve<Service, A1, A2, A3, A4, A5, A6, A7, A8>(_ s: Service.Type, arguments a1: A1, _ a2: A2, _ a3: A3, _ a4: A4, _ a5: A5, _ a6: A6, _ a7: A7, _ a8: A8) -> Service? {
        resolve(s, name: nil, arguments: a1, a2, a3, a4, a5, a6, a7, a8)
    }

    /// Placeholder returning `nil`; override to resolve 8-argument registrations.
    func resolve<Service, A1, A2, A3, A4, A5, A6, A7, A8>(_: Service.Type, name _: String?, arguments _: A1, _: A2, _: A3, _: A4, _: A5, _: A6, _: A7, _: A8) -> Service? { nil }

    /// Forwards to the 9-argument named variant with no name.
    func resolve<Service, A1, A2, A3, A4, A5, A6, A7, A8, A9>(_ s: Service.Type, arguments a1: A1, _ a2: A2, _ a3: A3, _ a4: A4, _ a5: A5, _ a6: A6, _ a7: A7, _ a8: A8, _ a9: A9) -> Service? {
        resolve(s, name: nil, arguments: a1, a2, a3, a4, a5, a6, a7, a8, a9)
    }

    /// Placeholder returning `nil`; override to resolve 9-argument registrations.
    func resolve<Service, A1, A2, A3, A4, A5, A6, A7, A8, A9>(_: Service.Type, name _: String?, arguments _: A1, _: A2, _: A3, _: A4, _: A5, _: A6, _: A7, _: A8, _: A9) -> Service? { nil }
}
