import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct TSwinjectMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ImplementsMacro.self
    ]
}
