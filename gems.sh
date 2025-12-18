#!/bin/zsh

# Ignore SIGPIPE to prevent script crash when window closes early
trap '' PIPE

#==========================================================
# LLM Prompt Tool
# 
# This script runs a local LLM command and applies selected
# pre-configured prompts to user input, making it easy to use LLMs
# for specific tasks without writing new prompts each time.
#
# PLATFORM SUPPORT:
# Currently supports macOS only. Cross-platform support for Linux
# and other Unix-like systems is planned. See TODO comments throughout
# the code for areas that need cross-platform implementation.
#==========================================================

#==========================================================
# CONFIGURATION - All settings loaded from gems.yml
#==========================================================
# Configuration variables are loaded from gems.yml at runtime.
# Command line arguments can override YAML settings.
# See gems.yml for all available configuration options.

# Configuration variables (loaded from gems.yml)
API_BASE_URL=""
API_KEY=""
API_TIMEOUT=""
DEFAULT_MODEL=""
LANGUAGE_DETECTION_MODEL=""
DEFAULT_PROMPT_TEMPLATE=""
REASONING_EFFORT=""
TEMPLATE_YAML_FILE="gems.yml"  # Preferred filename; script also supports gems.yaml
RESULT_VIEWER_APP=""

#==========================================================
# FUNCTIONS
#==========================================================

# Declare associative arrays at global scope
typeset -gA PROMPT_TEMPLATES
typeset -gA TEMPLATE_PROPERTIES

# Log message if in verbose mode
function log_verbose() {
    if [ "$VERBOSE_MODE" = true ]; then
        echo "[DEBUG] $1" >&2
    fi
}

