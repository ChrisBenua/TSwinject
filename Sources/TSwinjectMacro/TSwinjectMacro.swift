/// Generates TSwinject forwarding registrations for one concrete type that is
/// exposed under several protocols.
///
/// The base registration of the concrete type — the one carrying the real
/// factory closure — is written by hand. This macro expands only the
/// `.transient` forwarding registrations, each of which resolves the base type:
///
/// ```swift
/// container.register(CredentialsService.self, scope: .container) { _ in
///     CredentialsService()
/// }
/// #implements(
///     container,
///     CredentialsService.self,
///     CredentialsReading.self,
///     TokenProviding.self
/// )
/// ```
///
/// expands to:
///
/// ```swift
/// {
///     container.register(CredentialsReading.self, scope: .transient) { resolver in
///         resolver.resolve(CredentialsService.self)!
///     }
///     container.register(TokenProviding.self, scope: .transient) { resolver in
///         resolver.resolve(CredentialsService.self)!
///     }
/// }()
/// ```
///
/// For a single protocol the wrapping closure is omitted and the macro expands
/// to one `container.register(...)` expression.
///
/// - Important: The base type must conform to every protocol listed, and must
///   itself be registered — the generated forwarders force-unwrap the resolve.
///   Every forwarder is `.transient`, so the base registration's own scope is
///   what governs the instance's lifetime.
///
/// - Parameters:
///   - container: The container the registrations are performed on.
///   - baseType: The concrete type resolved for each protocol, e.g. `Service.self`.
///   - protocols: The additional protocols the base type is registered under.
@freestanding(expression)
public macro implements(
    _ container: Any,
    _ baseType: Any.Type,
    _ protocols: Any.Type...
) = #externalMacro(module: "TSwinjectMacroPlugin", type: "ImplementsMacro")
