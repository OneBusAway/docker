# Multiple GTFS-RT Feeds — Docker Image Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Teach the `onebusaway/docker` image to render one `GtfsRealtimeSource` Spring bean per feed from a new `GTFS_RT_FEEDS` JSON env var, while keeping the legacy single-feed env vars working.

**Architecture:** A new `GTFS_RT_FEEDS` env var carries a JSON array of feed objects. `bootstrap.sh` prefers it; when it's unset it normalizes the legacy single-feed vars (`TRIP_UPDATES_URL`, etc.) into a one-element array. Either way it hands `{ "FEEDS": [...] }` to the Go/raymond Handlebars renderer, and the data-sources template iterates with `{{#each FEEDS}}` to emit one bean per feed.

**Tech Stack:** Bash, Handlebars (Go `github.com/mailgun/raymond/v2`), Go test, GitHub Actions.

> **⚠️ This plan operates in a DIFFERENT repository:** `/Users/aaron/repos/onebusaway/docker` (not the obacloud repo this plan file lives in). All paths below are relative to that repo. `cd /Users/aaron/repos/onebusaway/docker` before starting, and make all commits there.

> **⚠️ Ship order:** This plan must merge AND be released (so `2.7.1-latest` is re-published with these changes) BEFORE the OBACloud plan ships. See the spec's "Backward compatibility & ship sequencing" section. The legacy-normalization path is exercised by every existing deployment on its next rebuild, which is why it has its own test below.

**Reference spec:** `docs/superpowers/specs/2026-05-23-multi-gtfs-rt-feeds-design.md` (in the obacloud repo).

---

## File Structure

- **Modify** `oba/config/onebusaway-transit-data-federation-webapp-data-sources.xml.hbs` — wrap the single `GtfsRealtimeSource` bean in `{{#each FEEDS}}`.
- **Modify** `oba/config/template_renderer/main_test.go` — add tests that render the real federation template against `FEEDS` JSON.
- **Modify** `oba/bootstrap.sh` — build the `FEEDS` array (prefer `GTFS_RT_FEEDS`, else normalize legacy vars).
- **Modify** `.github/workflows/test.yaml` — add a `go test` step so the renderer tests run in CI.
- **Modify** `README.md` — document `GTFS_RT_FEEDS`.

---

## Task 1: Multi-feed Handlebars template (TDD via Go test)

**Files:**
- Test: `oba/config/template_renderer/main_test.go`
- Modify: `oba/config/onebusaway-transit-data-federation-webapp-data-sources.xml.hbs`

- [ ] **Step 1: Write failing Go tests that render the real federation template**

Append to `oba/config/template_renderer/main_test.go` (the package is `main`, so `renderTemplate` is directly callable; the template lives one directory up):

