import Swinject
@testable import TSwinject
@testable import TSwinjectSwinjectInterop
import XCTest

private protocol Animal: AnyObject { var name: String { get } }
private final class Cat: Animal {
    let name: String
    init(_ n: String) { self.name = n }
}

private extension TSwinject.ObjectScope {
    // A PermanentStorage-backed custom scope, mirroring a host app's `singleton`.
    static let singleton = TSwinject.ObjectScope(storageFactory: PermanentStorage.init, description: "singleton")
    // A non-permanent (graph-backed) custom scope, used to exercise `scopeMap`.
    static let customCache = TSwinject.ObjectScope(storageFactory: GraphStorage.init, description: "customCache")
}

/// Single-registry takeover: the TSwinject container is a typed façade over the
/// legacy Swinject container. Both sides read and write ONE registry, so
/// registered-here-resolved-there can never silently miss in either direction.
final class InteropTests: XCTestCase {

    // MARK: - Both-direction visibility through the single registry

    func testRegisteredViaFacade_resolvedFromSwinject() {
        let legacy = Swinject.Container()
        let t = TSwinject.Container()
        t.attachSwinjectBridge(legacy)

        t.register(Animal.self) { _ in Cat("migrated") }

        XCTAssertEqual(legacy.resolve(Animal.self)?.name, "migrated")
        XCTAssertEqual(t.resolve(Animal.self)?.name, "migrated")
    }

    func testRegisteredInSwinject_resolvedViaFacade() {
        let legacy = Swinject.Container()
        legacy.register(Animal.self) { _ in Cat("legacy") }

        let t = TSwinject.Container()
        t.attachSwinjectBridge(legacy)

        XCTAssertEqual(t.resolve(Animal.self)?.name, "legacy")
    }

    func testNamedRegistrations_bothDirections() {
        let legacy = Swinject.Container()
        legacy.register(Animal.self, name: "old") { _ in Cat("legacy") }

        let t = TSwinject.Container()
        t.attachSwinjectBridge(legacy)
        t.register(Animal.self, name: "new") { _ in Cat("migrated") }

        XCTAssertEqual(t.resolve(Animal.self, name: "old")?.name, "legacy")
        XCTAssertEqual(t.resolve(Animal.self, name: "new")?.name, "migrated")
        XCTAssertEqual(legacy.resolve(Animal.self, name: "new")?.name, "migrated")
        XCTAssertNil(t.resolve(Animal.self, name: "missing"))
    }

    func testOneArg_bothDirections() {
        let legacy = Swinject.Container()
        legacy.register(Cat.self, name: "legacy") { (_: Swinject.Resolver, name: String) in Cat(name) }

        let t = TSwinject.Container()
        t.attachSwinjectBridge(legacy)
        t.register(Cat.self, name: "migrated") { (_: TSwinject.Resolver, name: String) in Cat(name) }

        XCTAssertEqual(t.resolve(Cat.self, name: "legacy", argument: "a")?.name, "a")
        XCTAssertEqual(legacy.resolve(Cat.self, name: "migrated", argument: "b")?.name, "b")
        XCTAssertEqual(t.resolve(Cat.self, name: "migrated", argument: "c")?.name, "c")
    }

    // MARK: - Singleton identity: one registry, one instance

    func testContainerScope_singleInstanceAcrossBothSides() {
        let legacy = Swinject.Container()
        let t = TSwinject.Container()
        t.attachSwinjectBridge(legacy)

        t.register(Cat.self, scope: .container) { _ in Cat("c") }

        let viaFacade = t.resolve(Cat.self)
        let viaSwinjectA = legacy.resolve(Cat.self)
        let viaSwinjectB = legacy.resolve(Cat.self)
        XCTAssertNotNil(viaFacade)
        XCTAssertTrue(viaFacade === viaSwinjectA)
        XCTAssertTrue(viaSwinjectA === viaSwinjectB)
    }

    func testCustomPermanentScope_mapsToContainer_singleInstance() {
        let legacy = Swinject.Container()
        let t = TSwinject.Container()
        t.attachSwinjectBridge(legacy)

        // PermanentStorage-backed custom scope → default map sends it to
        // Swinject's .container, not .graph.
        t.register(Cat.self, scope: .singleton) { _ in Cat("single") }

        let a = legacy.resolve(Cat.self)
        let b = legacy.resolve(Cat.self)
        let c = t.resolve(Cat.self)
        XCTAssertNotNil(a)
        XCTAssertTrue(a === b)
        XCTAssertTrue(b === c)
    }

    func testLegacySingleton_sharedWithFacadeConsumers() {
        let legacy = Swinject.Container()
        legacy.register(Cat.self) { _ in Cat("shared") }
        legacy.register(Animal.self) { r in r.resolve(Cat.self)! }
            .inObjectScope(.container)

        let t = TSwinject.Container()
        t.attachSwinjectBridge(legacy)

        let viaFacade = t.resolve(Animal.self)
        let viaLegacy = legacy.resolve(Animal.self)
        XCTAssertNotNil(viaFacade)
        XCTAssertTrue(viaFacade === viaLegacy)
    }

