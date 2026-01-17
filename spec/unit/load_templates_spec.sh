# shellcheck shell=bash
# spec/unit/load_templates_spec.sh

Describe 'load_templates_from_yaml()'
    Include "$GEMS_SCRIPT"

    setup() {
        # Reset template arrays
        typeset -gA PROMPT_TEMPLATES
        typeset -gA TEMPLATE_PROPERTIES
        PROMPT_TEMPLATES=()
        TEMPLATE_PROPERTIES=()
        VERBOSE_MODE=false
    }

    BeforeEach 'setup'

    Describe 'loading templates'
        It 'loads templates from valid YAML file'
            When call load_templates_from_yaml "$FIXTURES_DIR/test_gems.yml"
            The status should be success
        End

        It 'loads Passthrough template'
            load_templates_from_yaml "$FIXTURES_DIR/test_gems.yml"
            The variable 'PROMPT_TEMPLATES["Passthrough"]' should equal "{{input}}"
        End

        It 'loads SimpleTemplate'
            load_templates_from_yaml "$FIXTURES_DIR/test_gems.yml"
            The variable 'PROMPT_TEMPLATES["SimpleTemplate"]' should include "Process this"
        End

        It 'loads TemplateWithModel'
            load_templates_from_yaml "$FIXTURES_DIR/test_gems.yml"
            The variable 'PROMPT_TEMPLATES["TemplateWithModel"]' should include "Process with specific model"
        End
    End

    Describe 'loading template properties'
        BeforeEach 'load_templates_from_yaml "$FIXTURES_DIR/test_gems.yml"'

        It 'loads model property for TemplateWithModel'
            The variable 'TEMPLATE_PROPERTIES["TemplateWithModel"]' should include "model=template-specific-model"
        End

        It 'loads detect_language property'
            The variable 'TEMPLATE_PROPERTIES["TemplateWithProperties"]' should include "detect_language=true"
        End

        It 'loads json_field property'
            The variable 'TEMPLATE_PROPERTIES["TemplateWithProperties"]' should include "json_field=text"
        End

        It 'loads multiple properties together'
            The variable 'TEMPLATE_PROPERTIES["TemplateWithModelAndProperties"]' should include "model=custom-model"
            The variable 'TEMPLATE_PROPERTIES["TemplateWithModelAndProperties"]' should include "detect_language=true"
        End
    End

    Describe 'error handling'
        It 'returns failure for non-existent file'
            When call load_templates_from_yaml "/nonexistent/path/gems.yml"
            The status should be failure
        End

        It 'returns failure for empty file path'
            When call load_templates_from_yaml ""
            The status should be failure
        End
    End

    Describe 'edge cases'
        setup_empty_templates() {
            EMPTY_CONFIG="$(mktemp)"
            cat > "$EMPTY_CONFIG" << 'EOF'
configuration:
  api_base_url: "http://localhost"
# No prompt_templates section
EOF
        }

        cleanup_empty_templates() {
            rm -f "$EMPTY_CONFIG"
        }

        BeforeEach 'setup_empty_templates'
        AfterEach 'cleanup_empty_templates'

        It 'returns failure when no templates defined'
            When call load_templates_from_yaml "$EMPTY_CONFIG"
            The status should be failure
        End
    End

    Describe 'verbose logging'
        It 'logs template loading in verbose mode'
            VERBOSE_MODE=true
            When call load_templates_from_yaml "$FIXTURES_DIR/test_gems.yml"
            The status should be success
            The stderr should include "Loading templates"
        End
    End
End
