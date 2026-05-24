# Multiple GTFS-RT Feeds in the Dockerfile Config — Design

## Goal

The "Edit Dockerfile Config" modal currently supports exactly one set of GTFS-RT feed URLs (trip updates, vehicle positions, alerts) plus one refresh interval, agency-ID list, and API-key header. OneBusAway itself supports many realtime feeds — each is a separate `GtfsRealtimeSource` Spring bean — so the limitation is purely in OBACloud's UI/generator and in the docker image's bootstrap/template, not in OneBusAway.

This work lets an organization configure **N** GTFS-RT feed sets. It spans two repos:

1. **`onebusaway/docker`** (`/Users/aaron/repos/onebusaway/docker`) — teach the image to render one `GtfsRealtimeSource` bean per feed, driven by a new `GTFS_RT_FEEDS` env var, **while keeping the existing single-feed env vars working** (additive, non-breaking).
2. **`obacloud`** — replace `DockerfileConfig`'s flat single-feed fields with a `feeds` array, add an accordion editor to manage feeds, emit the `GTFS_RT_FEEDS` env var, and update the **service wizard** (which also writes the flat fields today) to produce a single `feeds[0]` during onboarding.

## Decisions

| Question | Decision |
|---|---|
| Does the docker image support multiple feeds today? | **No.** `bootstrap.sh` reads single env vars and the Handlebars template renders exactly one `<bean>`. OneBusAway *can* hold many `GtfsRealtimeSource` beans, so the fix is in the image's bootstrap + template, not in OneBusAway. |
| Cross-repo contract | **Single JSON env var `GTFS_RT_FEEDS`** carrying an array of feed objects. Matches the existing `AGENCY_ID_LIST`-as-JSON convention; the template iterates with `{{#each FEEDS}}`; no per-field shell loops. |
| Docker backward compatibility | **Additive.** The legacy single-feed env vars (`TRIP_UPDATES_URL`, `VEHICLE_POSITIONS_URL`, `ALERTS_URL`, `REFRESH_INTERVAL`, `AGENCY_ID`, `AGENCY_ID_LIST`, `FEED_API_KEY`, `FEED_API_VALUE`) keep working. When `GTFS_RT_FEEDS` is unset, `bootstrap.sh` normalizes the legacy vars into a one-element `FEEDS` array, so the template has a single code path and every already-deployed Dockerfile keeps building untouched. |
| OBACloud data model | **Clean `feeds` array.** Replace the flat single-feed attributes on `DockerfileConfig` with `attribute :feeds, GtfsRtFeed.to_array_type`. A one-time backfill migration copies any existing flat values into `feeds[0]` so nothing is lost. |
| Agency ID format | **Unchanged.** The per-feed "Agency ID List" field still takes a JSON array string (e.g. `["unitrans"]`), exactly like today. The generator parses it into the `agencyIds` array inside the feed object. No UX change. |
| Editor UI | **Accordion.** Each feed is a collapsible panel (`CollapsibleCardComponent` / `disclosure` controller) summarized by its label (or "Feed N"); "Add feed" / "Remove" via a Stimulus controller modeled on the existing `rt_feeds_controller.js`. |
| Feed label | **OBACloud-only metadata.** Optional; shown in the accordion header and stored on the feed, but **not** emitted to `GTFS_RT_FEEDS` (the image has no use for it). |
| Existing production usage | **Greenfield / negligible.** The JSONB column landed ~6 weeks ago; the backfill migration is a safety net rather than a migration of meaningful volume. |
| Service wizard | **In scope.** `ServiceWizards::SaveConfigStep` and the wizard's `config_params` also write the flat feed fields; both are updated to build a single `feeds[0]`. Onboarding stays single-feed in the UI. |
| Feed-level validation | **`validates :feeds, store_model: { merge_errors: true }`** on `DockerfileConfig`, so child feed errors actually surface — without it the single-quote safety never runs. |
| Refresh interval | **Validated numeric** per feed (`numericality: integer > 0`), closing a pre-existing gap where `"abc"` would render invalid Spring XML. |

