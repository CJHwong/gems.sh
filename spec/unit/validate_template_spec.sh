# shellcheck shell=bash
# spec/unit/validate_template_spec.sh

# Note: validate_template() accesses associative arrays in ways that require lenient mode
# We use a wrapper script approach to test in a subshell

Describe 'validate_template()'

    setup() {
        TEST_SCRIPT="$(mktemp)"
        cat > "$TEST_SCRIPT" << 'SCRIPT'
#!/bin/zsh
source "$1"

# Set up test templates
typeset -gA PROMPT_TEMPLATES
PROMPT_TEMPLATES["Passthrough"]="{{input}}"
PROMPT_TEMPLATES["TestTemplate"]="Test: {{input}}"
PROMPT_TEMPLATES["AnotherTemplate"]="Another: {{input}}"

# Set the template to validate
SELECTED_TEMPLATE="$2"

# Add special template if provided
if [[ -n "$3" ]]; then
    PROMPT_TEMPLATES["$3"]="Special: {{input}}"
fi

validate_template
echo "VALIDATION_SUCCESS"
SCRIPT
        chmod +x "$TEST_SCRIPT"
    }

    cleanup() {
        rm -f "$TEST_SCRIPT"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    Describe 'with valid template'
        It 'succeeds when template exists'
            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT" "Passthrough"
            The status should be success
            The output should include "VALIDATION_SUCCESS"
        End
    End

    Describe 'with invalid template'
        It 'exits with error when template not found'
            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT" "NonExistentTemplate"
            The status should be failure
            The output should include "Template 'NonExistentTemplate' not found"
        End

        It 'shows available templates in error message'
            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT" "BadTemplate"
            The status should be failure
            The output should include "Available templates:"
        End
    End

    Describe 'edge cases'
        It 'handles template names with special characters'
            # Third argument adds the special template
            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT" "My-Template_v2" "My-Template_v2"
            The status should be success
            The output should include "VALIDATION_SUCCESS"
        End

        It 'is case-sensitive'
            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT" "passthrough"
            The status should be failure
            The output should include "not found"
        End
    End
End
