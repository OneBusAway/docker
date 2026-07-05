#!/bin/bash

# Unit tests for oba/build_bundle.sh. Sources the script (main guard prevents
# execution) and exercises functions with stub binaries on PATH.
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

echo ""
echo "=============================="
echo "Results: $passed passed, $failed failed"
echo "=============================="
[ "$failed" -eq 0 ]
