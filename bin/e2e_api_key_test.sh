#!/bin/bash

# End-to-end test for the onebusaway-api-key-cli tool.
# Verifies that:
#   1. The server works with the default 'test' key (via bin/validate.sh)
#   2. An unauthorized key is rejected
#   3. A new key can be created via the CLI
#   4. The newly-created key works immediately

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CURL_TIMEOUT=120
API_BASE="http://localhost:8080"
CLI_JAR="/oba/libs/onebusaway-api-key-cli-withAllDependencies.jar"
CLI_DATA_SOURCES="/tmp/cli-data-sources.xml"
TEST_KEY="e2etest$$"
# Use a separate key for the unauthorized test to avoid negative caching
UNAUTH_KEY="bogus_no_such_key_$$"

passed=0
failed=0

pass() {
    echo "PASS: $1"
    passed=$((passed + 1))
}

fail() {
    echo "FAIL: $1"
    failed=$((failed + 1))
}

echo "=== E2E API Key Test ==="
echo ""

# Step 1: Run validate.sh to confirm the server is healthy
echo "--- Step 1: Validate server with default 'test' key ---"
if "$SCRIPT_DIR/validate.sh"; then
    pass "validate.sh passed"
else
    fail "validate.sh failed — server is not healthy"
    echo ""
    echo "=============================="
    echo "Results: $passed passed, $failed failed"
    echo "=============================="
    exit 1
fi
echo ""

# Step 2: Verify an unauthorized key is rejected
# Use a different key than TEST_KEY to avoid negative caching affecting step 4
echo "--- Step 2: Verify unauthorized key is rejected ---"
response=$(curl -s --max-time "$CURL_TIMEOUT" "$API_BASE/api/where/current-time.json?key=$UNAUTH_KEY")
code=$(echo "$response" | jq -r '.code' 2>/dev/null || echo "")
time_val=$(echo "$response" | jq -r '.data.entry.time' 2>/dev/null || echo "")

if [ "$code" = "401" ] || [ -z "$time_val" ] || [ "$time_val" = "null" ]; then
    pass "Unauthorized key '$UNAUTH_KEY' was correctly rejected (code=$code)"
else
    fail "Unauthorized key '$UNAUTH_KEY' was NOT rejected (got time=$time_val, code=$code)"
fi
echo ""

# Step 3: Create a CLI-compatible data-sources.xml and create the key
# The webapp's data-sources.xml uses JNDI, which isn't available outside Tomcat.
# The CLI needs a direct JDBC data source.
echo "--- Step 3: Create API key '$TEST_KEY' via CLI ---"
docker exec oba_app bash -c 'cat > /tmp/cli-data-sources.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<beans xmlns="http://www.springframework.org/schema/beans"
       xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
       xsi:schemaLocation="http://www.springframework.org/schema/beans
         http://www.springframework.org/schema/beans/spring-beans.xsd">
  <bean id="dataSource" class="org.springframework.jdbc.datasource.DriverManagerDataSource">
    <property name="driverClassName" value="com.mysql.cj.jdbc.Driver" />
    <property name="url" value="jdbc:mysql://oba_database:3306/oba_database" />
    <property name="username" value="oba_user" />
    <property name="password" value="oba_password" />
  </bean>
</beans>
EOF'

create_output=$(docker exec oba_app java \
    -jar "$CLI_JAR" create \
    --config "$CLI_DATA_SOURCES" \
    --key "$TEST_KEY" 2>&1) || true
echo "$create_output"

if echo "$create_output" | grep -qi "created\|success"; then
    pass "CLI reported key creation"
else
    echo "  (CLI output was unexpected, but continuing to verify key functionality)"
fi
echo ""

# Step 4: Verify the newly-created key works
echo "--- Step 4: Verify newly-created key works ---"
response=$(curl -s --max-time "$CURL_TIMEOUT" "$API_BASE/api/where/current-time.json?key=$TEST_KEY")
time_val=$(echo "$response" | jq -r '.data.entry.time' 2>/dev/null || echo "")

if [ -n "$time_val" ] && [ "$time_val" != "null" ] && [[ "$time_val" =~ ^[0-9]+$ ]]; then
    pass "Key '$TEST_KEY' works — returned time=$time_val"
else
    fail "Key '$TEST_KEY' does not work after creation (response: $response)"
fi
echo ""

# Step 5: Clean up — delete the test key
echo "--- Step 5: Clean up test key ---"
docker exec oba_app java \
    -jar "$CLI_JAR" delete \
    --config "$CLI_DATA_SOURCES" \
    --key "$TEST_KEY" 2>&1 || true
docker exec oba_app rm -f "$CLI_DATA_SOURCES"
echo "  Cleanup done."

echo ""
echo "=============================="
echo "Results: $passed passed, $failed failed"
echo "=============================="
if [ "$failed" -gt 0 ]; then
    exit 1
fi
