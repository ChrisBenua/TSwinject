@testable import TSwinject
import XCTest

private final class Box {
    let label: String
    init(_ label: String) { self.label = label }
}

final class ArgumentsTests: XCTestCase {
    // MARK: - 1 argument

    func testOneArg_resolve() {
        let c = Container()
        c.register(Box.self) { (_: Resolver, label: String) in Box(label) }
        XCTAssertEqual(c.resolve(Box.self, argument: "a")?.label, "a")
    }

    func testOneArg_named() {
        let c = Container()
        c.register(Box.self, name: "n") { (_: Resolver, label: String) in Box(label) }
        XCTAssertEqual(c.resolve(Box.self, name: "n", argument: "named")?.label, "named")
        XCTAssertNil(c.resolve(Box.self, argument: "missing"))
    }

    func testOneArg_scope() {
        let c = Container()
        c.register(Box.self, scope: .container) { (_: Resolver, label: String) in Box(label) }
        let a = c.resolve(Box.self, argument: "x")
        let b = c.resolve(Box.self, argument: "y") // arg ignored after first since scoped
        XCTAssertTrue(a === b)
    }

    func testOneArg_initCompleted() {
        let c = Container()
        var seen: Box?
        c.register(
            Box.self,
            scope: .transient,
            factory: { (_: Resolver, l: String) in Box(l) },
            initCompleted: { _, b in seen = b }
        )
        let box = c.resolve(Box.self, argument: "ic")
        XCTAssertTrue(seen === box)
    }

    func testOneArg_doesNotCollideWithZeroArg() {
        let c = Container()
        c.register(Box.self) { _ in Box("zero") }
        c.register(Box.self) { (_: Resolver, label: String) in Box(label) }
        XCTAssertEqual(c.resolve(Box.self)?.label, "zero")
        XCTAssertEqual(c.resolve(Box.self, argument: "one")?.label, "one")
    }

    // MARK: - registerWeak with args

    func testOneArg_weak() {
        // Note: with `registerWeak`, the args are baked in on first resolve;
        // subsequent resolves re-use the wrapper. Calling with different args
        // after the wrapper exists returns a box built from the *original* args.
        let c = Container()
        c.registerWeak(Box.self) { (_: Resolver, label: String) in
            weakInstance(Box(label))
        }
        weak var firstBox: Box?
        autoreleasepool {
            let box = c.resolve(Box.self, argument: "w")
            XCTAssertEqual(box?.label, "w")
            firstBox = box
        }
        XCTAssertNil(firstBox, "weak holder should release the instance")
        // Wrapper still cached; rebuilds with the original captured args.
        XCTAssertEqual(c.resolve(Box.self, argument: "ignored")?.label, "w")
    }

    // MARK: - 2..9 arguments

    func testTwoArgs() {
        let c = Container()
        c.register(Box.self) { (_: Resolver, a: String, b: String) in Box(a + b) }
        XCTAssertEqual(c.resolve(Box.self, arguments: "a", "b")?.label, "ab")
    }

    func testThreeArgs() {
        let c = Container()
        c.register(Box.self) { (_: Resolver, a: String, b: String, x: Int) in
            Box(a + b + "\(x)")
        }
        XCTAssertEqual(c.resolve(Box.self, arguments: "a", "b", 3)?.label, "ab3")
    }

    func testFourArgs() {
        let c = Container()
        c.register(Box.self) { (_: Resolver, a: Int, b: Int, c: Int, d: Int) in
            Box("\(a + b + c + d)")
        }
        XCTAssertEqual(c.resolve(Box.self, arguments: 1, 2, 3, 4)?.label, "10")
    }

    func testFiveArgs() {
        let c = Container()
        c.register(Box.self) { (_: Resolver, a1: Int, a2: Int, a3: Int, a4: Int, a5: Int) in
            Box("\(a1 + a2 + a3 + a4 + a5)")
        }
        XCTAssertEqual(c.resolve(Box.self, arguments: 1, 2, 3, 4, 5)?.label, "15")
    }

    func testSixArgs() {
        let c = Container()
        c.register(Box.self) { (_: Resolver, a1: Int, a2: Int, a3: Int, a4: Int, a5: Int, a6: Int) in
            Box("\(a1 + a2 + a3 + a4 + a5 + a6)")
        }
        XCTAssertEqual(c.resolve(Box.self, arguments: 1, 2, 3, 4, 5, 6)?.label, "21")
    }

