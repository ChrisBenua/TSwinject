@testable import TSwinject
import XCTest

private protocol Animal: AnyObject { var name: String { get } }
private final class Cat: Animal {
    let name: String
    init(_ n: String) { self.name = n }
}

private final class Dog: Animal {
    let name: String
    init(_ n: String) { self.name = n }
}

private final class Owner {
    let pet: Animal
    init(pet: Animal) { self.pet = pet }
}

final class AdvancedTests: XCTestCase {
    // MARK: - initCompleted

    func testInitCompleted_isCalled() {
        let container = Container()
        var called: Cat?
        container.register(
            Cat.self,
            scope: .transient,
            factory: { _ in Cat("ic") },
            initCompleted: { _, cat in called = cat }
        )
        let cat = container.resolve(Cat.self)
        XCTAssertNotNil(called)
        XCTAssertTrue(called === cat)
    }

    func testInitCompleted_canBreakCircularity() {
        // Both sides strong, container-scoped so the link survives the graph teardown.
        final class P { var child: C?; init() {} }
        final class C { weak var parent: P?; init() {} }

        let container = Container()
        container.register(
            P.self,
            scope: .container,
            factory: { _ in P() },
            initCompleted: { r, p in p.child = r.resolve(C.self) }
        )
        container.register(
            C.self,
            scope: .container,
            factory: { _ in C() },
            initCompleted: { r, c in c.parent = r.resolve(P.self) }
        )
        let parent = container.resolve(P.self)!
        XCTAssertNotNil(parent.child)
        XCTAssertTrue(parent.child?.parent === parent)
    }

    // MARK: - resetObjectScope by service type

    func testResetObjectScope_byServiceType_onlyResetsMatching() {
        let container = Container()
        var catCount = 0
        var dogCount = 0
        container.register(Cat.self, scope: .container) { _ in catCount += 1; return Cat("c\(catCount)") }
        container.register(Dog.self, scope: .container) { _ in dogCount += 1; return Dog("d\(dogCount)") }

        _ = container.resolve(Cat.self)
        _ = container.resolve(Dog.self)
        XCTAssertEqual(catCount, 1)
        XCTAssertEqual(dogCount, 1)

        container.resetObjectScope(.container, serviceType: Cat.self)
        _ = container.resolve(Cat.self)
        _ = container.resolve(Dog.self)
        XCTAssertEqual(catCount, 2)
        XCTAssertEqual(dogCount, 1, "Dog scope should not have been reset")
    }

    func testResetObjectScope_cascadesToParent() {
        let parent = Container()
        var ctr = 0
        parent.register(Cat.self, scope: .container) { _ in ctr += 1; return Cat("p\(ctr)") }
        let child = Container(parent: parent)

        _ = child.resolve(Cat.self)
        XCTAssertEqual(ctr, 1)
        child.resetObjectScope(.container)
        _ = child.resolve(Cat.self)
        XCTAssertEqual(ctr, 2)
    }

    // MARK: - synchronize

    func testSynchronize_returnsResolverThatResolves() {
        let container = Container()
        container.register(Cat.self) { _ in Cat("sync") }
        let synced = container.synchronize()
        XCTAssertEqual(synced.resolve(Cat.self)?.name, "sync")
    }

    func testSynchronize_concurrentResolves() {
        let container = Container()
        container.register(Cat.self, scope: .container) { _ in Cat("shared") }
        let synced = container.synchronize()
        let queue = DispatchQueue(label: "t", attributes: .concurrent)
        let group = DispatchGroup()
        var results = [Cat?](repeating: nil, count: 100)
        for i in 0 ..< 100 {
            group.enter()
            queue.async { @Sendable in
                results[i] = synced.resolve(Cat.self)
                group.leave()
            }
        }
        group.wait()
        let first = results[0]
        XCTAssertNotNil(first)
        XCTAssertTrue(results.allSatisfy { $0 === first })
    }

    // MARK: - Optional resolution

    func testResolveOptional_returnsNilWhenNotRegistered() {
        let container = Container()
        let result: Cat?? = container.resolve(Cat?.self)
        XCTAssertNil(result)
    }

