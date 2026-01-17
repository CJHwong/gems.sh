# shellcheck shell=bash
# spec/unit/call_llm_api_spec.sh

# Tests for the core LLM API function
# Uses PATH manipulation to mock curl

Describe 'call_llm_api()'
    setup() {
        # Create mock directory
        MOCK_DIR="$(mktemp -d)"
        ORIGINAL_PATH="$PATH"
        PATH="$MOCK_DIR:$PATH"

        # Set required globals
        API_BASE_URL="http://localhost:11434/v1"
        API_TIMEOUT="30"
        API_KEY=""
        VERBOSE_MODE=false
        REASONING_EFFORT=""
    }

    cleanup() {
        PATH="$ORIGINAL_PATH"
        rm -rf "$MOCK_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    Include "$GEMS_SCRIPT"

    Describe 'streaming mode SSE parsing'
        It 'parses single SSE chunk correctly'
            cat > "$MOCK_DIR/curl" << 'MOCK'
#!/bin/zsh
echo 'data: {"choices":[{"delta":{"content":"Hello"}}]}'
echo 'data: [DONE]'
echo 'HTTP_STATUS:200'
MOCK
            chmod +x "$MOCK_DIR/curl"

            When call call_llm_api "model" "prompt" "" "true"
            The output should equal "Hello"
            The status should be success
        End

        It 'concatenates multiple SSE chunks'
            cat > "$MOCK_DIR/curl" << 'MOCK'
#!/bin/zsh
echo 'data: {"choices":[{"delta":{"content":"Hello"}}]}'
echo 'data: {"choices":[{"delta":{"content":" "}}]}'
echo 'data: {"choices":[{"delta":{"content":"World"}}]}'
echo 'data: [DONE]'
echo 'HTTP_STATUS:200'
MOCK
            chmod +x "$MOCK_DIR/curl"

            When call call_llm_api "model" "prompt" "" "true"
            The output should equal "Hello World"
            The status should be success
        End

        It 'handles empty delta content gracefully'
            cat > "$MOCK_DIR/curl" << 'MOCK'
#!/bin/zsh
echo 'data: {"choices":[{"delta":{}}]}'
echo 'data: {"choices":[{"delta":{"content":"Text"}}]}'
echo 'data: {"choices":[{"delta":{"content":""}}]}'
echo 'data: [DONE]'
echo 'HTTP_STATUS:200'
MOCK
            chmod +x "$MOCK_DIR/curl"

            When call call_llm_api "model" "prompt" "" "true"
            The output should equal "Text"
            The status should be success
        End

        It 'saves output to temp file when provided'
            cat > "$MOCK_DIR/curl" << 'MOCK'
#!/bin/zsh
echo 'data: {"choices":[{"delta":{"content":"Saved"}}]}'
echo 'data: [DONE]'
echo 'HTTP_STATUS:200'
MOCK
            chmod +x "$MOCK_DIR/curl"

            TEMP_OUTPUT="$(mktemp)"
            When call call_llm_api "model" "prompt" "$TEMP_OUTPUT" "true"
            The status should be success
            The output should equal "Saved"
            The contents of file "$TEMP_OUTPUT" should equal "Saved"
            rm -f "$TEMP_OUTPUT"
        End

        It 'handles quotes in response'
            cat > "$MOCK_DIR/curl" << 'MOCK'
#!/bin/zsh
echo 'data: {"choices":[{"delta":{"content":"Say \"hello\""}}]}'
echo 'data: [DONE]'
echo 'HTTP_STATUS:200'
MOCK
            chmod +x "$MOCK_DIR/curl"

            When call call_llm_api "model" "prompt" "" "true"
            The output should include "hello"
            The status should be success
        End
    End

    Describe 'non-streaming mode'
        It 'extracts message content correctly'
            cat > "$MOCK_DIR/curl" << 'MOCK'
#!/bin/zsh
echo '{"choices":[{"message":{"content":"Non-stream response"}}]}'
MOCK
            chmod +x "$MOCK_DIR/curl"

            When call call_llm_api "model" "prompt" "" "false"
            The output should equal "Non-stream response"
        End

        It 'handles empty response'
            cat > "$MOCK_DIR/curl" << 'MOCK'
#!/bin/zsh
echo '{}'
MOCK
            chmod +x "$MOCK_DIR/curl"

            When call call_llm_api "model" "prompt" "" "false"
            The output should equal ""
        End
    End

    Describe 'error handling'
        It 'returns failure when no SSE data received'
            cat > "$MOCK_DIR/curl" << 'MOCK'
#!/bin/zsh
echo '{"error":{"message":"Model not found"}}'
echo 'HTTP_STATUS:404'
MOCK
            chmod +x "$MOCK_DIR/curl"

            When call call_llm_api "model" "prompt" "" "true"
            The status should be failure
            The stderr should include "API Error"
        End

        It 'reports HTTP status on error'
            cat > "$MOCK_DIR/curl" << 'MOCK'
#!/bin/zsh
echo '{"error":"unauthorized"}'
echo 'HTTP_STATUS:401'
MOCK
            chmod +x "$MOCK_DIR/curl"

            When call call_llm_api "model" "prompt" "" "true"
            The status should be failure
            The stderr should include "401"
        End

        It 'handles curl failure'
            cat > "$MOCK_DIR/curl" << 'MOCK'
#!/bin/zsh
exit 7  # curl exit code for connection refused
MOCK
            chmod +x "$MOCK_DIR/curl"

            When call call_llm_api "model" "prompt" "" "true"
            The status should be failure
            The stderr should include "Error"
        End
    End

    Describe 'API key handling'
        It 'works without API key'
            cat > "$MOCK_DIR/curl" << 'MOCK'
#!/bin/zsh
echo 'data: {"choices":[{"delta":{"content":"OK"}}]}'
echo 'data: [DONE]'
echo 'HTTP_STATUS:200'
MOCK
            chmod +x "$MOCK_DIR/curl"

            API_KEY=""
            When call call_llm_api "model" "prompt" "" "true"
            The output should equal "OK"
        End
    End

    Describe 'real-world SSE patterns'
        It 'handles typical OpenAI streaming response'
            cat > "$MOCK_DIR/curl" << 'MOCK'
#!/bin/zsh
echo 'data: {"id":"chatcmpl-123","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}'
echo 'data: {"id":"chatcmpl-123","choices":[{"index":0,"delta":{"content":"The"},"finish_reason":null}]}'
echo 'data: {"id":"chatcmpl-123","choices":[{"index":0,"delta":{"content":" answer"},"finish_reason":null}]}'
echo 'data: {"id":"chatcmpl-123","choices":[{"index":0,"delta":{"content":" is"},"finish_reason":null}]}'
echo 'data: {"id":"chatcmpl-123","choices":[{"index":0,"delta":{"content":" 42"},"finish_reason":null}]}'
echo 'data: {"id":"chatcmpl-123","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}'
echo 'data: [DONE]'
echo ''
echo 'HTTP_STATUS:200'
MOCK
            chmod +x "$MOCK_DIR/curl"

            When call call_llm_api "model" "What is the answer?" "" "true"
            The output should equal "The answer is 42"
            The status should be success
        End
    End
End
