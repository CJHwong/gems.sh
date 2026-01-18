# gems.sh

**gems.sh** is a Zsh script that simplifies interacting with local Large Language Models using [Ollama](https://ollama.com/). It provides a rich set of pre-configured prompt templates with advanced features like language detection, JSON schema processing, and flexible output handling.

Inspired by the workflow described in this Hacker News post by eliya_confiant: <https://news.ycombinator.com/item?id=39592297>.

---

## Core Features

- **Rich Prompt Templates**: Load from YAML configuration with templates like *TextReviser*, *CodeReview*, *ComplexAnalysis*
- **Multiple Model Support**: Use `-m` to specify any Ollama model (defaults to `gemma3n`)
- **Language Detection**: Automatic language detection for templates that support it
- **JSON Schema Processing**: Define expected response structure and extract specific fields
- **Template Properties**: Configure language detection, output language, and JSON processing per template

### Output & Display

- **Clipboard Integration**: Automatically copies results to clipboard with notifications
- **Raw Response Tracking**: When using JSON extraction, shows both raw LLM output and extracted result
- **Flexible Output Destinations:**  
  Results can be displayed in your choice of viewer:
  - **Terminal**
  - **iTerm2**
  - **Warp**
  - **homo** ([a custom Markdown viewer](https://github.com/CJHwong/rs-homo); set `RESULT_VIEWER_APP="homo"`)

---

## Installation

### Required Dependencies

1. **Ollama** (Required)

   ```sh
   brew install ollama
   # Start the service
   ollama serve
   ```

2. **macOS Tools** (Required - built-in)
   - `osascript` (AppleScript support)
   - `pbcopy` (clipboard functionality)

### Optional Dependencies

1. **YAML Processing** (Recommended)

   ```sh
   brew install yq
   ```

   - Required for loading templates from `gems.yml`

2. **JSON Processing** (Recommended)

   ```sh
   brew install jq
   ```

   - Required for JSON schema features

3. **Markdown Rendering with homo** (Recommended)
   - See <https://github.com/CJHwong/rs-homo>

4. **Markdown Rendering** (Optional)

   ```sh
   brew install glow
   ```

   - For Terminal/iTerm2 markdown display

5. **Path Resolution** (Optional)

   ```sh
   brew install coreutils
   ```

   - Provides `realpath` for better path handling

### Models Setup

Download the default models:

```sh
ollama pull gemma3n      # Default model
ollama pull gemma3n:e2b  # Language detection model
```

---

## Configuration

### Template Configuration (`gems.yml`)

Create a `gems.yml` file in the same directory as `gems.sh`:

```yaml
prompt_templates:
  TextReviser:
    template: |
      Revise the following text for clarity, grammar, and readability.
      Text: {{input}}
    properties:
      detect_language: true
      json_schema:
        revised_text: string
        additional_info: string
      json_field: revised_text

  CodeReview:
    template: |
      Review this code for best practices and potential improvements.
      Code: {{input}}
    properties:
      json_schema:
        issues:
          - type: string
            severity: string
            description: string
        summary: string
      json_field: summary
```

### Script Configuration

Edit the configuration section in `gems.sh`:

```bash
# LLM settings
DEFAULT_MODEL="gemma3n"
LANGUAGE_DETECTION_MODEL="gemma3n:e2b"

# Output settings
RESULT_VIEWER_APP="homo"  # Options: homo, Warp, Terminal, iTerm2
```

---

## Usage

### Basic Usage

```sh
# Use default template (Passthrough)
./gems.sh "Explain quantum computing"

# Specify a template
./gems.sh -t TextReviser "Me and him went to store"

# Use specific model
./gems.sh -m gemma3:27b-it-qat -t CodeReview "function buggyCode() { return x + y; }"

# Verbose mode for debugging
./gems.sh -v -t ComplexAnalysis "Sample text to analyze"
```

### Advanced Features

**Language Detection:**

```sh
# Automatically detects input language and preserves it
./gems.sh -t TextReviser "Bonjour, comment allez-vous?"
```

**JSON Schema Processing:**

```sh
# Returns structured data and extracts specific fields
./gems.sh -t ComplexAnalysis "This is a complex document to analyze"
# Returns only the 'summary' field due to json_field configuration
```

**Template Management:**

```sh
# List available templates and models
./gems.sh -h

# Check dependencies
./gems.sh -v -t Passthrough "test" | head -20
```

---

## Template Properties

### Available Properties

- **`detect_language: true`** - Auto-detect input language
- **`output_language: "English"`** - Force specific output language
- **`json_schema: {...}`** - Define expected JSON response structure
- **`json_field: "fieldname"`** - Extract specific field from JSON response

### Example Combinations

```yaml
# Language detection with JSON output
TranslationAnalysis:
  template: "Analyze and translate: {{input}}"
  properties:
    detect_language: true
    json_schema:
      original_language: string
      translation: string
      confidence: number
    json_field: translation

# Complex analysis with structured output
DocumentAnalysis:
  template: "Analyze this document: {{input}}"
  properties:
    json_schema:
      analysis:
        topics: [string]
        sentiment: string
      summary: string
    json_field: summary
```

---

## macOS Integration

### Using macOS Shortcuts (Recommended)

<img width="862" height="556" alt="412299048-0a34c8ca-a0b4-4c44-81a5-17446fd12aca" src="https://github.com/user-attachments/assets/aa76a8e9-f6db-4ebf-86d2-4c23f135e4f7" />


1. **Open Shortcuts App**
2. **Create New Shortcut** named "Ask AI"
3. **Add Actions:**
   - "Get Text from Input" (set to receive text from Quick Actions)
   - "Run Shell Script" with: `/path/to/gems.sh "$@"`
4. **Configure Quick Actions** to accept text input
5. **Optional:** Add keyboard shortcut in shortcut settings

**Usage:** Select text → Right-click → "Ask AI" or use keyboard shortcut

### Using Automator (Alternative)

<details>
<summary>Click to expand Automator setup</summary>

1. **Open Automator** → Create **Quick Action**
2. **Add "Run Shell Script"** action
3. **Paste gems.sh contents** or call script with full path
4. **Save** as service
5. **Assign keyboard shortcut** in System Settings → Keyboard → Shortcuts

</details>

---

## Available Templates

The included `gems.yml` provides these templates:

### Writing & Communication

- **Summarize** - Create concise summaries
- **TextReviser** - Grammar and clarity improvements
- **EmailProfessional** - Convert to professional email format
- **BulletPoints** - Convert text to organized bullet points

### Analysis & Research

- **ComplexAnalysis** - Comprehensive text analysis with sentiment and topics
- **ProsAndCons** - Balanced analysis of topics

### Code Development

- **CodeReview** - Best practices and security review
- **CodeExplain** - Simple explanations of code
- **CodeOptimize** - Performance and readability improvements

### Creative & Brainstorming

- **Brainstorm** - Generate creative ideas and solutions

---

## Troubleshooting

### Dependency Check

```sh
./gems.sh -v -t Passthrough "test" 2>&1 | grep -E "(ERROR|WARNING|✓)"
```

### Common Issues

**"No templates found":**

- Ensure `gems.yml` exists in script directory
- Install `yq`: `brew install yq`
- Check YAML syntax with: `yq eval . gems.yml`

**"Model not found":**

- List available models: `ollama list`
- Pull required model: `ollama pull model-name`

**"JSON extraction failed":**

- Install `jq`: `brew install jq`
- Check template's `json_schema` configuration
- Use `-v` flag to see raw LLM response

---

## Testing

The project uses [shellspec](https://shellspec.info/) for BDD-style testing.

### Install shellspec

```sh
brew install shellspec
```

### Run tests

```sh
# Run all tests
shellspec

# Run with documentation format
shellspec --format documentation

# Run specific test file
shellspec spec/unit/call_llm_api_spec.sh

# Run tests matching a pattern
shellspec --example "JSON extraction"
```
