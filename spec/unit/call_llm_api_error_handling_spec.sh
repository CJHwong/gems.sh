# shellcheck shell=bash
# spec/unit/call_llm_api_error_handling_spec.sh

# Tests for call_llm_api_with_error_handling - the wrapper with retry/error logic

Describe 'call_llm_api_with_error_handling()'

    setup() {
        MOCK_DIR="$(mktemp -d)"
        ORIGINAL_PATH="$PATH"

        # Create wrapper script to test the function
        TEST_SCRIPT="$(mktemp)"
        cat > "$TEST_SCRIPT" << 'WRAPPER'
#!/bin/zsh
GEMS_SCRIPT="$1"
MOCK_DIR="$2"
CURL_BEHAVIOR="$3"

source "$GEMS_SCRIPT"

# Override build_api_url to return predictable URL
build_api_url() { echo "http://test-api/v1/$1"; }

# Set required globals
API_TIMEOUT=30
API_KEY=""
VERBOSE_MODE=false

# Prepend mock dir to PATH for curl override
export PATH="$MOCK_DIR:$PATH"

# Run the function (non-streaming to test error handling path)
call_llm_api_with_error_handling "test-model" "test prompt" "false"
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

    Describe 'successful API response'
        It 'extracts content from valid JSON response'
            cat > "$MOCK_DIR/curl" << 'MOCK'
#!/bin/zsh
# Parse args to find -o (output file)
output_file=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) output_file="$2"; shift 2 ;;
        *) shift ;;
    esac
done
# Write successful response
echo '{"choices":[{"message":{"content":"Hello from API"}}]}' > "$output_file"
# Print HTTP status code (curl -w "%{http_code}")
echo -n "200"
MOCK
            chmod +x "$MOCK_DIR/curl"

            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT" "$MOCK_DIR" "success"
            The output should equal "Hello from API"
            The status should be success
        End

        It 'handles empty content gracefully'
            cat > "$MOCK_DIR/curl" << 'MOCK'
#!/bin/zsh
output_file=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) output_file="$2"; shift 2 ;;
        *) shift ;;
    esac
done
echo '{"choices":[{"message":{"content":""}}]}' > "$output_file"
echo -n "200"
MOCK
            chmod +x "$MOCK_DIR/curl"

            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT" "$MOCK_DIR" "empty"
            The output should equal ""
            The status should be success
        End
    End

    Describe 'API error handling'
        It 'returns failure on HTTP 401 Unauthorized'
            cat > "$MOCK_DIR/curl" << 'MOCK'
#!/bin/zsh
output_file=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) output_file="$2"; shift 2 ;;
        *) shift ;;
    esac
done
echo '{"error":{"message":"Invalid API key"}}' > "$output_file"
echo -n "401"
MOCK
            chmod +x "$MOCK_DIR/curl"

            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT" "$MOCK_DIR" "auth_error"
            The status should be failure
        End

        It 'returns failure on HTTP 404 Not Found'
            cat > "$MOCK_DIR/curl" << 'MOCK'
#!/bin/zsh
output_file=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) output_file="$2"; shift 2 ;;
        *) shift ;;
    esac
done
echo '{"error":{"message":"Model not found"}}' > "$output_file"
echo -n "404"
MOCK
            chmod +x "$MOCK_DIR/curl"

            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT" "$MOCK_DIR" "not_found"
            The status should be failure
        End

        It 'returns failure on HTTP 500 Server Error'
            cat > "$MOCK_DIR/curl" << 'MOCK'
#!/bin/zsh
output_file=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) output_file="$2"; shift 2 ;;
        *) shift ;;
    esac
done
echo '{"error":{"message":"Internal server error"}}' > "$output_file"
echo -n "500"
MOCK
            chmod +x "$MOCK_DIR/curl"

            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT" "$MOCK_DIR" "server_error"
            The status should be failure
        End

        It 'returns failure on HTTP 429 Rate Limit'
            cat > "$MOCK_DIR/curl" << 'MOCK'
#!/bin/zsh
output_file=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) output_file="$2"; shift 2 ;;
        *) shift ;;
    esac
done
echo '{"error":{"message":"Rate limit exceeded"}}' > "$output_file"
echo -n "429"
MOCK
            chmod +x "$MOCK_DIR/curl"

            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT" "$MOCK_DIR" "rate_limit"
            The status should be failure
        End
    End

    Describe 'network error handling'
        It 'returns curl exit code on connection failure'
            cat > "$MOCK_DIR/curl" << 'MOCK'
