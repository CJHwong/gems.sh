# shellcheck shell=bash
# spec/spec_helper.sh - Shellspec configuration for gems.sh tests

set -eu

# Minimum shellspec version required
spec_helper_precheck() {
    minimum_version "0.28.0"
}

# Called after shellspec is loaded
spec_helper_loaded() {
    # Set test environment flag
    export GEMS_TESTING=true

    # Suppress verbose output during tests
    export VERBOSE_MODE=false
}

# Called before each spec file
spec_helper_configure() {
    # Get the project root directory
    PROJECT_ROOT="$(cd "$(dirname "$SHELLSPEC_SPECDIR")" && pwd)"
    export PROJECT_ROOT

    # Path to the main script
    GEMS_SCRIPT="$PROJECT_ROOT/gems.sh"
    export GEMS_SCRIPT

    # Path to test fixtures
    FIXTURES_DIR="$SHELLSPEC_SPECDIR/support/fixtures"
    export FIXTURES_DIR
}

# Helper function to source gems.sh for testing
# This sources the script without executing main()
load_gems() {
    # shellcheck source=/dev/null
    source "$GEMS_SCRIPT"
}

# Helper to reset global state between tests
reset_globals() {
    CLI_MODEL_OVERRIDE=false
    SELECTED_MODEL=""
    SELECTED_TEMPLATE=""
    DEFAULT_MODEL=""
    API_BASE_URL=""
    API_KEY=""
    API_TIMEOUT=""
    VERBOSE_MODE=false

    # Clear associative arrays
    PROMPT_TEMPLATES=()
    TEMPLATE_PROPERTIES=()
}
