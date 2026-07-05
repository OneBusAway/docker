#!/bin/bash
# Integration test: runs the REAL federation builder inside the built oba image
# in multi-input mode against fixture feeds. Requires: docker, python3, an
# `oba-image:latest` local image (build with:
#   docker buildx build --load -t oba-image:latest ./oba ).
# Linux-first (uses --network host for the fixture HTTP server); on macOS run
# in CI instead.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
IMAGE="${OBA_IMAGE:-oba-image:latest}"
PORT=8123

passed=0
failed=0
pass() { echo "PASS: $1"; passed=$((passed + 1)); }
fail() { echo "FAIL: $1"; failed=$((failed + 1)); }

SERVE="$(mktemp -d)"
OUT_VALID="$(mktemp -d)"
OUT_KM="$(mktemp -d)"

bash "$REPO_ROOT/bin/testdata/build_bundle/make_fixtures.sh" "$SERVE"
cp "$REPO_ROOT/bin/testdata/build_bundle/mapping-valid.txt" "$SERVE/StopConsolidation.txt"

cat > "$SERVE/bundle-inputs.json" <<EOF
{
  "version": 1,
  "feeds": [
    {"id": "metro", "name": "King County Metro", "defaultAgencyId": "1", "url": "http://127.0.0.1:${PORT}/metro.zip"},
    {"id": "pierce", "name": "Pierce Transit", "defaultAgencyId": "3", "url": "http://127.0.0.1:${PORT}/pierce.zip"}
  ],
  "stopConsolidationUrl": "http://127.0.0.1:${PORT}/StopConsolidation.txt"
}
EOF

python3 -m http.server "$PORT" --directory "$SERVE" >/dev/null 2>&1 &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null; rm -rf "$SERVE" "$OUT_VALID" "$OUT_KM"' EXIT
sleep 1

run_build() {
    # --user matches the host user so the mounted output dir stays deletable
    # by the test's cleanup trap (files written as root would survive rm -rf
    # on CI runners).
    local out_dir="$1"
    docker run --rm --network host \
        --user "$(id -u):$(id -g)" \
        -v "$out_dir":/bundle \
        -e BUNDLE_INPUTS_URL="http://127.0.0.1:${PORT}/bundle-inputs.json" \
        --entrypoint bash \
        "$IMAGE" /oba/build_bundle.sh
}

echo "--- Valid mapping build ---"
if run_build "$OUT_VALID" > "$OUT_VALID/build.log" 2>&1; then
    pass "multi-input build with mapping exits 0"
else
    fail "multi-input build with mapping exits 0"
    tail -50 "$OUT_VALID/build.log"
fi

[ -f "$OUT_VALID/TransitGraph.obj" ] && pass "bundle artifact TransitGraph.obj built" || fail "bundle artifact TransitGraph.obj built"
[ -f "$OUT_VALID/StopConsolidation.txt" ] && pass "StopConsolidation.txt in bundle output" || fail "StopConsolidation.txt in bundle output"
grep -q "gtfs=/bundle/inputs/metro.zip"  "$OUT_VALID/build.log" && pass "metro loaded as its own bundle"  || fail "metro loaded as its own bundle"
grep -q "gtfs=/bundle/inputs/pierce.zip" "$OUT_VALID/build.log" && pass "pierce loaded as its own bundle" || fail "pierce loaded as its own bundle"

# Replaced stop is gone, keeper survives. TransitGraph.obj is one continuous
# Java serialization stream (TC_STRING tag + 2-byte length prefix + bytes,
# no line terminator), so `strings` glues "M2" to whatever stream token
# follows (observed: "M2pq") and an anchored `^M2$` line match is flaky —
# it happened to pass for the absence check and fail for the presence
# check on the same file. A direct byte-level substring grep on the raw
# file is reliable here because M2/P2 are short, unique 2-character ids
# that cannot occur elsewhere in the bundle's ASCII content (confirmed via
# `grep -aob "M2" TransitGraph.obj`: the sole hit is immediately preceded by
# the TC_STRING tag and a length=2 prefix, i.e. it is the serialized stop id
# field, not a coincidental substring).
grep -qa "P2" "$OUT_VALID/TransitGraph.obj" \
    && fail "replaced stop P2 absent from TransitGraph.obj" \
    || pass "replaced stop P2 absent from TransitGraph.obj"
grep -qa "M2" "$OUT_VALID/TransitGraph.obj" && pass "keeper M2 present in TransitGraph.obj" || fail "keeper M2 present in TransitGraph.obj"

echo "--- Keeper-missing mapping build (behavior pin) ---"
cp "$REPO_ROOT/bin/testdata/build_bundle/mapping-keeper-missing.txt" "$SERVE/StopConsolidation.txt"
set +e
run_build "$OUT_KM" > "$OUT_KM/build.log" 2>&1
KM_STATUS=$?
set -e
# Pin the observed behavior. "error replacing entity ... replacement not
# found" (hypothesized from reading app-modules source while writing this
# plan) does not appear against the real 2.7.1 builder jar — running this
# test is what surfaced that. What actually happens, verified by running
# it: the replaced stop (3_P2) is dropped from the graph exactly as in the
# valid-mapping build above, but nothing repoints the stopTime row that
# referenced it, so StopTimeEntriesFactory logs an ERROR for a stopTime
# with a null stop. That dangling reference — not a clean "replacement not
# found" warning — is the concrete harm that justifies obacloud excluding
# keeper-missing rows at publish.
grep -q "found stopTime without a stop id" "$OUT_KM/build.log" \
    && pass "keeper-missing line produces a dangling stopTime error" \
    || fail "keeper-missing line produces a dangling stopTime error"
grep -qa "P2" "$OUT_KM/TransitGraph.obj" \
    && fail "keeper-missing replaced stop P2 still absent from TransitGraph.obj" \
    || pass "keeper-missing replaced stop P2 still absent from TransitGraph.obj"
echo "keeper-missing build exit status: $KM_STATUS (recorded, not asserted — obacloud excludes such rows at publish)"

echo ""
echo "=============================="
echo "Results: $passed passed, $failed failed"
echo "=============================="
[ "$failed" -eq 0 ]