    func testSevenArgs() {
        let c = Container()
        c.register(Box.self) { (_: Resolver, a1: Int, a2: Int, a3: Int, a4: Int, a5: Int, a6: Int, a7: Int) in
            Box("\(a1 + a2 + a3 + a4 + a5 + a6 + a7)")
        }
        XCTAssertEqual(c.resolve(Box.self, arguments: 1, 2, 3, 4, 5, 6, 7)?.label, "28")
    }

    func testEightArgs() {
        let c = Container()
        c.register(Box.self) { (_: Resolver, a1: Int, a2: Int, a3: Int, a4: Int, a5: Int, a6: Int, a7: Int, a8: Int) in
            Box("\(a1 + a2 + a3 + a4 + a5 + a6 + a7 + a8)")
        }
        XCTAssertEqual(c.resolve(Box.self, arguments: 1, 2, 3, 4, 5, 6, 7, 8)?.label, "36")
    }

    // MARK: - named variant per arity (exercises the labeled `name:` resolves)

    func testNamedAcrossArities() {
        let c = Container()
        c.register(Box.self, name: "t") { (_: Resolver, a: Int, b: Int) in Box("\(a + b)") }
        c.register(Box.self, name: "t") { (_: Resolver, a: Int, b: Int, x: Int) in Box("\(a + b + x)") }
        c.register(Box.self, name: "t") { (_: Resolver, a: Int, b: Int, c: Int, d: Int) in Box("\(a + b + c + d)") }
        c.register(Box.self, name: "t") { (_: Resolver, a: Int, b: Int, c: Int, d: Int, e: Int) in Box("\(a + b + c + d + e)") }
        c.register(Box.self, name: "t") { (_: Resolver, a: Int, b: Int, c: Int, d: Int, e: Int, f: Int) in Box("\(a + b + c + d + e + f)") }
        c.register(Box.self, name: "t") { (_: Resolver, a: Int, b: Int, c: Int, d: Int, e: Int, f: Int, g: Int) in Box("\(a + b + c + d + e + f + g)") }
        c.register(Box.self, name: "t") { (_: Resolver, a: Int, b: Int, c: Int, d: Int, e: Int, f: Int, g: Int, h: Int) in Box("\(a + b + c + d + e + f + g + h)") }

        XCTAssertEqual(c.resolve(Box.self, name: "t", arguments: 1, 1)?.label, "2")
        XCTAssertEqual(c.resolve(Box.self, name: "t", arguments: 1, 1, 1)?.label, "3")
        XCTAssertEqual(c.resolve(Box.self, name: "t", arguments: 1, 1, 1, 1)?.label, "4")
        XCTAssertEqual(c.resolve(Box.self, name: "t", arguments: 1, 1, 1, 1, 1)?.label, "5")
        XCTAssertEqual(c.resolve(Box.self, name: "t", arguments: 1, 1, 1, 1, 1, 1)?.label, "6")
        XCTAssertEqual(c.resolve(Box.self, name: "t", arguments: 1, 1, 1, 1, 1, 1, 1)?.label, "7")
        XCTAssertEqual(c.resolve(Box.self, name: "t", arguments: 1, 1, 1, 1, 1, 1, 1, 1)?.label, "8")
    }

    // MARK: - registerWeak across all arities

    func testWeakArity2() {
        let c = Container()
        c.registerWeak(Box.self) { (_: Resolver, a: Int, b: Int) in weakInstance(Box("\(a + b)")) }
        XCTAssertEqual(c.resolve(Box.self, arguments: 10, 20)?.label, "30")
    }

    func testWeakArity3() {
        let c = Container()
        c.registerWeak(Box.self) { (_: Resolver, a: Int, b: Int, x: Int) in weakInstance(Box("\(a + b + x)")) }
        XCTAssertEqual(c.resolve(Box.self, arguments: 1, 2, 3)?.label, "6")
    }

    func testWeakArity4() {
        let c = Container()
        c.registerWeak(Box.self) { (_: Resolver, a: Int, b: Int, c: Int, d: Int) in weakInstance(Box("\(a + b + c + d)")) }
        XCTAssertEqual(c.resolve(Box.self, arguments: 1, 2, 3, 4)?.label, "10")
    }

    func testWeakArity5() {
        let c = Container()
        c.registerWeak(Box.self) { (_: Resolver, a: Int, b: Int, c: Int, d: Int, e: Int) in
            weakInstance(Box("\(a + b + c + d + e)"))
        }
        XCTAssertEqual(c.resolve(Box.self, arguments: 1, 2, 3, 4, 5)?.label, "15")
    }

