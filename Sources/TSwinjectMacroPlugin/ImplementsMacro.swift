import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct ImplementsMacro: ExpressionMacro {

    // MARK: - ExpressionMacro

    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in _: some MacroExpansionContext
    ) throws -> ExprSyntax {
        let arguments = Array(node.arguments)

        guard arguments.count >= 3 else {
            throw MacroError(
                message: "#implements requires a container, a base type and at least one protocol"
            )
        }

        let container = arguments[0].expression.trimmedDescription
        let baseType = arguments[1].expression.trimmedDescription
        let protocols = arguments[2...].map(\.expression.trimmedDescription)

        let registrations = protocols.map { proto in
            """
            \(container).register(\(proto), scope: .transient) { resolver in
                resolver.resolve(\(baseType))!
            }
            """
        }

        // A single registration is already one expression, so no wrapping closure.
        if registrations.count == 1 {
            return "\(raw: registrations[0])"
        }

        // Several registrations are wrapped in an immediately-invoked closure so the
        // expansion stays a single expression, as a freestanding expression macro must.
        let body = registrations
            .map { registration in
                registration
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map { "    \($0)" }
                    .joined(separator: "\n")
            }
            .joined(separator: "\n")

        return "{\n\(raw: body)\n}()"
    }
}
