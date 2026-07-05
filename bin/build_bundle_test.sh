#!/bin/bash

# Unit tests for oba/build_bundle.sh. Runs the script as a subprocess
# (run_script; main DOES execute) and exercises functions with stub binaries
# on PATH.
# Style follows bin/e2e_api_key_test.sh (pass/fail counters).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SUT="$REPO_ROOT/oba/build_bundle.sh"

passed=0
failed=0

pass() { echo "PASS: $1"; passed=$((passed + 1)); }
fail() { echo "FAIL: $1"; failed=$((failed + 1)); }

# The harness deliberately runs WITHOUT errexit: failing invocations of the
# script under test are expected and asserted on.

# Run the script as a subprocess with a controlled env.
# usage: run_script <extra PATH dir or ""> [VAR=value ...]
# stdout+stderr -> $RUN_OUTPUT, exit code -> $RUN_STATUS
run_script() {
    local stub_dir="$1"; shift
    local tmp_out
    tmp_out="$(mktemp)"
    local path_prefix=""
    [ -n "$stub_dir" ] && path_prefix="$stub_dir:"
    env -i PATH="${path_prefix}/usr/bin:/bin:/usr/sbin:/sbin" HOME="$HOME" "$@" bash "$SUT" >"$tmp_out" 2>&1
    RUN_STATUS=$?
    RUN_OUTPUT="$(cat "$tmp_out")"
    rm -f "$tmp_out"
}

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if printf '%s' "$haystack" | grep -qF -- "$needle"; then
        pass "$label"
    else
        fail "$label — expected to find: $needle"
        printf 'GOT:\n%s\n' "$haystack"
    fi
}

echo "=== build_bundle.sh unit tests ==="

# --- Mode validation: existing single-mode errors preserved -----------------

run_script "" GTFS_URL=http://x/gtfs.zip GTFS_ZIP_FILENAME=local.zip
[ "$RUN_STATUS" -ne 0 ] && pass "both GTFS_URL and GTFS_ZIP_FILENAME exits nonzero" \
                        || fail "both GTFS_URL and GTFS_ZIP_FILENAME exits nonzero"
assert_contains "$RUN_OUTPUT" "Both GTFS_URL and GTFS_ZIP_FILENAME are set" "both-set error message preserved"

run_script ""
[ "$RUN_STATUS" -ne 0 ] && pass "no mode env exits nonzero" || fail "no mode env exits nonzero"
assert_contains "$RUN_OUTPUT" "Neither GTFS_URL nor GTFS_ZIP_FILENAME is set" "neither-set error message preserved"

# --- Single mode happy path with stubbed binaries ---------------------------

STUBS="$(mktemp -d)"
WORK="$(mktemp -d)"