    func testResolveOptional_forWeakRegistration() {
        let container = Container()
        container.registerWeak(Cat.self) { _ in weakInstance(Cat("w")) }
        let strong = container.resolve(Cat.self)
        XCTAssertNotNil(strong)
        let optional: Cat?? = container.resolve(Cat?.self)
        XCTAssertEqual(optional??.name, "w")
        _ = strong
    }

    // E1: the optional mirror must thread the *invoking* resolver, so
    // child.resolve(T?) honors a child override of a parent registration —
    // agreeing with child.resolve(T).
    func testResolveOptional_honorsChildOverride() {
        let parent = Container()
        parent.register(Animal.self) { _ in Cat("parent") }
        let child = Container(parent: parent)
        child.register(Animal.self) { _ in Cat("child") }

        XCTAssertEqual(child.resolve(Animal.self)?.name, "child")
        let optional: Animal?? = child.resolve(Animal?.self)
        XCTAssertEqual(optional??.name, "child")
    }

    func testResolveOptional_honorsChildOverride_weak() {
        let parent = Container()
        parent.registerWeak(Animal.self) { _ -> (Animal, () -> Animal?) in
            let c = Cat("parent"); return (c, { [weak c] in c })
        }
        let child = Container(parent: parent)
        child.registerWeak(Animal.self) { _ -> (Animal, () -> Animal?) in
            let c = Cat("child"); return (c, { [weak c] in c })
        }

        let strong = child.resolve(Animal.self)
        XCTAssertEqual(strong?.name, "child")
        let optional: Animal?? = child.resolve(Animal?.self)
        XCTAssertEqual(optional??.name, "child")
        _ = strong
    }

    // MARK: - fallbackResolver direct

    func testFallbackResolver_used() {
        final class Stub: Resolver {
            func resolve<S>(_: S.Type, name: String?) -> S? {
                Cat("stub") as? S
            }
        }
        let container = Container()
        container.fallbackResolver = Stub()
        XCTAssertEqual(container.resolve(Cat.self)?.name, "stub")
    }

    // MARK: - removeAll & hasAnyRegistration named

    func testHasAnyRegistration_named() {
        let c = Container()
        c.register(Cat.self, name: "k") { _ in Cat("k") }
        XCTAssertFalse(c.hasAnyRegistration(of: Cat.self))
        XCTAssertTrue(c.hasAnyRegistration(of: Cat.self, name: "k"))
    }

    // E4: arg-based registrations must be visible to hasAnyRegistration
    // (Swinject parity — matches on service type, ignoring argument arity).
    func testHasAnyRegistration_argBased() {
        let c = Container()
        c.register(Cat.self) { (_, n: String) in Cat(n) }
        XCTAssertTrue(c.hasAnyRegistration(of: Cat.self))

        c.register(Dog.self, name: "d") { (_, a: String, _: Int) in Dog(a) }
        XCTAssertTrue(c.hasAnyRegistration(of: Dog.self, name: "d"))
        XCTAssertFalse(c.hasAnyRegistration(of: Dog.self))
    }

    // MARK: - Behavior with named registration

    func testBehavior_capturesName() {
        final class Recorder: Behavior {
            var names: [String?] = []
            func container<S>(_ c: Container, didRegisterType: S.Type, withName n: String?) {
                names.append(n)
            }
        }
        let r = Recorder()
        let c = Container(behaviors: [r])
        c.register(Cat.self) { _ in Cat("a") }
        c.register(Cat.self, name: "b") { _ in Cat("b") }
        XCTAssertEqual(r.names, [nil, "b"])
    }

    // MARK: - WeakScope custom subclass

    func testWeakObjectScope_subclassUsable() {
        final class CustomWeak: WeakObjectScope, @unchecked Sendable {}
        let c = Container()
        c.registerWeak(Cat.self, scope: CustomWeak()) { _ in weakInstance(Cat("custom")) }
        XCTAssertEqual(c.resolve(Cat.self)?.name, "custom")
    }