    func testWeakArity6() {
        let c = Container()
        c.registerWeak(Box.self) { (_: Resolver, a: Int, b: Int, c: Int, d: Int, e: Int, f: Int) in
            weakInstance(Box("\(a + b + c + d + e + f)"))
        }
        XCTAssertEqual(c.resolve(Box.self, arguments: 1, 2, 3, 4, 5, 6)?.label, "21")
    }

    func testWeakArity7() {
        let c = Container()
        c.registerWeak(Box.self) { (_: Resolver, a: Int, b: Int, c: Int, d: Int, e: Int, f: Int, g: Int) in
            weakInstance(Box("\(a + b + c + d + e + f + g)"))
        }
        XCTAssertEqual(c.resolve(Box.self, arguments: 1, 2, 3, 4, 5, 6, 7)?.label, "28")
    }

    func testWeakArity8() {
        let c = Container()
        c.registerWeak(Box.self) { (_: Resolver, a: Int, b: Int, c: Int, d: Int, e: Int, f: Int, g: Int, h: Int) in
            weakInstance(Box("\(a + b + c + d + e + f + g + h)"))
        }
        XCTAssertEqual(c.resolve(Box.self, arguments: 1, 2, 3, 4, 5, 6, 7, 8)?.label, "36")
    }

    func testWeakArity9() {
        let c = Container()
        c.registerWeak(Box.self) { (_: Resolver, a1: Int, a2: Int, a3: Int, a4: Int, a5: Int, a6: Int, a7: Int, a8: Int, a9: Int) in
            weakInstance(Box("\(a1 + a2 + a3 + a4 + a5 + a6 + a7 + a8 + a9)"))
        }
        XCTAssertEqual(c.resolve(Box.self, arguments: 1, 2, 3, 4, 5, 6, 7, 8, 9)?.label, "45")
    }

    // MARK: - Resolver protocol default impls

    func testResolverProtocolDefaults_returnNilForArgsOnCustomConformers() {
        final class Stub: Resolver {
            func resolve<S>(_: S.Type, name: String?) -> S? { nil }
        }
        let r: Resolver = Stub()
        XCTAssertNil(r.resolve(Box.self, argument: "a"))
        XCTAssertNil(r.resolve(Box.self, arguments: 1, 2))
        XCTAssertNil(r.resolve(Box.self, arguments: 1, 2, 3))
        XCTAssertNil(r.resolve(Box.self, arguments: 1, 2, 3, 4))
        XCTAssertNil(r.resolve(Box.self, arguments: 1, 2, 3, 4, 5))
        XCTAssertNil(r.resolve(Box.self, arguments: 1, 2, 3, 4, 5, 6))
        XCTAssertNil(r.resolve(Box.self, arguments: 1, 2, 3, 4, 5, 6, 7))
        XCTAssertNil(r.resolve(Box.self, arguments: 1, 2, 3, 4, 5, 6, 7, 8))
        XCTAssertNil(r.resolve(Box.self, arguments: 1, 2, 3, 4, 5, 6, 7, 8, 9))
        XCTAssertNil(r.resolve(Box.self, name: "x", argument: "a"))
        XCTAssertNil(r.resolve(Box.self, name: "x", arguments: 1, 2))
        XCTAssertNil(r.resolve(Box.self, name: "x", arguments: 1, 2, 3))
        XCTAssertNil(r.resolve(Box.self, name: "x", arguments: 1, 2, 3, 4))
        XCTAssertNil(r.resolve(Box.self, name: "x", arguments: 1, 2, 3, 4, 5))
        XCTAssertNil(r.resolve(Box.self, name: "x", arguments: 1, 2, 3, 4, 5, 6))
        XCTAssertNil(r.resolve(Box.self, name: "x", arguments: 1, 2, 3, 4, 5, 6, 7))
        XCTAssertNil(r.resolve(Box.self, name: "x", arguments: 1, 2, 3, 4, 5, 6, 7, 8))
        XCTAssertNil(r.resolve(Box.self, name: "x", arguments: 1, 2, 3, 4, 5, 6, 7, 8, 9))
    }

    func testNineArgs() {
        let c = Container()
        c.register(Box.self) { (_: Resolver, a1: Int, a2: Int, a3: Int, a4: Int, a5: Int, a6: Int, a7: Int, a8: Int, a9: Int) in
            Box("\(a1)\(a2)\(a3)\(a4)\(a5)\(a6)\(a7)\(a8)\(a9)")
        }
        let result = c.resolve(Box.self, arguments: 1, 2, 3, 4, 5, 6, 7, 8, 9)
        XCTAssertEqual(result?.label, "123456789")
    }

