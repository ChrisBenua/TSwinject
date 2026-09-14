# Unique-types benchmark

10 000 unique protocol/class pairs, registered once and resolved twice. This is
the benchmark that shows what TSwinject is actually for; the 5-protocol
throughput benchmark in `Tests/TSwinjectBenchmarks` measures the steady state
*after* the Swift runtime has cached everything, which is the shape where the
gap is smallest.

```sh
cd Benchmarks/UniqueTypes
./run.sh                     # build + 5 samples of each runner + table
./run.sh --samples 20
swift run -c release BenchTSwinject   # one raw sample
```

The first build takes ~9 minutes: 10 000 public `Codable` classes is a lot of
code. It is cached afterwards, and it lives in a **separate SwiftPM package** so
that nobody building or testing TSwinject itself ever pays for it.

## Results

Apple M2 Max, macOS 26.6.2, Swift 6.3.3, release build, best of 5 fresh
processes per phase:

| phase | Swinject 2.10.0 | TSwinject | |
|---|---|---|---|
| register | 1.45 µs | 2.73 µs | 0.53× — TSwinject is *slower* |
| resolve #1 (cold) | 174.67 µs | 2.37 µs | **73.6× faster** |
| resolve #2 (warm) | 2.42 µs | 1.22 µs | **2.0× faster** |

Read that table as three separate facts.

**Registration is slower, and that is expected.** TSwinject keys its registry on
`ObjectIdentifier(DiEntryConcrete<Service>.self)`, so registering a type forces
the runtime to instantiate one generic class metadata record per service. That
cost is paid once, at startup, and it is the price of the O(1) cast later:
~13 ms extra across 10 000 registrations.

**The cold first resolve is where the difference lives.** Swinject's
`instance as? Service` has to find the conformance of a concrete type to a
protocol the runtime has never been asked about before, which means walking
conformance records in the image. With 10 000 protocols in the binary that is
175 µs per resolve — 1.75 s to build the graph once. TSwinject casts to
`DiEntryConcrete<Service>`, which is correct by construction, so it never
consults the conformance tables at all: 2.4 µs, and the number does not care how
many protocols the binary defines.

This is the realistic case for an app launch. Every service on the startup path
is resolved for the first time, in a binary full of protocols, exactly once.

**The warm second resolve still favours TSwinject, by ~2×** — consistent with
the 1.34× the 5-protocol benchmark reports, with the extra margin coming from
the larger conformance cache Swinject now has to hash into.

## Why two executables

`BenchSwinject` and `BenchTSwinject` each link exactly *one* container library.
The effect under test is a property of the image (how many conformance records
it contains) and of the process (whether the runtime's conformance cache is
warm). A single binary linking both, switched by a compile flag, would measure
neither cleanly.

For the same reason `run.sh` spawns a **new process per sample**. Measuring
resolve #1 twice in one process gives you a warm cache the second time. Do not
turn the sampling into an in-process loop.

## Why the default scope

Both passes use the container's default object scope (`.graph`), so pass 2
constructs 10 000 fresh instances just like pass 1 — it is *not* a container
cache hit. That is deliberate: it holds the work constant so the only thing
differing between the two numbers is how much the runtime still has to do to
satisfy the cast.

A `.container`-scope variant, where pass 2 is a genuine cache hit, would
separate "cheap cast" from "cheap construction". Not implemented yet.

## Layout

```
Package.swift                    two executables + the shared model module
run.sh                           build, sample, compare
Tools/generate-bench-sources.py  regenerates everything under Sources/*/Generated
Sources/
  BenchModels/Generated/         Protocol0…Protocol9999, Class0…Class9999
  BenchTSwinject/                Aliases.swift + Generated/ + main.swift
  BenchSwinject/                 same, pointed at Swinject
```

`BenchModels` has no DI dependency, so the expensive half of the build compiles
once and is shared by both runners.

Everything under a `Generated/` directory is script output — **never edit it by
hand**. To change the scale:

```sh
python3 Tools/generate-bench-sources.py --types 50000
swift build -c release
```

Re-running the script with no arguments must leave the working tree clean; that
is the check that the committed sources match the generator.

The two runners' `Registration.swift` / `Resolution.swift` differ in exactly one
line — `import TSwinject` vs. `import Swinject`. The registration and resolution
calls themselves are identical, because `register(_:factory:)` and `resolve(_:)`
have compatible signatures in both libraries. The import is needed only because
some of those methods live in extensions.