    func testWeakObjectScope_protocolConformerUsable() {
        // Conforms to WeakObjectScopeProtocol WITHOUT subclassing WeakObjectScope —
        // impossible before `registerWeak`'s `scope:` was widened from the concrete
        // class to the protocol.
        final class ProtocolWeakScope: WeakObjectScopeProtocol, @unchecked Sendable {
            func makeStorage() -> InstanceStorage { PermanentStorage() }
        }
        let c = Container()
        c.registerWeak(Cat.self, scope: ProtocolWeakScope()) { _ in weakInstance(Cat("proto")) }
        XCTAssertEqual(c.resolve(Cat.self)?.name, "proto")
    }

    func testResetObjectScope_weak_rebuildsWrapper() {
        let c = Container()
        var builds = 0
        c.registerWeak(Cat.self) { _ in
            builds += 1
            return weakInstance(Cat("w\(builds)"))
        }

        let held = c.resolve(Cat.self) // build #1
        XCTAssertEqual(held?.name, "w1")
        XCTAssertEqual(c.resolve(Cat.self)?.name, "w1", "same wrapper while the value is alive")
        XCTAssertEqual(builds, 1)

        c.resetObjectScope(WeakScope.shared) // discard the cached weak wrapper
        XCTAssertEqual(c.resolve(Cat.self)?.name, "w2", "reset forces a fresh weak wrapper")
        XCTAssertEqual(builds, 2)
        _ = held
    }

    func testResetObjectScope_weak_byServiceType() {
        let c = Container()
        var catBuilds = 0
        var dogBuilds = 0
        c.registerWeak(Cat.self) { _ in catBuilds += 1; return weakInstance(Cat("c")) }
        c.registerWeak(Dog.self) { _ in dogBuilds += 1; return weakInstance(Dog("d")) }

        let heldCat = c.resolve(Cat.self)
        let heldDog = c.resolve(Dog.self)
        XCTAssertEqual(catBuilds, 1)
        XCTAssertEqual(dogBuilds, 1)

        c.resetObjectScope(WeakScope.shared, serviceType: Cat.self)
        _ = c.resolve(Cat.self) // Cat's weak wrapper discarded → rebuild
        _ = c.resolve(Dog.self) // Dog untouched (still alive) → no rebuild
        XCTAssertEqual(catBuilds, 2, "only Cat's weak entry was reset")
        XCTAssertEqual(dogBuilds, 1, "Dog must not have been reset")
        _ = heldCat
        _ = heldDog
    }

    // MARK: - Customizable resolution-depth cap

    func testMaxResolutionDepth_custom_allowsDeeperGraph() {
        struct Counter { let value: Int }
        let c = Container(maxResolutionDepth: 400)
        c.register(Counter.self, scope: .transient) { (r, n: Int) -> Counter in
            n <= 0 ? Counter(value: 0) : Counter(value: (r.resolve(Counter.self, argument: n - 1)?.value ?? 0) + 1)
        }
        // 250 > the default cap of 200 — would fatalError without the raise.
        XCTAssertEqual(c.resolve(Counter.self, argument: 250)?.value, 250)
    }

    func testMaxResolutionDepth_childInheritsParent() {
        struct Counter { let value: Int }
        let parent = Container(maxResolutionDepth: 400)
        let child = Container(parent: parent)
        child.register(Counter.self, scope: .transient) { (r, n: Int) -> Counter in
            n <= 0 ? Counter(value: 0) : Counter(value: (r.resolve(Counter.self, argument: n - 1)?.value ?? 0) + 1)
        }
        // child has no explicit cap → must inherit the parent's 400 (else fatalError at 200).
        XCTAssertEqual(child.resolve(Counter.self, argument: 250)?.value, 250)
    }

    // MARK: - Storage primitives

    func testCompositeStorage_persistsViaAnyComponent() {
        let composite = CompositeStorage([TransientStorage(), PermanentStorage()])
        let g = GraphIdentifier()
        composite.setInstance("x", inGraph: g)
        XCTAssertEqual(composite.instance(inGraph: g) as? String, "x")
        composite.graphResolutionCompleted()
        // Permanent still has it
        XCTAssertEqual(composite.instance as? String, "x")
    }

