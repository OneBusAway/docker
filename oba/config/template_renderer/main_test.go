package main

import (
	"os"
	"strings"
	"testing"
)

func TestRenderTemplate(t *testing.T) {
	// Create a temporary template file
	tempFile, err := os.CreateTemp("", "test-template-*.hbs")
	if err != nil {
		t.Fatalf("Failed to create temp file: %v", err)
	}
	defer os.Remove(tempFile.Name()) // clean up

	// Write test template content
	templateContent := "Hello, {{name}}! Your favorite color is {{color}}."
	if _, err := tempFile.Write([]byte(templateContent)); err != nil {
		t.Fatalf("Failed to write to temp file: %v", err)
	}
	if err := tempFile.Close(); err != nil {
		t.Fatalf("Failed to close temp file: %v", err)
	}

	// Set up test cases
	testCases := []struct {
		name     string
		jsonData string
		expected string
	}{
		{
			name:     "Basic rendering",
			jsonData: `{"name": "Alice", "color": "blue"}`,
			expected: "Hello, Alice! Your favorite color is blue.",
		},
		{
			name:     "Missing data",
			jsonData: `{"name": "Bob"}`,
			expected: "Hello, Bob! Your favorite color is .",
		},
		{
			name:     "Extra data",
			jsonData: `{"name": "Charlie", "color": "green", "age": 30}`,
			expected: "Hello, Charlie! Your favorite color is green.",
		},
	}

	// Run test cases
	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			result, err := renderTemplate(tempFile.Name(), tc.jsonData)
			if err != nil {
				t.Fatalf("renderTemplate returned an error: %v", err)
			}

			if !strings.Contains(result, tc.expected) {
				t.Errorf("Expected output to contain %q, but got %q", tc.expected, result)
			}
		})
	}
}

func TestRenderTemplateWithArray(t *testing.T) {
	// Create a temporary template file
	tempFile, err := os.CreateTemp("", "test-template-*.hbs")
	if err != nil {
		t.Fatalf("Failed to create temp file: %v", err)
	}
	defer os.Remove(tempFile.Name()) // clean up

	// Write test template content
	templateContent := "Hello, {{name}}! Your favorite colors are {{#each colors}}{{this}} {{else}}unknown{{/each}}."
	if _, err := tempFile.Write([]byte(templateContent)); err != nil {
		t.Fatalf("Failed to write to temp file: %v", err)
	}
	if err := tempFile.Close(); err != nil {
		t.Fatalf("Failed to close temp file: %v", err)
	}

	// Set up test cases
	testCases := []struct {
		name     string
		jsonData string
		expected string
	}{
		{
			name:     "Basic rendering",
			jsonData: `{"name": "Alice", "colors": ["blue", "green"]}`,
			expected: "Hello, Alice! Your favorite colors are blue green .",
		},
		{
			name:     "only one item rendering",
			jsonData: `{"name": "Alice", "colors": ["green"]}`,
			expected: "Hello, Alice! Your favorite colors are green .",
		},
		{
			name:     "only one item rendering",
			jsonData: `{"name": "Alice", "colors": []}`,
			expected: "Hello, Alice! Your favorite colors are unknown.",
		},
	}

	// Run test cases
	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			result, err := renderTemplate(tempFile.Name(), tc.jsonData)
			if err != nil {
				t.Fatalf("renderTemplate returned an error: %v", err)
			}

			if !strings.Contains(result, tc.expected) {
				t.Errorf("Expected output to contain %q, but got %q", tc.expected, result)
			}
		})
	}
}

func TestRenderTemplateErrors(t *testing.T) {
	// Test with non-existent file
	_, err := renderTemplate("non-existent-file.hbs", "{}")
	if err == nil {
		t.Error("Expected an error with non-existent file, but got none")
	}

	// Test with invalid JSON
	tempFile, _ := os.CreateTemp("", "test-template-*.hbs")
	defer os.Remove(tempFile.Name())
	tempFile.Write([]byte("{{name}}"))
	tempFile.Close()

	_, err = renderTemplate(tempFile.Name(), "invalid json")
	if err == nil {
		t.Error("Expected an error with invalid JSON, but got none")
	}
}

const federationTemplatePath = "../onebusaway-transit-data-federation-webapp-data-sources.xml.hbs"

func TestFederationTemplateMultipleFeeds(t *testing.T) {
	json := `{"FEEDS":[` +
		`{"tripUpdatesUrl":"https://a/trips","agencyIds":["unitrans"],"feedApiKey":"x-key","feedApiValue":"secret"},` +
		`{"vehiclePositionsUrl":"https://b/vehicles","agencyIds":["kcm"]}` +
		`]}`

	out, err := renderTemplate(federationTemplatePath, json)
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
	if !strings.Contains(out, `<value>unitrans</value>`) {
		t.Errorf("missing agencyId for first feed:\n%s", out)
	}
	if !strings.Contains(out, `<value>kcm</value>`) {
		t.Errorf("missing agencyId for second feed:\n%s", out)
	}
	if !strings.Contains(out, `<entry key="x-key" value="secret"`) {
		t.Errorf("missing first feed headersMap:\n%s", out)
	}
	if c := strings.Count(out, "headersMap"); c != 1 {
		t.Errorf("expected headersMap exactly once, got %d:\n%s", c, out)
	}
}

func TestFederationTemplateNoFeeds(t *testing.T) {
	out, err := renderTemplate(federationTemplatePath, `{"FEEDS":[]}`)
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
	json := `{"FEEDS":[{"tripUpdatesUrl":"https://a/trips","vehiclePositionsUrl":"https://a/veh",` +
		`"alertsUrl":"https://a/alerts","refreshInterval":"30","agencyIds":["unitrans"],` +
		`"feedApiKey":"","feedApiValue":""}]}`

	out, err := renderTemplate(federationTemplatePath, json)
	if err != nil {
		t.Fatalf("renderTemplate returned an error: %v", err)
	}
	if c := strings.Count(out, "GtfsRealtimeSource"); c != 1 {
		t.Errorf("expected 1 bean, got %d\n%s", c, out)
	}
	for _, want := range []string{`value="https://a/trips"`, `value="https://a/veh"`, `value="https://a/alerts"`, `value="30"`} {
		if !strings.Contains(out, want) {
			t.Errorf("missing %s:\n%s", want, out)
		}
	}
	if strings.Contains(out, "headersMap") {
		t.Errorf("blank feedApiKey should produce no headersMap:\n%s", out)
	}
}

func TestFederationTemplateSingularAgencyId(t *testing.T) {
	json := `{"FEEDS":[{"tripUpdatesUrl":"https://x/trips","agencyId":"unitrans"}]}`
	out, err := renderTemplate(federationTemplatePath, json)
	if err != nil {
		t.Fatalf("renderTemplate returned an error: %v", err)
	}
	if !strings.Contains(out, `<property name="agencyId" value="unitrans"`) {
		t.Errorf("missing singular agencyId property:\n%s", out)
	}
	if strings.Contains(out, `<property name="agencyIds"`) {
		t.Errorf("did not expect plural agencyIds list:\n%s", out)
	}
}
