import Swinject

/// The container under test.
///
/// This typealias is the whole difference between the two runner targets: the
/// generated `Registration.swift` / `Resolution.swift` are otherwise the same
/// code, because `register(_:factory:)` and `resolve(_:)` have compatible
/// signatures in both libraries.
public typealias Container = Swinject.Container

/// Label printed in the benchmark output.
let containerName = "Swinject"