    func testCompositeStorage_instanceSetterFansOut() {
        let permanent = PermanentStorage()
        let composite = CompositeStorage([permanent, TransientStorage()])
        composite.instance = "y"
        XCTAssertEqual(permanent.instance as? String, "y")
        XCTAssertEqual(composite.instance as? String, "y")
    }

    func testTransientStorage_neverPersists() {
        let s = TransientStorage()
        s.instance = "x"
        XCTAssertNil(s.instance)
    }

    func testGraphStorage_clearsOnCompletion() {
        let s = GraphStorage()
        let g = GraphIdentifier()
        s.setInstance("x", inGraph: g)
        XCTAssertEqual(s.instance(inGraph: g) as? String, "x")
        s.graphResolutionCompleted()
        XCTAssertNil(s.instance(inGraph: g))
    }

    // MARK: - Custom ObjectScope via parent storage composition

    func testObjectScope_withParentComposesStorage() {
        let scope = ObjectScope(
            storageFactory: TransientStorage.init,
            description: "custom",
            parent: ObjectScope.container
        )
        let c = Container()
        var ctr = 0
        c.register(Cat.self, scope: scope) { _ in ctr += 1; return Cat("x\(ctr)") }
        let a = c.resolve(Cat.self)
        let b = c.resolve(Cat.self)
        // Parent .container makes it persistent
        XCTAssertTrue(a === b)
    }

    // MARK: - Custom ObjectScope behavior (native, end-to-end)

    func testCustomScope_permanentStorage_isSingleton() {
        let scope = ObjectScope(storageFactory: PermanentStorage.init, description: "customPermanent")
        let c = Container()
        var ctr = 0
        c.register(Cat.self, scope: scope) { _ in ctr += 1; return Cat("p\(ctr)") }

        let a = c.resolve(Cat.self)
        let b = c.resolve(Cat.self)
        XCTAssertTrue(a === b, "PermanentStorage-backed custom scope shares one instance")
        XCTAssertEqual(ctr, 1)

        // The scope is a recipe, not a shared store: a second container with the
        // same scope object gets its own storage and does not share `a`.
        let c2 = Container()
        c2.register(Cat.self, scope: scope) { _ in Cat("other") }
        XCTAssertFalse(c2.resolve(Cat.self) === a)
    }

    func testCustomScope_graphStorage_sharesWithinGraph() {
        final class Pair { let a: Animal; let b: Animal; init(_ a: Animal, _ b: Animal) { self.a = a; self.b = b } }
        let graphScope = ObjectScope(storageFactory: GraphStorage.init, description: "customGraph")
        let c = Container()
        var leaves = 0
        c.register(Cat.self, scope: graphScope) { _ in leaves += 1; return Cat("leaf\(leaves)") }
        c.register(Pair.self) { r in Pair(r.resolve(Cat.self)!, r.resolve(Cat.self)!) }

        let pair = c.resolve(Pair.self)!
        XCTAssertTrue(pair.a === pair.b, "custom graph scope shares one instance within a resolution")
        XCTAssertEqual(leaves, 1)

        let pair2 = c.resolve(Pair.self)!
        XCTAssertFalse(pair2.a === pair.a, "a new top-level resolve builds a fresh graph instance")
        XCTAssertEqual(leaves, 2)
    }

    func testCustomScope_resetObjectScope_rebuilds() {
        let scope = ObjectScope(storageFactory: PermanentStorage.init, description: "resettable")
        let c = Container()
        var ctr = 0
        c.register(Cat.self, scope: scope) { _ in ctr += 1; return Cat("n\(ctr)") }

        XCTAssertEqual(c.resolve(Cat.self)?.name, "n1")
        XCTAssertEqual(c.resolve(Cat.self)?.name, "n1")
        c.resetObjectScope(scope)
        XCTAssertEqual(c.resolve(Cat.self)?.name, "n2", "reset of the custom scope rebuilds")
    }

