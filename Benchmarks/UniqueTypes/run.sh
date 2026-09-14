#!/usr/bin/env bash
#
# Builds both runners in release and samples each one, then prints the
# comparison table.
#
# Every sample is a FRESH PROCESS, and that is load-bearing. The first resolve
# pass is measured against a cold Swift-runtime conformance cache; re-running it
# inside the same process would measure a warm one and quietly erase the effect
# the benchmark exists to show. Do not "optimise" this into an in-process loop.

set -euo pipefail

cd "$(dirname "$0")"

samples=5
while [ $# -gt 0 ]; do
    case "$1" in
        --samples) samples="$2"; shift 2 ;;
        -h|--help) sed -n '2,10p' "$0"; echo "usage: $0 [--samples N]"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

echo "Building (release)…"
swift build -c release >/dev/null
bin=$(swift build -c release --show-bin-path)

# Minimum over the samples, per phase: the fastest run is the one least
# disturbed by other work on the machine.
sample() {
    "${bin}/$1" --json | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(d["types"], d["register"], d["resolve1"], d["resolve2"])
'
}

collect() {
    local target="$1"
    local i
    for ((i = 0; i < samples; i++)); do
        sample "${target}"
    done | python3 -c '
import sys
rows = [list(map(float, line.split())) for line in sys.stdin]
print(int(rows[0][0]), *(min(r[i] for r in rows) for i in (1, 2, 3)))
'
}

echo "Sampling BenchSwinject  (${samples} fresh processes)…"
swinject=$(collect BenchSwinject)
echo "Sampling BenchTSwinject (${samples} fresh processes)…"
tswinject=$(collect BenchTSwinject)

python3 - "$swinject" "$tswinject" <<'PY'
import sys

types, s_reg, s_1, s_2 = (float(x) for x in sys.argv[1].split())
_,     t_reg, t_1, t_2 = (float(x) for x in sys.argv[2].split())
n = int(types)

print()
print(f"{n} unique types, default object scope, best of each phase\n")
head = f"| {'phase':<18} | {'Swinject':>14} | {'TSwinject':>14} | {'speedup':>8} |"
print(head)
print("|" + "-" * 20 + "|" + "-" * 16 + "|" + "-" * 16 + "|" + "-" * 10 + "|")

def row(label, s, t, unit):
    print(f"| {label:<18} | {s / n * 1e6:>11.2f} µs | {t / n * 1e6:>11.2f} µs | {s / t:>7.2f}x |")

row("register", s_reg, t_reg, "registration")
row("resolve #1 (cold)", s_1, t_1, "resolve")
row("resolve #2 (warm)", s_2, t_2, "resolve")
print()
print(f"totals: Swinject  register {s_reg:.4f}s  #1 {s_1:.4f}s  #2 {s_2:.4f}s")
print(f"        TSwinject register {t_reg:.4f}s  #1 {t_1:.4f}s  #2 {t_2:.4f}s")
PY
