#!/bin/zsh

#==========================================================
# LLM Prompt Tool
# 
# This script runs a local LLM command and applies selected
# pre-configured prompts to user input, making it easy to use LLMs
# for specific tasks without writing new prompts each time.
#==========================================================

#==========================================================
# CONFIGURATION
#==========================================================
# LLM settings
LLM_COMMAND="ollama"                         # Command to run LLM
LLM_ATTR="run"                               # Command attribute (run for Ollama)
DEFAULT_MODEL="gemma3n"                      # Default model to use if none specified
LANGUAGE_DETECTION_MODEL="gemma3n:e2b"       # Model used for language detection
DEFAULT_PROMPT_TEMPLATE="Passthrough"        # Default prompt template if none selected

# Template settings
TEMPLATE_YAML_FILE="gems.yml"                # YAML file containing prompt templates (relative to script directory)

# Output settings
RESULT_VIEWER_APP=""                         # Application to open results: homo, Warp, Terminal, or iTerm2

#==========================================================
# FUNCTIONS
#==========================================================

# Declare associative arrays at global scope
typeset -gA PROMPT_TEMPLATES
typeset -gA TEMPLATE_PROPERTIES

# Log message if in verbose mode
function log_verbose() {
    if [ "$VERBOSE_MODE" = true ]; then
        echo "[DEBUG] $1"
    fi
}

# Get available models from ollama
function get_available_models() {
    # Check if ollama command exists
    if ! command -v "$LLM_COMMAND" &> /dev/null; then
        echo "Error: '$LLM_COMMAND' is not installed or not in PATH."
        return 1
    fi
    
    # Run ollama ls and extract the model names (first column), skipping the header row
    local models
    models=$($LLM_COMMAND ls 2>/dev/null | awk 'NR>1 {print $1}' | sort)
    
    echo "$models"
}