cat > "$STUBS/wget" <<'EOF'
#!/bin/bash
# stub wget: records argv; creates the -O target
out=""
while [ $# -gt 0 ]; do
    if [ "$1" = "-O" ]; then out="$2"; shift 2; else shift; fi
done
echo "wget $out" >> "$STUB_LOG"
echo "fake-zip" > "$out"
EOF

cat > "$STUBS/gtfstidy" <<'EOF'
#!/bin/bash
echo "gtfstidy $*" >> "$STUB_LOG"
EOF

cat > "$STUBS/java" <<'EOF'
#!/bin/bash
echo "java $*" >> "$STUB_LOG"
echo "cwd $PWD" >> "$STUB_LOG"
EOF

chmod +x "$STUBS/wget" "$STUBS/gtfstidy" "$STUBS/java"

STUB_LOG="$WORK/stub.log"
: > "$STUB_LOG"

run_script "$STUBS" STUB_LOG="$STUB_LOG" BUNDLE_DIR="$WORK" \
    GTFS_URL=http://example.test/gtfs.zip TDF_BUILDER_JAR=/fake/builder.jar OBA_VERSION=test
[ "$RUN_STATUS" -eq 0 ] && pass "single mode (stubbed) exits 0" || fail "single mode (stubbed) exits 0: $RUN_OUTPUT"
assert_contains "$(cat "$STUB_LOG")" "wget $WORK/gtfs_pristine.zip" "single mode downloads to gtfs_pristine.zip"
assert_contains "$(cat "$STUB_LOG")" "gtfstidy" "single mode still runs gtfstidy"
assert_contains "$(cat "$STUB_LOG")" "java -Xss4m -Xmx3g -jar /fake/builder.jar ./gtfs_pristine.zip ." "single mode builder argv unchanged"
assert_contains "$(cat "$STUB_LOG")" "cwd $WORK" "builder runs from bundle dir"

# --- Failed download now aborts (set -e hardening) ---------------------------

cat > "$STUBS/wget" <<'EOF'
#!/bin/bash
exit 8
EOF
chmod +x "$STUBS/wget"

run_script "$STUBS" STUB_LOG="$STUB_LOG" BUNDLE_DIR="$WORK" GTFS_URL=http://example.test/gtfs.zip
[ "$RUN_STATUS" -ne 0 ] && pass "failed GTFS download aborts the build" || fail "failed GTFS download aborts the build"
assert_contains "$RUN_OUTPUT" "ERROR:" "failed download prints an ERROR: line"

rm -rf "$STUBS" "$WORK"

# --- Multi-input mode selection ----------------------------------------------

run_script "" BUNDLE_INPUTS_URL=http://x/bundle-inputs.json GTFS_URL=http://x/gtfs.zip
[ "$RUN_STATUS" -ne 0 ] && pass "BUNDLE_INPUTS_URL + GTFS_URL exits nonzero" || fail "BUNDLE_INPUTS_URL + GTFS_URL exits nonzero"
assert_contains "$RUN_OUTPUT" "BUNDLE_INPUTS_URL cannot be combined" "combined-mode error message"

run_script "" BUNDLE_INPUTS_URL=http://x/bundle-inputs.json GTFS_ZIP_FILENAME=local.zip
[ "$RUN_STATUS" -ne 0 ] && pass "BUNDLE_INPUTS_URL + GTFS_ZIP_FILENAME exits nonzero" || fail "BUNDLE_INPUTS_URL + GTFS_ZIP_FILENAME exits nonzero"

run_script "" BUNDLE_INPUTS_URL=http://x/bundle-inputs.json STOP_CONSOLIDATION_URL=http://x/map.txt
[ "$RUN_STATUS" -ne 0 ] && pass "BUNDLE_INPUTS_URL + STOP_CONSOLIDATION_URL exits nonzero" || fail "BUNDLE_INPUTS_URL + STOP_CONSOLIDATION_URL exits nonzero"
assert_contains "$RUN_OUTPUT" "comes from the manifest" "consolidation-env-in-multi-mode error message"

run_script "" BUNDLE_INPUTS_URL=http://x/bundle-inputs.json
assert_contains "$RUN_OUTPUT" "Multi-input mode" "BUNDLE_INPUTS_URL alone selects multi mode"

# --- download_bundle_inputs ---------------------------------------------------

TESTDATA="$REPO_ROOT/bin/testdata/build_bundle"
STUBS2="$(mktemp -d)"
WORK2="$(mktemp -d)"
SERVE="$(mktemp -d)"

cat > "$STUBS2/wget" <<'EOF'
#!/bin/bash
# stub wget: serves $SERVE/<basename of URL>; 404s (exit 8) when absent
out="" url=""
while [ $# -gt 0 ]; do
    if [ "$1" = "-O" ]; then out="$2"; shift 2; else url="$1"; shift; fi
done
src="$SERVE/$(basename "$url")"
if [ -f "$src" ]; then cp "$src" "$out"; else exit 8; fi
EOF
chmod +x "$STUBS2/wget"

# helper: run a snippet in a subshell that sources the SUT with a controlled env
# usage: run_sourced <snippet> [VAR=value ...]
run_sourced() {
    local snippet="$1"; shift
    local tmp_out; tmp_out="$(mktemp)"
    env -i PATH="$STUBS2:/usr/bin:/bin:/usr/sbin:/sbin" HOME="$HOME" SERVE="$SERVE" "$@" \
        bash -c "source '$SUT'; $snippet" >"$tmp_out" 2>&1
    RUN_STATUS=$?
    RUN_OUTPUT="$(cat "$tmp_out")"
    rm -f "$tmp_out"
}

cp "$TESTDATA/bundle-inputs.json" "$SERVE/bundle-inputs.json"
echo "zipbytes-metro"  > "$SERVE/metro.zip"
echo "zipbytes-pierce" > "$SERVE/pierce.zip"
echo "1_M1 3_P1"       > "$SERVE/StopConsolidation.txt"

run_sourced "download_bundle_inputs && echo MAPPING=\$MAPPING_PATH" \
    BUNDLE_DIR="$WORK2" BUNDLE_INPUTS_URL=http://fixtures.test/bundle-inputs.json
[ "$RUN_STATUS" -eq 0 ] && pass "download_bundle_inputs succeeds" || fail "download_bundle_inputs succeeds: $RUN_OUTPUT"
[ -f "$WORK2/inputs/metro.zip" ]  && pass "metro.zip downloaded"  || fail "metro.zip downloaded"
[ -f "$WORK2/inputs/pierce.zip" ] && pass "pierce.zip downloaded" || fail "pierce.zip downloaded"
[ -f "$WORK2/StopConsolidation.txt" ] && pass "mapping downloaded to StopConsolidation.txt" || fail "mapping downloaded to StopConsolidation.txt"
assert_contains "$RUN_OUTPUT" "MAPPING=$WORK2/StopConsolidation.txt" "MAPPING_PATH set"

# no-mapping manifest → MAPPING_PATH empty
rm -rf "$WORK2"; WORK2="$(mktemp -d)"
cp "$TESTDATA/bundle-inputs-no-mapping.json" "$SERVE/bundle-inputs.json"
run_sourced "download_bundle_inputs && echo MAPPING=[\$MAPPING_PATH]" \
    BUNDLE_DIR="$WORK2" BUNDLE_INPUTS_URL=http://fixtures.test/bundle-inputs.json
assert_contains "$RUN_OUTPUT" "MAPPING=[]" "no stopConsolidationUrl -> empty MAPPING_PATH"
[ ! -e "$WORK2/StopConsolidation.txt" ] && pass "no mapping file created" || fail "no mapping file created"

# unsupported version
rm -rf "$WORK2"; WORK2="$(mktemp -d)"
echo '{"version": 2, "feeds": []}' > "$SERVE/bundle-inputs.json"
run_sourced "download_bundle_inputs" BUNDLE_DIR="$WORK2" BUNDLE_INPUTS_URL=http://fixtures.test/bundle-inputs.json
[ "$RUN_STATUS" -ne 0 ] && pass "unsupported manifest version fails" || fail "unsupported manifest version fails"
assert_contains "$RUN_OUTPUT" "ERROR: unsupported bundle-inputs version" "version error message"

# empty feeds
echo '{"version": 1, "feeds": []}' > "$SERVE/bundle-inputs.json"
run_sourced "download_bundle_inputs" BUNDLE_DIR="$WORK2" BUNDLE_INPUTS_URL=http://fixtures.test/bundle-inputs.json
[ "$RUN_STATUS" -ne 0 ] && pass "empty feeds fails" || fail "empty feeds fails"
assert_contains "$RUN_OUTPUT" "ERROR: bundle-inputs manifest lists no feeds" "empty-feeds error message"

# missing feed zip → ERROR naming the feed
cp "$TESTDATA/bundle-inputs.json" "$SERVE/bundle-inputs.json"
rm -f "$SERVE/pierce.zip"
run_sourced "download_bundle_inputs" BUNDLE_DIR="$WORK2" BUNDLE_INPUTS_URL=http://fixtures.test/bundle-inputs.json
[ "$RUN_STATUS" -ne 0 ] && pass "missing feed download fails" || fail "missing feed download fails"
assert_contains "$RUN_OUTPUT" "ERROR: failed to download feed 'pierce'" "feed download error names the feed"
echo "zipbytes-pierce" > "$SERVE/pierce.zip"

# sha256 mismatch → ERROR naming the feed
rm -rf "$WORK2"; WORK2="$(mktemp -d)"
python3 - "$TESTDATA/bundle-inputs.json" "$SERVE/bundle-inputs.json" <<'EOF'
import json, sys
m = json.load(open(sys.argv[1]))
m["feeds"][0]["sha256"] = "0" * 64
json.dump(m, open(sys.argv[2], "w"))
EOF
run_sourced "download_bundle_inputs" BUNDLE_DIR="$WORK2" BUNDLE_INPUTS_URL=http://fixtures.test/bundle-inputs.json
[ "$RUN_STATUS" -ne 0 ] && pass "sha256 mismatch fails" || fail "sha256 mismatch fails"
assert_contains "$RUN_OUTPUT" "ERROR: sha256 mismatch for feed 'metro'" "sha mismatch error names the feed"

# sha256 match succeeds
GOOD_SHA="$(sha256sum "$SERVE/metro.zip" | cut -d' ' -f1)"
python3 - "$TESTDATA/bundle-inputs.json" "$SERVE/bundle-inputs.json" "$GOOD_SHA" <<'EOF'
import json, sys
m = json.load(open(sys.argv[1]))
m["feeds"][0]["sha256"] = sys.argv[3]
json.dump(m, open(sys.argv[2], "w"))
EOF
rm -rf "$WORK2"; WORK2="$(mktemp -d)"
run_sourced "download_bundle_inputs" BUNDLE_DIR="$WORK2" BUNDLE_INPUTS_URL=http://fixtures.test/bundle-inputs.json
[ "$RUN_STATUS" -eq 0 ] && pass "matching sha256 passes" || fail "matching sha256 passes: $RUN_OUTPUT"

rm -rf "$WORK2"
# NOTE: $STUBS2 and $SERVE are intentionally NOT removed here — Task 4's tests
# reuse run_sourced (which references $STUBS2 in PATH). Cleanup happens at the
# end of the file once all sourced-function tests are done.

# --- generate_bundle_context_xml ----------------------------------------------

WORK3="$(mktemp -d)"
mkdir -p "$WORK3/inputs"
cp "$TESTDATA/bundle-inputs.json" "$WORK3/inputs/bundle-inputs.json"

run_sourced "generate_bundle_context_xml '$WORK3/inputs/bundle-inputs.json' '$WORK3/inputs' '$WORK3/StopConsolidation.txt' '$WORK3/bundle-context.xml'" \
    BUNDLE_DIR="$WORK3"
[ "$RUN_STATUS" -eq 0 ] && pass "xml generation (with mapping) succeeds" || fail "xml generation (with mapping) succeeds: $RUN_OUTPUT"

sed -e "s|@INPUTS@|$WORK3/inputs|g" -e "s|@MAPPING@|$WORK3/StopConsolidation.txt|g" \
    "$TESTDATA/golden-context-with-mapping.xml" > "$WORK3/expected.xml"
if diff -u "$WORK3/expected.xml" "$WORK3/bundle-context.xml"; then
    pass "context XML matches golden (with mapping)"
else
    fail "context XML matches golden (with mapping)"
fi

run_sourced "generate_bundle_context_xml '$WORK3/inputs/bundle-inputs.json' '$WORK3/inputs' '' '$WORK3/bundle-context-nm.xml'" \
    BUNDLE_DIR="$WORK3"
sed -e "s|@INPUTS@|$WORK3/inputs|g" "$TESTDATA/golden-context-no-mapping.xml" > "$WORK3/expected-nm.xml"
if diff -u "$WORK3/expected-nm.xml" "$WORK3/bundle-context-nm.xml"; then
    pass "context XML matches golden (no mapping)"
else
    fail "context XML matches golden (no mapping)"
fi

rm -rf "$WORK3"

echo ""
echo "=============================="
echo "Results: $passed passed, $failed failed"
echo "=============================="
[ "$failed" -eq 0 ]
