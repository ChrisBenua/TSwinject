import TSwinject

// Touch enough of the core API that the target cannot be optimised into nothing.
protocol Greeting: AnyObject {
    var text: String { get }
}

final class Hello: Greeting {
    let text = "hello"
}

enum CoreOnlyConsumer {
    static func resolveOnce() -> String? {
        let container = Container()
        container.register(Greeting.self, scope: .container) { _ in Hello() }
        return container.resolve(Greeting.self)?.text
    }
}
