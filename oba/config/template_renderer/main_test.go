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