    // MARK: - Scope mapping

    func testDefaultScopeMap_mapsBuiltInAndPermanentScopes() {
        let map = TSwinject.Container.defaultSwinjectScopeMap
        XCTAssertEqual(map(.transient).description, Swinject.ObjectScope.transient.description)
        XCTAssertEqual(map(.graph).description, Swinject.ObjectScope.graph.description)
        XCTAssertEqual(map(.container).description, Swinject.ObjectScope.container.description)
        // Custom permanent scope → .container (shared), not .graph.
        XCTAssertEqual(map(.singleton).description, Swinject.ObjectScope.container.description)
        // Graph-backed custom scope degrades to .graph.
        XCTAssertEqual(map(.customCache).description, Swinject.ObjectScope.graph.description)
    }

    func testCustomScopeMapOverride() {
        let legacy = Swinject.Container()
        let t = TSwinject.Container()
        t.attachSwinjectBridge(legacy) { scope in
            scope.description == "customCache" ? .container : TSwinject.Container.defaultSwinjectScopeMap(scope)
        }

        t.register(Cat.self, scope: .customCache) { _ in Cat("cached") }

        let a = legacy.resolve(Cat.self)
        let b = legacy.resolve(Cat.self)
        XCTAssertNotNil(a)
        XCTAssertTrue(a === b, "the override mapped customCache → .container, so one shared instance")
    }

    func testTransientScope_independentPerResolve() {
        let legacy = Swinject.Container()
        let t = TSwinject.Container()
        t.attachSwinjectBridge(legacy)

        t.register(Cat.self, scope: .transient) { _ in Cat("t") }
        let a = legacy.resolve(Cat.self)
        let b = legacy.resolve(Cat.self)
        XCTAssertFalse(a === b)
    }

    // MARK: - Weak registrations

    func testRegisterWeak_sharedAcrossBothSidesWhileAlive() {
        let legacy = Swinject.Container()
        let t = TSwinject.Container()
        t.attachSwinjectBridge(legacy)

        t.registerWeak(Cat.self) { _ in weakInstance(Cat("w")) }

        let holder: Cat? = t.resolve(Cat.self)
        let viaLegacy = legacy.resolve(Cat.self)
        XCTAssertNotNil(holder)
        XCTAssertTrue(holder === viaLegacy, "one registry → one weak instance while a strong ref exists")
    }

    // MARK: - Factories pull dependencies through the shared registry

    func testFacadeFactory_resolvesLegacyDependency() {
        let legacy = Swinject.Container()
        legacy.register(String.self) { _ in "injected" }

        let t = TSwinject.Container()
        t.attachSwinjectBridge(legacy)
        t.register(Cat.self) { r in Cat(r.resolve(String.self) ?? "n/a") }

        XCTAssertEqual(legacy.resolve(Cat.self)?.name, "injected")
        XCTAssertEqual(t.resolve(Cat.self)?.name, "injected")
    }

    func testLegacyFactory_resolvesFacadeRegisteredDependency() {
        let legacy = Swinject.Container()
        legacy.register(Animal.self) { r in r.resolve(Cat.self)! }

        let t = TSwinject.Container()
        t.attachSwinjectBridge(legacy)
        t.register(Cat.self) { _ in Cat("from-facade") }

        XCTAssertEqual(legacy.resolve(Animal.self)?.name, "from-facade")
        XCTAssertEqual(t.resolve(Animal.self)?.name, "from-facade")
    }

    // MARK: - hasAnyRegistration sees the whole shared registry

    func testHasAnyRegistration_seesDirectLegacyRegistrations() {
        let legacy = Swinject.Container()
        legacy.register(Animal.self, name: "direct") { _ in Cat("legacy") }

        let t = TSwinject.Container()
        t.attachSwinjectBridge(legacy)
        t.register(Cat.self) { _ in Cat("via-facade") }

        // Registered directly on the legacy container — now visible through the
        // façade probe (it delegates to Swinject's own hasAnyRegistration).
        XCTAssertTrue(t.hasAnyRegistration(of: Animal.self, name: "direct"))
        // Registered through the façade — visible too.
        XCTAssertTrue(t.hasAnyRegistration(of: Cat.self))
        // Never registered — false.
        XCTAssertFalse(t.hasAnyRegistration(of: Animal.self, name: "missing"))
    }

    // MARK: - Scope descriptions are load-bearing bridge keys

    /// The bridge maps built-in scopes by matching `ObjectScope.description`
    /// against string literals. Renaming a description would silently send every
    /// built-in scope down the `default:` branch and degrade it to `.graph`,
    /// with no compile error — so pin the descriptions here.
    func testBuiltInScopeDescriptions_areStableBridgeKeys() {
        XCTAssertEqual(TSwinject.ObjectScope.transient.description, "transient")
        XCTAssertEqual(TSwinject.ObjectScope.graph.description, "graph")
        XCTAssertEqual(TSwinject.ObjectScope.container.description, "container")
    }
}
