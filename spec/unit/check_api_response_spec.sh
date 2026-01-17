# shellcheck shell=bash
# spec/unit/check_api_response_spec.sh

Describe 'check_api_response()'
    Include "$GEMS_SCRIPT"

    setup() {
        VERBOSE_MODE=false
    }

    BeforeEach 'setup'

    Describe 'successful responses'
        It 'returns success for HTTP 200'
            When call check_api_response '{"result": "ok"}' "200"
            The status should be success
        End

        It 'returns success for HTTP 201'
            When call check_api_response '{"result": "created"}' "201"
            The status should be success
        End
    End

    Describe 'client errors'
        It 'returns failure for HTTP 400 Bad Request'
            When call check_api_response '{"error": {"message": "Invalid request"}}' "400"
            The status should be failure
        End

        It 'returns failure for HTTP 401 Unauthorized'
            When call check_api_response '{"error": "unauthorized"}' "401"
            The status should be failure
        End

        It 'returns failure for HTTP 404 Not Found'
            When call check_api_response '{"error": {"message": "Model not found"}}' "404"
            The status should be failure
        End

        It 'returns failure for HTTP 429 Rate Limit'
            When call check_api_response '{"error": "rate limited"}' "429"
            The status should be failure
        End
    End

    Describe 'server errors'
        It 'returns failure for HTTP 500'
            When call check_api_response '{"error": "internal error"}' "500"
            The status should be failure
        End

        It 'returns failure for HTTP 502'
            When call check_api_response '{"error": "bad gateway"}' "502"
            The status should be failure
        End

        It 'returns failure for HTTP 503'
            When call check_api_response '{"error": "service unavailable"}' "503"
            The status should be failure
        End
    End

    Describe 'edge cases'
        It 'returns failure for empty response'
            When call check_api_response "" "200"
            The status should be failure
        End

        It 'returns failure for unexpected HTTP code'
            When call check_api_response '{"result": "ok"}' "418"
            The status should be failure
        End

        It 'handles response without error message'
            When call check_api_response '{}' "400"
            The status should be failure
        End
    End

    Describe 'verbose logging'
        It 'logs success message in verbose mode'
            VERBOSE_MODE=true
            When call check_api_response '{"result": "ok"}' "200"
            The status should be success
            The stderr should include "API call successful"
        End

        It 'logs error message in verbose mode for 401'
            VERBOSE_MODE=true
            When call check_api_response '{}' "401"
            The status should be failure
            The stderr should include "Unauthorized"
        End

        It 'logs rate limit message in verbose mode'
            VERBOSE_MODE=true
            When call check_api_response '{}' "429"
            The status should be failure
            The stderr should include "Rate limit exceeded"
        End
    End
End
