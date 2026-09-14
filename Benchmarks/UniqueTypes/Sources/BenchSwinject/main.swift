import BenchModels
import Foundation

// Unique-types benchmark. One process = one sample:
//
//   register   10 000 unique protocol/class pairs
//   resolve #1 every one of them, once — cold Swift-runtime conformance cache
//   resolve #2 every one of them, again — same work, cache now warm
//
// Both passes run in the container's *default* scope, so pass 2 builds 10 000
// fresh instances just like pass 1. It is not a container-cache hit: the only
// thing that differs between the two numbers is how much the runtime still has
// to do to satisfy the cast from the factory's result to the protocol type.
// Swinject pays that per-(type, protocol) conformance lookup; TSwinject casts
// to `DiEntryConcrete<Service>` instead and does not.
//
// Pass 1 is only meaningful in a freshly launched process — measure it twice in
// one process and the second measurement is warm. run.sh spawns a new process
// per sample for exactly this reason.

/// Keeps resolved instances alive so the optimiser cannot delete the work.
@inline(never)
func blackHole<T>(_ value: T) {
    withExtendedLifetime(value) {}
}

func seconds(_ duration: Duration) -> Double {
    let (whole, atto) = duration.components
    return Double(whole) + Double(atto) * 1e-18
}

let emitJSON = CommandLine.arguments.contains("--json")

let clock = ContinuousClock()
let container = Container()

let registerDuration = clock.measure {
    registerAll(in: container)
}

var firstPass: [Any] = []
let firstDuration = clock.measure {
    firstPass = resolveAll(from: container)
}

var secondPass: [Any] = []
let secondDuration = clock.measure {
    secondPass = resolveAll(from: container)
}

blackHole(firstPass)
blackHole(secondPass)

let register = seconds(registerDuration)
let first = seconds(firstDuration)
let second = seconds(secondDuration)
let count = Double(benchTypeCount)

guard firstPass.count == benchTypeCount, secondPass.count == benchTypeCount else {
    FileHandle.standardError.write(
        Data("FAIL: resolved \(firstPass.count)/\(secondPass.count) of \(benchTypeCount) types\n".utf8)
    )
    exit(1)
}

if emitJSON {
    print("""
    {"container":"\(containerName)","types":\(benchTypeCount),\
    "register":\(register),"resolve1":\(first),"resolve2":\(second)}
    """)
} else {
    func line(_ label: String, _ total: Double, _ unit: String) -> String {
        String(
            format: "%-9@ %8.4f s   %7.2f µs/%@",
            label as NSString,
            total,
            total / count * 1e6,
            unit as NSString
        )
    }
    print("container=\(containerName) types=\(benchTypeCount)")
    print(line("register", register, "registration"))
    print(line("resolve#1", first, "resolve"))
    print(line("resolve#2", second, "resolve"))
}
