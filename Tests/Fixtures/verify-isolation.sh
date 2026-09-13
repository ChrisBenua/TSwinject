#!/usr/bin/env bash
#
# Guards the core library's "no dependencies" promise.
#
# TSwinject's manifest declares Swinject (for the interop product) and
# swift-syntax (for the macro plugin). SwiftPM *resolves and checks out* both
# for anyone who depends on this package, even a consumer that only imports the
# TSwinject product — they will show up in that consumer's Package.resolved.
# That is a disk and fetch cost, and it is unavoidable while all three products
# live in one package.
#
# What must never happen is either dependency being *compiled* into a core-only
# consumer. That is the real invariant, and it is what this script checks: build
# a consumer that imports TSwinject alone, then assert no object files were
# produced for Swinject or swift-syntax.
#
# If this fails, the core target has grown a dependency edge it should not have.

set -euo pipefail

cd "$(dirname "$0")/CoreOnlyConsumer"

rm -rf .build Package.resolved
swift build

BUILD_DIR=$(swift build --show-bin-path)
status=0

for forbidden in Swinject SwiftSyntax; do
    # TSwinject.build would match "Swinject" as a substring; exclude it.
    count=$(find "${BUILD_DIR}" -name '*.o' -path "*${forbidden}*" \
        -not -path '*TSwinject*' 2>/dev/null | wc -l | tr -d ' ')
    if [ "${count}" != "0" ]; then
        echo "FAIL: ${count} ${forbidden} object file(s) compiled into a core-only consumer" >&2
        status=1
    fi
done

# Sanity check: the core itself really was built, so a green run means something.
core=$(find "${BUILD_DIR}" -name '*.o' -path '*TSwinject.build*' | wc -l | tr -d ' ')
if [ "${core}" = "0" ]; then
    echo "FAIL: TSwinject itself did not compile — this check proves nothing" >&2
    status=1
fi

if [ "${status}" = "0" ]; then
    echo "OK: core-only consumer compiled ${core} TSwinject objects, 0 from Swinject/swift-syntax"
fi

exit "${status}"
