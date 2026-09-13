import Swinject
import TSwinject
import XCTest

private protocol Service0: AnyObject { func ping() -> Int }
private protocol Service1: AnyObject { func ping() -> Int }
private protocol Service2: AnyObject { func ping() -> Int }
private protocol Service3: AnyObject { func ping() -> Int }
private protocol Service4: AnyObject { func ping() -> Int }

private final class Impl0: Service0 { func ping() -> Int { 0 } }
private final class Impl1: Service1 { func ping() -> Int { 1 } }
private final class Impl2: Service2 { func ping() -> Int { 2 } }
private final class Impl3: Service3 { func ping() -> Int { 3 } }
private final class Impl4: Service4 { func ping() -> Int { 4 } }

// Must be run in release configuration or the numbers are noise:
//
//     swift test -c release --filter ContainerBenchmarkTests
//
// `test_rawComparison_printOnly` prints the ns/resolve and speedup quoted in the
// README. It brackets the measured loop with `Date()` inside the test body, so
// XCTest's own overhead falls outside the timed region.
final class ContainerBenchmarkTests: XCTestCase {

    func test_tswinject_resolveThroughput() {
        let iterations = 200_000
        measure(metrics: [XCTClockMetric()]) {
            let c = TSwinject.Container()
            c.register(Service0.self, scope: .container) { _ in Impl0() }
            c.register(Service1.self, scope: .container) { _ in Impl1() }
            c.register(Service2.self, scope: .container) { _ in Impl2() }
            c.register(Service3.self, scope: .container) { _ in Impl3() }
            c.register(Service4.self, scope: .container) { _ in Impl4() }
            var sink = 0
            for _ in 0 ..< iterations {
                sink += c.resolve(Service0.self)!.ping()
                sink += c.resolve(Service1.self)!.ping()
                sink += c.resolve(Service2.self)!.ping()
                sink += c.resolve(Service3.self)!.ping()
                sink += c.resolve(Service4.self)!.ping()
            }
            _ = sink
        }
    }

    func test_swinject_resolveThroughput() {
        let iterations = 200_000
        measure(metrics: [XCTClockMetric()]) {
            let c = Swinject.Container()
            c.register(Service0.self) { _ in Impl0() }.inObjectScope(.container)
            c.register(Service1.self) { _ in Impl1() }.inObjectScope(.container)
            c.register(Service2.self) { _ in Impl2() }.inObjectScope(.container)
            c.register(Service3.self) { _ in Impl3() }.inObjectScope(.container)
            c.register(Service4.self) { _ in Impl4() }.inObjectScope(.container)
            var sink = 0
            for _ in 0 ..< iterations {
                sink += c.resolve(Service0.self)!.ping()
                sink += c.resolve(Service1.self)!.ping()
                sink += c.resolve(Service2.self)!.ping()
                sink += c.resolve(Service3.self)!.ping()
                sink += c.resolve(Service4.self)!.ping()
            }
            _ = sink
        }
    }

    // Prints raw ns/resolve numbers to the test log — mirrors the SPM executable output.
    func test_rawComparison_printOnly() {
        _ = runTSwinject(); _ = runSwinject()
        let t = runTSwinject()
        let s = runSwinject()
        let total = Double(200_000) * 5
        print("Swinject:  \(String(format: "%.3f", s))s  (\(Int(total / s)) r/s, \(String(format: "%.0f", s * 1e9 / total)) ns/resolve)")
        print("TSwinject: \(String(format: "%.3f", t))s  (\(Int(total / t)) r/s, \(String(format: "%.0f", t * 1e9 / total)) ns/resolve)")
        print("Speedup:   \(String(format: "%.2fx", s / t))")
    }

    private func runTSwinject() -> Double {
        let c = TSwinject.Container()
        c.register(Service0.self, scope: .container) { _ in Impl0() }
        c.register(Service1.self, scope: .container) { _ in Impl1() }
        c.register(Service2.self, scope: .container) { _ in Impl2() }
        c.register(Service3.self, scope: .container) { _ in Impl3() }
        c.register(Service4.self, scope: .container) { _ in Impl4() }
        var sink = 0
        let start = Date()
        for _ in 0 ..< 200_000 {
            sink += c.resolve(Service0.self)!.ping()
            sink += c.resolve(Service1.self)!.ping()
            sink += c.resolve(Service2.self)!.ping()
            sink += c.resolve(Service3.self)!.ping()
            sink += c.resolve(Service4.self)!.ping()
        }
        let elapsed = Date().timeIntervalSince(start)
        if sink == Int.max { print(sink) }
        return elapsed
    }

    private func runSwinject() -> Double {
        let c = Swinject.Container()
        c.register(Service0.self) { _ in Impl0() }.inObjectScope(.container)
        c.register(Service1.self) { _ in Impl1() }.inObjectScope(.container)
        c.register(Service2.self) { _ in Impl2() }.inObjectScope(.container)
        c.register(Service3.self) { _ in Impl3() }.inObjectScope(.container)
        c.register(Service4.self) { _ in Impl4() }.inObjectScope(.container)
        var sink = 0
        let start = Date()
        for _ in 0 ..< 200_000 {
            sink += c.resolve(Service0.self)!.ping()
            sink += c.resolve(Service1.self)!.ping()
            sink += c.resolve(Service2.self)!.ping()
            sink += c.resolve(Service3.self)!.ping()
            sink += c.resolve(Service4.self)!.ping()
        }
        let elapsed = Date().timeIntervalSince(start)
        if sink == Int.max { print(sink) }
        return elapsed
    }
}
