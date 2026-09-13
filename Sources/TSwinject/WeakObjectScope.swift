/// Public protocol for scopes used with `Container.registerWeak`. The wrapper itself
/// (a `DiEntryWeak<T>`) is stored in the produced storage; the wrapped *value* is held
/// weakly by the closure inside `DiEntryWeak`.
///
/// This is deliberately *not* ``ObjectScopeProtocol``, because the two mean
/// different things and are not interchangeable: an object scope decides how
/// long the resolved value lives, whereas a weak scope always keeps the wrapper
/// alive and lets the value die once its last strong reference goes. Keeping the
/// types separate means `register` and `registerWeak` cannot be handed each
/// other's scopes by accident.
///
/// The practical effect: callers share one instance for as long as somebody
/// still holds it, and the next resolve after it deallocates builds a new one.
public protocol WeakObjectScopeProtocol: AnyObject {
    /// Produces the storage holding the weak wrapper for one registration.
    func makeStorage() -> InstanceStorage
}

/// Default open class implementation of `WeakObjectScopeProtocol`.
/// Stores the `DiEntryWeak` wrapper permanently in the container; the value inside it
/// remains weakly referenced.
///
/// Subclass and override ``makeStorage()`` only to change where the *wrapper*
/// lives; the value's weak semantics come from the wrapper, not the storage.
open class WeakObjectScope: WeakObjectScopeProtocol, @unchecked Sendable {
    /// Creates a weak scope.
    public init() {}
    /// Returns permanent storage for the wrapper — the wrapper is retained, the
    /// value it points at is not.
    open func makeStorage() -> InstanceStorage { PermanentStorage() }
}

/// Out-of-the-box concrete weak scope.
public final class WeakScope: WeakObjectScope, @unchecked Sendable {
    /// The scope to pass to `registerWeak` unless you need a custom one.
    public static let shared = WeakScope()
}
