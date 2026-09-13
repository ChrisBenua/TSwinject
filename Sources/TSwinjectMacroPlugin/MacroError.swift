struct MacroError: Error, CustomStringConvertible {

    // MARK: - Properties

    /// The diagnostic text surfaced at the macro's call site.
    let message: String

    // MARK: - CustomStringConvertible

    var description: String {
        message
    }

    // MARK: - Initializers

    init(message: String) {
        self.message = message
    }
}