# Display usage information
function show_help() {
    echo "Usage: gems.sh [-m model] [-t template] [-v] [-h] [--list-templates] [--template-info template] [text]"
    echo "Options:"
    echo "  -m <model>            Specify LLM model (default: $DEFAULT_MODEL)"
    echo "  -t <template>         Specify prompt template to use"
    echo "  -v                    Verbose mode (show debug information)"
    echo "  -h                    Display this help message"
    echo "  --list-templates      List all available templates with descriptions"
    echo "  --template-info <name>  Show detailed information about a specific template"
    echo ""
    echo "Templates:"
    echo "  Templates are loaded from $TEMPLATE_YAML_FILE if available (requires yq)."
    echo "  If YAML loading fails, built-in templates are used as fallback."
    echo ""
    echo "Examples:"
    echo "  gems.sh 'Fix this sentence: Me and him went to store'"
    echo "  gems.sh -t CodeReview 'function foo() { return x + y; }'"
    echo "  gems.sh -m gemma3:4b-it-qat -t Summarize 'Long text to summarize...'"
    echo ""
    echo "Available prompt templates:"
    for template_name in ${(k)PROMPT_TEMPLATES}; do
        echo "  - $template_name"
    done
    
    echo ""
    echo "Available models:"
    local available_models
    available_models=$(get_available_models)
    if [ $? -eq 0 ] && [ -n "$available_models" ]; then
        echo "$available_models" | while read -r model; do
            echo "  - $model"
        done
    else
        echo "  Unable to retrieve model list. Check if ollama is installed and running."
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
        log_verbose "yq not found. Install with: brew install yq"
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
    
    # Check LLM command (required)
    if ! command -v "$LLM_COMMAND" &> /dev/null; then
        echo "ERROR: '$LLM_COMMAND' is not installed or not in PATH."
        echo "Please install $LLM_COMMAND: https://ollama.com/download"
        ((errors++))
    else
        log_verbose "✓ $LLM_COMMAND found"
        
        # Test if ollama service is running
        if ! $LLM_COMMAND list &> /dev/null; then
            echo "WARNING: $LLM_COMMAND service may not be running. Try: ollama serve"
            ((warnings++))
        else
            log_verbose "✓ $LLM_COMMAND service is running"
        fi
    fi
    
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
    
    # Optional dependencies with warnings
    log_verbose "Checking optional dependencies..."
    
    # Check for yq (YAML parsing - optional but recommended)
    if ! command -v yq &> /dev/null; then
        log_verbose "WARNING: 'yq' not found. YAML template loading will be disabled."
        log_verbose "Install with: brew install yq"
        ((warnings++))
    else
        log_verbose "✓ yq found (YAML template support)"
        
        # Test yq functionality
        if ! echo "test: value" | yq eval '.test' &> /dev/null; then
            log_verbose "WARNING: yq installation may be corrupted"
            ((warnings++))
        fi
    fi
    
    # Check for jq (JSON parsing - required for JSON schema features)
    if ! command -v jq &> /dev/null; then
        log_verbose "WARNING: 'jq' not found. JSON field extraction will be disabled."
        log_verbose "Install with: brew install jq"
        ((warnings++))
    else
        log_verbose "✓ jq found (JSON processing support)"
        
        # Test jq functionality
        if ! echo '{"test": "value"}' | jq -r '.test' &> /dev/null; then
            log_verbose "WARNING: jq installation may be corrupted"
            ((warnings++))
        fi
    fi
    
    # Check for glow (markdown rendering - optional)
    if ! command -v glow &> /dev/null; then
        log_verbose "WARNING: 'glow' not found. Markdown rendering will be disabled."
        log_verbose "Install with: brew install glow"
        ((warnings++))
    else
        log_verbose "✓ glow found (markdown rendering support)"
    fi
    
    # Check for realpath/readlink (path resolution - semi-optional)
    if ! command -v realpath &> /dev/null && ! command -v readlink &> /dev/null; then
        log_verbose "WARNING: Neither 'realpath' nor 'readlink' found. Path resolution may be limited."
        log_verbose "Install coreutils with: brew install coreutils"
        ((warnings++))
    else
        if command -v realpath &> /dev/null; then
            log_verbose "✓ realpath found (path resolution support)"
        else
            log_verbose "✓ readlink found (path resolution support)"
        fi
    fi
    
    # Check for default model availability
    if command -v "$LLM_COMMAND" &> /dev/null && $LLM_COMMAND list &> /dev/null; then
        if ! $LLM_COMMAND list | grep -q "^$DEFAULT_MODEL"; then
            log_verbose "WARNING: Default model '$DEFAULT_MODEL' not found."
            log_verbose "Available models:"
            $LLM_COMMAND list 2>/dev/null | awk 'NR>1 {print "  - " $1}' | while read line; do log_verbose "$line"; done || log_verbose "  Unable to list models"
            log_verbose "You can download the default model with: ollama pull $DEFAULT_MODEL"
            ((warnings++))
        else
            log_verbose "✓ Default model '$DEFAULT_MODEL' is available"
        fi
        
        # Check language detection model
        if ! $LLM_COMMAND list | grep -q "^$LANGUAGE_DETECTION_MODEL"; then
            log_verbose "WARNING: Language detection model '$LANGUAGE_DETECTION_MODEL' not found."
            log_verbose "Language detection features will be limited."
            log_verbose "Download with: ollama pull $LANGUAGE_DETECTION_MODEL"
            ((warnings++))
        else
            log_verbose "✓ Language detection model '$LANGUAGE_DETECTION_MODEL' is available"
        fi
    fi
    
    # Check YAML template file
    local script_dir="$(dirname "${BASH_SOURCE[0]:-$0}")"
    local yaml_file="$script_dir/$TEMPLATE_YAML_FILE"
    if [[ ! -f "$yaml_file" ]]; then
        log_verbose "WARNING: Template file '$yaml_file' not found."
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
                if [[ ! -d "/Applications/Warp.app" ]]; then
                    log_verbose "WARNING: Warp app not found at /Applications/Warp.app"
                    log_verbose "Results won't be displayed in Warp."
                    ((warnings++))
                else
                    log_verbose "✓ Warp app found"
                fi
                ;;
            "iTerm2")
                if [[ ! -d "/Applications/iTerm.app" ]]; then
                    log_verbose "WARNING: iTerm2 app not found at /Applications/iTerm.app"
                    log_verbose "Results won't be displayed in iTerm2."
                    ((warnings++))
                else
                    log_verbose "✓ iTerm2 app found"
                fi
                ;;
            "Terminal")
                log_verbose "✓ Using built-in Terminal app"
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
    if [[ -z "$LLM_COMMAND" ]]; then
        echo "Error: LLM_COMMAND is not configured"
        ((errors++))
    fi
    
    if [[ -z "$DEFAULT_MODEL" ]]; then
        echo "Error: DEFAULT_MODEL is not configured"
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

    # Set default model if not specified
    if [ -z "$SELECTED_MODEL" ]; then
        SELECTED_MODEL="$DEFAULT_MODEL"
    fi

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
    
    # Special handling for macOS Shortcuts and other edge cases
    # If the script path looks like a temp file or doesn't contain our expected script name,
    # try to find the script in common locations
    if [[ "$script_path" == *"/tmp/"* ]] || [[ "$script_path" == *"/var/"* ]] || [[ ! "$script_path" == *"gems.sh"* ]]; then
        log_verbose "Detected execution from Shortcuts or temp location, searching for actual script"
        
        # Try some common locations where the script might be
        local possible_locations=(
            "/Users/hoss/Workspace/_tools/gems.sh"
            "$HOME/Workspace/_tools/gems.sh"
            "$(dirname "$HOME")/hoss/Workspace/_tools/gems.sh"
        )
        
        for location in "${possible_locations[@]}"; do
            if [[ -f "$location" ]]; then
                script_path="$location"
                log_verbose "Found script at: $script_path"
                break
            fi
        done
    fi
    
    # Resolve the real path (handles symlinks and relative paths)
    if command -v realpath &> /dev/null; then
        script_path="$(realpath "$script_path")"
    elif command -v readlink &> /dev/null; then
        # Alternative using readlink (available on macOS)
        script_path="$(readlink -f "$script_path" 2>/dev/null || echo "$script_path")"
    fi
    
    script_dir="$(dirname "$script_path")"
    local yaml_file="$script_dir/$TEMPLATE_YAML_FILE"
    
    log_verbose "Script directory: $script_dir"
    log_verbose "Script path: $script_path"
    log_verbose "YAML file path: $yaml_file"
    log_verbose "YAML file exists: $(test -f "$yaml_file" && echo "YES" || echo "NO")"
    
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
        SELECTED_TEMPLATE=$(osascript -e "choose from list {$available_templates} with prompt \"Select a prompt template to use:\" default items {\"$DEFAULT_PROMPT_TEMPLATE\"}")

        if [ "$SELECTED_TEMPLATE" = "false" ]; then
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
        echo "  brew install yq"
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
        # Write to pipe using file descriptor 3
        printf '%s' "$content" >&3
    else
        # Direct to terminal
        printf '%s' "$content"
    fi
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
        case "$RESULT_VIEWER_APP" in
            "homo")
                # This case should not happen since homo uses pipe, but handle it gracefully
                log_verbose "Warning: homo was specified but markdown file was used instead"
                ;;
            "Terminal")
                osascript -e "tell application \"Terminal\"
                    do script \"glow -p ${OUTPUT_MARKDOWN_FILE} && exit\"
                end tell"
                ;;
            "iTerm2")
                osascript -e "tell application \"iTerm2\"
                    create window with default profile
                    tell current session of current window
                        write text \"glow -p ${OUTPUT_MARKDOWN_FILE} && exit\"
                    end tell
                end tell"
                ;;
            "Warp")
                open -a /Applications/Warp.app "${OUTPUT_MARKDOWN_FILE}"
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
    
    # Start LLM process and capture output in real-time
    local result_header_written=false
    write_to_output "### Result
