# shellcheck shell=bash
# spec/unit/process_with_template_spec.sh

# Tests for process_with_template - the main processing function
# Uses wrapper scripts with mocked dependencies

Describe 'process_with_template()'

    setup() {
        # Create test directory for mocks
        MOCK_DIR="$(mktemp -d)"
        TEST_SCRIPT="$(mktemp)"
        ORIGINAL_PATH="$PATH"

        # Create a comprehensive wrapper script
        cat > "$TEST_SCRIPT" << 'WRAPPER'
#!/bin/zsh
GEMS_SCRIPT="$1"
shift

# Source the script
source "$GEMS_SCRIPT"

# Override functions that have side effects
setup_output() { : }
write_to_output() { : }
write_to_output_stream() { cat }
cleanup_output() { : }
copy_to_clipboard() { : }
detect_language() { echo "English" }

# Mock call_llm_api to return controlled responses
MOCK_RESPONSE=""
call_llm_api() {
    local model="$1"
    local prompt="$2"
    local temp_file="$3"

    echo -n "$MOCK_RESPONSE"
    if [[ -n "$temp_file" ]]; then
        echo -n "$MOCK_RESPONSE" > "$temp_file"
    fi
}

# Parse test parameters
while [[ $# -gt 0 ]]; do
    case "$1" in
        --template) SELECTED_TEMPLATE="$2"; shift 2 ;;
        --input) USER_INPUT="$2"; shift 2 ;;
        --response) MOCK_RESPONSE="$2"; shift 2 ;;
        --model) SELECTED_MODEL="$2"; shift 2 ;;
        --cli-override) CLI_MODEL_OVERRIDE="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Initialize templates
typeset -gA PROMPT_TEMPLATES
typeset -gA TEMPLATE_PROPERTIES
VERBOSE_MODE=false

# Set up test templates
PROMPT_TEMPLATES["Simple"]="Process: {{input}}"
PROMPT_TEMPLATES["NoPlaceholder"]="Just process the text"
PROMPT_TEMPLATES["JsonTemplate"]="Extract data from: {{input}}"
TEMPLATE_PROPERTIES["JsonTemplate"]="json_schema={\"items\":[\"string\"]} json_field=items"
PROMPT_TEMPLATES["JsonObjectTemplate"]="Analyze: {{input}}"
TEMPLATE_PROPERTIES["JsonObjectTemplate"]="json_schema={\"points\":[{\"title\":\"string\",\"description\":\"string\"}]} json_field=points"
PROMPT_TEMPLATES["DetectLangTemplate"]="Revise: {{input}}"
TEMPLATE_PROPERTIES["DetectLangTemplate"]="detect_language=true"
PROMPT_TEMPLATES["ModelOverride"]="Test: {{input}}"
TEMPLATE_PROPERTIES["ModelOverride"]="model=template-model"

