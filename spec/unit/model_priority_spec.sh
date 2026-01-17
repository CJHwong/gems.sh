# shellcheck shell=bash
# spec/unit/model_priority_spec.sh

Describe 'Model priority selection'
    Include "$GEMS_SCRIPT"

    # Helper function to test model priority logic
    # Extracts the effective model determination logic from process_with_template
    determine_effective_model() {
        local template_model="$1"
        local effective_model="$SELECTED_MODEL"

        if [[ "$CLI_MODEL_OVERRIDE" == "true" ]]; then
            effective_model="$SELECTED_MODEL"
        elif [[ -n "$template_model" ]]; then
            effective_model="$template_model"
        fi

        echo "$effective_model"
    }

    Describe 'priority chain: CLI > template > default'

        It 'uses CLI model when -m flag is provided (highest priority)'
            CLI_MODEL_OVERRIDE=true
            SELECTED_MODEL="cli-model"
            When call determine_effective_model "template-model"
            The output should equal "cli-model"
        End

        It 'uses template model when CLI not specified'
            CLI_MODEL_OVERRIDE=false
            SELECTED_MODEL="default-model"
            When call determine_effective_model "template-model"
            The output should equal "template-model"
        End

        It 'uses default model when neither CLI nor template specified'
            CLI_MODEL_OVERRIDE=false
            SELECTED_MODEL="default-model"
            When call determine_effective_model ""
            The output should equal "default-model"
        End

        It 'CLI overrides template even when template has model'
            CLI_MODEL_OVERRIDE=true
            SELECTED_MODEL="user-specified-model"
            When call determine_effective_model "codellama"
            The output should equal "user-specified-model"
        End
    End

End

Describe 'get_template_property()'
    Include "$GEMS_SCRIPT"

    setup() {
        # Initialize associative arrays (zsh syntax)
        typeset -gA TEMPLATE_PROPERTIES
        VERBOSE_MODE=false
    }

    BeforeEach 'setup'

    It 'extracts model property from template'
        TEMPLATE_PROPERTIES["TestTemplate"]="detect_language=true model=custom-model"
        When call get_template_property "TestTemplate" "model" ""
        The output should equal "custom-model"
        The status should be success
    End

    It 'extracts detect_language property'
        TEMPLATE_PROPERTIES["TestTemplate"]="detect_language=true json_field=text"
        When call get_template_property "TestTemplate" "detect_language" "false"
        The output should equal "true"
        The status should be success
    End

    It 'returns default when property not found'
        TEMPLATE_PROPERTIES["TestTemplate"]="detect_language=true"
        When call get_template_property "TestTemplate" "model" "fallback-model"
        The output should equal "fallback-model"
        The status should be failure
    End

    It 'returns default when template has no properties'
        # Empty properties
        TEMPLATE_PROPERTIES["EmptyTemplate"]=""
        When call get_template_property "EmptyTemplate" "model" "default"
        The output should equal "default"
        The status should be failure
    End

    It 'extracts json_field property'
        TEMPLATE_PROPERTIES["JsonTemplate"]="json_schema={} json_field=summary"
        When call get_template_property "JsonTemplate" "json_field" ""
        The output should equal "summary"
        The status should be success
    End
End
