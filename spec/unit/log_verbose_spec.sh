# shellcheck shell=bash
# spec/unit/log_verbose_spec.sh

Describe 'log_verbose()'
    Include "$GEMS_SCRIPT"

    It 'outputs message to stderr when VERBOSE_MODE is true'
        VERBOSE_MODE=true
        When call log_verbose "test message"
        The stderr should equal "[DEBUG] test message"
    End

    It 'outputs nothing when VERBOSE_MODE is false'
        VERBOSE_MODE=false
        When call log_verbose "test message"
        The stderr should equal ""
    End

    It 'handles empty message'
        VERBOSE_MODE=true
        When call log_verbose ""
        The stderr should equal "[DEBUG] "
    End
End
