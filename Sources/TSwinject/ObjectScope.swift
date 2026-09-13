//
//  Portions derived from Swinject (https://github.com/Swinject/Swinject)
//  Copyright © 2019 Swinject Contributors. All rights reserved.
//  Licensed under the MIT License — see NOTICE.
//

/// A configuration how an instance provided by a ``Container`` is shared in the system.
/// The configuration is ignored if it is applied to a value type.
public protocol ObjectScopeProtocol: AnyObject {
    /// Used to create `InstanceStorage` to persist an instance for single service.
    func makeStorage() -> InstanceStorage
}

/// Basic implementation of ``ObjectScopeProtocol``.
///
/// Scopes are compared by reference, not by `description`, so two scopes sharing
/// a description are still distinct. The description is a label — except when
/// bridging to Swinject, where `TSwinjectSwinjectInterop` matches the built-in
/// descriptions (`"transient"`, `"graph"`, `"container"`) to pick the
/// corresponding Swinject scope. Custom scopes are mapped by their backing
/// storage instead, so their description is free-form.
public final class ObjectScope: ObjectScopeProtocol, CustomStringConvertible, @unchecked Sendable {
    /// A human-readable label, also used as the bridge key for built-in scopes.
    public let description: String
    private let storageFactory: () -> InstanceStorage
    private let parent: ObjectScopeProtocol?

    /// Creates a scope from the storage strategy that defines its sharing semantics.
    ///
    /// - Parameters:
    ///   - storageFactory: Produces a fresh ``InstanceStorage`` per registration.
    ///     The storage type is what actually decides the lifetime — see
    ///     ``TransientStorage``, ``GraphStorage`` and ``PermanentStorage``.
    ///   - description: A label for the scope. Avoid reusing a built-in scope's
    ///     description if you also use the Swinject bridge.
    ///   - parent: If given, its storage is composed with this scope's, so an
    ///     instance satisfies both. Used to layer a narrower scope over `.graph`.
    public init(
        storageFactory: @escaping () -> InstanceStorage,
        description: String = "",
        parent: ObjectScopeProtocol? = nil
    ) {
        self.storageFactory = storageFactory
        self.description = description
        self.parent = parent
    }

    /// Builds the storage backing one registration in this scope, composing the
    /// parent scope's storage when there is a parent.
    public func makeStorage() -> InstanceStorage {
        if let parent = parent {
            return CompositeStorage([storageFactory(), parent.makeStorage()])
        } else {
            return storageFactory()
        }
    }

    /// A new instance is always created by the ``Container`` when a type is resolved.
    public static let transient = ObjectScope(storageFactory: TransientStorage.init, description: "transient")

    /// Instances are shared only while a single object graph is being created,
    /// so two dependencies resolved during one top-level `resolve` receive the
    /// same instance, and a later `resolve` starts fresh. This is the default
    /// scope when a registration does not pass one.
    public static let graph = ObjectScope(storageFactory: GraphStorage.init, description: "graph")

    /// An instance provided by the ``Container`` is shared within the ``Container`` and its child `Containers`.
    public static let container = ObjectScope(storageFactory: PermanentStorage.init, description: "container")
}
