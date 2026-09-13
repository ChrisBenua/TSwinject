import TSwinject
import TSwinjectMacro
import XCTest

// MARK: - Fixtures

private protocol AuthReading: AnyObject {}
private protocol TokenProviding: AnyObject {}
private protocol SessionClearing: AnyObject {}

private final class AuthService: AuthReading, TokenProviding, SessionClearing {}

// MARK: - MacroRuntimeTests

/// Exercises `#implements` against a real ``TSwinject/Container`` rather than a
/// mock, so these tests double as the executable specification of what the macro
/// expands into.
final class MacroRuntimeTests: XCTestCase {

    func testForwardersResolveToTheSameContainerScopedInstance() {
        let container = Container()
        container.register(AuthService.self, scope: .container) { _ in AuthService() }
        #implements(
            container,
            AuthService.self,
            AuthReading.self,
            TokenProviding.self,
            SessionClearing.self
        )

        let base = container.resolve(AuthService.self)
        XCTAssertNotNil(base)
        // Every protocol forwards to the one container-scoped base instance.
        XCTAssertTrue(container.resolve(AuthReading.self) === base)
        XCTAssertTrue(container.resolve(TokenProviding.self) === base)
        XCTAssertTrue(container.resolve(SessionClearing.self) === base)
    }

    func testSingleProtocolExpandsToAWorkingRegistration() {
        let container = Container()
        container.register(AuthService.self, scope: .container) { _ in AuthService() }
        #implements(container, AuthService.self, AuthReading.self)

        XCTAssertTrue(container.resolve(AuthReading.self) === container.resolve(AuthService.self))
    }

    /// The forwarders are `.transient`, so the base registration's scope — not the
    /// forwarder's — is what decides whether callers share an instance.
    func testTransientBaseYieldsADistinctInstancePerResolve() {
        let container = Container()
        container.register(AuthService.self, scope: .transient) { _ in AuthService() }
        #implements(container, AuthService.self, AuthReading.self)

        XCTAssertFalse(container.resolve(AuthReading.self) === container.resolve(AuthReading.self))
    }

    func testForwardingDoesNotRegisterTheBaseType() {
        let container = Container()
        #implements(container, AuthService.self, AuthReading.self)

        // The macro only emits forwarders; the base registration is written by hand.
        XCTAssertTrue(container.hasAnyRegistration(of: AuthReading.self))
        XCTAssertFalse(container.hasAnyRegistration(of: AuthService.self))
    }
}
