# shellcheck shell=bash
# spec/unit/load_configuration_spec.sh

Describe 'load_configuration_from_yaml()'
    Include "$GEMS_SCRIPT"

    setup() {
        # Reset configuration variables
        API_BASE_URL=""
        API_KEY=""
        API_TIMEOUT=""
        DEFAULT_MODEL=""
        LANGUAGE_DETECTION_MODEL=""
        DEFAULT_PROMPT_TEMPLATE=""
        REASONING_EFFORT=""
        RESULT_VIEWER_APP=""
        VERBOSE_MODE=false
    }

    BeforeEach 'setup'

    Describe 'with valid configuration file'
        It 'loads all required configuration values'
            When call load_configuration_from_yaml "$FIXTURES_DIR/test_gems.yml"
            The status should be success
            The variable API_BASE_URL should equal "http://localhost:11434/v1"
            The variable DEFAULT_MODEL should equal "default-model"
            The variable API_TIMEOUT should equal "120"
        End

        It 'loads language detection model'
            When call load_configuration_from_yaml "$FIXTURES_DIR/test_gems.yml"
            The status should be success
            The variable LANGUAGE_DETECTION_MODEL should equal "lang-detect-model"
        End

        It 'loads default prompt template'
            When call load_configuration_from_yaml "$FIXTURES_DIR/test_gems.yml"
            The status should be success
            The variable DEFAULT_PROMPT_TEMPLATE should equal "Passthrough"
        End

        It 'handles empty optional values'
            When call load_configuration_from_yaml "$FIXTURES_DIR/test_gems.yml"
            The status should be success
            The variable API_KEY should equal ""
            The variable RESULT_VIEWER_APP should equal ""
        End
    End

    Describe 'with missing file'
        It 'returns failure for non-existent file'
            When call load_configuration_from_yaml "/nonexistent/path/gems.yml"
            The status should be failure
            The stderr should include "Configuration file not found"
        End
    End

    Describe 'with invalid configuration'
        setup_invalid_config() {
            INVALID_CONFIG="$(mktemp)"
            cat > "$INVALID_CONFIG" << 'EOF'
configuration:
  api_key: "test"
  # Missing required fields
EOF
        }

        cleanup_invalid_config() {
            rm -f "$INVALID_CONFIG"
        }

        BeforeEach 'setup_invalid_config'
        AfterEach 'cleanup_invalid_config'

        It 'returns failure when api_base_url is missing'
            When call load_configuration_from_yaml "$INVALID_CONFIG"
            The status should be failure
            The stderr should include "api_base_url not found"
        End
    End

    Describe 'verbose logging'
        It 'logs configuration details in verbose mode'
            VERBOSE_MODE=true
            When call load_configuration_from_yaml "$FIXTURES_DIR/test_gems.yml"
            The status should be success
            The stderr should include "Loading configuration"
        End
    End
End