## The contract: `GTFS_RT_FEEDS`

A single Dockerfile line, single-quoted to match the existing `AGENCY_ID_LIST` convention:

```dockerfile
ENV GTFS_RT_FEEDS='[{"tripUpdatesUrl":"https://a/trips","vehiclePositionsUrl":"https://a/vehicles","alertsUrl":"https://a/alerts","refreshInterval":"30","agencyIds":["unitrans"],"feedApiKey":"x-api-key","feedApiValue":"secret"},{"tripUpdatesUrl":"https://b/trips","agencyIds":["kcm"]}]'
```

Per-feed object keys (all optional; a feed needs at least one URL to be useful):

| JSON key | Source field | Bean property |
|---|---|---|
| `tripUpdatesUrl` | `trip_updates_url` | `tripUpdatesUrl` |
| `vehiclePositionsUrl` | `vehicle_positions_url` | `vehiclePositionsUrl` |
| `alertsUrl` | `alerts_url` | `alertsUrl` |
| `refreshInterval` | `refresh_interval` | `refreshInterval` |
| `agencyIds` | `agency_id_list` (JSON array string, parsed) | `agencyIds` → `<list>` |
| `feedApiKey` | `feed_api_key` | `headersMap` entry key |
| `feedApiValue` | `feed_api_value` | `headersMap` entry value |