    func testNineArgs_named() {
        let c = Container()
        c.register(Box.self, name: "x") { (_: Resolver, a1: Int, a2: Int, a3: Int, a4: Int, a5: Int, a6: Int, a7: Int, a8: Int, a9: Int) in
            Box("\(a1)-\(a2)-\(a3)-\(a4)-\(a5)-\(a6)-\(a7)-\(a8)-\(a9)")
        }
        let result = c.resolve(Box.self, name: "x", arguments: 1, 2, 3, 4, 5, 6, 7, 8, 9)
        XCTAssertEqual(result?.label, "1-2-3-4-5-6-7-8-9")
    }

    // MARK: - Resolver protocol surface

    func testFactoryCanReceiveResolverWithArgs() {
        let c = Container()
        c.register(String.self) { _ in "dep" }
        c.register(Box.self) { (r: Resolver, label: String) in
            Box("\(label):\(r.resolve(String.self) ?? "?")")
        }
        XCTAssertEqual(c.resolve(Box.self, argument: "L")?.label, "L:dep")
    }

    // MARK: - Different arities key independently

    func testDifferentAritiesCoexist() {
        let c = Container()
        c.register(Box.self) { (_: Resolver, a: String) in Box("1:\(a)") }
        c.register(Box.self) { (_: Resolver, a: String, b: String) in Box("2:\(a)\(b)") }
        XCTAssertEqual(c.resolve(Box.self, argument: "x")?.label, "1:x")
        XCTAssertEqual(c.resolve(Box.self, arguments: "x", "y")?.label, "2:xy")
    }

    // MARK: - Parent chain with args

    func testParentResolvedWithArgs() {
        let parent = Container()
        parent.register(Box.self) { (_: Resolver, a: String) in Box("parent:\(a)") }
        let child = Container(parent: parent)
        XCTAssertEqual(child.resolve(Box.self, argument: "z")?.label, "parent:z")
    }

    // MARK: - N-arg optional mirror

    func testOneArg_optional_hitsRegistration() {
        let c = Container()
        c.register(Box.self) { (_: Resolver, label: String) in Box(label) }
        let result = c.resolve(Box?.self, argument: "hi")
        XCTAssertEqual(result??.label, "hi")
    }

    func testOneArg_optional_returnsNilWhenNotRegistered() {
        let c = Container()
        XCTAssertNil(c.resolve(Box?.self, argument: "missing") as Any?)
    }

    func testOneArg_optional_namedVariant() {
        let c = Container()
        c.register(Box.self, name: "n") { (_: Resolver, l: String) in Box(l) }
        XCTAssertEqual(c.resolve(Box?.self, name: "n", argument: "yes")??.label, "yes")
        XCTAssertNil(c.resolve(Box?.self, name: "other", argument: "no") as Any?)
    }

    func testTwoArgs_optional_hitsRegistration() {
        let c = Container()
        c.register(Box.self) { (_: Resolver, a: String, b: String) in Box(a + b) }
        let result = c.resolve(Box?.self, arguments: "x", "y")
        XCTAssertEqual(result??.label, "xy")
    }

    func testTwoArgs_optional_returnsNilWhenNotRegistered() {
        let c = Container()
        XCTAssertNil(c.resolve(Box?.self, arguments: "a", "b") as Any?)
    }

    func testOneArg_weak_optional_hitsRegistration() {
        let c = Container()
        c.registerWeak(Box.self) { (_: Resolver, label: String) in weakInstance(Box(label)) }
        let result = c.resolve(Box?.self, argument: "w")
        XCTAssertEqual(result??.label, "w")
    }

    func testTwoArgs_weak_optional_hitsRegistration() {
        let c = Container()
        c.registerWeak(Box.self) { (_: Resolver, a: String, b: String) in weakInstance(Box(a + b)) }
        let result = c.resolve(Box?.self, arguments: "p", "q")
        XCTAssertEqual(result??.label, "pq")
    }

    func testOneArg_optional_throughParent() {
        let parent = Container()
        parent.register(Box.self) { (_: Resolver, l: String) in Box(l) }
        let child = Container(parent: parent)
        XCTAssertEqual(child.resolve(Box?.self, argument: "inherit")??.label, "inherit")
    }
}