    func testCustomScope_distinctInstancesResetIndependently() {
        // Same backing AND same description, but two DISTINCT scope objects.
        let scopeA = ObjectScope(storageFactory: PermanentStorage.init, description: "dup")
        let scopeB = ObjectScope(storageFactory: PermanentStorage.init, description: "dup")
        let c = Container()
        var aCtr = 0, bCtr = 0
        c.register(Cat.self, scope: scopeA) { _ in aCtr += 1; return Cat("a\(aCtr)") }
        c.register(Dog.self, scope: scopeB) { _ in bCtr += 1; return Dog("b\(bCtr)") }
        _ = c.resolve(Cat.self)
        _ = c.resolve(Dog.self)
        XCTAssertEqual(aCtr, 1)
        XCTAssertEqual(bCtr, 1)

        c.resetObjectScope(scopeA) // native reset keys on === identity, not description
        _ = c.resolve(Cat.self)
        _ = c.resolve(Dog.self)
        XCTAssertEqual(aCtr, 2, "scopeA was reset")
        XCTAssertEqual(bCtr, 1, "scopeB shares scopeA's description but is a distinct identity → untouched")
    }

    func testCustomScope_asDefaultObjectScope() {
        let scope = ObjectScope(storageFactory: PermanentStorage.init, description: "defaultCustom")
        let c = Container(defaultObjectScope: scope)
        var ctr = 0
        c.register(Cat.self) { _ in ctr += 1; return Cat("d\(ctr)") } // no explicit scope:

        let a = c.resolve(Cat.self)
        let b = c.resolve(Cat.self)
        XCTAssertTrue(a === b, "registration with no scope uses the custom default scope")
        XCTAssertEqual(ctr, 1)
    }

    func testCustomScope_sharedByTwoTypes_independentInstances() {
        let scope = ObjectScope(storageFactory: PermanentStorage.init, description: "shared")
        let c = Container()
        var catCtr = 0, dogCtr = 0
        c.register(Cat.self, scope: scope) { _ in catCtr += 1; return Cat("c\(catCtr)") }
        c.register(Dog.self, scope: scope) { _ in dogCtr += 1; return Dog("d\(dogCtr)") }

        let cat1 = c.resolve(Cat.self)
        let dog1 = c.resolve(Dog.self)
        // Each registration gets its own makeStorage() → independent singletons.
        XCTAssertTrue(c.resolve(Cat.self) === cat1)
        XCTAssertTrue(c.resolve(Dog.self) === dog1)
        XCTAssertEqual(catCtr, 1)
        XCTAssertEqual(dogCtr, 1)

        // Resetting the shared scope object resets both (both entries' objectScope === scope).
        c.resetObjectScope(scope)
        _ = c.resolve(Cat.self)
        _ = c.resolve(Dog.self)
        XCTAssertEqual(catCtr, 2)
        XCTAssertEqual(dogCtr, 2)
    }

    // MARK: - registerWeak memory (N3)

    // The DiEntryWeak wrapper lives in PermanentStorage inside the container's
    // own services map. If its rebuild closure captured the resolving container,
    // the container would retain itself after the first weak resolve and never
    // deallocate.
    func testRegisterWeak_containerDoesNotRetainItself() {
        weak var leaked: Container?
        var holder: Cat?

        do {
            let container = Container()
            container.registerWeak(Cat.self) { _ in weakInstance(Cat("leak-check")) }
            holder = container.resolve(Cat.self)
            leaked = container
        }

        XCTAssertNotNil(holder, "the weak service itself must resolve")
        XCTAssertNil(leaked, "resolving a weak registration must not make the container retain itself")
    }

    func testRegisterWeak_argVariant_containerDoesNotRetainItself() {
        weak var leaked: Container?
        var holder: Cat?

        do {
            let container = Container()
            container.registerWeak(Cat.self) { (_: Resolver, n: String) in weakInstance(Cat(n)) }
            holder = container.resolve(Cat.self, argument: "arg-leak-check")
            leaked = container
        }

        XCTAssertEqual(holder?.name, "arg-leak-check")
        XCTAssertNil(leaked, "N-arg weak registrations must not capture the container either")
    }