# Build a full API URL by safely joining API_BASE_URL with a path.
# Ensures exactly one slash between base and path regardless of trailing/leading slashes.
function build_api_url() {
    local path="$1"
    local base="$API_BASE_URL"
    # Strip trailing slash from base
    base="${base%/}"
    # Ensure path starts with a single slash
    if [[ -z "$path" ]]; then
        echo "$base"
        return 0
    fi
    if [[ "$path" != /* ]]; then
        path="/$path"
    fi
    echo "$base$path"
}

# Resolve YAML file path in a directory, supporting both .yml and .yaml
# Contract:
# - Input: directory path (required)
# - Output: echo absolute path to the YAML file if found; return 0
# - Behavior: honors TEMPLATE_YAML_FILE if that exact file exists; otherwise tries
#   the same basename with .yml/.yaml, then falls back to gems.yml/gems.yaml
function resolve_yaml_in_dir() {
    local dir="$1"
    [[ -z "$dir" ]] && return 1

    # 1) Exact match from TEMPLATE_YAML_FILE if present
    if [[ -n "$TEMPLATE_YAML_FILE" && -f "$dir/$TEMPLATE_YAML_FILE" ]]; then
        echo "$dir/$TEMPLATE_YAML_FILE"
        return 0
    fi

    # 2) Try same basename with .yml/.yaml variants (if TEMPLATE_YAML_FILE provided)
    if [[ -n "$TEMPLATE_YAML_FILE" ]]; then
        local stem="${TEMPLATE_YAML_FILE%.*}"
        if [[ -f "$dir/${stem}.yml" ]]; then
            echo "$dir/${stem}.yml"
            return 0
        fi
        if [[ -f "$dir/${stem}.yaml" ]]; then
            echo "$dir/${stem}.yaml"
            return 0
        fi
    fi

    # 3) Default gems.* filenames
    if [[ -f "$dir/gems.yml" ]]; then
        echo "$dir/gems.yml"
        return 0
    fi
    if [[ -f "$dir/gems.yaml" ]]; then
        echo "$dir/gems.yaml"
        return 0
    fi

    return 1
}

# Call LLM API with streaming support
function call_llm_api() {
    local model="$1"
    local prompt="$2"
    local temp_file="$3"
    local stream="${4:-true}"
    
    # Construct JSON payload for OpenAI-compatible API
    local json_payload
    if [[ -n "$REASONING_EFFORT" ]]; then
        json_payload=$(jq -n \
            --arg model "$model" \
            --arg content "$prompt" \
            --argjson stream "$stream" \
            --arg reasoning_effort "$REASONING_EFFORT" \
            '{
                "model": $model,
                "messages": [{"role": "user", "content": $content}],
                "stream": $stream,
                "reasoning_effort": $reasoning_effort,
                "temperature": 1
            }')
    else
        json_payload=$(jq -n \
            --arg model "$model" \
            --arg content "$prompt" \
            --argjson stream "$stream" \
            '{
                "model": $model,
                "messages": [{"role": "user", "content": $content}],
                "stream": $stream,
                "temperature": 1
            }')
    fi
    
    log_verbose "API payload: $json_payload"
    log_verbose "Calling API: $(build_api_url "chat/completions")"
    
    # Prepare curl command with headers
    local curl_headers=("-H" "Content-Type: application/json")
    
    # Add authorization header if API key is provided
    if [[ -n "$API_KEY" ]]; then
        curl_headers+=("-H" "Authorization: Bearer $API_KEY")
    fi
    
    # Make API call with streaming support
    if [[ "$stream" == "true" ]]; then
        # Streaming mode - parse Server-Sent Events
        # Use a temp file to capture the full response for error handling
        local stream_temp=$(mktemp)
        local found_data=false
        local error_response=""
        
        while IFS= read -r line; do
            # Capture all output for error analysis
            echo "$line" >> "$stream_temp"
            
            # Parse SSE format: "data: {...}"
            if [[ "$line" == "data: "* ]]; then
                data_content="${line#data: }"
                
                # Skip [DONE] signal
                if [[ "$data_content" == "[DONE]" ]]; then
                    break
                fi
                
                found_data=true
                
                # Extract and output content directly from jq without adding extra newlines
                printf '%s' "$data_content" | jq -j 'if .choices[0].delta.content != null and .choices[0].delta.content != "" then .choices[0].delta.content else empty end' 2>/dev/null | {
                    # Stream directly to output and temp file simultaneously using tee with error handling
                    if [[ -n "$temp_file" && "$temp_file" != "false" ]]; then
                        if ! tee -a "$temp_file" 2>/dev/null; then
                            # If tee fails (broken pipe), try to at least save to temp file
                            cat >> "$temp_file" 2>/dev/null || true
                        fi
                    else
                        cat 2>/dev/null || true
                    fi
                }
            fi
        done < <(curl -s --no-buffer -w "\nHTTP_STATUS:%{http_code}" \
            "${curl_headers[@]}" \
            --connect-timeout 10 \
            --max-time "$API_TIMEOUT" \
            -d "$json_payload" \
            "$(build_api_url "chat/completions")")
        
        local curl_exit=$?
        
        # Check if we received any SSE data
        if [[ "$found_data" == "false" ]]; then
            # No SSE data received - likely an error
            local full_response=$(cat "$stream_temp")
            
            # Extract HTTP status if present
            local http_status=""
            if [[ "$full_response" == *"HTTP_STATUS:"* ]]; then
                http_status="${full_response##*HTTP_STATUS:}"
                full_response="${full_response%HTTP_STATUS:*}"
            fi
            
            log_verbose "No streaming data received. HTTP Status: ${http_status:-unknown}"
            log_verbose "Raw response: $full_response"
            
            # Try to parse as JSON error
            local error_msg=$(echo "$full_response" | jq -r '.error.message // .error // "Unknown error"' 2>/dev/null)
            if [[ -n "$error_msg" && "$error_msg" != "null" ]]; then
                echo "API Error: $error_msg" >&2
                if [[ -n "$http_status" ]]; then
                    echo "HTTP Status: $http_status" >&2
                fi
            else
                echo "API Error: Empty or invalid response" >&2
                echo "HTTP Status: ${http_status:-unknown}" >&2
                if [[ "$VERBOSE_MODE" == true ]]; then
                    echo "Full response: $full_response" >&2
                fi
            fi
            
            rm -f "$stream_temp"
            return 1
        fi
        
        rm -f "$stream_temp"
        
        if [[ $curl_exit -ne 0 ]]; then
            log_verbose "curl failed with exit code: $curl_exit"
            return $curl_exit
        fi
    else
        # Non-streaming mode
        curl -s \
            "${curl_headers[@]}" \
            --connect-timeout 10 \
            --max-time "$API_TIMEOUT" \
            -d "$json_payload" \
            "$(build_api_url "chat/completions")" | \
        jq -r '.choices[0].message.content // empty' 2>/dev/null
    fi
    
    # Return curl exit code
    return ${PIPESTATUS[0]:-$?}
}

# Check API response and handle common HTTP errors
function check_api_response() {
    local response="$1"
    local http_code="$2"
    
    # Check for empty response
    if [[ -z "$response" ]]; then
        log_verbose "API Error: Empty response received"
        return 1
    fi
    
    # Check HTTP status codes
    case "$http_code" in
        200|201)
            log_verbose "API call successful (HTTP $http_code)"
            return 0
            ;;
        400)
            local error_msg=$(echo "$response" | jq -r '.error.message // "Bad Request"' 2>/dev/null)
            log_verbose "API Error (HTTP 400): $error_msg"
            return 1
            ;;
        401)
            log_verbose "API Error (HTTP 401): Unauthorized - check your API key"
            return 1
            ;;
        404)
            local error_msg=$(echo "$response" | jq -r '.error.message // "Not Found"' 2>/dev/null)
            log_verbose "API Error (HTTP 404): $error_msg"
            return 1
            ;;
        429)
            log_verbose "API Error (HTTP 429): Rate limit exceeded"
            return 1
            ;;
        500|502|503)
            log_verbose "API Error (HTTP $http_code): Server error"
            return 1
            ;;
        *)
            log_verbose "API Error: Unexpected HTTP status $http_code"
            return 1
            ;;
    esac
}

# Enhanced API call with better error handling
function call_llm_api_with_error_handling() {
    local model="$1"
    local prompt="$2"
    local stream="${3:-true}"
    
    # Create temp file for response headers
    local temp_headers=$(mktemp)
    local temp_response=$(mktemp)
    
    # Prepare curl command with headers
    local curl_headers=("-H" "Content-Type: application/json")
    if [[ -n "$API_KEY" ]]; then
        curl_headers+=("-H" "Authorization: Bearer $API_KEY")
    fi
    
    # Construct JSON payload
    local json_payload
    if [[ -n "$REASONING_EFFORT" ]]; then
        json_payload=$(jq -n \
            --arg model "$model" \
            --arg content "$prompt" \
            --argjson stream "$stream" \
            --arg reasoning_effort "$REASONING_EFFORT" \
            '{
                "model": $model,
                "messages": [{"role": "user", "content": $content}],
                "stream": $stream,
                "reasoning_effort": $reasoning_effort,
                "temperature": 1
            }')
    else
        json_payload=$(jq -n \
            --arg model "$model" \
            --arg content "$prompt" \
            --argjson stream "$stream" \
            '{
                "model": $model,
                "messages": [{"role": "user", "content": $content}],
                "stream": $stream,
                "temperature": 1
            }')
    fi
    
    if [[ "$stream" == "true" ]]; then
        # For streaming, we can't easily capture HTTP status, so just use the original function
        call_llm_api "$model" "$prompt" "$stream"
    else
        # For non-streaming, capture both response and HTTP status
        local http_code
        http_code=$(curl -s -w "%{http_code}" \
            "${curl_headers[@]}" \
            --connect-timeout 10 \
            --max-time "$API_TIMEOUT" \
            -d "$json_payload" \
            -o "$temp_response" \
            "$(build_api_url "chat/completions")")
        
        local curl_exit_code=$?
        local response_content=$(cat "$temp_response")
        
        # Clean up temp files
        rm -f "$temp_headers" "$temp_response"
        
        # Check curl exit code first
        if [[ $curl_exit_code -ne 0 ]]; then
            log_verbose "Network error: curl failed with exit code $curl_exit_code"
            return $curl_exit_code
        fi
        
        # Check API response
        if check_api_response "$response_content" "$http_code"; then
            # Extract content from successful response
            echo "$response_content" | jq -r '.choices[0].message.content // empty' 2>/dev/null
            return 0
        else
            return 1
        fi
    fi
}

# Get available models from API endpoint
function get_available_models() {
    # Check if curl command exists
    if ! command -v curl &> /dev/null; then
        echo "Error: 'curl' is not installed or not in PATH."
        return 1
    fi
    
    # Prepare curl headers
    local curl_headers=("-H" "Content-Type: application/json")
    if [[ -n "$API_KEY" ]]; then
        curl_headers+=("-H" "Authorization: Bearer $API_KEY")
    fi
    
    # Call API to get models list with better error handling
    local temp_response=$(mktemp)
    local http_code
    
    http_code=$(curl -s -w "%{http_code}" \
        "${curl_headers[@]}" \
        --connect-timeout 10 \
        --max-time 30 \
        -o "$temp_response" \
        "$(build_api_url "models")")
    
    local curl_exit_code=$?
    local models_response=$(cat "$temp_response")
    rm -f "$temp_response"
    
    # Check curl exit code
    if [[ $curl_exit_code -ne 0 ]]; then
        log_verbose "Network error retrieving models: curl failed with exit code $curl_exit_code"
        echo "Error: Network error while retrieving models from API."
        return 1
    fi
    
    # Check API response
    if ! check_api_response "$models_response" "$http_code"; then
        echo "Error: Failed to retrieve models from API (HTTP $http_code)."
        return 1
    fi
    
    # Extract model IDs using jq
    local models
    models=$(echo "$models_response" | jq -r '.data[]?.id // empty' 2>/dev/null | sort)
    
    if [[ -z "$models" ]]; then
        log_verbose "API response: $models_response"
        echo "Error: No models found or invalid API response format."
        return 1
    fi
    
    echo "$models"
}

# Display usage information
function show_help() {
    echo "Usage: gems.sh [-m model] [-t template] [-v] [-h] [--list-templates] [--list-models] [--template-info template] [text]"
    echo "Options:"
    echo "  -m <model>              Specify LLM model (overrides gems.yml default)"
    echo "  -t <template>           Specify prompt template to use"
    echo "  -v                      Verbose mode (show debug information)"
    echo "  -h                      Display this help message"
    echo "  --list-models           List all available models from the API"
    echo "  --list-templates        List all available templates with descriptions"
    echo "  --template-info <name>  Show detailed information about a specific template"
    echo ""
    echo "Configuration:"
    echo "  All settings are loaded from gems.yml or gems.yaml (requires yq)."
    echo "  Command line arguments override YAML configuration."
    echo ""
    echo "Examples:"
    echo "  gems.sh 'Fix this sentence: Me and him went to store'"
    echo "  gems.sh -t CodeReview 'function foo() { return x + y; }'"
    echo "  gems.sh -m gemma3:4b-it-qat -t Summarize 'Long text to summarize...'"
    echo "  gems.sh --list-models"

    exit 0
}

# List available models from the API
function list_models() {
    # Load configuration first to get API endpoint
    local script_path="${BASH_SOURCE[0]:-$0}"
    local script_dir="$(dirname "$script_path")"
    local yaml_file
    yaml_file=$(resolve_yaml_in_dir "$script_dir") || yaml_file="$script_dir/$TEMPLATE_YAML_FILE"
    
    if ! load_configuration_from_yaml "$yaml_file"; then
        echo "ERROR: Failed to load configuration from YAML file" >&2
        echo "Please check that gems.yml or gems.yaml exists next to the script and contains valid configuration." >&2
        exit 1
    fi
    
    echo "Available models from API:"
    local available_models
    available_models=$(get_available_models)
    if [ $? -eq 0 ] && [ -n "$available_models" ]; then
        echo "$available_models" | while read -r model; do
            echo "  - $model"
        done
    else
        echo "  Unable to retrieve model list. Check if your LLM service is running and accessible."
        echo "  API endpoint: $API_BASE_URL"
        exit 1
    fi
    
    exit 0
}

# Load prompt templates from YAML file
function load_templates_from_yaml() {
    local yaml_file="$1"
    
    if [[ ! -f "$yaml_file" ]]; then
        log_verbose "YAML file not found: $yaml_file"
        return 1
    fi
    
    # Check if yq is available for YAML parsing
    if ! command -v yq &> /dev/null; then
        log_verbose "yq not found."
        return 1
    fi
    
    log_verbose "Loading templates from YAML file: $yaml_file"
    
    # Ensure UTF-8 locale for proper character handling
    local original_lang="$LANG"
    export LANG="en_US.UTF-8"
    export LC_ALL="en_US.UTF-8"
    
    # Get list of template names from YAML
    local template_names=$(yq eval '.prompt_templates | keys | .[]' "$yaml_file" 2>/dev/null)
    
    if [[ -z "$template_names" ]]; then
        log_verbose "No templates found in YAML file"
        # Restore original locale
        export LANG="$original_lang"
        unset LC_ALL
        return 1
    fi
    
    log_verbose "Found templates: $(echo "$template_names" | tr '\n' ',' | sed 's/,$//')"
    
    # Load each template
    while IFS= read -r template_name; do
        [[ -z "$template_name" ]] && continue
        # Load template text with proper UTF-8 handling
        local template_text=$(yq eval ".prompt_templates.${template_name}.template" "$yaml_file" 2>/dev/null | cat)
        
        if [[ "$template_text" != "null" && -n "$template_text" ]]; then
            # Use printf to properly handle special characters and preserve encoding
            PROMPT_TEMPLATES["$template_name"]=$(printf '%s' "$template_text")
            log_verbose "Loaded template: $template_name"
            
            # Load properties if they exist
            local properties=""
            
            # Check for detect_language
            local detect_lang=$(yq eval ".prompt_templates.${template_name}.properties.detect_language" "$yaml_file" 2>/dev/null)
            if [[ "$detect_lang" == "true" ]]; then
                properties+="detect_language=true "
            fi
            
            # Check for output_language
            local output_lang=$(yq eval ".prompt_templates.${template_name}.properties.output_language" "$yaml_file" 2>/dev/null | cat)
            if [[ "$output_lang" != "null" && -n "$output_lang" ]]; then
                properties+="output_language=$(printf '%s' "$output_lang") "
            fi
            
            # Check for json_schema
            local json_schema=$(yq eval ".prompt_templates.${template_name}.properties.json_schema" "$yaml_file" 2>/dev/null)
            if [[ "$json_schema" != "null" && -n "$json_schema" ]]; then
                # Convert YAML to JSON format
                local json_string=$(yq eval ".prompt_templates.${template_name}.properties.json_schema" "$yaml_file" -o=json 2>/dev/null)
                if [[ -n "$json_string" ]]; then
                    properties+="json_schema=$json_string "
                fi
            fi
            
            # Check for json_field
            local json_field=$(yq eval ".prompt_templates.${template_name}.properties.json_field" "$yaml_file" 2>/dev/null | cat)
            if [[ "$json_field" != "null" && -n "$json_field" ]]; then
                properties+="json_field=$(printf '%s' "$json_field")"
            fi
            
            # Store properties if any were found
            if [[ -n "$properties" ]]; then
                TEMPLATE_PROPERTIES["$template_name"]=$(printf '%s' "$properties")
                log_verbose "Loaded properties for $template_name"
            fi
        fi
    done <<< "$template_names" 2>/dev/null
    
    # Restore original locale
    export LANG="$original_lang"
    unset LC_ALL
    
    return 0
}

# Load configuration from YAML file
function load_configuration_from_yaml() {
    local yaml_file="$1"
    
    if [[ ! -f "$yaml_file" ]]; then
        echo "ERROR: Configuration file not found: $yaml_file" >&2
        echo "Please ensure gems.yml or gems.yaml exists in the script directory." >&2
        return 1
    fi
    
    # Check if yq is available for YAML parsing
    if ! command -v yq &> /dev/null; then
        echo "ERROR: yq not found." >&2
        echo "yq is required to parse the YAML configuration file." >&2
        return 1
    fi
    
    log_verbose "Loading configuration from YAML file: $yaml_file"
    
    # Load API settings (required)
    API_BASE_URL=$(yq eval '.configuration.api_base_url' "$yaml_file" 2>/dev/null | cat)
    if [[ "$API_BASE_URL" == "null" || -z "$API_BASE_URL" ]]; then
        echo "ERROR: api_base_url not found in gems.yml configuration" >&2
        return 1
    fi
    
    API_KEY=$(yq eval '.configuration.api_key' "$yaml_file" 2>/dev/null | cat)
    if [[ "$API_KEY" == "null" ]]; then API_KEY=""; fi
    
    API_TIMEOUT=$(yq eval '.configuration.api_timeout' "$yaml_file" 2>/dev/null)
    if [[ "$API_TIMEOUT" == "null" || -z "$API_TIMEOUT" ]]; then
        echo "ERROR: api_timeout not found in gems.yml configuration" >&2
        return 1
    fi
    
    DEFAULT_MODEL=$(yq eval '.configuration.default_model' "$yaml_file" 2>/dev/null | cat)
    if [[ "$DEFAULT_MODEL" == "null" || -z "$DEFAULT_MODEL" ]]; then
        echo "ERROR: default_model not found in gems.yml configuration" >&2
        return 1
    fi
    
    LANGUAGE_DETECTION_MODEL=$(yq eval '.configuration.language_detection_model' "$yaml_file" 2>/dev/null | cat)
    if [[ "$LANGUAGE_DETECTION_MODEL" == "null" || -z "$LANGUAGE_DETECTION_MODEL" ]]; then
        echo "ERROR: language_detection_model not found in gems.yml configuration" >&2
        return 1
    fi
    
    DEFAULT_PROMPT_TEMPLATE=$(yq eval '.configuration.default_prompt_template' "$yaml_file" 2>/dev/null | cat)
    if [[ "$DEFAULT_PROMPT_TEMPLATE" == "null" || -z "$DEFAULT_PROMPT_TEMPLATE" ]]; then
        echo "ERROR: default_prompt_template not found in gems.yml configuration" >&2
        return 1
    fi
    
    REASONING_EFFORT=$(yq eval '.configuration.reasoning_effort' "$yaml_file" 2>/dev/null | cat)
    if [[ "$REASONING_EFFORT" == "null" ]]; then REASONING_EFFORT=""; fi
    
    RESULT_VIEWER_APP=$(yq eval '.configuration.result_viewer_app' "$yaml_file" 2>/dev/null | cat)
    if [[ "$RESULT_VIEWER_APP" == "null" ]]; then RESULT_VIEWER_APP=""; fi
    
    log_verbose "Configuration loaded successfully"
    log_verbose "API Base URL: $API_BASE_URL"
    log_verbose "Default Model: $DEFAULT_MODEL"
    log_verbose "Language Detection Model: $LANGUAGE_DETECTION_MODEL"
    log_verbose "API Timeout: $API_TIMEOUT"
    log_verbose "Reasoning Effort: $REASONING_EFFORT"
    return 0
}

# Parse template properties
function get_template_property() {
    local template_name="$1"
    local property_name="$2"
    local default_value="$3"
    
    # Check if the template has properties
    if [[ -n "$TEMPLATE_PROPERTIES[\"$template_name\"]" ]]; then
        local properties="$TEMPLATE_PROPERTIES[\"$template_name\"]"
        
        # Use parameter expansion to find and extract the property value
        # First, try to match the property at the beginning or after a space
        local temp_props=" $properties "
        if [[ "$temp_props" == *" ${property_name}="* ]]; then
            # Extract everything after the property name and equals sign
            local after_prop="${temp_props#*" ${property_name}="}"
            
            # For JSON schema, extract everything between { and }
            if [[ "$property_name" == "json_schema" && "$after_prop" == "{"* ]]; then
                local property_value
                # Extract the JSON object including nested braces
                local brace_count=0
                local i=0
                local char
                property_value=""
                
                while [[ $i -lt ${#after_prop} ]]; do
                    char="${after_prop:$i:1}"
                    property_value+="$char"
                    
                    if [[ "$char" == "{" ]]; then
                        ((brace_count++))
                    elif [[ "$char" == "}" ]]; then
                        ((brace_count--))
                        if [[ $brace_count -eq 0 ]]; then
                            break
                        fi
                    fi
                    ((i++))
                done
            else
                # Extract just the value (everything before the next space)
                local property_value="${after_prop%% *}"
            fi
            
            log_verbose "Found property '$property_name' = '$property_value'" >&2
            
            echo "$property_value"
            return 0
        else
            log_verbose "Property '$property_name' not found in '$temp_props'" >&2
        fi
    else
        log_verbose "No properties found for template '$template_name'" >&2
    fi
    
    # Return default value if property not found
    log_verbose "Returning default value: '$default_value'" >&2
    echo "$default_value"
    return 1
}

# Verify that all required dependencies are installed and accessible
function verify_dependencies() {
    local errors=0
    local warnings=0
    
    # Required dependencies
    log_verbose "Checking required dependencies..."
    
    # Check curl (required for API calls)
    if ! command -v curl &> /dev/null; then
        echo "ERROR: 'curl' is not installed or not in PATH."
        echo "curl is required for API communication. It should be pre-installed on macOS."
        ((errors++))
    else
        log_verbose "✓ curl found (API communication support)"
        
        # Test API endpoint availability
        if ! curl -s --connect-timeout 5 --max-time 10 "$(build_api_url "models")" &> /dev/null; then
            log_verbose "WARNING: API endpoint '$API_BASE_URL' may not be accessible."
            log_verbose "Make sure your LLM service is running and accessible."
            ((warnings++))
        else
            log_verbose "✓ API endpoint is accessible"
        fi
    fi
    
    # Check platform-specific dependencies
    # TODO: Add platform detection and call appropriate dependency checker
    local platform_errors
    platform_errors=$(macos_check_dependencies)
    errors=$((errors + $?))
    
    # Optional dependencies with warnings
    log_verbose "Checking optional dependencies..."
    
    # Check for yq (YAML parsing - optional but recommended)
    if ! command -v yq &> /dev/null; then
        log_verbose "WARNING: 'yq' not found. YAML template loading will be disabled."
        ((warnings++))
    else
        log_verbose "✓ yq found (YAML template support)"
        
        # Test yq functionality
        if ! echo "test: value" | yq eval '.test' &> /dev/null; then
            log_verbose "WARNING: yq installation may be corrupted"
            ((warnings++))
        fi
    fi
    
    # Check for jq (JSON parsing - required for API communication)
    if ! command -v jq &> /dev/null; then
        echo "ERROR: 'jq' not found. JSON processing is required for API communication."
        ((errors++))
    else
        log_verbose "✓ jq found (JSON processing support)"
        
        # Test jq functionality
        if ! echo '{"test": "value"}' | jq -r '.test' &> /dev/null; then
            echo "ERROR: jq installation may be corrupted"
            ((errors++))
        fi
    fi
    
    # Check for glow (markdown rendering - optional)
    if ! command -v glow &> /dev/null; then
        log_verbose "WARNING: 'glow' not found. Markdown rendering will be disabled."
        ((warnings++))
    else
        log_verbose "✓ glow found (markdown rendering support)"
    fi
    
    # Check for realpath/readlink (path resolution - semi-optional)
    if ! command -v realpath &> /dev/null && ! command -v readlink &> /dev/null; then
        log_verbose "WARNING: Neither 'realpath' nor 'readlink' found. Path resolution may be limited."
        ((warnings++))
    else
        if command -v realpath &> /dev/null; then
            log_verbose "✓ realpath found (path resolution support)"
        else
            log_verbose "✓ readlink found (path resolution support)"
        fi
    fi
    
    # Check for default model availability via API
    if command -v curl &> /dev/null && command -v jq &> /dev/null; then
        local available_models
        available_models=$(get_available_models 2>/dev/null)
        
        if [[ $? -eq 0 && -n "$available_models" ]]; then
            if ! echo "$available_models" | grep -q "^$DEFAULT_MODEL$"; then
                log_verbose "WARNING: Default model '$DEFAULT_MODEL' not found via API."
                log_verbose "Available models:"
                echo "$available_models" | while read -r model; do 
                    log_verbose "  - $model"
                done
                log_verbose "Make sure the model is available through your LLM service."
                ((warnings++))
            else
                log_verbose "✓ Default model '$DEFAULT_MODEL' is available"
            fi
            
            # Check language detection model
            if ! echo "$available_models" | grep -q "^$LANGUAGE_DETECTION_MODEL$"; then
                log_verbose "WARNING: Language detection model '$LANGUAGE_DETECTION_MODEL' not found via API."
                log_verbose "Language detection features will be limited."
                log_verbose "Make sure the model is available through your LLM service."
                ((warnings++))
            else
                log_verbose "✓ Language detection model '$LANGUAGE_DETECTION_MODEL' is available"
            fi
        else
            log_verbose "WARNING: Unable to retrieve model list from API."
            log_verbose "Model availability cannot be verified."
            ((warnings++))
        fi
    fi
    
    # Check YAML template file
    local script_dir="$(dirname "${BASH_SOURCE[0]:-$0}")"
    local yaml_file
    yaml_file=$(resolve_yaml_in_dir "$script_dir") || yaml_file="$script_dir/$TEMPLATE_YAML_FILE"
    if [[ ! -f "$yaml_file" ]]; then
        log_verbose "WARNING: Template file not found (tried gems.yml and gems.yaml in $script_dir)."
        log_verbose "Only built-in templates will be available."
        ((warnings++))
    else
        log_verbose "✓ Template file found: $yaml_file"
        
        # Test YAML file validity if yq is available
        if command -v yq &> /dev/null; then
            if ! yq eval '.prompt_templates' "$yaml_file" &> /dev/null; then
                log_verbose "WARNING: Template file appears to be invalid YAML"
                ((warnings++))
            else
                local template_count=$(yq eval '.prompt_templates | keys | length' "$yaml_file" 2>/dev/null || echo "0")
                log_verbose "✓ Found $template_count templates in YAML file"
            fi
        fi
    fi
    
    # Check result viewer app if configured
    if [[ -n "$RESULT_VIEWER_APP" ]]; then
        case "$RESULT_VIEWER_APP" in
            "Warp")
                # TODO: Add cross-platform app detection
                if [[ ! -d "/Applications/Warp.app" ]]; then  # macOS-specific path
                    log_verbose "WARNING: Warp app not found at /Applications/Warp.app"
                    log_verbose "Results won't be displayed in Warp."
                    ((warnings++))
                else
                    log_verbose "✓ Warp app found"
                fi
                ;;
            "iTerm2")
                # TODO: Add cross-platform terminal detection
                if [[ ! -d "/Applications/iTerm.app" ]]; then  # macOS-specific path
                    log_verbose "WARNING: iTerm2 app not found at /Applications/iTerm.app"
                    log_verbose "Results won't be displayed in iTerm2."
                    ((warnings++))
                else
                    log_verbose "✓ iTerm2 app found"
                fi
                ;;
            "Terminal")
                # TODO: Add cross-platform terminal support
                log_verbose "✓ Using built-in Terminal app"  # macOS-specific
                ;;
        esac
    fi
    
    # Check shell compatibility
    if [[ -z "$ZSH_VERSION" && -z "$BASH_VERSION" ]]; then
        log_verbose "WARNING: This script is designed for Zsh or Bash shells"
        ((warnings++))
    else
        if [[ -n "$ZSH_VERSION" ]]; then
            log_verbose "✓ Running in Zsh $ZSH_VERSION"
        else
            log_verbose "✓ Running in Bash $BASH_VERSION"
        fi
    fi
    
    # Summary - always show critical information
    if [[ $errors -gt 0 ]]; then
        echo ""
        echo "CRITICAL: $errors required dependencies are missing."
        echo "Please install missing dependencies before using this script."
        exit 1
    elif [[ $warnings -gt 0 ]]; then
        log_verbose ""
        log_verbose "Dependency check complete: $warnings optional features may be limited due to missing dependencies."
        log_verbose "The script will continue with reduced functionality."
    else
        log_verbose ""
        log_verbose "✓ All dependencies are available!"
    fi
    
    return $errors
}

# Add configuration validation
function validate_configuration() {    
    local errors=0
    
    # Validate that required configuration variables are set
    if [[ -z "$API_BASE_URL" ]]; then
        echo "Error: API_BASE_URL is not configured"
        ((errors++))
    fi
    
    if [[ -z "$DEFAULT_MODEL" ]]; then
        echo "Error: DEFAULT_MODEL is not configured"
        ((errors++))
    fi
    
    if [[ -z "$API_TIMEOUT" ]]; then
        echo "Error: API_TIMEOUT is not configured"
        ((errors++))
    fi
    
    return $errors
}

# Parse command line arguments
function parse_arguments() {
    # Handle long options first
    while [[ $# -gt 0 ]]; do
        case $1 in
            --list-templates)
                list_templates
                exit 0
                ;;
            --list-models)
                list_models
                exit 0
                ;;
            --template-info)
                shift
                if [[ -n $1 && $1 != -* ]]; then
                    show_template_info "$1"
                    exit 0
                else
                    echo "Error: --template-info requires a template name" >&2
                    exit 1
                fi
                ;;
            -*)
                # Keep other options for getopts
                break
                ;;
            *)
                # Keep non-option arguments for getopts
                break
                ;;
        esac
        shift
    done
    
    # Handle short options with getopts
    while getopts ":m:t:vh" opt; do
        case $opt in
            m) SELECTED_MODEL="$OPTARG" ;;
            t) SELECTED_TEMPLATE="$OPTARG" ;;
            v) VERBOSE_MODE=true ;;
            h) show_help ;;
            \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
        esac
    done

    # SELECTED_MODEL will be set later after YAML configuration is loaded

    # Set default for verbose mode if not specified
    if [ -z "$VERBOSE_MODE" ]; then
        VERBOSE_MODE=false
    fi

    # Shift past the processed options to get user input
    shift $((OPTIND-1))
    USER_INPUT=$@
    
    # Check if input is empty
    if [ -z "$USER_INPUT" ]; then
        echo "Error: No input provided. Please provide text to process."
        echo "Use -h for help information."
        exit 1
    fi
}

# List all available templates with descriptions
function list_templates() {
    # Initialize templates to get the full list
    init_prompt_templates
    
    echo "Available Prompt Templates:"
    echo "=========================="
    echo ""
    
    # Get template names sorted alphabetically
    local sorted_templates=()
    for template_name in ${(k)PROMPT_TEMPLATES}; do
        sorted_templates+=("$template_name")
    done
    
    # Sort the array
    sorted_templates=($(printf '%s\n' "${sorted_templates[@]}" | sort))
    
    # Display each template with its description
    for template_name in "${sorted_templates[@]}"; do
        echo "📋 $template_name"
        
        # Get template content and extract description from it
        local template_content="${PROMPT_TEMPLATES["$template_name"]}"
        local description=""
        
        # Try to extract a meaningful description from the template
        if [[ "$template_content" == *"{{input}}"* ]]; then
            # Extract the part before {{input}} as description
            description="${template_content%%{{input}}*}"
            # Clean up the description - remove excess whitespace and newlines
            description="$(echo "$description" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
            # Limit description length
            if [[ ${#description} -gt 100 ]]; then
                description="${description:0:97}..."
            fi
        fi
        
        if [[ -n "$description" ]]; then
            echo "   $description"
        else
            echo "   Custom template"
        fi
        
        # Show properties if they exist
        if [[ -n "$TEMPLATE_PROPERTIES[\"$template_name\"]" ]]; then
            local properties="$TEMPLATE_PROPERTIES[\"$template_name\"]"
            echo "   Properties: $properties"
        fi
        
        echo ""
    done
    
    echo "Usage: gems.sh -t <template_name> \"your text here\""
    echo "For detailed template info: gems.sh --template-info <template_name>"
}

# Show detailed information about a specific template
function show_template_info() {
    local requested_template="$1"
    
    # Initialize templates to get the full list
    init_prompt_templates
    
    # Check if template exists (template keys have quotes around them)
    local quoted_template_name="\"$requested_template\""
    if [[ -z "${PROMPT_TEMPLATES[$quoted_template_name]}" ]]; then
        echo "Error: Template '$requested_template' not found."
        echo ""
        echo "Available templates:"
        for name in ${(k)PROMPT_TEMPLATES}; do
            echo "  - $name"
        done
        exit 1
    fi
    
    echo "Template Information: $requested_template"
    echo "======================================"
    echo ""
    
    # Show template content
    echo "Template Content:"
    echo "-----------------"
    echo "${PROMPT_TEMPLATES[$quoted_template_name]}"
    echo ""
    
    # Show properties if they exist
    if [[ -n "$TEMPLATE_PROPERTIES[$quoted_template_name]" ]]; then
        echo "Properties:"
        echo "-----------"
        local properties="$TEMPLATE_PROPERTIES[$quoted_template_name]"
        
        # Parse and display properties nicely
        echo "$properties" | tr ' ' '\n' | while IFS='=' read -r key value; do
            if [[ -n "$key" && -n "$value" ]]; then
                case "$key" in
                    "detect_language")
                        echo "• Language Detection: $value"
                        ;;
                    "output_language")
                        echo "• Output Language: $value"
                        ;;
                    "json_schema")
                        echo "• JSON Schema: $value"
                        ;;
                    "json_field")
                        echo "• JSON Field Extraction: $value"
                        ;;
                    *)
                        echo "• $key: $value"
                        ;;
                esac
            fi
        done
        echo ""
    else
        echo "Properties: None"
        echo ""
    fi
    
    # Show usage example
    echo "Usage Example:"
    echo "--------------"
    echo "gems.sh -t $requested_template \"your input text here\""
    echo "gems.sh -m your_model -t $requested_template \"your input text here\""
}

# Initialize the prompt templates with instructions
function init_prompt_templates() {
    # Always include the basic Passthrough template
    PROMPT_TEMPLATES["Passthrough"]="{{input}}"
    
    # Try to load templates from YAML file first
    # Get script directory - use realpath to resolve the actual script location
    # This works even when called from other scripts or via symlinks
    local script_path
    local script_dir

    # First, try to get the actual script path
    if [[ -n "${BASH_SOURCE[0]}" ]]; then
        # Bash context
        script_path="${BASH_SOURCE[0]}"
    elif [[ -n "${(%):-%x}" ]]; then
        # Zsh context when sourced/called directly
        script_path="${(%):-%x}"
    else
        # Fallback: use $0
        script_path="$0"
    fi
    
    # Use the script's own location to find accompanying files like gems.yml
    # Avoid any user-specific hardcoded paths or external searches.
    
    # Resolve the real path (handles symlinks and relative paths)
    if command -v realpath &> /dev/null; then
        script_path="$(realpath "$script_path")"
    elif command -v readlink &> /dev/null; then
        # Alternative using readlink (available on macOS)
        script_path="$(readlink -f "$script_path" 2>/dev/null || echo "$script_path")"
    fi
    
    script_dir="$(dirname "$script_path")"
    local yaml_file
    yaml_file=$(resolve_yaml_in_dir "$script_dir") || yaml_file="$script_dir/$TEMPLATE_YAML_FILE"
    
    log_verbose "Script directory: $script_dir"
    log_verbose "Script path: $script_path"
    log_verbose "YAML file path: $yaml_file"
    log_verbose "YAML file exists: $(test -f "$yaml_file" && echo "YES" || echo "NO")"
    
    # Load configuration from YAML file first
    if ! load_configuration_from_yaml "$yaml_file"; then
        echo "FATAL: Failed to load configuration from YAML file" >&2
        echo "Please check that gems.yml or gems.yaml exists and contains valid configuration." >&2
        exit 1
    fi
    
    # Update SELECTED_MODEL if it wasn't explicitly set via command line
    if [ -z "$SELECTED_MODEL" ]; then
        SELECTED_MODEL="$DEFAULT_MODEL"
        log_verbose "Using default model from YAML configuration: $SELECTED_MODEL"
    fi
    
    if load_templates_from_yaml "$yaml_file"; then
        log_verbose "Successfully loaded templates from YAML file"
    else
        log_verbose "YAML template loading failed. Only Passthrough template available."
        # Note: Only Passthrough template is available as inline fallback
        # For other templates, use gems.yml configuration file
    fi

    # Add new prompt templates below this line
    # Example format:
    # PROMPT_TEMPLATES["TemplateName"]="Your Prompt Template with {{input}} placeholder"
    # TEMPLATE_PROPERTIES["TemplateName"]="detect_language=false output_language=English"
    
    # Use cases for TEMPLATE_PROPERTIES:
    #
    # 1. Basic language detection:
    # TEMPLATE_PROPERTIES["TemplateName"]="detect_language=true"
    #
    # 2. Force specific output language:
    # TEMPLATE_PROPERTIES["TemplateName"]="output_language=Spanish"
    #
    # 3. JSON response with field extraction:
    # TEMPLATE_PROPERTIES["TemplateName"]="json_schema={\"result\": \"string\", \"confidence\": \"number\"} json_field=result"
    #
    # 4. Language detection + JSON output:
    # TEMPLATE_PROPERTIES["TemplateName"]="detect_language=true json_schema={\"translation\": \"string\"} json_field=translation"
    #
    # 5. Complex JSON structure:
    # TEMPLATE_PROPERTIES["TemplateName"]="json_schema={\"analysis\": {\"topics\": [\"string\"], \"sentiment\": \"string\"}, \"summary\": \"string\"} json_field=summary"
    #
    # 6. Multiple properties combined:
    # TEMPLATE_PROPERTIES["TemplateName"]="detect_language=true output_language=French json_schema={\"text\": \"string\"} json_field=text"
}

# Select prompt template using GUI if not provided via command line
# TODO: Add cross-platform template selection (terminal-based for non-macOS)
function select_prompt_template() {
    # Build comma-separated list of prompt templates
    available_templates=""
    for template_name in ${(k)PROMPT_TEMPLATES}; do
        if [[ $available_templates == "" ]]; then
            available_templates="$template_name"
        else
            available_templates="$available_templates, $template_name"
        fi
    done

    # Prompt user to select template if not provided via command line
    if [ -z "$SELECTED_TEMPLATE" ]; then
        # Use macOS-specific GUI selection for now
        # TODO: Add platform detection and alternative selection methods
        SELECTED_TEMPLATE=$(macos_select_template_gui "$available_templates" "$DEFAULT_PROMPT_TEMPLATE")

        if [ -z "$SELECTED_TEMPLATE" ]; then
            echo "No template selected. Operation cancelled."
            exit 0
        fi
    fi
}

# Validate that the selected template exists
function validate_template() {
    if [[ -z "${PROMPT_TEMPLATES[\"$SELECTED_TEMPLATE\"]}" ]]; then
        echo "Error: Template '$SELECTED_TEMPLATE' not found."
        echo ""
        echo "Available templates:"
        for template_name in ${(k)PROMPT_TEMPLATES}; do
            echo "  - $template_name"
        done
        echo ""
        echo "To use other templates, ensure gems.yml is present and yq is installed:"
        exit 1
    fi
}

# Global variables for output management
OUTPUT_PIPE=""
OUTPUT_PROCESS_PID=""
OUTPUT_MARKDOWN_FILE=""
CLEANUP_CALLED="false"

# Setup output stream based on configuration
function setup_output() {
    # Setup output destination based on configuration
    if [[ "$RESULT_VIEWER_APP" == "homo" ]] && command -v homo &> /dev/null; then
        # Use homo with named pipe when explicitly specified
        OUTPUT_PIPE="$(mktemp -u).fifo"
        mkfifo "$OUTPUT_PIPE"
        
        # Start homo in background, reading from the pipe
        homo < "$OUTPUT_PIPE" &
        OUTPUT_PROCESS_PID=$!
        
        # Open the pipe for writing with file descriptor 3
        exec 3>"$OUTPUT_PIPE"
        
        log_verbose "Using homo with pipe: $OUTPUT_PIPE (PID: $OUTPUT_PROCESS_PID)"
    elif [[ -n "$RESULT_VIEWER_APP" ]]; then
        # Use other configured viewer apps with temporary file
        OUTPUT_MARKDOWN_FILE="$(mktemp).md"
        log_verbose "Using viewer app: $RESULT_VIEWER_APP with file: $OUTPUT_MARKDOWN_FILE"
    else
        # Direct terminal output
        log_verbose "Using direct terminal output"
    fi
}

# Write markdown content to output destination
function write_to_output() {
    local content="$1"
    
    if [[ -n "$OUTPUT_MARKDOWN_FILE" ]]; then
        # Append to markdown file
        printf '%s' "$content" >> "$OUTPUT_MARKDOWN_FILE"
    elif [[ -n "$OUTPUT_PIPE" ]]; then
        # Write to pipe using file descriptor 3 with error handling
        if ! printf '%s' "$content" >&3 2>/dev/null; then
            log_verbose "Pipe closed (window terminated early), stopping output..."
            return 0  # Return success - early window close is not an error
        fi
    else
        # Direct to terminal
        printf '%s' "$content"
    fi
}

# Write streaming content character by character for real-time display
function write_to_output_stream() {
    if [[ -n "$OUTPUT_MARKDOWN_FILE" ]]; then
        # For files, use stdbuf to avoid buffering with cat
        stdbuf -o0 cat >> "$OUTPUT_MARKDOWN_FILE"
    elif [[ -n "$OUTPUT_PIPE" ]]; then
        # For pipes, use stdbuf to avoid buffering with error handling
        if ! stdbuf -o0 cat >&3 2>/dev/null; then
            log_verbose "Pipe closed (window terminated early), stopping stream..."
            return 0  # Return success - early window close is not an error
        fi
    else
        # For terminal, use stdbuf to avoid buffering
        stdbuf -o0 cat
    fi
}

# Format JSON in output file to show properly formatted multi-line JSON
function format_json_in_output_file() {
    local output_file="$1"
    
    if [[ ! -f "$output_file" ]]; then
        return 0
    fi
    
    # Create a temporary file for processing
    local temp_file=$(mktemp)
    
    # Process the file line by line to find and format JSON blocks
    local in_json_block=false
    local json_start_line=""
    local json_content=""
    
    while IFS= read -r line; do
        if [[ "$line" == *'```json{'* && "$in_json_block" == false ]]; then
            # Found single-line compact JSON format
            in_json_block=true
            json_start_line="$line"
            
            # Extract JSON content from the line
            local extracted_json="${line#*\`\`\`json}"
            extracted_json="${extracted_json%\`\`\`*}"
            
            # Try to format the JSON
            if echo "$extracted_json" | jq '.' >/dev/null 2>&1; then
                # Successfully parsed, format it
                echo '```json' >> "$temp_file"
                echo "$extracted_json" | jq '.' >> "$temp_file"
                echo '```' >> "$temp_file"
            else
                # Invalid JSON, keep original
                echo "$line" >> "$temp_file"
            fi
            in_json_block=false
        else
            # Regular line, copy as-is
            echo "$line" >> "$temp_file"
        fi
    done < "$output_file"
    
    # Replace the original file
    mv "$temp_file" "$output_file"
}

# Cleanup output resources
function cleanup_output() {
    # Prevent multiple cleanup calls
    if [[ "$CLEANUP_CALLED" == "true" ]]; then
        return
    fi
    CLEANUP_CALLED="true"
    
    # Clean up homo process if it's still running
    if [[ -n "$OUTPUT_PROCESS_PID" ]]; then
        # Close pipe and wait for homo process to finish
        if [[ -n "$OUTPUT_PIPE" ]]; then
            # Close file descriptor 3 (this signals EOF to homo)
            exec 3>&- 2>/dev/null || true
            
            # Wait indefinitely for homo to finish (user controls when to close)
            log_verbose "Waiting for homo process to finish (close the homo window when done viewing)..."
            while kill -0 "$OUTPUT_PROCESS_PID" 2>/dev/null; do
                sleep 0.5
            done
            
            log_verbose "Homo process finished"
            rm -f "$OUTPUT_PIPE"
        fi
    fi
    
    if [[ -n "$OUTPUT_MARKDOWN_FILE" ]]; then
        # Display in configured viewer app
        # TODO: Add cross-platform viewer support
        case "$RESULT_VIEWER_APP" in
            "homo")
                # This case should not happen since homo uses pipe, but handle it gracefully
                log_verbose "Warning: homo was specified but markdown file was used instead"
                ;;
            "Terminal"|"iTerm2"|"Warp")
                # Use macOS-specific launcher for now
                # TODO: Add platform detection and cross-platform app launching
                macos_launch_viewer_app "$RESULT_VIEWER_APP" "$OUTPUT_MARKDOWN_FILE"
                ;;
            *)
                log_verbose "Unknown viewer app: $RESULT_VIEWER_APP"
                ;;
        esac
    fi
}

# Process user input with selected template
function process_with_template() {
    # Get prompt template
    local template="${PROMPT_TEMPLATES[\"$SELECTED_TEMPLATE\"]}"
    local final_prompt=""
    local response=""
    
    # Get template properties
    local detect_language=$(get_template_property "$SELECTED_TEMPLATE" "detect_language" "false" 2>/dev/null)
    local output_language=$(get_template_property "$SELECTED_TEMPLATE" "output_language" "" 2>/dev/null)
    local json_schema=$(get_template_property "$SELECTED_TEMPLATE" "json_schema" "" 2>/dev/null)
    local json_field=$(get_template_property "$SELECTED_TEMPLATE" "json_field" "" 2>/dev/null)

    log_verbose "Template properties for '$SELECTED_TEMPLATE': $TEMPLATE_PROPERTIES[\"$SELECTED_TEMPLATE\"]"
    log_verbose " Detect language: $detect_language"
    log_verbose " Output language: $output_language"
    log_verbose " JSON schema: $json_schema"
    log_verbose " JSON field to extract: $json_field"

    # Language detection logic
    local language_instruction=""
    if [[ "$detect_language" == "true" ]]; then
        log_verbose "Detecting input language..."
        local detected_language
        detected_language=$(detect_language "$USER_INPUT" "$LANGUAGE_DETECTION_MODEL")
        log_verbose "Language detected: $detected_language"
        
        language_instruction="Output instruction: the input is in language: $detected_language, preserve this language in the output."
    elif [[ -n "$output_language" ]]; then
        language_instruction="Output instruction: the input is in language: $output_language, preserve this language in the output."
    fi
    
    # Replace {{input}} placeholder with user input
    if [[ "$template" == *"{{input}}"* ]]; then
        final_prompt="${template//\{\{input\}\}/$USER_INPUT}"
    else
        # If no placeholder exists, append user input to the end (for backward compatibility)
        final_prompt="$template $USER_INPUT"
    fi
    
    # Add JSON schema instruction if present
    if [[ -n "$json_schema" ]]; then
        local json_instruction="IMPORTANT: You must respond with valid JSON that matches this exact schema: $json_schema. Do not include any text outside the JSON response."
        final_prompt="$json_instruction\n\n$final_prompt"
    fi
    
    # Add language instruction if present
    [[ -n "$language_instruction" ]] && final_prompt="$language_instruction\n$final_prompt"
    
    log_verbose "Final prompt: $final_prompt"

    # Setup output stream
    setup_output
    
    # Set up trap to ensure cleanup happens even if script is interrupted
    trap cleanup_output EXIT INT TERM

    # Stream user input and prompt in collapsible details
    if [ "$VERBOSE_MODE" = true ]; then
        local user_input_escaped=$(printf '%s' "$USER_INPUT" | sed 's/\\/\\\\/g')
        local prompt_escaped=$(printf '%s' "$final_prompt" | sed 's/\\/\\\\/g')
        
        write_to_output "### User Input
<details>
<summary>Expand</summary>

\`\`\`
$user_input_escaped
\`\`\`
</details>

"
        write_to_output "### Final Prompt
<details>
<summary>Expand</summary>

\`\`\`
$prompt_escaped
\`\`\`
</details>

"
    fi
    # Execute LLM command with streaming
    local temp_response=$(mktemp)
    local exit_code
    
    # Start LLM API call and capture output in real-time
    write_to_output "### Result

"
    
    # Check if we need to wrap raw JSON output in details
    if [[ -n "$json_field" && -n "$json_schema" ]]; then
        write_to_output "#### Raw JSON Output

"
    fi
    
    # Stream the API response directly to output 
    call_llm_api "$SELECTED_MODEL" "$final_prompt" "$temp_response" | write_to_output_stream
    
    # Get exit code from the pipeline
    exit_code=${PIPESTATUS[0]}
    
    # Read the complete response from temp file
    response=$(cat "$temp_response")
    
    
    rm -f "$temp_response"
    
    # Format JSON in the output if we have JSON templates
    if [[ -n "$json_field" && -n "$json_schema" ]]; then
        if [[ -n "$OUTPUT_MARKDOWN_FILE" ]]; then
            # Post-process the output file to format JSON properly
            format_json_in_output_file "$OUTPUT_MARKDOWN_FILE"
        fi
    fi
    
    
    # Handle errors
    if [[ $exit_code -ne 0 ]]; then
        write_to_output "

**Error: LLM command failed with code $exit_code**
"
        cleanup_output
        exit $exit_code
    fi
    
    if [[ -z "$response" ]]; then
        write_to_output "

**Error: No response received from the model**
"
        cleanup_output
        exit 1
    fi
    
    # If we opened a JSON details block, reformat the compact JSON for better readability
    if [[ -n "$json_field" && -n "$json_schema" ]]; then
        # Check if the response contains compact JSON that needs reformatting
        if [[ "$response" == *'```json'* && "$response" == *'}```'* ]]; then
            # The model generates compact JSON in streaming mode, so let's reformat it
            # Extract the JSON content between the code blocks
            local json_content
            if [[ "$response" == *$'```json\n{'* ]]; then
                # Multi-line format: extract everything between ```json\n and \n```
                json_content=$(echo "$response" | sed -n '/```json/,/```/{/```json/d; /```/d; p;}')
            else
                # Single-line format: extract JSON from ```json{...}```
                json_content=$(echo "$response" | sed -n 's/.*```json\(.*\)```.*/\1/p')
            fi
            
        fi
        
        # Close the JSON section
        write_to_output "

---

#### Extracted JSON Field (_${json_field}_)

"
    fi
    
    # Extract JSON field if specified (do this before closing pipe)
    local raw_response="$response"  # Store original response before extraction
    if [[ -n "$json_field" && -n "$json_schema" ]]; then
        log_verbose "Extracting JSON field: $json_field"
        log_verbose "Raw LLM response: $response"
        
        local extracted_value
        
        # First try to extract JSON from the response in case there's extra text
        local json_content
        
        # Try to find JSON between ``` blocks first
        if [[ "$response" == *'```json'* ]]; then
            # Handle both multiline and single-line ```json{...}``` formats
            if [[ "$response" == *'```json{'* ]]; then
                # Single line format: ```json{...}```
                json_content=$(echo "$response" | sed -n 's/.*```json\(.*\)```.*/\1/p')
            else
                # Multiline format with separate lines
                json_content=$(printf '%s\n' "$response" | awk '/```json/{flag=1;next}/```/{flag=0}flag')
            fi
        else
            # Use a more robust approach to extract JSON content
            # First, try to validate if the entire response is valid JSON
            if printf '%s\n' "$response" | jq empty 2>/dev/null; then
                json_content="$response"
            else
                # Try to extract JSON block starting with { and ending with }
                # Use awk for better multiline handling
                json_content=$(printf '%s\n' "$response" | awk '
                    /^[[:space:]]*\{/ { json_start=1; json_lines="" }
                    json_start { 
                        json_lines = json_lines $0 "\n"
                        # Count braces to find the end of JSON object
                        for(i=1; i<=length($0); i++) {
                            char = substr($0, i, 1)
                            if(char == "{") brace_count++
                            else if(char == "}") brace_count--
                        }
                        if(brace_count == 0) {
                            print json_lines
                            exit
                        }
                    }
                    BEGIN { brace_count=0; json_start=0 }
                ')
                
                # If awk approach didn't work, fall back to simpler extraction
                if [[ -z "$json_content" ]]; then
                    # Look for content between first { and last }
                    local temp_file=$(mktemp)
                    printf '%s\n' "$response" > "$temp_file"
                    local start_line=$(grep -n '{' "$temp_file" | head -1 | cut -d: -f1)
                    local end_line=$(grep -n '}' "$temp_file" | tail -1 | cut -d: -f1)
                    
                    if [[ -n "$start_line" && -n "$end_line" ]]; then
                        json_content=$(sed -n "${start_line},${end_line}p" "$temp_file")
                    fi
                    rm -f "$temp_file"
                fi
            fi
        fi
        
        if [[ -z "$json_content" ]]; then
            # If no JSON block found, try the full response
            json_content="$response"
        fi
        
        log_verbose "Extracted JSON content: $json_content"
        
        # Use jq to extract the specific field from JSON response
        # Use printf instead of echo to properly handle newlines and special characters
        extracted_value=$(printf '%s\n' "$json_content" | jq -r ".$json_field" 2>/dev/null)
        local jq_exit_code=$?
        
        log_verbose "jq exit code: $jq_exit_code"
        log_verbose "Extracted value: '$extracted_value'"
        
        if [[ $jq_exit_code -eq 0 && "$extracted_value" != "null" && -n "$extracted_value" ]]; then
            log_verbose "Successfully extracted field value"
            
            # Show the extracted value (details block was already closed above)
            # Check if the extracted value is a JSON array and format it as bullet points
            if [[ "$extracted_value" == "["* ]] && printf '%s\n' "$extracted_value" | jq -e 'type == "array"' >/dev/null 2>&1; then
                log_verbose "Formatting JSON array as bullet points"
                
                # Check if array contains objects or simple strings
                local first_element_type=$(printf '%s\n' "$extracted_value" | jq -r '.[0] | type' 2>/dev/null)
                
                if [[ "$first_element_type" == "object" ]]; then
                    # Array of objects - try to format them nicely
                    log_verbose "Array contains objects, formatting with titles and descriptions"
                    local formatted_result=$(printf '%s\n' "$extracted_value" | jq -r '.[] | "* " + .title + (if .description then ": " + .description else "" end)')
                    write_to_output "$formatted_result"
                    # Set formatted result for clipboard
                    response="$formatted_result"
                else
                    # Array of strings - simple bullet point format
                    log_verbose "Array contains strings, formatting as simple bullet points"
                    local formatted_result=$(printf '%s\n' "$extracted_value" | jq -r '.[] | "* " + .')
                    write_to_output "$formatted_result"
                    # Set formatted result for clipboard
                    response="$formatted_result"
                fi
            else
                # Show the extracted value as plain text
                write_to_output "$extracted_value"
                # Set response for clipboard
                response="$extracted_value"
            fi
        else
            log_verbose "Warning: Could not extract JSON field '$json_field', using full response"
            if [[ "$VERBOSE_MODE" == true ]]; then
                log_verbose "JSON parsing failed. Response was:"
                echo "$response" >&2
            fi
            # If extraction failed, show the original response as-is (details block was already closed above)
        fi
    else
        # No JSON extraction needed
        raw_response=""
    fi
    
    # Add finish indicator
    write_to_output "

---

**✓ Processing complete**
"
    
    # Close the streaming output now that all details are written
    if [[ -n "$OUTPUT_PROCESS_PID" ]]; then
        # Close pipe to send EOF, then launch a background janitor to clean up
        if [[ -n "$OUTPUT_PIPE" ]]; then
            # Close file descriptor 3 (this signals EOF to homo)
            exec 3>&- 2>/dev/null || true
            
            # Launch background janitor process to wait for homo and clean up
            (
                # This subshell runs in the background.
                # Wait for the homo process to exit.
                while kill -0 "$OUTPUT_PROCESS_PID" 2>/dev/null; do
                    sleep 1
                done
                
                # Once homo is closed, clean up the pipe.
                rm -f "$OUTPUT_PIPE"
            ) &
            
            # Disown the janitor process so it continues running after the script exits
            disown $! >/dev/null 2>&1
            
            log_verbose "Homo is running in the background. The script will now exit."
            
            # Clear the variables to prevent the main script's cleanup trap from interfering
            OUTPUT_PIPE=""
            OUTPUT_PROCESS_PID=""
        fi
    fi
    
    # Copy final result to clipboard
    copy_to_clipboard "$response"
    
    # Cleanup and display
    cleanup_output
}

# Identify the language of input text
function detect_language() {
    local input_text="$1"
    local model="$2"
    
    local detection_prompt="You are a language identification specialist. Your only task is to determine the language of the provided text. Identify the language of this text. Respond with only the language name (e.g., 'English', 'Traditional Chinese'): $input_text"
    
    # Run language detection via API (non-streaming for reliability)
    local detected_language
    detected_language=$(call_llm_api "$model" "$detection_prompt" false | head -n 1 | tr -d '\n')
    
    echo "$detected_language"
}

#==========================================================
# PLATFORM-SPECIFIC FUNCTIONS
#==========================================================

# macOS-specific clipboard copy function
# TODO: Add cross-platform support for Linux (xclip/xsel/wl-copy), BSD, etc.
function macos_copy_to_clipboard() {
    local content="$1"
    
    # Set UTF-8 locale temporarily and use a file-based approach for better UTF-8 handling
    local original_lang="$LANG"
    local original_lc_all="$LC_ALL"
    export LANG="en_US.UTF-8"
    export LC_ALL="en_US.UTF-8"
    
    # Create temporary file for clipboard content with UTF-8 encoding
    local clipboard_temp="$(mktemp)"
    printf '%s' "$content" > "$clipboard_temp"
    
    # Copy using file input to ensure proper UTF-8 handling
    pbcopy < "$clipboard_temp"
    rm -f "$clipboard_temp"
    
    # Restore original locale
    export LANG="$original_lang"
    export LC_ALL="$original_lc_all"
}

# macOS-specific notification function
# TODO: Add cross-platform support for Linux (notify-send), BSD, etc.
function macos_show_notification() {
    local message="$1"
    osascript -e "display notification \"$message\""
}

# macOS-specific template selection GUI
# TODO: Add cross-platform support with terminal-based selection (fzf, dialog, etc.)
function macos_select_template_gui() {
    local available_templates="$1"
    local default_template="$2"
    
    local selected=$(osascript -e "choose from list {$available_templates} with prompt \"Select a prompt template to use:\" default items {\"$default_template\"}")
    
    if [ "$selected" = "false" ]; then
        echo ""  # Return empty string for cancelled selection
    else
        echo "$selected"
    fi
}

# macOS-specific application launcher
# TODO: Add cross-platform support for Linux terminals (gnome-terminal, konsole, xterm)
# TODO: Add support for generic file opening (xdg-open on Linux)
function macos_launch_viewer_app() {
    local app="$1"
    local file_path="$2"
    
    case "$app" in
        "Terminal")
            osascript -e "tell application \"Terminal\"
                do script \"glow -p ${file_path} && exit\"
            end tell"
            ;;
        "iTerm2")
            osascript -e "tell application \"iTerm2\"
                create window with default profile
                tell current session of current window
                    write text \"glow -p ${file_path} && exit\"
                end tell
            end tell"
            ;;
        "Warp")
            open -a /Applications/Warp.app "${file_path}"
            ;;
        *)
            log_verbose "Unknown macOS viewer app: $app"
            return 1
            ;;
    esac
}

