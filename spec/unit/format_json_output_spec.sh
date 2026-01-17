# shellcheck shell=bash
# spec/unit/format_json_output_spec.sh

Describe 'format_json_in_output_file()'
    Include "$GEMS_SCRIPT"

    setup() {
        TEST_FILE="$(mktemp)"
    }

    cleanup() {
        rm -f "$TEST_FILE"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    Describe 'compact JSON formatting'
        It 'expands single-line compact JSON to multi-line'
            echo '```json{"name":"test","value":123}```' > "$TEST_FILE"
            When call format_json_in_output_file "$TEST_FILE"
            The status should be success
            The contents of file "$TEST_FILE" should include '"name": "test"'
            The contents of file "$TEST_FILE" should include '"value": 123'
        End

        It 'wraps formatted JSON in code fence'
            echo '```json{"key":"value"}```' > "$TEST_FILE"
            When call format_json_in_output_file "$TEST_FILE"
            The line 1 of contents of file "$TEST_FILE" should equal '```json'
            The contents of file "$TEST_FILE" should include '```'
        End

        It 'handles nested objects'
            echo '```json{"outer":{"inner":"value"}}```' > "$TEST_FILE"
            When call format_json_in_output_file "$TEST_FILE"
            The contents of file "$TEST_FILE" should include '"outer":'
            The contents of file "$TEST_FILE" should include '"inner": "value"'
        End

        It 'handles arrays'
            echo '```json{"items":["a","b","c"]}```' > "$TEST_FILE"
            When call format_json_in_output_file "$TEST_FILE"
            The contents of file "$TEST_FILE" should include '"items":'
            The contents of file "$TEST_FILE" should include '"a"'
        End
    End

    Describe 'preserving non-JSON content'
        It 'preserves regular text lines'
            cat > "$TEST_FILE" << 'EOF'
# Header
Some regular text
More text here
EOF
            When call format_json_in_output_file "$TEST_FILE"
            The contents of file "$TEST_FILE" should include '# Header'
            The contents of file "$TEST_FILE" should include 'Some regular text'
        End

        It 'preserves multiline JSON blocks unchanged'
            cat > "$TEST_FILE" << 'EOF'
```json
{
  "already": "formatted"
}
```
EOF
            When call format_json_in_output_file "$TEST_FILE"
            The contents of file "$TEST_FILE" should include '"already": "formatted"'
        End

        It 'preserves mixed content with compact JSON'
            cat > "$TEST_FILE" << 'EOF'
# Result
```json{"status":"ok"}```
Done processing.
EOF
            When call format_json_in_output_file "$TEST_FILE"
            The contents of file "$TEST_FILE" should include '# Result'
            The contents of file "$TEST_FILE" should include '"status": "ok"'
            The contents of file "$TEST_FILE" should include 'Done processing.'
        End
    End

    Describe 'invalid JSON handling'
        It 'keeps original line when JSON is invalid'
            echo '```json{invalid json here}```' > "$TEST_FILE"
            When call format_json_in_output_file "$TEST_FILE"
            The contents of file "$TEST_FILE" should include '{invalid json here}'
        End

        It 'keeps original when JSON has syntax error'
            echo '```json{"key": "missing closing brace"```' > "$TEST_FILE"
            When call format_json_in_output_file "$TEST_FILE"
            The contents of file "$TEST_FILE" should include 'missing closing brace'
        End
    End

    Describe 'edge cases'
        It 'handles empty file'
            : > "$TEST_FILE"  # Create empty file
            When call format_json_in_output_file "$TEST_FILE"
            The status should be success
            The contents of file "$TEST_FILE" should equal ""
        End

        It 'returns success for non-existent file'
            rm -f "$TEST_FILE"
            When call format_json_in_output_file "$TEST_FILE"
            The status should be success
        End

        It 'handles JSON with special characters'
            echo '```json{"message":"hello \"world\""}```' > "$TEST_FILE"
            When call format_json_in_output_file "$TEST_FILE"
            The contents of file "$TEST_FILE" should include 'hello \"world\"'
        End

        It 'handles JSON with unicode'
            echo '```json{"text":"你好世界"}```' > "$TEST_FILE"
            When call format_json_in_output_file "$TEST_FILE"
            The contents of file "$TEST_FILE" should include '你好世界'
        End

        It 'handles multiple compact JSON blocks in one file'
            cat > "$TEST_FILE" << 'EOF'
First result:
```json{"a":1}```
Second result:
```json{"b":2}```
EOF
            When call format_json_in_output_file "$TEST_FILE"
            The contents of file "$TEST_FILE" should include '"a": 1'
            The contents of file "$TEST_FILE" should include '"b": 2'
        End
    End

    Describe 'complex real-world scenarios'
        It 'handles LLM response with analysis JSON'
            cat > "$TEST_FILE" << 'EOF'
### Result

#### Raw JSON Output

```json{"analysis":{"sentiment":"positive","confidence":0.95},"summary":"Good feedback"}```

---

#### Extracted Field
EOF
            When call format_json_in_output_file "$TEST_FILE"
            The contents of file "$TEST_FILE" should include '"sentiment": "positive"'
            The contents of file "$TEST_FILE" should include '"confidence": 0.95'
            The contents of file "$TEST_FILE" should include '### Result'
            The contents of file "$TEST_FILE" should include '#### Extracted Field'
        End
    End
End
