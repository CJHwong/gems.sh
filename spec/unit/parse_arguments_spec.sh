# shellcheck shell=bash
# spec/unit/parse_arguments_spec.sh

# Note: parse_arguments() uses array indexing that requires lenient mode
# We use 'run source' approach to test in a subshell

Describe 'parse_arguments()'
    # Create a wrapper script that sources gems.sh and calls parse_arguments
    # This avoids Zsh strict mode issues with array access

    setup() {
        TEST_SCRIPT="$(mktemp)"
        cat > "$TEST_SCRIPT" << 'SCRIPT'
#!/bin/zsh
source "$1"
parse_arguments "${@:2}"
echo "SELECTED_MODEL=$SELECTED_MODEL"
echo "SELECTED_TEMPLATE=$SELECTED_TEMPLATE"
echo "VERBOSE_MODE=$VERBOSE_MODE"
echo "CLI_MODEL_OVERRIDE=$CLI_MODEL_OVERRIDE"
echo "USER_INPUT=$USER_INPUT"
SCRIPT
        chmod +x "$TEST_SCRIPT"
    }

    cleanup() {
        rm -f "$TEST_SCRIPT"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    Describe 'model selection with -m flag'
        It 'sets SELECTED_MODEL when -m is provided'
            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT" -m "test-model" "some input"
            The output should include "SELECTED_MODEL=test-model"
        End

        It 'sets CLI_MODEL_OVERRIDE to true when -m is provided'
            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT" -m "test-model" "some input"
            The output should include "CLI_MODEL_OVERRIDE=true"
        End
    End

    Describe 'template selection with -t flag'
        It 'sets SELECTED_TEMPLATE when -t is provided'
            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT" -t "TestTemplate" "some input"
            The output should include "SELECTED_TEMPLATE=TestTemplate"
        End
    End

    Describe 'verbose mode with -v flag'
        It 'sets VERBOSE_MODE to true when -v is provided'
            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT" -v "some input"
            The output should include "VERBOSE_MODE=true"
        End

        It 'sets VERBOSE_MODE to false when -v is not provided'
            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT" "some input"
            The output should include "VERBOSE_MODE=false"
        End
    End

    Describe 'user input handling'
        It 'captures single word input'
            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT" "hello"
            The output should include "USER_INPUT=hello"
        End

        It 'captures multi-word input'
            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT" "hello world test"
            The output should include "USER_INPUT=hello world test"
        End

        It 'captures input after flags'
            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT" -t "Template" -v "input text here"
            The output should include "USER_INPUT=input text here"
        End
    End

    Describe 'combined flags'
        It 'handles -m and -t together'
            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT" -m "model" -t "template" "input"
            The output should include "SELECTED_MODEL=model"
            The output should include "SELECTED_TEMPLATE=template"
            The output should include "USER_INPUT=input"
        End

        It 'handles -m, -t, and -v together'
            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT" -m "model" -t "template" -v "input"
            The output should include "SELECTED_MODEL=model"
            The output should include "SELECTED_TEMPLATE=template"
            The output should include "VERBOSE_MODE=true"
        End
    End

    Describe 'config file with -c flag'
        It 'sets CUSTOM_CONFIG_FILE when -c is provided with valid file'
            # Create a temp config file
            TEMP_CONFIG="$(mktemp)"
            echo "configuration:" > "$TEMP_CONFIG"

            # Modify wrapper to also output CUSTOM_CONFIG_FILE
            cat > "$TEST_SCRIPT" << 'SCRIPT'
#!/bin/zsh
source "$1"
parse_arguments "${@:2}"
echo "CUSTOM_CONFIG_FILE=$CUSTOM_CONFIG_FILE"
SCRIPT
            chmod +x "$TEST_SCRIPT"

            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT" -c "$TEMP_CONFIG" "input"
            The output should include "CUSTOM_CONFIG_FILE=$TEMP_CONFIG"
            rm -f "$TEMP_CONFIG"
        End

        It 'exits with error when -c config file not found'
            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT" -c "/nonexistent/config.yml" "input"
            The status should be failure
            The stderr should include "Config file not found"
        End
    End

    Describe 'error handling'
        It 'exits with error when no input provided'
            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT" -t "Template"
            The status should be failure
            The output should include "No input provided"
        End
    End
End
