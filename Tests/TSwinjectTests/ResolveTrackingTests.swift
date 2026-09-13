@testable import TSwinject
import XCTest

// MARK: - Fixtures

private protocol Animal: AnyObject {}
private final class Cat: Animal {}
private final class Dog: Animal {}

private final class MockTracker: ResolveTracker {
    private let lock = NSLock()
    private var _events: [ResolveEvent] = []

    var events: [ResolveEvent] {
        lock.lock(); defer { lock.unlock() }
        return _events
    }

    var eventCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _events.count
    }

    func didResolve(_ event: ResolveEvent) {
        lock.lock(); defer { lock.unlock() }
        _events.append(event)
    }
}

// MARK: - Tests

final class ResolveTrackingTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        // Process-wide state must be reset so tests don't bleed into each other.
        ResolveTracking.factory = nil
    }

    // 1. No factory → no work. Smoke test; bench covers perf.
    func testNoFactoryNoWork() {
        XCTAssertNil(ResolveTracking.factory)
        let container = Container()
        container.register(Animal.self) { _ in Cat() }
        for _ in 0 ..< 1000 {
            _ = container.resolve(Animal.self)
        }
        // No crash, no tracker involvement.
    }

    // 2. Factory is invoked exactly once per Container, not once per resolve.
    func testFactoryCalledOncePerContainer() {
        var callCount = 0
        ResolveTracking.factory = { callCount += 1; return nil }

        let c1 = Container()
        let c2 = Container()
        _ = c1 // suppress unused-variable warnings
        _ = c2

        XCTAssertEqual(callCount, 2)

        // Resolving many times does not re-invoke the factory.
        c1.register(Animal.self) { _ in Cat() }
        for _ in 0 ..< 10 {
            _ = c1.resolve(Animal.self)
        }
        XCTAssertEqual(callCount, 2)
    }

    // 3. Factory returning nil → tracker never fires.
    func testFactoryReturningNilSkipsTracking() {
        let tracker = MockTracker()
        var factoryCalled = false
        ResolveTracking.factory = { factoryCalled = true; return nil } // returns nil

        let container = Container()
        XCTAssertTrue(factoryCalled)

        // Give the container the per-container slot nil too (default).
        container.register(Animal.self) { _ in Cat() }
        _ = container.resolve(Animal.self)

        XCTAssertEqual(
            tracker.eventCount,
            0,
            "factory returned nil so tracker should never be called"
        )
    }

    // 4. Fan-out: both factory tracker and per-container tracker receive the event.
    func testFanOutToBothTrackers() {
        let trackerA = MockTracker()
        let trackerB = MockTracker()

        ResolveTracking.factory = { trackerA }
        let container = Container()
        container.resolveTracker = trackerB

        container.register(Animal.self) { _ in Cat() }
        _ = container.resolve(Animal.self)

        XCTAssertEqual(trackerA.eventCount, 1, "factory tracker should receive event")
        XCTAssertEqual(trackerB.eventCount, 1, "per-container tracker should receive event")

        // Both events carry the same timing and service type.
        let a = trackerA.events[0]
        let b = trackerB.events[0]
        XCTAssertTrue(a.serviceType == b.serviceType)
        XCTAssertEqual(a.durationNanoseconds, b.durationNanoseconds)
    }

    // 5. Top-level event count: nested factory resolves do NOT emit extra events.
    func testOnlyTopLevelResolvesEmitEvents() {
        let tracker = MockTracker()
        ResolveTracking.factory = { tracker }

        let container = Container()
        // Owner's factory resolves a nested Animal.
        container.register(Animal.self) { _ in Cat() }
        container.register(String.self) { r in
            _ = r.resolve(Animal.self) // nested resolve
            return "owner"
        }

        _ = container.resolve(String.self) // one top-level call

        XCTAssertEqual(
            tracker.eventCount,
            1,
            "only the outer resolve should emit an event"
        )
    }

    // 6. Duration is non-zero when the factory introduces a real delay.
    func testDurationIsNonZero() {
        let tracker = MockTracker()
        ResolveTracking.factory = { tracker }

        let container = Container()
        container.register(Animal.self) { _ in
            // Tiny but measurable sleep.
            Thread.sleep(forTimeInterval: 0.001)
            return Cat()
        }
        _ = container.resolve(Animal.self)

        XCTAssertEqual(tracker.eventCount, 1)
        let ns = tracker.events[0].durationNanoseconds
        XCTAssertGreaterThanOrEqual(
            ns,
            500_000, // ≥ 0.5 ms
            "duration should reflect the sleep; got \(ns) ns"
        )
    }

    // 7. Service type and name are carried through correctly.
    func testServiceTypeAndNameCarriedThrough() {
        let tracker = MockTracker()
        ResolveTracking.factory = { tracker }

        let container = Container()
        container.register(Animal.self, name: "foo") { _ in Cat() }
        _ = container.resolve(Animal.self, name: "foo")

        XCTAssertEqual(tracker.eventCount, 1)
        let event = tracker.events[0]
        XCTAssertTrue(
            event.serviceType == Animal.self,
            "serviceType should be Animal.self, got \(event.serviceType)"
        )
        XCTAssertEqual(event.name, "foo")
    }

    // 8. Main vs background thread classification.
    func testThreadClassification() {
        let tracker = MockTracker()
        ResolveTracking.factory = { tracker }

        let container = Container()
        container.register(Animal.self) { _ in Cat() }

        // XCTest runs test methods on the main thread — resolve directly.
        XCTAssertTrue(Thread.isMainThread, "precondition: XCTest runs on main thread")
        _ = container.resolve(Animal.self)

        // Resolve on a background thread via semaphore.
        let sem = DispatchSemaphore(value: 0)
        let bgThread = Thread { @Sendable in
            _ = container.resolve(Animal.self)
            sem.signal()
        }
        bgThread.start()
        sem.wait()

        XCTAssertEqual(tracker.eventCount, 2)
        XCTAssertEqual(tracker.events[0].thread, .main)
        XCTAssertEqual(tracker.events[1].thread, .background)
    }

    // 9. Nil resolve (unregistered service) still reports an event.
    func testNilResolveStillReportsEvent() {
        let tracker = MockTracker()
        ResolveTracking.factory = { tracker }

        let container = Container()
        // Do NOT register Animal — resolve returns nil.
        let result = container.resolve(Animal.self)

        XCTAssertNil(result)
        XCTAssertEqual(tracker.eventCount, 1, "even failed resolves should emit an event")
        XCTAssertGreaterThan(tracker.events[0].durationNanoseconds, 0)
    }

    // 10. Tracked path fires for 1..9-arg resolve overloads.
    func testAllArgArities() {
        let tracker = MockTracker()
        ResolveTracking.factory = { tracker }

        let c = Container()

        // Register one service per arity using explicit type annotations so the
        // compiler picks the right overload for each distinct Arg count.
        c.register(Animal.self) { _ in Cat() }
        c.register(Animal.self) { (_: Resolver, _: Int) in Cat() }
        c.register(Animal.self) { (_: Resolver, _: Int, _: Int) in Cat() }
        c.register(Animal.self) { (_: Resolver, _: Int, _: Int, _: Int) in Cat() }
        c.register(Animal.self) { (_: Resolver, _: Int, _: Int, _: Int, _: Int) in Cat() }
        c.register(Animal.self) { (_: Resolver, _: Int, _: Int, _: Int, _: Int, _: Int) in Cat() }
        c.register(Animal.self) { (_: Resolver, _: Int, _: Int, _: Int, _: Int, _: Int, _: Int) in Cat() }
        c.register(Animal.self) { (_: Resolver, _: Int, _: Int, _: Int, _: Int, _: Int, _: Int, _: Int) in Cat() }
        c.register(Animal.self) { (_: Resolver, _: Int, _: Int, _: Int, _: Int, _: Int, _: Int, _: Int, _: Int) in Cat() }

        _ = c.resolve(Animal.self)
        _ = c.resolve(Animal.self, argument: 1)
        _ = c.resolve(Animal.self, arguments: 1, 2)
        _ = c.resolve(Animal.self, arguments: 1, 2, 3)
        _ = c.resolve(Animal.self, arguments: 1, 2, 3, 4)
        _ = c.resolve(Animal.self, arguments: 1, 2, 3, 4, 5)
        _ = c.resolve(Animal.self, arguments: 1, 2, 3, 4, 5, 6)
        _ = c.resolve(Animal.self, arguments: 1, 2, 3, 4, 5, 6, 7)
        _ = c.resolve(Animal.self, arguments: 1, 2, 3, 4, 5, 6, 7, 8)

        XCTAssertEqual(
            tracker.eventCount,
            9,
            "each of the 9 top-level resolves (arities 0-8) should emit one event"
        )
    }

    // 11. synchronize() child works with factory — events flow through the child.
    func testSynchronizedContainerWithFactory() {
        let tracker = MockTracker()
        // Factory will be called for both parent and the synchronized child.
        var factoryCallCount = 0
        ResolveTracking.factory = {
            factoryCallCount += 1
            return tracker
        }

        let parent = Container()
        parent.register(Animal.self) { _ in Cat() }

        let child = parent.synchronize()
        _ = child.resolve(Animal.self)

        // factory called for parent + synchronized child = 2
        XCTAssertEqual(factoryCallCount, 2)
        // The child resolve emits events to its own tracker(s).
        // (Both parent and child have the same tracker instance returned by factory.)
        // child has factoryTracker == tracker; parent also has factoryTracker == tracker.
        // The child resolves via getEntry → parent's services, so `resolutionDepth` on the
        // child (cast as Container) is what matters. We expect at least 1 event.
        XCTAssertGreaterThanOrEqual(
            tracker.eventCount,
            1,
            "event should flow through synchronized child"
        )
    }

    // 13. (H7) A nested factory resolve through a synchronize() child must NOT be
    // reported as a second top-level event.
    //
    // The depth gate in `_resolveTracked` reads `self.resolutionDepth` (the resolver
    // you called resolve() on), but `resolveEntry` only ever increments
    // `owner.resolutionDepth` (the container that OWNS the registration). For a
    // synchronize() child — which owns no registrations — `owner` is always the
    // parent, so the child's own `resolutionDepth` never leaves 0. The depth==0
    // re-entrancy guard therefore fails to suppress nested resolves, and each one
    // re-fires as a fresh "top-level" event (with the outer event's duration already
    // containing the inner one).
    //
    // Expected: exactly 1 event (the outer resolve). Actual today: 2.
    func testSynchronizedChildNestedResolveDoesNotDoubleCount() {
        let tracker = MockTracker()
        ResolveTracking.factory = { tracker }

        let parent = Container()
        parent.register(Animal.self) { _ in Cat() }
        parent.register(String.self) { r in
            _ = r.resolve(Animal.self) // nested resolve, runs with resolver == the child
            return "owner"
        }

        let child = parent.synchronize()
        _ = child.resolve(String.self) // ONE top-level call

        XCTAssertEqual(
            tracker.eventCount,
            1,
            "only the outer String resolve should emit an event; the nested Animal " +
                "resolve must be suppressed by the thread-local re-entrancy guard. Got " +
                "\(tracker.eventCount)."
        )
    }

    // 14. (H7, facet 2) A total miss through a synchronize() child must not emit
    // twice. On a miss, `_resolveUntracked` falls through to `parent?.resolve(...)`
    // — the parent's public, tracked entrypoint — and on a miss nothing increments
    // `resolutionDepth`, so a depth-based gate would let both child and parent fire.
    // The thread-local guard (set on the same thread for the whole resolution)
    // suppresses the parent's re-entry.
    func testSynchronizedChildMissDoesNotDoubleCount() {
        let tracker = MockTracker()
        ResolveTracking.factory = { tracker }

        let parent = Container()
        // Do NOT register Dog anywhere — resolve misses on the whole chain.
        let child = parent.synchronize()
        let result = child.resolve(Dog.self)

        XCTAssertNil(result)
        XCTAssertEqual(
            tracker.eventCount,
            1,
            "a top-level miss through the child should emit exactly one event, not " +
                "one for the child and one for the parent-chain fallthrough. Got \(tracker.eventCount)."
        )
    }

    // 15. (M8) synchronize() propagates the per-property resolveTracker.
    // Before the fix, the synchronized child received nil resolveTracker, so
    // hasTracker returned false and _resolveTracked was never called.
    func testSynchronizedChild_propertyTracker_receivesEvents() {
        let tracker = MockTracker()
        // No factory installed — property-only tracking.
        let parent = Container()
        parent.register(Animal.self) { _ in Cat() }
        parent.resolveTracker = tracker

        let child = parent.synchronize()
        _ = child.resolve(Animal.self)

        XCTAssertEqual(
            tracker.eventCount,
            1,
            "property resolveTracker must emit through a synchronized child (M8)"
        )
    }

    // 12. Concurrent set/get of factory is crash-free.
    func testThreadSafeFactorySetGet() {
        let iterations = 200
        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            if i % 3 == 0 {
                ResolveTracking.factory = { nil }
            } else if i % 3 == 1 {
                ResolveTracking.factory = nil
            } else {
                _ = ResolveTracking.factory
            }
        }
        // If we reach here without crashing, the lock is working.
        // Clean up regardless of final state.
        ResolveTracking.factory = nil
    }
}
