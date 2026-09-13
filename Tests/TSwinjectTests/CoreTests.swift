@testable import TSwinject
import XCTest

private protocol Animal: AnyObject {
    var name: String { get }
}

private final class Cat: Animal {
    let name: String
    init(name: String) { self.name = name }
}

private final class Owner {
    let pet: Animal
    init(pet: Animal) { self.pet = pet }
}

final class CoreTests: XCTestCase {
    func testRegisterAndResolve() {
        let container = Container()
        container.register(Animal.self) { _ in Cat(name: "Mimi") }

        let animal = container.resolve(Animal.self)
        XCTAssertEqual(animal?.name, "Mimi")
    }

    func testNamedRegistrations() {
        let container = Container()
        container.register(Animal.self, name: "a") { _ in Cat(name: "A") }
        container.register(Animal.self, name: "b") { _ in Cat(name: "B") }

        XCTAssertEqual(container.resolve(Animal.self, name: "a")?.name, "A")
        XCTAssertEqual(container.resolve(Animal.self, name: "b")?.name, "B")
        XCTAssertNil(container.resolve(Animal.self, name: "c"))
    }

    func testGraphSharing() {
        let container = Container()
        container.register(Animal.self) { _ in Cat(name: "X") }
        container.register(Owner.self) { r in Owner(pet: r.resolve(Animal.self)!) }

        let owner = container.resolve(Owner.self)!
        let pet = container.resolve(Animal.self)!
        // Each top-level resolve is its own graph, so pets differ.
        XCTAssertFalse(owner.pet === pet)
    }

    func testContainerScopeSharesAcrossResolves() {
        let container = Container()
        container.register(Animal.self, scope: .container) { _ in Cat(name: "shared") }

        let a = container.resolve(Animal.self)
        let b = container.resolve(Animal.self)
        XCTAssertTrue(a === b)
    }

    func testTransientScopeAlwaysFresh() {
        let container = Container()
        container.register(Animal.self, scope: .transient) { _ in Cat(name: "fresh") }
        let a = container.resolve(Animal.self)
        let b = container.resolve(Animal.self)
        XCTAssertFalse(a === b)
    }

    func testOptionalResolve() {
        let container = Container()
        container.register(Animal.self) { _ in Cat(name: "opt") }
        let optional: Animal?? = container.resolve(Animal?.self)
        XCTAssertNotNil(optional)
        XCTAssertEqual(optional??.name, "opt")
    }

    func testHasAnyRegistration() {
        let container = Container()
        XCTAssertFalse(container.hasAnyRegistration(of: Animal.self))
        container.register(Animal.self) { _ in Cat(name: "x") }
        XCTAssertTrue(container.hasAnyRegistration(of: Animal.self))
    }

    func testRegisterWeak_releasesWhenNoStrongRefs() {
        let container = Container()
        container.registerWeak(Cat.self) { _ in weakInstance(Cat(name: "weak")) }

        autoreleasepool {
            let first = container.resolve(Cat.self)
            XCTAssertEqual(first?.name, "weak")
        }
        // The wrapper stayed in the container; its value should be released
        // and a fresh one produced on the next resolve.
        let second = container.resolve(Cat.self)
        XCTAssertEqual(second?.name, "weak")
    }

    func testRegisterWeak_strongHolderKeepsAlive() {
        let container = Container()
        container.registerWeak(Cat.self) { _ in weakInstance(Cat(name: "kept")) }

        let strong = container.resolve(Cat.self)
        let again = container.resolve(Cat.self)
        XCTAssertTrue(strong === again)
        _ = strong
    }

    func testParentContainer() {
        let parent = Container()
        parent.register(Animal.self) { _ in Cat(name: "parent") }
        let child = Container(parent: parent)
        XCTAssertEqual(child.resolve(Animal.self)?.name, "parent")
    }

    func testRemoveAll() {
        let container = Container()
        container.register(Animal.self) { _ in Cat(name: "x") }
        container.removeAll()
        XCTAssertNil(container.resolve(Animal.self))
    }

    func testResetObjectScope() {
        let container = Container()
        var ctr = 0
        container.register(Cat.self, scope: .container) { _ in
            ctr += 1
            return Cat(name: "n\(ctr)")
        }
        let first = container.resolve(Cat.self)
        XCTAssertEqual(first?.name, "n1")
        container.resetObjectScope(.container)
        let second = container.resolve(Cat.self)
        XCTAssertEqual(second?.name, "n2")
    }

    func testBehaviorReceivesRegistrations() {
        final class Counter: Behavior {
            var count = 0
            func container<S>(_ c: Container, didRegisterType: S.Type, withName: String?) {
                count += 1
            }
        }
        let counter = Counter()
        let container = Container(behaviors: [counter])
        container.register(Animal.self) { _ in Cat(name: "x") }
        XCTAssertEqual(counter.count, 1)
    }

    func testAssemblerLoadsAssemblies() {
        struct CatAssembly: Assembly {
            func assemble(container: Container) {
                container.register(Animal.self) { _ in Cat(name: "assembled") }
            }
        }
        let assembler = Assembler([CatAssembly()])
        XCTAssertEqual(assembler.resolver.resolve(Animal.self)?.name, "assembled")
    }
}