"
    $LLM_COMMAND $LLM_ATTR $SELECTED_MODEL "$final_prompt" | tee "$temp_response" | while IFS= read -r line; do
        # Stream each line of LLM output as it arrives
        if [[ "$result_header_written" != "true" ]]; then
            # Check if we need to wrap raw JSON output in details
            if [[ -n "$json_field" && -n "$json_schema" ]]; then
                write_to_output "#### Raw JSON Output
"
            fi
            result_header_written=true
        fi
        write_to_output "$line
"
    done
    
    # Get exit code from the pipeline
    exit_code=${PIPESTATUS[0]}
    
    # Read the complete response from temp file
    response=$(cat "$temp_response")
    rm -f "$temp_response"
    
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
    
    # If we opened a JSON details block, we need to close it properly
    if [[ -n "$json_field" && -n "$json_schema" ]]; then
        # Close the JSON code block first
        write_to_output "---
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
            # Use awk to properly extract content between ```json and ``` while preserving newlines
            json_content=$(printf '%s\n' "$response" | awk '/```json/{flag=1;next}/```/{flag=0}flag')
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
                else
                    # Array of strings - simple bullet point format
                    log_verbose "Array contains strings, formatting as simple bullet points"
                    local formatted_result=$(printf '%s\n' "$extracted_value" | jq -r '.[] | "* " + .')
                    write_to_output "$formatted_result"
                fi
            else
                # Show the extracted value as plain text
                write_to_output "$extracted_value"
            fi
            
            # Set response for clipboard
            response="$extracted_value"
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
    
    # Run language detection
    local detected_language
    detected_language=$($LLM_COMMAND $LLM_ATTR "$model" "$detection_prompt" | head -n 1)
    
    echo "$detected_language"
}

# Copy content to clipboard with UTF-8 support
function copy_to_clipboard() {
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
    
    osascript -e "display notification \"LLM results copied to clipboard\""
}

#==========================================================
# MAIN SCRIPT
#==========================================================
# Initialize variables
VERBOSE_MODE=false

# Parse command line arguments first
parse_arguments "$@"

# Check for required dependencies
verify_dependencies

# Validate configuration
validate_configuration

# Initialize the prompt templates after we know verbose mode
init_prompt_templates

# Show configuration information
log_verbose "Using model: $SELECTED_MODEL"
log_verbose "Using command: $LLM_COMMAND $LLM_ATTR"
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
process_with_template
