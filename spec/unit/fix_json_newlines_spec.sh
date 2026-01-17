# shellcheck shell=bash
# spec/unit/fix_json_newlines_spec.sh

Describe 'fix_json_string_newlines()'
    Include "$GEMS_SCRIPT"

    It 'escapes literal newlines inside JSON string values'
        input='{"text": "line1
line2"}'
        expected='{"text": "line1\nline2"}'
        When call fix_json_string_newlines "$input"
        The output should equal "$expected"
    End

    It 'preserves newlines outside of strings'
        input='{
  "key": "value"
}'
        When call fix_json_string_newlines "$input"
        The output should include '"key": "value"'
        # Newlines outside strings should be preserved
        The output should include $'\n'
    End

    It 'handles escaped quotes inside strings'
        input='{"text": "say \"hello\""}'
        When call fix_json_string_newlines "$input"
        The output should equal '{"text": "say \"hello\""}'
    End

    It 'handles multiple string fields'
        input='{"a": "line1
line2", "b": "line3
line4"}'
        When call fix_json_string_newlines "$input"
        The output should include 'line1\nline2'
        The output should include 'line3\nline4'
    End

    It 'passes through valid JSON unchanged'
        input='{"text": "no newlines here"}'
        When call fix_json_string_newlines "$input"
        The output should equal "$input"
    End

    It 'handles empty strings'
        input='{"text": ""}'
        When call fix_json_string_newlines "$input"
        The output should equal "$input"
    End
End
