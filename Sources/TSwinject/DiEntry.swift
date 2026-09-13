@usableFromInline
final class DiEntryConcrete<T> {
    @usableFromInline var value: T

    @usableFromInline
    init(value: T) {
        self.value = value
    }
}

@usableFromInline
final class DiEntryWeak<T> {
    /// Receives the *current* resolver at (re)build time. Deliberately NOT a
    /// `() -> …` closure with a captured resolver: this wrapper is held in
    /// `PermanentStorage` inside the container's own `services`, so capturing
    /// the resolving container would close a permanent retain cycle
    /// (container → services → entry → storage → wrapper → closure → container)
    /// and the container could never deallocate. See DESIGN_REVIEW_V2.md N3.
    @usableFromInline var factory: (Resolver) -> (T, () -> T?)
    private var weakStore: (() -> T?)?

    @usableFromInline
    func value(_ resolver: Resolver) -> T? {
        if let value = weakStore?() {
            return value
        }
        let (newValue, newWeakStore) = factory(resolver)
        weakStore = newWeakStore
        return newValue
    }

    @usableFromInline
    init(factory: @escaping (Resolver) -> (T, () -> T?)) {
        self.factory = factory
    }
}
