# shellcheck shell=bash
# spec/unit/build_api_url_spec.sh

Describe 'build_api_url()'
    Include "$GEMS_SCRIPT"

    It 'joins base URL and path correctly'
        API_BASE_URL="http://localhost:11434/v1"
        When call build_api_url "chat/completions"
        The output should equal "http://localhost:11434/v1/chat/completions"
    End

    It 'handles trailing slash in base URL'
        API_BASE_URL="http://localhost:11434/v1/"
        When call build_api_url "models"
        The output should equal "http://localhost:11434/v1/models"
    End

    It 'handles leading slash in path'
        API_BASE_URL="http://localhost:11434/v1"
        When call build_api_url "/chat/completions"
        The output should equal "http://localhost:11434/v1/chat/completions"
    End

    It 'handles both trailing and leading slashes'
        API_BASE_URL="http://localhost:11434/v1/"
        When call build_api_url "/models"
        The output should equal "http://localhost:11434/v1/models"
    End

    It 'returns base URL when path is empty'
        API_BASE_URL="http://localhost:11434/v1"
        When call build_api_url ""
        The output should equal "http://localhost:11434/v1"
    End
End
