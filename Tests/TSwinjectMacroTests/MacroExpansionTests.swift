import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(TSwinjectMacroPlugin)
    import TSwinjectMacro
    import TSwinjectMacroPlugin

    nonisolated(unsafe) let testMacros: [String: Macro.Type] = [
        "implements": ImplementsMacro.self
    ]
#endif

/// Asserts on the exact source `#implements` expands to. The behavioural
/// counterpart lives in ``MacroRuntimeTests``.
final class MacroExpansionTests: XCTestCase {

    func testMultipleProtocolsExpandToInvokedClosure() throws {
        #if canImport(TSwinjectMacroPlugin)
            assertMacroExpansion(
                """
                #implements(
                    container,
                    AuthService.self,
                    AuthReading.self,
                    TokenProviding.self,
                    Session.Clearing.self
                )
                """,
                expandedSource:
                """
                {
                    container.register(AuthReading.self, scope: .transient) { resolver in
                        resolver.resolve(AuthService.self)!
                    }
                    container.register(TokenProviding.self, scope: .transient) { resolver in
                        resolver.resolve(AuthService.self)!
                    }
                    container.register(Session.Clearing.self, scope: .transient) { resolver in
                        resolver.resolve(AuthService.self)!
                    }
                }()
                """,
                macros: testMacros
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testSingleProtocolHasNoClosureWrapper() throws {
        #if canImport(TSwinjectMacroPlugin)
            assertMacroExpansion(
                """
                #implements(container, AuthService.self, AuthReading.self)
                """,
                expandedSource:
                """
                container.register(AuthReading.self, scope: .transient) { resolver in
                    resolver.resolve(AuthService.self)!
                }
                """,
                macros: testMacros
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testMissingProtocolsEmitsDiagnostic() throws {
        #if canImport(TSwinjectMacroPlugin)
            assertMacroExpansion(
                """
                #implements(container, AuthService.self)
                """,
                expandedSource:
                """
                #implements(container, AuthService.self)
                """,
                diagnostics: [
                    DiagnosticSpec(
                        message: "#implements requires a container, a base type and at least one protocol",
                        line: 1,
                        column: 1
                    )
                ],
                macros: testMacros
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
}
