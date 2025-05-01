#!/bin/bash

# Launches portable Windows games on Linux using umu-launcher.

# --- Configuration ---
CUSTOM_PROTON_DIRS=(
    "$HOME/.local/share/Steam/compatibilitytools.d"
    "$HOME/.steam/root/compatibilitytools.d"
    "$HOME/.steam/steam/compatibilitytools.d"
    "$HOME/.var/app/com.valvesoftware.Steam/data/Steam/compatibilitytools.d/"
)

STEAM_LIB_DIRS=(
    "$HOME/.local/share/Steam"
    "$HOME/.steam/steam"
    "$HOME/.var/app/com.valvesoftware.Steam/data/Steam"
)
STEAM_PROTON_SUBDIR="steamapps/common"

GAMESCOPE_PARAMS="-f --backend wayland --grab"
UNIVERSAL_PREFIX_NAME="umu-default"

# --- Log Configuration ---
CONFIG_DIR="$HOME/.local/share/umu-launch-gum"
LOG_DIR="$CONFIG_DIR/logs"

# --- TUI Styling (using gum) ---
INFO_STYLE="--foreground 99"
SUCCESS_STYLE="--foreground 40"
WARNING_STYLE="--foreground 214"
ERROR_STYLE="--foreground 196 --bold"

# --- Global Variables ---
declare -a PROTON_VERSIONS
declare -a PROTON_PATHS
declare -a SELECTED_OPTIONS
declare -a FINAL_COMMAND
GAME_EXECUTABLE=""
GAME_DIR=""
GAME_BASENAME=""
CUSTOM_INPUT=""

# --- Helper Functions ---

# Displays styled messages using gum
gum_log() {
    local style_flags="$1" message="$2"
    # Pipe message to gum style for consistent output handling
    echo "$message" | gum style $style_flags
}

# Displays a styled error message and exits
error_exit() {
    local message="$1"
    # Pipe message to gum style and exit
    echo "Error: $message" | gum style $ERROR_STYLE
    exit 1
}

# Ensures the log directory exists
setup_config_dirs() {
    # Create directory if it doesn't exist, handle potential errors
    mkdir -p "$LOG_DIR" || error_exit "Failed to create log directory: $LOG_DIR"
}

# --- Dependency Checks ---
check_dependencies() {
    gum_log "$INFO_STYLE" "Checking dependencies..."
    local missing_dep=0
    # Check for essential commands
    for cmd in gum umu-run realpath date tee mkdir sort printf; do
        if ! command -v "$cmd" &>/dev/null; then
            gum_log "$ERROR_STYLE" "Essential command not found: $cmd. Please install it (often in coreutils or package manager)."
            missing_dep=1
        fi
    done
    [ $missing_dep -eq 1 ] && exit 1

    # Check for optional commands and set availability flags
    gamemode_available=$(command -v gamemoderun &>/dev/null && echo 1 || echo 0)
    gamescope_available=$(command -v gamescope &>/dev/null && echo 1 || echo 0)
    mangohud_available=$(command -v mangohud &>/dev/null && echo 1 || echo 0)
}