`label` is **not** present in the contract. When zero feeds are configured, the `GTFS_RT_FEEDS` line is omitted entirely and no GTFS-RT beans are rendered (matching today's "GTFS-RT optional" behavior).

## Architecture

```
OBACloud accordion editor
  │  (global: base_image, timezone · repeatable feeds)
  ▼
DockerfileConfig.feeds  ── GtfsRtFeed StoreModel array, persisted in existing JSONB column
  │
  ▼  Dockerfiles::GenerateObaApi
ENV GTFS_RT_FEEDS='[{…},{…}]'   ◄── THE CROSS-REPO CONTRACT
  │  pushed to OneBusAway/obacloud-dockerfiles → Render builds image
  ▼
bootstrap.sh   ── if $GTFS_RT_FEEDS set → use it; else normalize legacy single-feed vars into a 1-element FEEDS array
  │  hands { "FEEDS": [...] } to hbs_renderer (raymond)
  ▼
data-sources.xml.hbs   ── {{#each FEEDS}} → one <bean class="GtfsRealtimeSource"> per feed
  ▼
OneBusAway runs with N realtime feeds
```

The `GTFS_RT_FEEDS` JSON is the contract; everything above it is OBACloud, everything below is the docker image.

---

## Repo 1: Docker image (`onebusaway/docker`)

### `oba/bootstrap.sh`

Replace the single-feed `JSON_CONFIG` construction (current lines ~34–76) with: prefer `GTFS_RT_FEEDS`; otherwise normalize the legacy single-feed vars into a one-element array. The template then only sees a `FEEDS` array.

```bash
# Build the FEEDS array for the transit-data-federation data-sources.xml.
# Prefer the multi-feed GTFS_RT_FEEDS env var; fall back to the legacy
# single-feed vars so already-deployed Dockerfiles keep working.
if [ -n "$GTFS_RT_FEEDS" ] && [ "$GTFS_RT_FEEDS" != "[]" ]; then
    FEEDS_JSON="$GTFS_RT_FEEDS"
elif [ -n "$TRIP_UPDATES_URL" ] || [ -n "$VEHICLE_POSITIONS_URL" ]; then
    # Normalize legacy single-feed vars into a one-element FEEDS array.
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
fi

JSON_CONFIG="{ \"FEEDS\": $FEEDS_JSON }"

hbs_renderer -input "$FEDERATION_XML_SOURCE" \
             -json "$JSON_CONFIG" \
             -output "$FEDERATION_XML_DESTINATION"
```

Notes:
- The `GTFS_RT_AVAILABLE` / `HAS_API_KEY` globals are gone — per-feed presence is decided in the template via `{{#if this.…}}`.
- Empty per-feed strings (`""`) are pruned in the template with `{{#if}}` guards, so an empty `feedApiKey`/`alertsUrl` produces no property — same effect as the current `{{#if}}` guards.
- Direct interpolation of `$GTFS_RT_FEEDS` into the JSON string is **safe**: the shell does a single expansion pass, so `$`, backticks, and `$(…)` inside the value are not re-evaluated (verified empirically). The legacy heredoc interpolates legacy vars unescaped exactly as the current script does — no regression, since OBACloud's char rules forbid `"`/`\`/newlines in those fields.
- A set-but-**malformed** `GTFS_RT_FEEDS` (e.g. stray whitespace, truncated JSON) passes the `-n` / `!= "[]"` guards and yields invalid JSON → `hbs_renderer` errors out. The renderer already fails loudly on parse error; bootstrap should surface that clearly (and may add a lightweight JSON sanity check before rendering).

### `oba/config/onebusaway-transit-data-federation-webapp-data-sources.xml.hbs`

Wrap the existing single bean (current lines 48–87) in an iteration:

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

The renderer is Go + `github.com/mailgun/raymond/v2` (a full Handlebars implementation). `{{#each}}`, `{{this.prop}}`, `{{#if x.length}}`, nested `{{#each this.agencyIds}}`, and `{{else if}}` are all supported — the existing template already uses `{{#each}}` + `.length`, and the new constructs were verified by running raymond v2 directly (including empty `agencyIds: []` correctly rendering nothing). The `{{else if this.agencyId}}` (singular) branch is **unreachable** for OBACloud-generated configs — both the generator and the legacy normalization only ever emit `agencyIds`. Keep it solely to honor hand-written `GTFS_RT_FEEDS` that use a singular `agencyId`.

### Testing the render — and a CI gap to close

Two existing "safety nets" don't currently hold, and the design depends on fixing them:

- **No `go test` step in CI.** `.github/workflows/test.yaml` only builds images and runs the compose e2e — it never runs `go test`. A renderer test protects nothing until CI runs it. **Add** a `go test ./oba/config/template_renderer/...` step to `test.yaml`.
- **The compose e2e sets no GTFS-RT env.** `bin/validate.sh` / `compose.yaml` configure zero realtime feeds, so the e2e only ever exercises the "no feeds" path and never renders a `GtfsRealtimeSource` bean — neither legacy nor multi-feed.

**New Go tests** in `oba/config/template_renderer/main_test.go` that render the *actual* federation template:
- A 2-feed `FEEDS` JSON → two `GtfsRealtimeSource` beans with correct per-feed `tripUpdatesUrl`, `agencyIds` (`<list>`), and `headersMap`.
- Empty `FEEDS` (`[]`) → zero beans.
- A **legacy-normalized** one-element array (what `bootstrap.sh` builds from `TRIP_UPDATES_URL` et al.) → one correct bean. This path matters disproportionately because of the mutable-tag blast radius below.

Optionally extend `compose.yaml` + `bin/validate.sh` to set `GTFS_RT_FEEDS` and assert a rendered bean end-to-end.

### `README.md`

Document `GTFS_RT_FEEDS` (the JSON shape) and note the legacy single-feed vars remain supported for one feed.

### Backward compatibility & ship sequencing

The production base image `opentransitsoftwarefoundation/onebusaway-api-webapp:2.7.1-latest` is published via a **GitHub Release** (`docker.yaml` → `buildx-release`), and `-latest` is a **mutable tag** re-pushed on each `2.7.1-vX.Y.Z` release.

**Ship order:**
1. Merge the docker change.
2. Cut a docker release so `2.7.1-latest` includes multi-feed support.
3. Ship the OBACloud change. New multi-feed Dockerfiles now build correctly; existing single-feed Dockerfiles continue to build because the legacy env vars are still honored.

**Blast radius — important.** "Cannot break" holds *at rest*, but `-latest` is mutable. The next time an existing service is rebuilt — `RebuildAppServicesForRuleSetJob` after any GTFS merge (`app/jobs/rebuild_app_services_for_rule_set_job.rb`), or a manual redeploy — it pulls the new image and runs the **new `bootstrap.sh` legacy-normalization branch**. So that branch is exercised by *every existing deployment* on its next rebuild, asynchronously, triggered by routine merges — not just by new configs. The legacy normalization must therefore have automated coverage (see the legacy-path Go test above), not just a visual once-over.

---

## Repo 2: OBACloud

### New model: `app/models/gtfs_rt_feed.rb`

A `StoreModel` mirroring the existing `FeedValidationTargetRtFeed` pattern.

```ruby
class GtfsRtFeed
  include StoreModel::Model

  # Everything below lands inside a single-quoted ENV line wrapping JSON, so a
  # literal single quote would terminate the wrapper. JSON encoding handles
  # double quotes and backslashes; newlines/CRs are rejected for cleanliness.
  UNSAFE_CHARACTERS = /[\n\r']/

  attribute :label, :string
  attribute :trip_updates_url, :string
  attribute :vehicle_positions_url, :string
  attribute :alerts_url, :string
  attribute :refresh_interval, :string, default: "30"
  attribute :agency_id_list, :string
  attribute :feed_api_key, :string
  attribute :feed_api_value, :string

  validates :label, :trip_updates_url, :vehicle_positions_url, :alerts_url,
            :refresh_interval, :agency_id_list, :feed_api_key, :feed_api_value,
            format: { without: UNSAFE_CHARACTERS, message: "contains invalid characters" },
            allow_blank: true
  validates :refresh_interval,
            numericality: { only_integer: true, greater_than: 0 }, allow_blank: true
end
```

### `app/models/dockerfile_config.rb`

Drop the nine flat feed attributes; keep `base_image`, `timezone`, `revision`. Add the feeds array + nested attributes (exactly how `RegionData` holds `bounds`).

```ruby
class DockerfileConfig
  include StoreModel::Model

  UNSAFE_CHARACTERS = /[\n\r"\\]/

  attribute :base_image, :string, default: "opentransitsoftwarefoundation/onebusaway-api-webapp:2.7.1-latest"
  attribute :timezone, :string, default: "America/Los_Angeles"
  attribute :feeds, GtfsRtFeed.to_array_type, default: -> { [] }
  attribute :revision, :integer, default: 1

  # reject_if drops the template row and all-blank added rows. refresh_interval
  # defaults to "30", so it must be excluded or it would make every row "present".
  # No _destroy: the editor physically removes rows and the full feeds list is
  # re-submitted on every save, so the array is replaced wholesale.
  accepts_nested_attributes_for :feeds,
    reject_if: ->(attrs) { attrs.except("_destroy", "label", "refresh_interval").values.all?(&:blank?) }

  validates :base_image, :timezone,
            format: { without: UNSAFE_CHARACTERS, message: "contains invalid characters" },
            allow_blank: true
  # Surfaces child GtfsRtFeed errors (e.g. a single quote in a URL) up through the
  # array via StoreModel's array validation strategy. WITHOUT this, an invalid feed
  # passes validation, gets serialized, and breaks the single-quoted Dockerfile
  # line — the exact failure §Validation claims to prevent.
  validates :feeds, store_model: { merge_errors: true }
end
```

### Backfill migration

A data migration that, for every `AppConfig` whose `dockerfile_config` JSONB still has flat feed keys and an empty `feeds`, moves those values into `feeds[0]`. Idempotent; safe to run on an empty/greenfield dataset.

```ruby
class BackfillDockerfileConfigFeeds < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    AppConfig.find_each do |app_config|
      raw = app_config.read_attribute_before_type_cast(:dockerfile_config)
      cfg = raw.is_a?(String) ? JSON.parse(raw) : (raw || {})
      next if cfg["feeds"].present?

      flat_keys = %w[alerts_url trip_updates_url vehicle_positions_url
                     refresh_interval agency_id_list feed_api_key feed_api_value]
      # "Real" data excludes refresh_interval — it defaults to "30" on EVERY row
      # (the JSONB serializes all attributes), so counting it would fabricate a
      # junk feed[0] on configs that never set up a feed.
      real_keys = flat_keys - %w[refresh_interval]
      next if real_keys.all? { |k| cfg[k].blank? }

      feed = cfg.slice(*flat_keys).compact
      feed["refresh_interval"] = feed["refresh_interval"].presence || "30"
      app_config.update_columns(
        dockerfile_config: cfg.except(*flat_keys).merge("feeds" => [feed])
      )
    end
  end

  def down
    # no-op: the flat columns no longer exist on the model
  end
end
```

*(Exact attribute access to be confirmed against StoreModel during implementation; the intent is "copy flat → feeds[0], drop flat keys, leave already-migrated rows alone.")*

### Controller: `app/controllers/organizations/app_configs_controller.rb`

No `:id` (StoreModel feeds have no persistent id) and no `:_destroy` (removal is DOM-only; the array is replaced wholesale from the submitted rows) — matching the regions/bounds precedent.

```ruby
DOCKERFILE_CONFIG_FIELDS = [
  :base_image, :timezone,
  { feeds_attributes: %i[label trip_updates_url vehicle_positions_url
                         alerts_url refresh_interval agency_id_list
                         feed_api_key feed_api_value] }
].freeze

def dockerfile_config_params
  params.require(:app_config).permit(dockerfile_config: DOCKERFILE_CONFIG_FIELDS)
end
```

### Service wizard: `ServiceWizards::SaveConfigStep` + wizard `config_params`

**This is required, not optional** — the onboarding wizard also writes the flat feed fields today, so once `DockerfileConfig` drops them, the wizard crashes with `ActiveModel::UnknownAttributeError`. The wizard collects a *single* feed (the session's `rt_feeds` are keyed by kind: `trip_updates` / `vehicle_positions` / `alerts` — all one feed), so it maps cleanly to `feeds[0]`; **onboarding stays single-feed in the UI**, only the written shape changes.

- `app/commands/service_wizards/save_config_step.rb` (`build_app_config`, line ~62): instead of `dockerfile_config: overrides.merge(rt_urls_from_session)`, build `dockerfile_config: { base_image:, timezone:, feeds: [ { trip_updates_url:, vehicle_positions_url:, alerts_url:, refresh_interval:, agency_id_list:, feed_api_key:, feed_api_value: } ] }` — drop the all-blank feed if onboarding provided no URLs.
- `app/controllers/organizations/service_wizards_controller.rb` (`config_params`, lines ~86–90): replace the flat `dockerfile_config: [...]` permit with the nested `feeds`/`feeds_attributes` shape.
- Existing wizard specs assume flat fields and will fail: `spec/system/service_wizard_flow_spec.rb` and `spec/requests/organizations/service_wizards_spec.rb` — update both.

### Generator: `app/commands/dockerfiles/generate_oba_api.rb`

Replace the six single-feed `ENV` lines (current lines 18–24) with one `GTFS_RT_FEEDS` line, emitted only when at least one feed has content.

The global `ENV REFRESH_INTERVAL` line is **dropped** — refresh interval is now per-feed inside the JSON. (`REFRESH_INTERVAL` still works as a legacy single-feed var in the image, so nothing breaks.)

```ruby
lines << env_line("GTFS_URL", gtfs_url) if gtfs_url.present?
lines << gtfs_rt_feeds_line if feeds_json.present?
lines << env_line("REVISION", @config.revision.to_s)

# ...

def feeds_json
  payload = @config.feeds.filter_map do |feed|
    obj = {
      "tripUpdatesUrl"      => feed.trip_updates_url,
      "vehiclePositionsUrl" => feed.vehicle_positions_url,
      "alertsUrl"           => feed.alerts_url,
      "refreshInterval"     => feed.refresh_interval,
      "agencyIds"           => parse_agency_ids(feed.agency_id_list),
      "feedApiKey"          => feed.feed_api_key,
      "feedApiValue"        => feed.feed_api_value
    }.reject { |_k, v| v.blank? }
    obj if obj.key?("tripUpdatesUrl") || obj.key?("vehiclePositionsUrl")
  end
  payload.present? ? JSON.generate(payload) : nil
end

def gtfs_rt_feeds_line
  "ENV GTFS_RT_FEEDS='#{feeds_json}'"   # single-quoted, like AGENCY_ID_LIST
end

def parse_agency_ids(raw)
  return [] if raw.blank?
  parsed = JSON.parse(raw) rescue nil
  parsed.is_a?(Array) ? parsed : []
end
```

`JSON.generate` escapes the double quotes inside the value; wrapping the whole thing in single quotes (as `AGENCY_ID_LIST` already does) keeps the Dockerfile line valid. The `GtfsRtFeed` validation forbids literal single quotes, which is the only character that could break the single-quote wrapper. `label` is intentionally never serialized.

### UI: `app/views/organizations/app_configs/edit_dockerfile_config.html.erb`

Global fields up top, then a feeds section using the established nested-form pattern (`<template>` + `child_index: "NEW_RECORD"`), with each feed rendered as a collapsible accordion panel.

```erb
<%= f.fields_for :dockerfile_config, @app_config.dockerfile_config do |dc| %>
  <%= render Forms::TextFieldComponent.new(form: dc, method: :base_image, label: "Base Image") %>
  <%= render Forms::TextFieldComponent.new(form: dc, method: :timezone, label: "Timezone") %>

  <div data-controller="dockerfile-feeds">
    <div data-dockerfile-feeds-target="fields" class="space-y-2">
      <% @app_config.dockerfile_config.feeds.each_with_index do |feed, idx| %>
        <%= dc.fields_for :feeds, feed, child_index: idx do |ff| %>
          <%= render AppConfigs::FeedFieldsComponent.new(form: ff, index: idx, feed: feed) %>
        <% end %>
      <% end %>
    </div>

    <template data-dockerfile-feeds-target="template">
      <%= dc.fields_for :feeds, GtfsRtFeed.new, child_index: "NEW_RECORD" do |ff| %>
        <%= render AppConfigs::FeedFieldsComponent.new(form: ff, index: "NEW_RECORD", feed: GtfsRtFeed.new) %>
      <% end %>
    </template>

    <button type="button" class="oba-btn oba-btn--sm mt-2" data-action="dockerfile-feeds#add">
      Add feed
    </button>
  </div>
<% end %>
```

**New component `AppConfigs::FeedFieldsComponent`** wraps one feed's fields in a `CollapsibleCardComponent`: the header shows the feed's label (or "Feed N") and a Remove button (`data-action="dockerfile-feeds#remove"`); the body holds the per-feed `Forms::TextFieldComponent`s (trip updates, vehicle positions, alerts, refresh interval, agency ID list, API key, API value) plus the optional Label field.

**Accessibility / height:** `disclosure_controller.js` only toggles a `hidden` class — no `aria-expanded`/`aria-controls` or keyboard focus management, and N feeds can overflow the `LazyModalComponent`. Add `aria-expanded`/`aria-controls` to the accordion toggle and confirm the modal body scrolls (it uses `max-h-[90vh]` + `overflow-y-auto`, so this should hold) before shipping.

**New Stimulus controller `app/javascript/controllers/dockerfile_feeds_controller.js`** modeled on `rt_feeds_controller.js`: `add` clones the `<template>`, replacing `NEW_RECORD` with a unique index and appending to the fields target; `remove` deletes the row's DOM node (the `feeds` array is rebuilt from the rows that are still present on submit — StoreModel array items have no persistent id, so no `_destroy` bookkeeping is needed for new rows). Optionally reuse `feed_label_matcher.js` to auto-suggest a label from the trip-updates URL.

The modal mechanics (`Modals::LazyModalComponent`, lazy Turbo Frame load, `Forms::ButtonBarComponent`) are unchanged.

### `show.html.erb` display

The Dockerfile-config summary currently hard-codes single-feed rows and masks `feed_api_value` as `********`. Rewrite it to list each feed (label + URLs), **preserving per-feed masking of `feed_api_value`** — likely a small read-only component mirroring the accordion. The `DockerfilePreviewComponent` needs no change — it splits on newlines and colorizes `ENV` lines, so the single `GTFS_RT_FEEDS` line renders fine (verified).

---

## Validation & safety

- **Single-quote safety:** `GTFS_RT_FEEDS` is emitted single-quoted; `GtfsRtFeed` rejects `'`, `\n`, `\r` in every string field. Double quotes and backslashes are handled by `JSON.generate` and are safe inside the single-quoted value.
- **Empty feeds:** a feed with no trip-updates and no vehicle-positions URL is dropped from the payload; an entirely empty feeds list omits the `GTFS_RT_FEEDS` line.
- **Edit lockout:** the existing `require_no_app_services` before_action still blocks editing once the config is attached to a provisioned AppService — unchanged.

## Testing

**OBACloud**
- `spec/models/gtfs_rt_feed_spec.rb` — defaults, attribute assignment, unsafe-character validation (incl. single quote), `refresh_interval` numericality.
- `spec/models/dockerfile_config_spec.rb` — feeds array round-trips through JSONB; nested attributes build/**replace** feeds; `reject_if` drops all-blank/template rows; an invalid child feed makes the config invalid (the `validates :feeds, store_model:` path).
- `spec/commands/dockerfiles/generate_oba_api_spec.rb` — 0 / 1 / N feeds; `agency_id_list` JSON parsed into `agencyIds`; API key/value emitted; blank keys pruned; single-quote wrapping; `label` never serialized; **no** top-level `REFRESH_INTERVAL` line.
- `spec/requests/organizations/app_configs_spec.rb` — `PATCH update_dockerfile_config` adds, edits, and removes feeds via nested params; rejects unsafe characters; still blocked when attached to an AppService. **Update** the existing case that passes top-level `dockerfile_config: { refresh_interval: "60" }` (line ~574) — that attribute no longer exists.
- `spec/system/service_wizard_flow_spec.rb` and `spec/requests/organizations/service_wizards_spec.rb` — update to the `feeds[0]` shape (they pass flat `dockerfile_config` today and will fail).
- Migration spec (incl. the "empty config → no junk feed" case from C2) and factory updates for `GtfsRtFeed` and multi-feed `dockerfile_config`.

**Docker**
- New `oba/config/template_renderer/main_test.go` cases (multi-feed, empty, legacy-normalized) — see "Testing the render" above — **plus a `go test` step added to `.github/workflows/test.yaml`** so they actually run in CI.
- Existing `bin/validate.sh` compose e2e covers startup only (no RT env today); optionally extend it to assert a rendered bean.

## Non-goals

- No change to how the GTFS *static* bundle (`GTFS_URL`) is configured.
- No change to JDBC, timezone, base image, or revision handling.
- No per-feed UI for advanced `GtfsRealtimeSource` properties beyond the seven already exposed.
- No automation of the docker release cut (manual, per existing process).

## Open questions / future

- Whether to auto-derive feed labels from agency IDs when the label is blank (cosmetic; can follow later).
- The global `REFRESH_INTERVAL` ENV line is dropped from the generator (refresh interval is per-feed); it remains supported in the image as a legacy single-feed var. Confirm nothing else in OBACloud reads a top-level `refresh_interval` before deleting the attribute.