# Run the function and capture output
process_with_template
WRAPPER
        chmod +x "$TEST_SCRIPT"
    }

    cleanup() {
        rm -rf "$MOCK_DIR"
        rm -f "$TEST_SCRIPT"
        PATH="$ORIGINAL_PATH"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    Describe 'prompt building'
        It 'substitutes {{input}} placeholder with user input'
            cat > "$TEST_SCRIPT" << 'WRAPPER'
#!/bin/zsh
source "$1"
setup_output() { : }
write_to_output() { : }
write_to_output_stream() { cat > /dev/null }
cleanup_output() { : }
copy_to_clipboard() { : }

call_llm_api() {
    echo "PROMPT_RECEIVED: $2" >&2
    local temp_file="$3"
    [[ -n "$temp_file" ]] && echo "response" > "$temp_file"
}

typeset -gA PROMPT_TEMPLATES
typeset -gA TEMPLATE_PROPERTIES
PROMPT_TEMPLATES["Simple"]="Process this: {{input}}"
SELECTED_TEMPLATE="Simple"
USER_INPUT="hello world"
SELECTED_MODEL="test-model"
CLI_MODEL_OVERRIDE=false
VERBOSE_MODE=false

process_with_template
WRAPPER
            chmod +x "$TEST_SCRIPT"

            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT"
            The stderr should include "PROMPT_RECEIVED: Process this: hello world"
        End

        It 'appends input when no {{input}} placeholder exists'
            cat > "$TEST_SCRIPT" << 'WRAPPER'
#!/bin/zsh
source "$1"
setup_output() { : }
write_to_output() { : }
write_to_output_stream() { cat > /dev/null }
cleanup_output() { : }
copy_to_clipboard() { : }

call_llm_api() {
    echo "PROMPT_RECEIVED: $2" >&2
    local temp_file="$3"
    [[ -n "$temp_file" ]] && echo "response" > "$temp_file"
}

typeset -gA PROMPT_TEMPLATES
typeset -gA TEMPLATE_PROPERTIES
PROMPT_TEMPLATES["NoPlaceholder"]="Just process"
SELECTED_TEMPLATE="NoPlaceholder"
USER_INPUT="the text"
SELECTED_MODEL="test-model"
CLI_MODEL_OVERRIDE=false
VERBOSE_MODE=false

process_with_template
WRAPPER
            chmod +x "$TEST_SCRIPT"

            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT"
            The stderr should include "PROMPT_RECEIVED: Just process the text"
        End

        It 'adds JSON schema instruction when json_schema is set'
            cat > "$TEST_SCRIPT" << 'WRAPPER'
#!/bin/zsh
source "$1"
setup_output() { : }
write_to_output() { : }
write_to_output_stream() { cat > /dev/null }
cleanup_output() { : }
copy_to_clipboard() { : }

call_llm_api() {
    echo "PROMPT: $2" >&2
    local temp_file="$3"
    [[ -n "$temp_file" ]] && echo '{"items":["a"]}' > "$temp_file"
}

typeset -gA PROMPT_TEMPLATES
typeset -gA TEMPLATE_PROPERTIES
PROMPT_TEMPLATES["JsonTemplate"]="Extract: {{input}}"
TEMPLATE_PROPERTIES["JsonTemplate"]="json_schema={items:[string]} json_field=items"
SELECTED_TEMPLATE="JsonTemplate"
USER_INPUT="test data"
SELECTED_MODEL="test-model"
CLI_MODEL_OVERRIDE=false
VERBOSE_MODE=false

process_with_template
WRAPPER
            chmod +x "$TEST_SCRIPT"

            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT"
            The stderr should include "IMPORTANT: You must respond with valid JSON"
            The stderr should include "Extract: test data"
        End
    End

    Describe 'JSON extraction'
        It 'extracts JSON from ```json code blocks'
            cat > "$TEST_SCRIPT" << 'WRAPPER'
#!/bin/zsh
source "$1"
setup_output() { : }
write_to_output() { echo "OUTPUT: $1" }
write_to_output_stream() { cat > /dev/null }
cleanup_output() { : }
copy_to_clipboard() { echo "CLIPBOARD: $1" }

call_llm_api() {
    local temp_file="$3"
    local response='```json
{"items": ["one", "two", "three"]}
```'
    echo -n "$response"
    [[ -n "$temp_file" ]] && echo -n "$response" > "$temp_file"
}

typeset -gA PROMPT_TEMPLATES
typeset -gA TEMPLATE_PROPERTIES
PROMPT_TEMPLATES["JsonTemplate"]="Extract: {{input}}"
TEMPLATE_PROPERTIES["JsonTemplate"]="json_schema={items:[string]} json_field=items"
SELECTED_TEMPLATE="JsonTemplate"
USER_INPUT="test"
SELECTED_MODEL="test-model"
CLI_MODEL_OVERRIDE=false
VERBOSE_MODE=false

process_with_template
WRAPPER
            chmod +x "$TEST_SCRIPT"

            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT"
            The output should include "* one"
            The output should include "* two"
            The output should include "* three"
        End

        It 'extracts JSON from raw JSON response'
            cat > "$TEST_SCRIPT" << 'WRAPPER'
#!/bin/zsh
source "$1"
setup_output() { : }
write_to_output() { echo "OUTPUT: $1" }
write_to_output_stream() { cat > /dev/null }
cleanup_output() { : }
copy_to_clipboard() { echo "CLIPBOARD: $1" }

call_llm_api() {
    local temp_file="$3"
    local response='{"items": ["apple", "banana"]}'
    echo -n "$response"
    [[ -n "$temp_file" ]] && echo -n "$response" > "$temp_file"
}

typeset -gA PROMPT_TEMPLATES
typeset -gA TEMPLATE_PROPERTIES
PROMPT_TEMPLATES["JsonTemplate"]="Extract: {{input}}"
TEMPLATE_PROPERTIES["JsonTemplate"]="json_schema={items:[string]} json_field=items"
SELECTED_TEMPLATE="JsonTemplate"
USER_INPUT="test"
SELECTED_MODEL="test-model"
CLI_MODEL_OVERRIDE=false
VERBOSE_MODE=false

process_with_template
WRAPPER
            chmod +x "$TEST_SCRIPT"

            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT"
            The output should include "* apple"
            The output should include "* banana"
        End

        It 'extracts specific field from JSON'
            cat > "$TEST_SCRIPT" << 'WRAPPER'
#!/bin/zsh
source "$1"
setup_output() { : }
write_to_output() { echo "$1" }
write_to_output_stream() { cat > /dev/null }
cleanup_output() { : }
copy_to_clipboard() { : }

call_llm_api() {
    local temp_file="$3"
    local response='{"summary": "This is the extracted summary", "other": "ignored"}'
    echo -n "$response"
    [[ -n "$temp_file" ]] && echo -n "$response" > "$temp_file"
}

typeset -gA PROMPT_TEMPLATES
typeset -gA TEMPLATE_PROPERTIES
PROMPT_TEMPLATES["SummaryTemplate"]="Summarize: {{input}}"
TEMPLATE_PROPERTIES["SummaryTemplate"]="json_schema={summary:string} json_field=summary"
SELECTED_TEMPLATE="SummaryTemplate"
USER_INPUT="test"
SELECTED_MODEL="test-model"
CLI_MODEL_OVERRIDE=false
VERBOSE_MODE=false

process_with_template
WRAPPER
            chmod +x "$TEST_SCRIPT"

            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT"
            The output should include "This is the extracted summary"
        End
    End

    Describe 'array formatting'
        It 'formats string arrays as bullet points'
            cat > "$TEST_SCRIPT" << 'WRAPPER'
#!/bin/zsh
source "$1"
setup_output() { : }
write_to_output() { echo "$1" }
write_to_output_stream() { cat > /dev/null }
cleanup_output() { : }
copy_to_clipboard() { : }

call_llm_api() {
    local temp_file="$3"
    local response='{"points": ["First point", "Second point", "Third point"]}'
    echo -n "$response"
    [[ -n "$temp_file" ]] && echo -n "$response" > "$temp_file"
}

typeset -gA PROMPT_TEMPLATES
typeset -gA TEMPLATE_PROPERTIES
PROMPT_TEMPLATES["PointsTemplate"]="List: {{input}}"
TEMPLATE_PROPERTIES["PointsTemplate"]="json_schema={points:[string]} json_field=points"
SELECTED_TEMPLATE="PointsTemplate"
USER_INPUT="test"
SELECTED_MODEL="test-model"
CLI_MODEL_OVERRIDE=false
VERBOSE_MODE=false

process_with_template
WRAPPER
            chmod +x "$TEST_SCRIPT"

            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT"
            The output should include "* First point"
            The output should include "* Second point"
            The output should include "* Third point"
        End

        It 'formats object arrays with title and description'
            cat > "$TEST_SCRIPT" << 'WRAPPER'
#!/bin/zsh
source "$1"
setup_output() { : }
write_to_output() { echo "$1" }
write_to_output_stream() { cat > /dev/null }
cleanup_output() { : }
copy_to_clipboard() { : }

call_llm_api() {
    local temp_file="$3"
    local response='{"items": [{"title": "Feature A", "description": "Does something"}, {"title": "Feature B", "description": "Does another thing"}]}'
    echo -n "$response"
    [[ -n "$temp_file" ]] && echo -n "$response" > "$temp_file"
}

typeset -gA PROMPT_TEMPLATES
typeset -gA TEMPLATE_PROPERTIES
PROMPT_TEMPLATES["FeaturesTemplate"]="List features: {{input}}"
TEMPLATE_PROPERTIES["FeaturesTemplate"]="json_schema={items:[{title:string,description:string}]} json_field=items"
SELECTED_TEMPLATE="FeaturesTemplate"
USER_INPUT="test"
SELECTED_MODEL="test-model"
CLI_MODEL_OVERRIDE=false
VERBOSE_MODE=false

process_with_template
WRAPPER
            chmod +x "$TEST_SCRIPT"

            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT"
            The output should include "* Feature A: Does something"
            The output should include "* Feature B: Does another thing"
        End
    End

    Describe 'error handling'
        It 'reports error when LLM returns empty response'
            cat > "$TEST_SCRIPT" << 'WRAPPER'
#!/bin/zsh
source "$1"
setup_output() { : }
write_to_output() { echo "$1" }
write_to_output_stream() { cat > /dev/null }
cleanup_output() { : }
copy_to_clipboard() { : }

call_llm_api() {
    local temp_file="$3"
    echo -n ""
    [[ -n "$temp_file" ]] && echo -n "" > "$temp_file"
}

typeset -gA PROMPT_TEMPLATES
typeset -gA TEMPLATE_PROPERTIES
PROMPT_TEMPLATES["Simple"]="Test: {{input}}"
SELECTED_TEMPLATE="Simple"
USER_INPUT="test"
SELECTED_MODEL="test-model"
CLI_MODEL_OVERRIDE=false
VERBOSE_MODE=false

process_with_template
WRAPPER
            chmod +x "$TEST_SCRIPT"

            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT"
            The status should be failure
            The output should include "No response received"
        End
    End

    Describe 'model selection integration'
        It 'uses template model when CLI override is false'
            cat > "$TEST_SCRIPT" << 'WRAPPER'
#!/bin/zsh
source "$1"
setup_output() { : }
write_to_output() { : }
write_to_output_stream() { cat > /dev/null }
cleanup_output() { : }
copy_to_clipboard() { : }

call_llm_api() {
    echo "MODEL_USED: $1" >&2
    local temp_file="$3"
    [[ -n "$temp_file" ]] && echo "response" > "$temp_file"
}

typeset -gA PROMPT_TEMPLATES
typeset -gA TEMPLATE_PROPERTIES
PROMPT_TEMPLATES["ModelTemplate"]="Test: {{input}}"
TEMPLATE_PROPERTIES["ModelTemplate"]="model=special-model"
SELECTED_TEMPLATE="ModelTemplate"
USER_INPUT="test"
SELECTED_MODEL="default-model"
CLI_MODEL_OVERRIDE=false
VERBOSE_MODE=false

process_with_template
WRAPPER
            chmod +x "$TEST_SCRIPT"

            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT"
            The stderr should include "MODEL_USED: special-model"
        End

        It 'uses CLI model when CLI override is true'
            cat > "$TEST_SCRIPT" << 'WRAPPER'
#!/bin/zsh
source "$1"
setup_output() { : }
write_to_output() { : }
write_to_output_stream() { cat > /dev/null }
cleanup_output() { : }
copy_to_clipboard() { : }

call_llm_api() {
    echo "MODEL_USED: $1" >&2
    local temp_file="$3"
    [[ -n "$temp_file" ]] && echo "response" > "$temp_file"
}

typeset -gA PROMPT_TEMPLATES
typeset -gA TEMPLATE_PROPERTIES
PROMPT_TEMPLATES["ModelTemplate"]="Test: {{input}}"
TEMPLATE_PROPERTIES["ModelTemplate"]="model=template-model"
SELECTED_TEMPLATE="ModelTemplate"
USER_INPUT="test"
SELECTED_MODEL="cli-model"
CLI_MODEL_OVERRIDE=true
VERBOSE_MODE=false

process_with_template
WRAPPER
            chmod +x "$TEST_SCRIPT"

            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT"
            The stderr should include "MODEL_USED: cli-model"
        End
    End
End
