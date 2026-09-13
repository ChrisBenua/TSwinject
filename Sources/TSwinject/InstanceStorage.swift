//
//  Portions derived from Swinject (https://github.com/Swinject/Swinject)
//  Copyright © 2019 Swinject Contributors. All rights reserved.
//  Licensed under the MIT License — see NOTICE.
//

/// Storage provided by ``ObjectScope``. It is used by ``Container`` to persist resolved instances.
///
/// A storage type *is* the lifetime policy: the container asks the scope for a
/// storage per registration, then reads and writes instances through it. Whether
/// an instance is kept forever, for one object graph, or not at all is decided
/// entirely here. Implement this to add a custom scope.
public protocol InstanceStorage: AnyObject {
    /// The stored instance, ignoring graph identity. `nil` when nothing is held.
    var instance: Any? { get set }
    /// Called once the top-level `resolve` that started the current graph has
    /// finished, so graph-scoped storages can release what they cached.
    func graphResolutionCompleted()
    /// The instance cached for `graph`, or `nil` if this storage has none for it.
    func instance(inGraph graph: GraphIdentifier) -> Any?
    /// Caches `instance` as belonging to `graph`.
    func setInstance(_ instance: Any?, inGraph graph: GraphIdentifier)
}

/// Defaults for storages that ignore graph identity — implement `instance` alone
/// and the graph-aware members degrade to it.
public extension InstanceStorage {
    /// No-op: a storage that ignores graph identity has nothing to release.
    func graphResolutionCompleted() {}
    /// Ignores `graph` and returns ``instance``.
    func instance(inGraph _: GraphIdentifier) -> Any? { return instance }
    /// Ignores `graph` and assigns ``instance``.
    func setInstance(_ instance: Any?, inGraph _: GraphIdentifier) { self.instance = instance }
}

/// Persists storage during the resolution of the object graph.
///
/// Backs ``ObjectScope/graph``: instances are keyed by ``GraphIdentifier`` and
/// dropped when that graph completes, so dependencies shared within one
/// top-level `resolve` are the same object, and the next `resolve` is fresh.
public final class GraphStorage: InstanceStorage {
    private var instances = [GraphIdentifier: Any]()
    /// The most recently stored instance, regardless of graph.
    public var instance: Any?

    /// Creates an empty graph storage.
    public init() {}

    /// Discards every cached instance, ending their shared lifetime.
    public func graphResolutionCompleted() {
        instance = nil
        instances.removeAll(keepingCapacity: true)
    }

    /// The instance cached for `graph`, or `nil` if this graph has not resolved it yet.
    public func instance(inGraph graph: GraphIdentifier) -> Any? {
        return instances[graph]
    }

    /// Caches `instance` for the duration of `graph`.
    public func setInstance(_ instance: Any?, inGraph graph: GraphIdentifier) {
        self.instance = instance
        instances[graph] = instance
    }
}

/// Persists stored instance until it is explicitly discarded.
///
/// Backs ``ObjectScope/container``. The instance lives as long as the container
/// does, or until `removeAll` / `resetObjectScope` clears it.
public final class PermanentStorage: InstanceStorage {
    /// The single retained instance.
    public var instance: Any?
    /// Creates an empty permanent storage.
    public init() {}
}

/// Does not persist stored instance.
///
/// Backs ``ObjectScope/transient``. Reads always yield `nil` and writes are
/// discarded, so every resolve runs the factory again.
public final class TransientStorage: InstanceStorage {
    /// Always `nil`; assignments are discarded.
    public var instance: Any? {
        get { return nil }
        set {} // swiftlint:disable:this unused_setter_value
    }

    /// Creates a transient storage.
    public init() {}
}

/// Combines the behavior of multiple instance storages.
/// Instance is persisted as long as at least one of the underlying storages is persisting it.
///
/// Produced by ``ObjectScope`` when a scope has a parent, so the instance
/// satisfies both scopes' lifetimes.
public final class CompositeStorage: InstanceStorage {
    private let components: [InstanceStorage]

    /// The first non-`nil` instance among the components; assignment writes to all.
    public var instance: Any? {
        get { components.first(where: { $0.instance != nil })?.instance }
        set { components.forEach { $0.instance = newValue } }
    }

    /// Creates a storage that layers `components`, earliest first when reading.
    public init(_ components: [InstanceStorage]) {
        self.components = components
    }

    /// Forwards graph completion to every component.
    public func graphResolutionCompleted() {
        components.forEach { $0.graphResolutionCompleted() }
    }

    /// Writes `instance` into every component for `graph`.
    public func setInstance(_ instance: Any?, inGraph graph: GraphIdentifier) {
        components.forEach { $0.setInstance(instance, inGraph: graph) }
    }

    /// The first component holding an instance for `graph`, or `nil`.
    public func instance(inGraph graph: GraphIdentifier) -> Any? {
        components.first(where: { $0.instance(inGraph: graph) != nil })?.instance(inGraph: graph)
    }
}