# macOS-specific dependency checking
# TODO: Add cross-platform dependency functions for Linux, BSD, etc.
function macos_check_dependencies() {
    local errors=0
    
    # Check for osascript (macOS AppleScript - required for GUI features)
    if ! command -v osascript &> /dev/null; then
        echo "ERROR: osascript not found. This script requires macOS."
        ((errors++))
    else
        log_verbose "✓ osascript found (macOS AppleScript support)"
    fi
    
    # Check for pbcopy (clipboard functionality - required)
    if ! command -v pbcopy &> /dev/null; then
        echo "ERROR: pbcopy not found. This script requires macOS clipboard support."
        ((errors++))
    else
        log_verbose "✓ pbcopy found (clipboard support)"
    fi
    
    return $errors
}

# Cross-platform clipboard copy function (currently macOS-only)
# TODO: Implement platform detection and call appropriate clipboard function
function copy_to_clipboard() {
    local content="$1"
    
    # For now, only macOS is supported
    macos_copy_to_clipboard "$content"
    macos_show_notification "LLM results copied to clipboard"
}

#==========================================================
# MAIN SCRIPT
#==========================================================
# Initialize variables
VERBOSE_MODE=false

# Parse command line arguments first
parse_arguments "$@"

# Initialize the prompt templates and load configuration
init_prompt_templates

# Check for required dependencies (after configuration is loaded)
verify_dependencies

# Validate configuration
validate_configuration

# Show configuration information
log_verbose "Using model: $SELECTED_MODEL"
log_verbose "Using API: $API_BASE_URL"
log_verbose "Language detection model: $LANGUAGE_DETECTION_MODEL"
log_verbose "Default prompt template: $DEFAULT_PROMPT_TEMPLATE"

# Select a template if not specified in command line
select_prompt_template

# Validate that the selected template exists
validate_template

# Show template info in verbose mode
log_verbose "Selected template: $SELECTED_TEMPLATE"
log_verbose "Template content:"
log_verbose " ${PROMPT_TEMPLATES[\"$SELECTED_TEMPLATE\"]}"

# Process the input with the selected template
# Filter out unwanted debug output that may leak through
{
    process_with_template
} | grep -v "^json_content=" || true