#!/bin/zsh
# Simulate connection refused (curl exit code 7)
exit 7
MOCK
            chmod +x "$MOCK_DIR/curl"

            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT" "$MOCK_DIR" "network_error"
            The status should equal 7
        End

        It 'returns curl exit code on timeout'
            cat > "$MOCK_DIR/curl" << 'MOCK'
#!/bin/zsh
# Simulate timeout (curl exit code 28)
exit 28
MOCK
            chmod +x "$MOCK_DIR/curl"

            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT" "$MOCK_DIR" "timeout"
            The status should equal 28
        End
    End

    Describe 'streaming mode delegation'
        It 'delegates to call_llm_api when stream=true'
            cat > "$TEST_SCRIPT" << 'WRAPPER'
#!/bin/zsh
source "$1"

# Track which function was called
CALL_LLM_API_CALLED=false

call_llm_api() {
    CALL_LLM_API_CALLED=true
    echo "DELEGATED_TO_CALL_LLM_API"
}

API_TIMEOUT=30
API_KEY=""
VERBOSE_MODE=false

# Call with streaming enabled (default)
call_llm_api_with_error_handling "test-model" "test prompt" "true"
WRAPPER
            chmod +x "$TEST_SCRIPT"

            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT"
            The output should include "DELEGATED_TO_CALL_LLM_API"
        End
    End

    Describe 'API key handling'
        It 'includes Authorization header when API_KEY is set'
            cat > "$TEST_SCRIPT" << 'WRAPPER'
#!/bin/zsh
MOCK_DIR="$2"
source "$1"

build_api_url() { echo "http://test-api/v1/$1"; }
API_TIMEOUT=30
API_KEY="test-secret-key"
VERBOSE_MODE=false

export PATH="$MOCK_DIR:$PATH"
call_llm_api_with_error_handling "test-model" "test prompt" "false"
WRAPPER
            chmod +x "$TEST_SCRIPT"

            # Mock curl that checks for auth header
            cat > "$MOCK_DIR/curl" << 'MOCK'
#!/bin/zsh
output_file=""
has_auth=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) output_file="$2"; shift 2 ;;
        -H)
            if [[ "$2" == "Authorization: Bearer"* ]]; then
                has_auth=true
            fi
            shift 2
            ;;
        *) shift ;;
    esac
done
if [[ "$has_auth" == "true" ]]; then
    echo '{"choices":[{"message":{"content":"Auth OK"}}]}' > "$output_file"
else
    echo '{"choices":[{"message":{"content":"No Auth"}}]}' > "$output_file"
fi
echo -n "200"
MOCK
            chmod +x "$MOCK_DIR/curl"

            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT" "$MOCK_DIR"
            The output should equal "Auth OK"
        End
    End

    Describe 'reasoning effort parameter'
        It 'includes reasoning_effort in payload when REASONING_EFFORT is set'
            cat > "$TEST_SCRIPT" << 'WRAPPER'
#!/bin/zsh
MOCK_DIR="$2"
source "$1"

build_api_url() { echo "http://test-api/v1/$1"; }
API_TIMEOUT=30
API_KEY=""
REASONING_EFFORT="high"
VERBOSE_MODE=false

export PATH="$MOCK_DIR:$PATH"
call_llm_api_with_error_handling "test-model" "test prompt" "false"
WRAPPER
            chmod +x "$TEST_SCRIPT"

            # Mock curl that captures the JSON payload
            cat > "$MOCK_DIR/curl" << 'MOCK'
#!/bin/zsh
output_file=""
payload=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) output_file="$2"; shift 2 ;;
        -d) payload="$2"; shift 2 ;;
        *) shift ;;
    esac
done
# Check if reasoning_effort is in payload
if echo "$payload" | grep -q '"reasoning_effort"'; then
    echo '{"choices":[{"message":{"content":"Has reasoning_effort"}}]}' > "$output_file"
else
    echo '{"choices":[{"message":{"content":"No reasoning_effort"}}]}' > "$output_file"
fi
echo -n "200"
MOCK
            chmod +x "$MOCK_DIR/curl"

            When run zsh "$TEST_SCRIPT" "$GEMS_SCRIPT" "$MOCK_DIR"
            The output should equal "Has reasoning_effort"
        End
    End
End
