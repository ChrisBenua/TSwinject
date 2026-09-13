@testable import TSwinject
import XCTest

private protocol Animal: AnyObject { var name: String { get } }
private final class Cat: Animal {
    let name: String
    init(_ n: String) { self.name = n }
}

private final class CountingAssembly: Assembly {
    var loadedCalled = false
    func assemble(container: Container) {
        container.register(Animal.self) { _ in Cat("asm") }
    }

    func loaded(resolver: Resolver) {
        loadedCalled = true
    }
}

private final class SecondAssembly: Assembly {
    func assemble(container: Container) {
        container.register(Cat.self) { _ in Cat("second") }
    }
}

final class AssemblerCoverageTests: XCTestCase {
    func testInit_withDefaultContainer() {
        let assembler = Assembler()
        XCTAssertNil(assembler.resolver.resolve(Cat.self))
    }

    func testInit_withAssembliesAndDefaultContainer() {
        let assembler = Assembler([CountingAssembly()])
        XCTAssertEqual(assembler.resolver.resolve(Animal.self)?.name, "asm")
    }

    func testInit_parentAssembler() {
        let parent = Assembler([CountingAssembly()])
        let child = Assembler(parentAssembler: parent)
        // The child container can resolve parent registrations.
        XCTAssertEqual(child.resolver.resolve(Animal.self)?.name, "asm")
    }

    func testInit_withAssembliesAndParent() {
        let parent = Assembler([CountingAssembly()])
        let child = Assembler([SecondAssembly()], parent: parent)
        XCTAssertNotNil(child.resolver.resolve(Animal.self))
        XCTAssertEqual(child.resolver.resolve(Cat.self)?.name, "second")
    }

    func testLoadedHook_invokedAfterAllAssemblies() {
        let a = CountingAssembly()
        _ = Assembler([a])
        XCTAssertTrue(a.loadedCalled)
    }

    func testApply_assemblyHotLoads() {
        let assembler = Assembler()
        XCTAssertNil(assembler.resolver.resolve(Animal.self))
        let a = CountingAssembly()
        assembler.apply(assembly: a)
        XCTAssertEqual(assembler.resolver.resolve(Animal.self)?.name, "asm")
        XCTAssertTrue(a.loadedCalled)
    }

    func testDeprecatedThrowingInit_withContainer() throws {
        let assembler = Assembler([CountingAssembly()], container: Container())
        XCTAssertNotNil(assembler.resolver.resolve(Animal.self))
    }

    func testDeprecatedThrowingInit_withNilContainer() throws {
        let assembler = Assembler([CountingAssembly()])
        XCTAssertNotNil(assembler.resolver.resolve(Animal.self))
    }

    func testDeprecatedThrowingInit_withParent() throws {
        let parent = Assembler([CountingAssembly()])
        let child = Assembler([SecondAssembly()], parent: parent)
        XCTAssertNotNil(child.resolver.resolve(Animal.self))
        XCTAssertNotNil(child.resolver.resolve(Cat.self))
    }

    func testApply_multipleAssemblies() {
        let assembler = Assembler()
        assembler.apply(assemblies: [CountingAssembly(), SecondAssembly()])
        XCTAssertNotNil(assembler.resolver.resolve(Animal.self))
        XCTAssertNotNil(assembler.resolver.resolve(Cat.self))
    }
}