```go
func TestFederationTemplateMultipleFeeds(t *testing.T) {
	tmpl := "../onebusaway-transit-data-federation-webapp-data-sources.xml.hbs"
	json := `{"FEEDS":[` +
		`{"tripUpdatesUrl":"https://a/trips","agencyIds":["unitrans"],"feedApiKey":"x-key","feedApiValue":"secret"},` +
		`{"vehiclePositionsUrl":"https://b/vehicles","agencyIds":["kcm"]}` +
		`]}`

	out, err := renderTemplate(tmpl, json)
	if err != nil {
		t.Fatalf("renderTemplate returned an error: %v", err)
	}
	if c := strings.Count(out, "GtfsRealtimeSource"); c != 2 {
		t.Errorf("expected 2 GtfsRealtimeSource beans, got %d\n%s", c, out)
	}
	if !strings.Contains(out, `value="https://a/trips"`) {
		t.Errorf("missing first feed tripUpdatesUrl:\n%s", out)
	}
	if !strings.Contains(out, `value="https://b/vehicles"`) {
		t.Errorf("missing second feed vehiclePositionsUrl:\n%s", out)
	}
	if !strings.Contains(out, `<value>unitrans</value>`) || !strings.Contains(out, `<value>kcm</value>`) {
		t.Errorf("missing per-feed agencyIds:\n%s", out)
	}
	if !strings.Contains(out, `<entry key="x-key" value="secret"`) {
		t.Errorf("missing first feed headersMap:\n%s", out)
	}
}

func TestFederationTemplateNoFeeds(t *testing.T) {
	tmpl := "../onebusaway-transit-data-federation-webapp-data-sources.xml.hbs"
	out, err := renderTemplate(tmpl, `{"FEEDS":[]}`)
	if err != nil {
		t.Fatalf("renderTemplate returned an error: %v", err)
	}
	if strings.Contains(out, "GtfsRealtimeSource") {
		t.Errorf("expected 0 beans for empty FEEDS, got:\n%s", out)
	}
}

func TestFederationTemplateLegacyNormalizedFeed(t *testing.T) {
	// Exactly the one-element array bootstrap.sh builds from the legacy
	// single-feed env vars. Blank feedApiKey must produce no headersMap.
	tmpl := "../onebusaway-transit-data-federation-webapp-data-sources.xml.hbs"
	json := `{"FEEDS":[{"tripUpdatesUrl":"https://a/trips","vehiclePositionsUrl":"https://a/veh",` +
		`"alertsUrl":"https://a/alerts","refreshInterval":"30","agencyIds":["unitrans"],` +
		`"feedApiKey":"","feedApiValue":""}]}`

	out, err := renderTemplate(tmpl, json)
	if err != nil {
		t.Fatalf("renderTemplate returned an error: %v", err)
	}
	if c := strings.Count(out, "GtfsRealtimeSource"); c != 1 {
		t.Errorf("expected 1 bean, got %d\n%s", c, out)
	}
	if !strings.Contains(out, `value="30"`) {
		t.Errorf("missing refreshInterval:\n%s", out)
	}
	if strings.Contains(out, "headersMap") {
		t.Errorf("blank feedApiKey should produce no headersMap:\n%s", out)
	}
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `cd /Users/aaron/repos/onebusaway/docker/oba/config/template_renderer && go test ./...`
Expected: FAIL — the current template uses `{{#if GTFS_RT_AVAILABLE}}` and top-level vars, so with `FEEDS` JSON it renders **0** beans (`TestFederationTemplateMultipleFeeds` expects 2).

- [ ] **Step 3: Rewrite the GTFS-RT block in the template to iterate FEEDS**

In `oba/config/onebusaway-transit-data-federation-webapp-data-sources.xml.hbs`, replace the entire block from the `<!-- GTFS-RT related beans... -->` comment through its closing `{{/if}}` (currently lines 48–87) with:

```hbs
  <!-- GTFS-RT related beans, automatically populated by `bootstrap.sh` -->
  {{#if FEEDS.length}}
    {{#each FEEDS}}
      <bean class="org.onebusaway.transit_data_federation.impl.realtime.gtfs_realtime.GtfsRealtimeSource">
        {{#if this.tripUpdatesUrl}}
          <property name="tripUpdatesUrl" value="{{ this.tripUpdatesUrl }}" />
        {{/if}}

        {{#if this.vehiclePositionsUrl}}
          <property name="vehiclePositionsUrl" value="{{ this.vehiclePositionsUrl }}" />
        {{/if}}

        {{#if this.alertsUrl}}
          <property name="alertsUrl" value="{{ this.alertsUrl }}" />
        {{/if}}

        {{#if this.refreshInterval}}
          <property name="refreshInterval" value="{{ this.refreshInterval }}" />
        {{/if}}

        {{#if this.agencyIds.length}}
          <property name="agencyIds">
            <list>
              {{#each this.agencyIds}}
                <value>{{ this }}</value>
              {{/each}}
            </list>
          </property>
        {{else if this.agencyId}}
          <property name="agencyId" value="{{ this.agencyId }}" />
        {{/if}}

        {{#if this.feedApiKey}}
          <property name="headersMap">
            <map>
              <entry key="{{ this.feedApiKey }}" value="{{ this.feedApiValue }}" />
            </map>
          </property>
        {{/if}}
      </bean>
    {{/each}}
  {{/if}}
```

(Leave the surrounding `<beans>…</beans>` and the other static beans untouched.)

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `cd /Users/aaron/repos/onebusaway/docker/oba/config/template_renderer && go test ./...`
Expected: PASS (all three new tests plus the existing ones).

- [ ] **Step 5: Commit**

```bash
cd /Users/aaron/repos/onebusaway/docker
git add oba/config/onebusaway-transit-data-federation-webapp-data-sources.xml.hbs oba/config/template_renderer/main_test.go
git commit -m "feat: render one GtfsRealtimeSource bean per feed via FEEDS array"
```

---

## Task 2: bootstrap.sh builds the FEEDS array

**Files:**
- Modify: `oba/bootstrap.sh`

- [ ] **Step 1: Replace the single-feed JSON_CONFIG block**

In `oba/bootstrap.sh`, replace everything from the comment `# Check if the GTFS_RT authentication header is set` through the `hbs_renderer ... "$FEDERATION_XML_DESTINATION"` invocation for the federation webapp (currently lines ~42–76, i.e. the `HAS_API_KEY` / `AGENCY_ID_LIST_JSON` / `JSON_CONFIG` logic and the federation render call) with:

```bash
# Build the FEEDS array for the transit-data-federation data-sources.xml.
# Prefer the multi-feed GTFS_RT_FEEDS env var; fall back to the legacy
# single-feed vars so already-deployed Dockerfiles keep working.
if [ -n "$GTFS_RT_FEEDS" ] && [ "$GTFS_RT_FEEDS" != "[]" ]; then
    FEEDS_JSON="$GTFS_RT_FEEDS"
    echo "GTFS_RT_FEEDS is set. Rendering multiple GTFS-RT feeds."
elif [ -n "$TRIP_UPDATES_URL" ] || [ -n "$VEHICLE_POSITIONS_URL" ]; then
    echo "Legacy single-feed GTFS-RT env vars are set. Normalizing into one feed."
    if [ -n "$AGENCY_ID_LIST" ]; then
        AGENCY_IDS_JSON="$AGENCY_ID_LIST"
    elif [ -n "$AGENCY_ID" ]; then
        AGENCY_IDS_JSON="[\"$AGENCY_ID\"]"
    else
        AGENCY_IDS_JSON="[]"
    fi
    FEEDS_JSON=$(cat <<EOF
[{
  "tripUpdatesUrl": "$TRIP_UPDATES_URL",
  "vehiclePositionsUrl": "$VEHICLE_POSITIONS_URL",
  "alertsUrl": "$ALERTS_URL",
  "refreshInterval": "$REFRESH_INTERVAL",
  "agencyIds": $AGENCY_IDS_JSON,
  "feedApiKey": "$FEED_API_KEY",
  "feedApiValue": "$FEED_API_VALUE"
}]
EOF
)
else
    FEEDS_JSON="[]"
    echo "No GTFS-RT environment variables are set. No realtime feeds will be configured."
fi

JSON_CONFIG="{ \"FEEDS\": $FEEDS_JSON }"

hbs_renderer -input "$FEDERATION_XML_SOURCE" \
             -json "$JSON_CONFIG" \
             -output "$FEDERATION_XML_DESTINATION"
```

Keep the `FEDERATION_XML_SOURCE` / `FEDERATION_XML_DESTINATION` assignments above this block as-is, and leave the api-webapp and context.xml render calls untouched.

- [ ] **Step 2: Smoke-test both paths with the real renderer**

Run (multi-feed path):

```bash
cd /Users/aaron/repos/onebusaway/docker/oba/config/template_renderer
GTFS_RT_FEEDS='[{"tripUpdatesUrl":"https://a/trips","agencyIds":["unitrans"]},{"vehiclePositionsUrl":"https://b/veh","agencyIds":["kcm"]}]'
go run . -input ../onebusaway-transit-data-federation-webapp-data-sources.xml.hbs -json "{ \"FEEDS\": $GTFS_RT_FEEDS }"
```
Expected: output contains **two** `GtfsRealtimeSource` beans, one with `value="https://a/trips"` and one with `value="https://b/veh"`.

Run (legacy path — simulate bootstrap's normalization, no `GTFS_RT_FEEDS`):

```bash
cd /Users/aaron/repos/onebusaway/docker/oba/config/template_renderer
TRIP_UPDATES_URL="https://a/trips"; VEHICLE_POSITIONS_URL=""; ALERTS_URL=""
REFRESH_INTERVAL="30"; AGENCY_ID_LIST='["unitrans"]'; FEED_API_KEY=""; FEED_API_VALUE=""
AGENCY_IDS_JSON="$AGENCY_ID_LIST"
FEEDS_JSON="[{\"tripUpdatesUrl\":\"$TRIP_UPDATES_URL\",\"vehiclePositionsUrl\":\"$VEHICLE_POSITIONS_URL\",\"alertsUrl\":\"$ALERTS_URL\",\"refreshInterval\":\"$REFRESH_INTERVAL\",\"agencyIds\":$AGENCY_IDS_JSON,\"feedApiKey\":\"$FEED_API_KEY\",\"feedApiValue\":\"$FEED_API_VALUE\"}]"
go run . -input ../onebusaway-transit-data-federation-webapp-data-sources.xml.hbs -json "{ \"FEEDS\": $FEEDS_JSON }"
```
Expected: output contains **one** `GtfsRealtimeSource` bean with `value="https://a/trips"`, `value="30"`, a `<value>unitrans</value>`, and **no** `headersMap`.

- [ ] **Step 3: Commit**

```bash
cd /Users/aaron/repos/onebusaway/docker
git add oba/bootstrap.sh
git commit -m "feat: bootstrap builds FEEDS array (GTFS_RT_FEEDS or legacy fallback)"
```

---

## Task 3: Run the renderer tests in CI

**Files:**
- Modify: `.github/workflows/test.yaml`

- [ ] **Step 1: Add a Go test job**

In `.github/workflows/test.yaml`, add this job under `jobs:` (sibling to `image:`):

```yaml
  renderer:
    name: Template renderer tests
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Go
        uses: actions/setup-go@v5
        with:
          go-version: "1.22"

      - name: Run renderer tests
        working-directory: oba/config/template_renderer
        run: go test ./...
```

- [ ] **Step 2: Verify the command the CI step runs passes locally**

Run: `cd /Users/aaron/repos/onebusaway/docker/oba/config/template_renderer && go test ./...`
Expected: PASS (this is the exact command CI will run).

- [ ] **Step 3: Commit**

```bash
cd /Users/aaron/repos/onebusaway/docker
git add .github/workflows/test.yaml
git commit -m "ci: run template_renderer go tests"
```

---

## Task 4: Document GTFS_RT_FEEDS in the README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add the multi-feed env var to the GTFS-RT section**

In `README.md`, in the `* GTFS-RT Support (Optional)` list (currently lines ~101–113), add a new bullet immediately under the `* TZ ...` line:

```markdown
  * `GTFS_RT_FEEDS` - Preferred for configuring one OR many GTFS-RT feeds. A JSON array of feed objects; each object may contain `tripUpdatesUrl`, `vehiclePositionsUrl`, `alertsUrl`, `refreshInterval`, `agencyIds` (array), `feedApiKey`, and `feedApiValue`. Example: `[{"tripUpdatesUrl":"https://a/trips","agencyIds":["unitrans"]},{"vehiclePositionsUrl":"https://b/veh","agencyIds":["kcm"]}]`. When set, it takes precedence over the single-feed variables below.
  * The following single-feed variables remain supported (and are normalized into one feed when `GTFS_RT_FEEDS` is not set):
```

(The existing `ALERTS_URL` / `TRIP_UPDATES_URL` / etc. bullets stay as the nested "single-feed variables" list.)

- [ ] **Step 2: Commit**

```bash
cd /Users/aaron/repos/onebusaway/docker
git add README.md
git commit -m "docs: document GTFS_RT_FEEDS multi-feed env var"
```

---

## Self-Review (completed during planning)

- **Spec coverage:** template loop (Task 1), bootstrap legacy-compat (Task 2), Go test + CI gap I1 (Tasks 1 & 3), README (Task 4). The compose e2e extension is optional in the spec and omitted here (the Go tests cover render correctness; the existing e2e covers startup).
- **Placeholder scan:** none — every step has complete code/commands.
- **Consistency:** the JSON key names (`tripUpdatesUrl`, `agencyIds`, `feedApiKey`, …) match the spec contract and the OBACloud generator output in the sibling plan.
- **raymond support:** `{{#each}}`, `{{this.prop}}`, `{{#if x.length}}`, `{{else if}}` confirmed (spec §template, verified by running raymond v2.0.48).