# --- Proton Detection ---
detect_proton_versions() {
    gum spin --spinner line --title "Searching for Proton versions..." -- sleep 0.2

    PROTON_VERSIONS=()
    PROTON_PATHS=()
    local found_paths_map # Associative array to handle duplicates and store paths
    declare -A found_paths_map

    # Search custom Proton directories
    gum_log "$INFO_STYLE" "Searching custom compatibilitytools.d directories..."
    for dir in "${CUSTOM_PROTON_DIRS[@]}"; do
        if [ -d "$dir" ]; then
             # Find directories inside, check for proton executable
             while IFS= read -r -d $'\0' p_dir; do
                local p_name=$(basename "$p_dir")
                local p_exec="$p_dir/proton"
                if [[ -f "$p_exec" && -x "$p_exec" ]]; then
                    found_paths_map["$p_name"]="$p_dir" # Add/overwrite path
                fi
             done < <(find "$dir" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null)
        fi
    done

    # Search official Steam library directories
    gum_log "$INFO_STYLE" "Searching official Steam directories..."
    for lib_dir in "${STEAM_LIB_DIRS[@]}"; do
        local common_dir="$lib_dir/$STEAM_PROTON_SUBDIR"
        if [ -d "$common_dir" ]; then
             # Find Proton* directories inside, check for proton executable
             while IFS= read -r -d $'\0' p_dir; do
                local p_name=$(basename "$p_dir")
                local p_exec="$p_dir/proton"
                if [[ -f "$p_exec" && -x "$p_exec" ]]; then
                    found_paths_map["$p_name"]="$p_dir" # Add/overwrite path
                fi
             done < <(find "$common_dir" -maxdepth 1 -name 'Proton*' -type d -print0 2>/dev/null)
        fi
    done

    # Populate arrays from the map
    for p_name in "${!found_paths_map[@]}"; do
        PROTON_VERSIONS+=("$p_name")
        PROTON_PATHS+=("${found_paths_map[$p_name]}")
    done

    # Sort the combined list alphabetically for display consistency
    local sorted_indices sorted_versions sorted_paths
    IFS=$'\n' sorted_indices=($(printf "%s\n" "${PROTON_VERSIONS[@]}" | sort -f | while read -r name; do
        for i in "${!PROTON_VERSIONS[@]}"; do if [[ "${PROTON_VERSIONS[$i]}" == "$name" ]]; then echo "$i"; break; fi; done
    done))
    unset IFS

    for index in "${sorted_indices[@]}"; do
        sorted_versions+=("${PROTON_VERSIONS[$index]}")
        sorted_paths+=("${PROTON_PATHS[$index]}")
    done
    PROTON_VERSIONS=("${sorted_versions[@]}")
    PROTON_PATHS=("${sorted_paths[@]}")

    # Check if any versions were found
    if [ ${#PROTON_VERSIONS[@]} -eq 0 ]; then error_exit "No Proton versions found."; fi
    gum_log "$SUCCESS_STYLE" "Found ${#PROTON_VERSIONS[@]} Proton versions."
}

# --- Game Selection ---
select_game_executable() {
    gum_log "$INFO_STYLE" "Please select the game's primary executable (.exe):"
    local selected_path
    selected_path=$(gum file "$HOME")

    # Handle cancellation or invalid selection
    [ -z "$selected_path" ] && error_exit "No game selected."
    [ ! -f "$selected_path" ] && error_exit "Invalid selection: Not a file."

    # Resolve path and set global variables
    GAME_EXECUTABLE=$(realpath "$selected_path") || error_exit "Failed to resolve path."
    GAME_DIR=$(dirname "$GAME_EXECUTABLE")
    GAME_BASENAME=$(basename "$GAME_EXECUTABLE")

    gum_log "$SUCCESS_STYLE" "Selected Game: $GAME_BASENAME"
    gum_log "$INFO_STYLE" "Game Directory: $GAME_DIR"
}

# --- Proton Selection ---
select_proton_version() {
    [ ${#PROTON_VERSIONS[@]} -eq 0 ] && error_exit "No Proton versions found."

    local header_text="Select Proton Version:"
    local chosen_option

    # Use gum choose for selection, increased height for more versions
    chosen_option=$(printf "%s\n" "${PROTON_VERSIONS[@]}" | gum choose \
        --height 15 \
        --header.foreground 212 --header.bold --header.margin '0 0 1 0' \
        --header="$header_text")

    [ -z "$chosen_option" ] && error_exit "No Proton selected."
    SELECTED_PROTON_NAME="$chosen_option"

    # Find the corresponding path
    SELECTED_PROTON_PATH=""
    for i in "${!PROTON_VERSIONS[@]}"; do
        if [[ "${PROTON_VERSIONS[$i]}" == "$SELECTED_PROTON_NAME" ]]; then
            SELECTED_PROTON_PATH="${PROTON_PATHS[$i]}"
            break
        fi
    done
    [ -z "$SELECTED_PROTON_PATH" ] && error_exit "Path not found for Proton '$SELECTED_PROTON_NAME'."

    gum_log "$SUCCESS_STYLE" "Selected Proton: $SELECTED_PROTON_NAME"
}

# --- Launch Options Selection ---
select_launch_options() {
    local top_options=() other_options=() final_options_list=()
    local -A option_map=(
        ["gamemode"]="Enable GameMode" ["gamescope"]="Enable Gamescope" ["mangohud"]="Enable MangoHud"
        ["dxvk_async"]="Enable DXVK Async" ["nvapi"]="Enable NVAPI" ["vkd3d_rt"]="Enable VKD3D RT"
        ["vk_validate"]="Enable Vulkan Validation"
    )
    local -A option_availability=(
        ["gamemode"]=$gamemode_available ["gamescope"]=$gamescope_available ["mangohud"]=$mangohud_available
        ["dxvk_async"]=1 ["nvapi"]=1 ["vkd3d_rt"]=1 ["vk_validate"]=1
    )
    local -A option_not_installed_text=(
        ["gamemode"]="GameMode (Not Installed)" ["gamescope"]="Gamescope (Not Installed)" ["mangohud"]="MangoHud (Not Installed)"
    )
    local top_order=("gamemode" "gamescope" "mangohud" "dxvk_async")

    # Build ordered list based on availability and desired order
    for key in "${top_order[@]}"; do
        if [[ -v option_map[$key] ]]; then
            if [[ ${option_availability[$key]} -eq 1 ]]; then top_options+=("${option_map[$key]}");
            elif [[ -v option_not_installed_text[$key] ]]; then top_options+=("${option_not_installed_text[$key]}"); fi
        fi
    done
    for key in "${!option_map[@]}"; do
        local is_top=0; for top_key in "${top_order[@]}"; do if [[ "$key" == "$top_key" ]]; then is_top=1; break; fi; done
        if [[ $is_top -eq 0 ]]; then
             if [[ ${option_availability[$key]} -eq 1 ]]; then other_options+=("${option_map[$key]}");
             elif [[ -v option_not_installed_text[$key] ]]; then other_options+=("${option_not_installed_text[$key]}"); fi
        fi
    done
    IFS=$'\n' sorted_other_options=($(sort <<<"${other_options[*]}")); unset IFS
    final_options_list=("${top_options[@]}" "${sorted_other_options[@]}")

    local header_text="Select launch options (Space to toggle, Enter to confirm):"
    gum_log "$INFO_STYLE" "Use Space to toggle options, Enter to confirm."

    # Use gum choose for multi-selection
    local selected_options_str
    selected_options_str=$(printf "%s\n" "${final_options_list[@]}" | gum choose \
        --no-limit \
        --height 10 \
        --header.foreground 212 --header.bold --header.margin '0 0 1 0' \
        --header="$header_text" \
        --selected.foreground="40" \
        --cursor.foreground="212")

    SELECTED_OPTIONS=()
    mapfile -t SELECTED_OPTIONS < <(echo "$selected_options_str")
}

# --- Synchronization Method Selection ---
select_sync_method() {
    local sync_methods=(
        "Fsync (Needs kernel support, e.g., Zen/Liquorix)"
        "Esync (Needs increased file descriptor limits)"
        "Ntsync (Needs Proton-GE/Wine-GE/TKG builds)"
        "None (Disable explicit sync method)"
    )
    local header_text="Select Sync Method:"
    local chosen_option

    # Use gum choose for single selection
    chosen_option=$(printf "%s\n" "${sync_methods[@]}" | gum choose \
        --header.foreground 212 --header.bold --header.margin '0 0 1 0' \
        --header="$header_text" \
        --item.padding '0 1')

    # Handle cancellation by defaulting to Fsync
    if [ -z "$chosen_option" ]; then
        gum_log "$WARNING_STYLE" "Cancelled, defaulting to Fsync."
        SELECTED_SYNC_METHOD="Fsync (Needs kernel support, e.g., Zen/Liquorix)"
    else
        SELECTED_SYNC_METHOD="$chosen_option"
    fi
    gum_log "$SUCCESS_STYLE" "Selected Sync Method: ${SELECTED_SYNC_METHOD%% *}"
}

# --- Get Custom Input ---
get_custom_input() {
    gum_log "$INFO_STYLE" "Enter any additional env vars (VAR=val) or arguments (-arg):"
    # Use gum input to capture custom user input
    CUSTOM_INPUT=$(gum input --placeholder "e.g., DXVK_HUD=1 -someflag")
    # Trim leading/trailing whitespace
    CUSTOM_INPUT=$(echo "$CUSTOM_INPUT" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -n "$CUSTOM_INPUT" ]; then
        gum_log "$SUCCESS_STYLE" "Added custom input: $CUSTOM_INPUT"
    fi
}

# --- Configure Environment Variables and Command ---
configure_environment_and_command() {
    local gamescope_prefix=() gamemode_prefix=() custom_args=()
    declare -A LAUNCH_ENV
    LAUNCH_ENV["PROTONPATH"]="$SELECTED_PROTON_PATH"
    LAUNCH_ENV["GAMEID"]="$UNIVERSAL_PREFIX_NAME"

    local gamescope_enabled=0 gamemode_enabled=0 mangohud_enabled=0
    local nvapi_enabled=0 dxvk_async_enabled=0 vkd3d_rt_enabled=0 vk_validate_enabled=0

    # Process standard selected options
    for opt in "${SELECTED_OPTIONS[@]}"; do
        case "$opt" in
            "Enable Gamescope"*) if [ "$gamescope_available" -eq 1 ]; then read -r -a gs_flags <<< "$GAMESCOPE_PARAMS"; gamescope_prefix=("gamescope" "${gs_flags[@]}" "--"); gamescope_enabled=1; else gum_log "$WARNING_STYLE" "Gamescope NA."; fi ;;
            "Enable MangoHud"*) if [ "$mangohud_available" -eq 1 ]; then LAUNCH_ENV["MANGOHUD"]="1"; mangohud_enabled=1; else gum_log "$WARNING_STYLE" "MangoHud NA."; fi ;;
            "Enable GameMode"*) if [ "$gamemode_available" -eq 1 ]; then gamemode_prefix=("gamemoderun"); gamemode_enabled=1; else gum_log "$WARNING_STYLE" "GameMode NA."; fi ;;
            "Enable NVAPI"*) LAUNCH_ENV["PROTON_ENABLE_NVAPI"]="1"; LAUNCH_ENV["DXVK_ENABLE_NVAPI"]="1"; nvapi_enabled=1 ;;
            "Enable DXVK Async"*) LAUNCH_ENV["DXVK_ASYNC"]="1"; dxvk_async_enabled=1 ;;
            "Enable VKD3D RT"*) LAUNCH_ENV["VKD3D_CONFIG"]="dxr11,dxr"; vkd3d_rt_enabled=1 ;;
            "Enable Vulkan Validation"*) LAUNCH_ENV["VK_INSTANCE_LAYERS"]="VK_LAYER_KHRONOS_validation"; vk_validate_enabled=1; gum_log "$WARNING_STYLE" "Vulkan Validation Layers enabled."; ;;
        esac
    done

    # Process sync method selection
    local sync_method_name="None"
    local clean_sync_method="${SELECTED_SYNC_METHOD}"
    case "$clean_sync_method" in
        "Fsync"*) LAUNCH_ENV["WINEFSYNC"]="1"; sync_method_name="Fsync" ;;
        "Esync"*) LAUNCH_ENV["WINEESYNC"]="1"; sync_method_name="Esync" ;;
        "Ntsync"*) LAUNCH_ENV["PROTON_USE_NTSYNC"]="1"; sync_method_name="Ntsync" ;;
        "None"*) sync_method_name="None" ;;
        *) gum_log "$WARNING_STYLE" "Unknown sync method, defaulting to Fsync."; LAUNCH_ENV["WINEFSYNC"]="1"; sync_method_name="Fsync (Defaulted)" ;;
    esac

    # Process custom input into env vars or args
    if [ -n "$CUSTOM_INPUT" ]; then
        read -r -a custom_tokens <<< "$CUSTOM_INPUT"
        for token in "${custom_tokens[@]}"; do
            if [[ "$token" == *"="* ]]; then LAUNCH_ENV["${token%%=*}"]="${token#*=} "; else custom_args+=("$token"); fi
        done
    fi

    # Build core command (env + umu-run + custom args)
    local core_command=("env")
    for key in "${!LAUNCH_ENV[@]}"; do core_command+=("${key}=${LAUNCH_ENV[$key]}"); done
    core_command+=("umu-run" "$GAME_BASENAME")
    core_command+=("${custom_args[@]}")

    # Assemble final command with wrappers
    FINAL_COMMAND=()
    [ ${#gamemode_prefix[@]} -gt 0 ] && FINAL_COMMAND+=("${gamemode_prefix[@]}")
    [ ${#gamescope_prefix[@]} -gt 0 ] && FINAL_COMMAND+=("${gamescope_prefix[@]}")
    FINAL_COMMAND+=("${core_command[@]}")

    # Store summary flags
    _SUMMARY_GAMESCOPE_ENABLED=$gamescope_enabled; _SUMMARY_GAMEMODE_ENABLED=$gamemode_enabled; _SUMMARY_MANGOHUD_ENABLED=$mangohud_enabled
    _SUMMARY_NVAPI_ENABLED=$nvapi_enabled; _SUMMARY_DXVK_ASYNC_ENABLED=$dxvk_async_enabled; _SUMMARY_VKD3D_RT_ENABLED=$vkd3d_rt_enabled
    _SUMMARY_VK_VALIDATE_ENABLED=$vk_validate_enabled; _SUMMARY_SYNC_METHOD_NAME=$sync_method_name
}

# --- Display Summary and Launch ---
display_summary_and_launch() {
    # Build summary content line by line for clarity and wrapping
    local summary_lines=()
    summary_lines+=("$(echo "Launch Configuration Summary" | gum style --foreground 51 --bold --align center)")
    summary_lines+=(" ")

    add_summary_line() {
        local label="$1" value="$2"
        local label_styled; label_styled=$(echo "$label:" | gum style --foreground 240)
        local value_styled; value_styled=$(echo "$value" | gum style --foreground 250)
        summary_lines+=("$label_styled $value_styled")
    }

    add_summary_line "Game" "$GAME_BASENAME"
    add_summary_line "Directory" "$GAME_DIR"
    add_summary_line "Proton" "$SELECTED_PROTON_NAME"
    add_summary_line "Prefix" "$UNIVERSAL_PREFIX_NAME"
    add_summary_line "Sync Method" "$_SUMMARY_SYNC_METHOD_NAME"
    summary_lines+=(" ")
    summary_lines+=("$(echo "--- Options ---" | gum style --foreground 240)")
    add_summary_line "GameMode" "$([ "$_SUMMARY_GAMEMODE_ENABLED" -eq 1 ] && echo "Enabled" || echo "Disabled")"
    add_summary_line "Gamescope" "$([ "$_SUMMARY_GAMESCOPE_ENABLED" -eq 1 ] && echo "Enabled" || echo "Disabled")"
    add_summary_line "MangoHud" "$([ "$_SUMMARY_MANGOHUD_ENABLED" -eq 1 ] && echo "Enabled" || echo "Disabled")"
    add_summary_line "NVAPI" "$([ "$_SUMMARY_NVAPI_ENABLED" -eq 1 ] && echo "Enabled" || echo "Disabled")"
    add_summary_line "DXVK Async" "$([ "$_SUMMARY_DXVK_ASYNC_ENABLED" -eq 1 ] && echo "Enabled" || echo "Disabled")"
    add_summary_line "VKD3D RT" "$([ "$_SUMMARY_VKD3D_RT_ENABLED" -eq 1 ] && echo "Enabled" || echo "Disabled")"
    add_summary_line "VK Validate" "$([ "$_SUMMARY_VK_VALIDATE_ENABLED" -eq 1 ] && echo "Enabled" || echo "Disabled")"
    add_summary_line "Custom Input" "$( [ -n "$CUSTOM_INPUT" ] && echo "$CUSTOM_INPUT" || echo "None" )"
    summary_lines+=(" ")
    local separator; separator=$(printf '%*s' 50 '' | tr ' ' '─')
    summary_lines+=("$(echo "$separator" | gum style --foreground 238)")

    # Prepare command string for display
    local display_command_str=""
    for item in "${FINAL_COMMAND[@]}"; do if [[ "$item" == *" "* || "$item" == *"="* || "$item" == "--" ]]; then display_command_str+=" '$item'"; else display_command_str+=" $item"; fi; done
    display_command_str="${display_command_str# }"
    summary_lines+=("$(echo "Executing Command (within '$GAME_DIR'):" | gum style --foreground 99)")
    summary_lines+=("$(echo "$display_command_str" | gum style --foreground 245)")

    local full_summary; full_summary=$(printf "%s\n" "${summary_lines[@]}")

    # Display summary within a styled box
    echo "$full_summary" | gum style --border normal --margin '1 0' --padding '1 2' --border-foreground 51

    # Confirmation
    if ! gum confirm "Proceed with launch?" --affirmative "Launch!" --negative "Cancel"; then error_exit "Launch cancelled."; fi

    gum_log "$SUCCESS_STYLE" "Launching game..."

    # Execution and Logging
    local safe_basename="${GAME_BASENAME//[^a-zA-Z0-9._-]/_}"
    local log_file="$LOG_DIR/${safe_basename}_$(date +%Y%m%d_%H%M%S).log"
    gum_log "$INFO_STYLE" "Logging output to: $log_file"
    echo "--- Launch Command ---" > "$log_file"
    printf "%q " "${FINAL_COMMAND[@]}" >> "$log_file" # Log command safely quoted
    echo -e "\n\n--- Game Output ---" >> "$log_file"
    (cd "$GAME_DIR" && set -o pipefail && "${FINAL_COMMAND[@]}" 2>&1 | tee -a "$log_file")
    local exit_code=${PIPESTATUS[0]}

    # Handle exit code
    if [ $exit_code -ne 0 ]; then
        local exit_msg="Game exited with status code: $exit_code"
        [ $exit_code -eq 139 ] && exit_msg+=" (Segmentation fault)"
        gum_log "$WARNING_STYLE" "$exit_msg"
    else
        gum_log "$SUCCESS_STYLE" "Game exited successfully."
        gum_log "$SUCCESS_STYLE" "Launch complete." # Added final message
    fi
}

# --- Main Script Logic ---
main() {
    setup_config_dirs
    # Display main header
    echo "UMU Game Launcher" | gum style --border double --padding '1 2' --border-foreground 212 --align center
    # Run main steps
    check_dependencies
    select_game_executable
    detect_proton_versions
    select_proton_version
    select_launch_options
    select_sync_method
    get_custom_input
    configure_environment_and_command
    display_summary_and_launch
}

# --- Script Execution ---
main
exit 0
