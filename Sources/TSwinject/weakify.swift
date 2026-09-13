/// Helper for `Container.registerWeak`. Captures a freshly built reference and returns it
/// alongside a closure that reads it weakly.
///
///     container.registerWeak(MyService.self) { _ in weakInstance(MyService()) }
public func weakInstance<T: AnyObject>(_ factory: @autoclosure @escaping () -> T) -> (T, () -> T?) {
    let value = factory()
    return (value, { [weak value] in value })
}
