# shellcheck shell=bash
# spec/unit/resolve_yaml_spec.sh

Describe 'resolve_yaml_in_dir()'
    Include "$GEMS_SCRIPT"

    setup() {
        TEST_DIR="$(mktemp -d)"
        CUSTOM_CONFIG_FILE=""
        TEMPLATE_YAML_FILE="gems.yml"
    }

    cleanup() {
        rm -rf "$TEST_DIR"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'finds gems.yml in directory'
        touch "$TEST_DIR/gems.yml"
        When call resolve_yaml_in_dir "$TEST_DIR"
        The output should equal "$TEST_DIR/gems.yml"
        The status should be success
    End

    It 'finds gems.yaml when gems.yml not present'
        touch "$TEST_DIR/gems.yaml"
        When call resolve_yaml_in_dir "$TEST_DIR"
        The output should equal "$TEST_DIR/gems.yaml"
        The status should be success
    End

    It 'prefers gems.yml over gems.yaml'
        touch "$TEST_DIR/gems.yml"
        touch "$TEST_DIR/gems.yaml"
        When call resolve_yaml_in_dir "$TEST_DIR"
        The output should equal "$TEST_DIR/gems.yml"
        The status should be success
    End

    It 'returns failure when no yaml file exists'
        When call resolve_yaml_in_dir "$TEST_DIR"
        The status should be failure
    End

    It 'returns failure for empty directory path'
        When call resolve_yaml_in_dir ""
        The status should be failure
    End

    It 'uses CUSTOM_CONFIG_FILE when set'
        touch "$TEST_DIR/custom.yml"
        touch "$TEST_DIR/gems.yml"
        CUSTOM_CONFIG_FILE="$TEST_DIR/custom.yml"
        When call resolve_yaml_in_dir "$TEST_DIR"
        The output should equal "$TEST_DIR/custom.yml"
        The status should be success
    End

    It 'respects TEMPLATE_YAML_FILE setting'
        touch "$TEST_DIR/myconfig.yml"
        TEMPLATE_YAML_FILE="myconfig.yml"
        When call resolve_yaml_in_dir "$TEST_DIR"
        The output should equal "$TEST_DIR/myconfig.yml"
        The status should be success
    End
End