    // Rebuilds now receive the resolver of the resolve that triggered them,
    // instead of whichever container happened to resolve first.
    func testRegisterWeak_rebuildUsesCurrentResolver() {
        let parent = Container()
        parent.register(String.self) { _ in "parent" }
        parent.registerWeak(Cat.self) { r in weakInstance(Cat(r.resolve(String.self) ?? "none")) }

        var first: Cat? = parent.resolve(Cat.self)
        XCTAssertEqual(first?.name, "parent")
        first = nil // let the weak value die

        let child = Container(parent: parent)
        child.register(String.self) { _ in "child" }
        let rebuilt = child.resolve(Cat.self)
        XCTAssertEqual(
            rebuilt?.name,
            "child",
            "the rebuild must use the resolver of the resolve that triggered it"
        )
    }

    // MARK: - Graph caching (identifier lifecycle + storage)

    // Ported from Swinject's ContainerTests.GraphCaching, adapted to TSwinject's API:
    // `currentObjectGraph` (internal, reached via @testable) replaces the public probe,
    // and the scoped `withObjectGraph(_:)` replaces `restoreObjectGraph`. Tests that rely
    // on `resolve(GraphIdentifier.self)` or on restoring a *completed* graph are omitted —
    // the latter is the Provider/Lazy mechanism, which TSwinject does not support (see the
    // negative test at the end).

    func testCurrentObjectGraph_isNilOutsideAndSetDuringResolution() {
        let container = Container()
        var captured: GraphIdentifier?
        container.register(Dog.self) { r in
            captured = (r as? Container)?.currentObjectGraph
            return Dog("d")
        }

        XCTAssertNil(container.currentObjectGraph, "no graph before any resolution")
        _ = container.resolve(Dog.self)
        XCTAssertNotNil(captured, "a graph identifier exists during resolution")
        XCTAssertNil(container.currentObjectGraph, "graph is torn down after resolution completes")
    }

    func testCurrentObjectGraph_isStableAcrossNestedResolves() {
        let container = Container()
        var ids = [GraphIdentifier?]()
        container.register(Dog.self) { r in
            ids.append((r as? Container)?.currentObjectGraph)
            _ = r.resolve(Cat.self)
            return Dog("d")
        }
        container.register(Cat.self) { r in
            ids.append((r as? Container)?.currentObjectGraph)
            return Cat("c")
        }

        _ = container.resolve(Dog.self)

        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(ids[0], ids[1], "a nested resolve shares the enclosing object graph")
    }

    func testCurrentObjectGraph_differsBetweenSeparateResolves() {
        let container = Container()
        var ids = [GraphIdentifier?]()
        container.register(Dog.self) { r in
            ids.append((r as? Container)?.currentObjectGraph)
            return Dog("d")
        }

        _ = container.resolve(Dog.self)
        _ = container.resolve(Dog.self)

        XCTAssertEqual(ids.count, 2)
        XCTAssertNotEqual(ids[0], ids[1], "each top-level resolve is its own graph")
    }

    func testGraphScope_sharesInstanceAcrossDiamondWithinResolution() {
        final class D {}
        final class B { let d: D; init(_ d: D) { self.d = d } }
        final class C { let d: D; init(_ d: D) { self.d = d } }
        final class A { let b: B; let c: C; init(_ b: B, _ c: C) { self.b = b; self.c = c } }

        let container = Container()
        var dCount = 0
        container.register(D.self) { _ in dCount += 1; return D() } // default .graph scope
        container.register(B.self) { r in B(r.resolve(D.self)!) }
        container.register(C.self) { r in C(r.resolve(D.self)!) }
        container.register(A.self) { r in A(r.resolve(B.self)!, r.resolve(C.self)!) }

        let a = container.resolve(A.self)!
        XCTAssertTrue(a.b.d === a.c.d, "one D is shared across the diamond within a single resolve")
        XCTAssertEqual(dCount, 1)

        let a2 = container.resolve(A.self)!
        XCTAssertFalse(a2.b.d === a.b.d, "a fresh top-level resolve builds a new graph instance")
        XCTAssertEqual(dCount, 2)
    }
}
