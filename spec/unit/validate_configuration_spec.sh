# shellcheck shell=bash
# spec/unit/validate_configuration_spec.sh

Describe 'validate_configuration()'
    Include "$GEMS_SCRIPT"

    setup() {
        # Set all required configuration variables
        API_BASE_URL="http://localhost:11434/v1"
        DEFAULT_MODEL="test-model"
        API_TIMEOUT="120"
    }

    BeforeEach 'setup'

    Describe 'with valid configuration'
        It 'returns success when all required variables are set'
            When call validate_configuration
            The status should be success
            The output should equal ""
        End
    End

    Describe 'with missing API_BASE_URL'
        It 'returns failure and shows error'
            API_BASE_URL=""
            When call validate_configuration
            The status should be failure
            The output should include "API_BASE_URL is not configured"
        End
    End

    Describe 'with missing DEFAULT_MODEL'
        It 'returns failure and shows error'
            DEFAULT_MODEL=""
            When call validate_configuration
            The status should be failure
            The output should include "DEFAULT_MODEL is not configured"
        End
    End

    Describe 'with missing API_TIMEOUT'
        It 'returns failure and shows error'
            API_TIMEOUT=""
            When call validate_configuration
            The status should be failure
            The output should include "API_TIMEOUT is not configured"
        End
    End

    Describe 'with multiple missing variables'
        It 'reports all missing variables'
            API_BASE_URL=""
            DEFAULT_MODEL=""
            API_TIMEOUT=""
            When call validate_configuration
            The status should be failure
            The output should include "API_BASE_URL is not configured"
            The output should include "DEFAULT_MODEL is not configured"
            The output should include "API_TIMEOUT is not configured"
        End

        It 'returns error count matching number of missing variables'
            API_BASE_URL=""
            DEFAULT_MODEL=""
            # API_TIMEOUT is still set
            When call validate_configuration
            The status should equal 2
            The output should include "API_BASE_URL"
            The output should include "DEFAULT_MODEL"
        End
    End
End
