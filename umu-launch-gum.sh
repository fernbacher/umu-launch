#!/bin/bash

DEFAULT_CUSTOM_PROTON_DIRS=(
    "$HOME/.local/share/Steam/compatibilitytools.d"
    "$HOME/.steam/root/compatibilitytools.d"
    "$HOME/.steam/steam/compatibilitytools.d"
    "$HOME/.var/app/com.valvesoftware.Steam/data/Steam/compatibilitytools.d/"
)
DEFAULT_STEAM_LIB_DIRS=(
    "$HOME/.local/share/Steam"
    "$HOME/.steam/steam"
    "$HOME/.var/app/com.valvesoftware.Steam/data/Steam"
)
DEFAULT_STEAM_PROTON_SUBDIR="steamapps/common"
DEFAULT_GAMESCOPE_PARAMS="-f --backend wayland --grab"
DEFAULT_UNIVERSAL_PREFIX_NAME="umu-default"

CONFIG_DIR="$HOME/.config/umu-launch-gum"
CONFIG_FILE="$CONFIG_DIR/config.conf"
DATA_DIR="$HOME/.local/share/umu-launch-gum"
LOG_DIR="$DATA_DIR/logs"
LIBRARY_DIR="$DATA_DIR/library"
LAST_GAME_FILE="$DATA_DIR/last_game_config.jsonpath"

INFO_STYLE_ARGS=("--foreground" "99")
SUCCESS_STYLE_ARGS=("--foreground" "40")
WARNING_STYLE_ARGS=("--foreground" "214")
ERROR_STYLE_ARGS=("--foreground" "196" "--bold")
HEADER_FG_COLOR="28" 
SELECTED_FG_COLOR="205"
CURSOR_FG_COLOR="28" 
ITEM_PADDING="0 1"
DEPENDENCY_LABEL_STYLE_ARGS=("--width" "15" "--foreground" "240")
DEPENDENCY_FOUND_STYLE_ARGS=("--foreground" "40" "--bold")
DEPENDENCY_MISSING_STYLE_ARGS=("--foreground" "196")

CUSTOM_PROTON_DIRS=("${DEFAULT_CUSTOM_PROTON_DIRS[@]}")
STEAM_LIB_DIRS=("${DEFAULT_STEAM_LIB_DIRS[@]}")
STEAM_PROTON_SUBDIR="$DEFAULT_STEAM_PROTON_SUBDIR"
GAMESCOPE_PARAMS="$DEFAULT_GAMESCOPE_PARAMS"
UNIVERSAL_PREFIX_NAME="$DEFAULT_UNIVERSAL_PREFIX_NAME"

declare -a PROTON_VERSIONS PROTON_PATHS SELECTED_OPTIONS FINAL_COMMAND
GAME_EXECUTABLE="" GAME_DIR="" GAME_BASENAME=""
SELECTED_PROTON_NAME="" SELECTED_PROTON_PATH="" CUSTOM_INPUT=""
GAMESCOPE_FLAGS_TO_USE="" SELECTED_SYNC_METHOD=""
GAMESCOPE_SELECTED=0
_SUMMARY_GAMESCOPE_ENABLED=0 _SUMMARY_GAMEMODE_ENABLED=0 _SUMMARY_MANGOHUD_ENABLED=0
_SUMMARY_NVAPI_ENABLED=0 _SUMMARY_DXVK_ASYNC_ENABLED=0 _SUMMARY_VKD3D_RT_ENABLED=0
_SUMMARY_VK_VALIDATE_ENABLED=0 _SUMMARY_SYNC_METHOD_NAME=""
IS_QUICK_LAUNCHING=0

gum_log() {
    local -n style_args_ref=$1 
    local message="$2"
    echo "$message" | gum style "${style_args_ref[@]}" 
}

error_exit() {
    local message="$1"
    echo "Error: $message" | gum style "${ERROR_STYLE_ARGS[@]}"
    exit 1
}

setup_data_dirs() {
    mkdir -p "$LOG_DIR" || error_exit "Failed to create log directory: $LOG_DIR"
    mkdir -p "$LIBRARY_DIR" || error_exit "Failed to create library directory: $LIBRARY_DIR"
}

load_config() {
    [[ ! -f "$CONFIG_FILE" ]] && return
    gum_log INFO_STYLE_ARGS "Loading config: $CONFIG_FILE"
    local var_name var_value
    while IFS='=' read -r var_name var_value || [[ -n "$var_name" ]]; do
        var_name=$(echo "$var_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        var_value=$(echo "$var_value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ "$var_name" =~ ^# ]] || [[ -z "$var_name" ]] && continue
        var_value="${var_value#\"}"; var_value="${var_value%\"}"
        var_value="${var_value#\'}"; var_value="${var_value%\'}"
        case "$var_name" in
            CUSTOM_PROTON_DIRS) read -r -a CUSTOM_PROTON_DIRS <<< "$var_value" ;;
            STEAM_LIB_DIRS) read -r -a STEAM_LIB_DIRS <<< "$var_value" ;;
            STEAM_PROTON_SUBDIR) STEAM_PROTON_SUBDIR="$var_value" ;;
            DEFAULT_GAMESCOPE_PARAMS) GAMESCOPE_PARAMS="$var_value" ;;
            UNIVERSAL_PREFIX_NAME) UNIVERSAL_PREFIX_NAME="$var_value" ;;
        esac
    done < "$CONFIG_FILE"
}

check_dependencies() {
    gum_log INFO_STYLE_ARGS "Checking dependencies..."
    local missing_dep=0
    for cmd in gum umu-run realpath date tee mkdir sort printf sed read jq; do 
        if ! command -v "$cmd" &>/dev/null; then
            gum_log ERROR_STYLE_ARGS "Command not found: $cmd. Please install it."
            missing_dep=1
        fi
    done
    [[ $missing_dep -eq 1 ]] && exit 1

    gamemode_available=$(command -v gamemoderun &>/dev/null && echo 1 || echo 0)
    gamescope_available=$(command -v gamescope &>/dev/null && echo 1 || echo 0)
    mangohud_available=$(command -v mangohud &>/dev/null && echo 1 || echo 0)

    local dep_lines=("$(echo "--- Optional Tools ---" | gum style --foreground "$HEADER_FG_COLOR" --margin '1 0 0 0')")
    add_dep_line() {
        local label_styled=$(echo "$1:" | gum style "${DEPENDENCY_LABEL_STYLE_ARGS[@]}")
        local status_text=$([[ "$2" -eq 1 ]] && echo "Found" || echo "Missing")
        local -a current_status_style_args
        if [[ "$2" -eq 1 ]]; then current_status_style_args=("${DEPENDENCY_FOUND_STYLE_ARGS[@]}"); 
        else current_status_style_args=("${DEPENDENCY_MISSING_STYLE_ARGS[@]}"); fi
        dep_lines+=("$(gum join --align left --horizontal "$label_styled" "$(echo "$status_text" | gum style "${current_status_style_args[@]}")")")
    }
    add_dep_line "GameMode" "$gamemode_available"
    add_dep_line "Gamescope" "$gamescope_available"
    add_dep_line "MangoHud" "$mangohud_available"
    printf "%s\n" "${dep_lines[@]}"
    echo 
}

detect_proton_versions() {
    gum spin --spinner line --title "Searching Proton versions..." -- sleep 0.1
    PROTON_VERSIONS=(); PROTON_PATHS=(); declare -A found_paths_map

    for dir in "${CUSTOM_PROTON_DIRS[@]}"; do
        [[ -d "$dir" ]] && while IFS= read -r -d $'\0' p_dir; do
            local p_name=$(basename "$p_dir"); local p_exec="$p_dir/proton"
            [[ -f "$p_exec" && -x "$p_exec" ]] && found_paths_map["$p_name"]="$p_dir"
        done < <(find "$dir" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null)
    done

    for lib_dir in "${STEAM_LIB_DIRS[@]}"; do
        local common_dir="$lib_dir/$STEAM_PROTON_SUBDIR"
        [[ -d "$common_dir" ]] && while IFS= read -r -d $'\0' p_dir; do
            local p_name=$(basename "$p_dir"); local p_exec="$p_dir/proton"
            [[ -f "$p_exec" && -x "$p_exec" ]] && found_paths_map["$p_name"]="$p_dir"
        done < <(find "$common_dir" -maxdepth 1 -name 'Proton*' -type d -print0 2>/dev/null)
    done

    for p_name in "${!found_paths_map[@]}"; do PROTON_VERSIONS+=("$p_name"); PROTON_PATHS+=("${found_paths_map[$p_name]}"); done

    local sorted_indices; IFS=$'\n' sorted_indices=($(printf "%s\n" "${PROTON_VERSIONS[@]}" | sort -f | while read -r name; do
        for i in "${!PROTON_VERSIONS[@]}"; do [[ "${PROTON_VERSIONS[$i]}" == "$name" ]] && { echo "$i"; break; }; done
    done)); unset IFS

    local sorted_versions=(); local sorted_paths=()
    for index in "${sorted_indices[@]}"; do sorted_versions+=("${PROTON_VERSIONS[$index]}"); sorted_paths+=("${PROTON_PATHS[$index]}"); done
    PROTON_VERSIONS=("${sorted_versions[@]}"); PROTON_PATHS=("${sorted_paths[@]}")

    [[ ${#PROTON_VERSIONS[@]} -eq 0 ]] && error_exit "No Proton versions found."
}

select_game_executable() {
    local selected_path=$(gum file "$HOME" --file --height 15 --cursor.foreground "$CURSOR_FG_COLOR")
    [[ -z "$selected_path" ]] && error_exit "No game selected."
    [[ ! -f "$selected_path" ]] && error_exit "Invalid selection: Not a file."
    GAME_EXECUTABLE=$(realpath "$selected_path") || error_exit "Failed to resolve path."
    GAME_DIR=$(dirname "$GAME_EXECUTABLE"); GAME_BASENAME=$(basename "$GAME_EXECUTABLE")
    gum_log SUCCESS_STYLE_ARGS "Selected: $GAME_BASENAME"
}

quick_launch_load_last_game() {
    IS_QUICK_LAUNCHING=0 
    if [[ ! -f "$LAST_GAME_FILE" ]]; then
        gum_log WARNING_STYLE_ARGS "Quick launch failed: Last game config file not found ($LAST_GAME_FILE)."
        return 1
    fi

    local last_game_config_path
    last_game_config_path=$(<"$LAST_GAME_FILE")

    if [[ -z "$last_game_config_path" || ! -f "$last_game_config_path" ]]; then
        gum_log WARNING_STYLE_ARGS "Quick launch failed: Invalid path in last game config file or file missing."
        rm -f "$LAST_GAME_FILE" 
        return 1
    fi

    if load_game_from_library "$last_game_config_path"; then
        gum_log SUCCESS_STYLE_ARGS "Loaded configuration for: $GAME_BASENAME"
        IS_QUICK_LAUNCHING=1
        return 0
    else
        gum_log WARNING_STYLE_ARGS "Quick launch failed: Could not load configuration from $last_game_config_path."
        return 1
    fi
}

select_proton_version() {
    local current_proton_name="$1"
    [[ ${#PROTON_VERSIONS[@]} -eq 0 ]] && error_exit "No Proton versions found."

    local gum_choose_args=(--height 12 --header "Proton Version:" --header.foreground "$HEADER_FG_COLOR" --cursor.foreground "$CURSOR_FG_COLOR")
    if [[ -n "$current_proton_name" ]]; then
        for p_name in "${PROTON_VERSIONS[@]}"; do
            if [[ "$p_name" == "$current_proton_name" ]]; then
                gum_choose_args+=(--selected "$current_proton_name")
                break
            fi
        done
    fi

    local chosen_option=$(printf "%s\n" "${PROTON_VERSIONS[@]}" | gum choose "${gum_choose_args[@]}")
    [[ -z "$chosen_option" ]] && error_exit "No Proton selected."
    SELECTED_PROTON_NAME="$chosen_option"; SELECTED_PROTON_PATH=""
    for i in "${!PROTON_VERSIONS[@]}"; do
        if [[ "${PROTON_VERSIONS[$i]}" == "$SELECTED_PROTON_NAME" ]]; then
            SELECTED_PROTON_PATH="${PROTON_PATHS[$i]}"; break
        fi
    done
    [[ -z "$SELECTED_PROTON_PATH" ]] && error_exit "Path not found for Proton '$SELECTED_PROTON_NAME'."
}

select_launch_options() {
    local current_selected_options_str="$1"
    local top_options=() other_options=() final_options_list=()
    local -A option_map=(
        ["gamemode"]="GameMode" ["gamescope"]="Gamescope" ["mangohud"]="MangoHud"
        ["dxvk_async"]="DXVK Async" ["nvapi"]="NVAPI" ["vkd3d_rt"]="VKD3D RT"
        ["vk_validate"]="Vulkan Validation"
    )
    local -A option_availability=(
        ["gamemode"]=$gamemode_available ["gamescope"]=$gamescope_available ["mangohud"]=$mangohud_available
        ["dxvk_async"]=1 ["nvapi"]=1 ["vkd3d_rt"]=1 ["vk_validate"]=1
    )
    local top_order=("gamemode" "gamescope" "mangohud" "dxvk_async")

    for key in "${top_order[@]}"; do
        if [[ -v option_map[$key] ]]; then
            if [[ ${option_availability[$key]} -eq 1 ]]; then top_options+=("Enable ${option_map[$key]}");
            else top_options+=("Enable ${option_map[$key]} (NA)"); fi 
        fi
    done
    for key in "${!option_map[@]}"; do
        local is_top=0; for top_key in "${top_order[@]}"; do if [[ "$key" == "$top_key" ]]; then is_top=1; break; fi; done
        if [[ $is_top -eq 0 ]]; then
            if [[ ${option_availability[$key]} -eq 1 ]]; then other_options+=("Enable ${option_map[$key]}");
            else other_options+=("Enable ${option_map[$key]} (NA)"); fi
        fi
    done
    IFS=$'\n' sorted_other_options=($(sort <<<"${other_options[*]}")); unset IFS
    final_options_list=("${top_options[@]}" "${sorted_other_options[@]}")

    local gum_choose_args=(--no-limit --height 10 --header "Launch Options:" --header.foreground "$HEADER_FG_COLOR" --selected.foreground "$SELECTED_FG_COLOR" --cursor.foreground "$CURSOR_FG_COLOR")
    [[ -n "$current_selected_options_str" ]] && gum_choose_args+=(--selected "$current_selected_options_str")
    
    local selected_options_str
    selected_options_str=$(printf "%s\n" "${final_options_list[@]}" | gum choose "${gum_choose_args[@]}")
    
    SELECTED_OPTIONS=()
    mapfile -t SELECTED_OPTIONS < <(echo "$selected_options_str")

    GAMESCOPE_SELECTED=0
    if [[ "$gamescope_available" -eq 1 ]]; then
        for opt in "${SELECTED_OPTIONS[@]}"; do
            if [[ "$opt" == "Enable Gamescope" ]]; then GAMESCOPE_SELECTED=1; break; fi
        done
    fi
}

select_sync_method() {
    local current_sync_method="$1"
    local sync_methods=(
        "Fsync (Kernel support)"
        "Esync (FD limits)"
        "Ntsync (GE/TKG builds)"
        "None" 
    )
    local header_text="Sync Method:"
    local gum_choose_args=(--height 7 --header "$header_text" --header.foreground "$HEADER_FG_COLOR" --item.padding "$ITEM_PADDING" --cursor.foreground "$CURSOR_FG_COLOR")
    
    if [[ -n "$current_sync_method" ]]; then
        for sm_desc in "${sync_methods[@]}"; do
            if [[ "$sm_desc" == "$current_sync_method" ]]; then
                gum_choose_args+=(--selected "$current_sync_method")
                break
            fi
        done
    fi

    local chosen_option
    chosen_option=$(printf "%s\n" "${sync_methods[@]}" | gum choose "${gum_choose_args[@]}")
    SELECTED_SYNC_METHOD=${chosen_option:-"Fsync (Kernel support)"} 
}

get_gamescope_flags() {
    local default_flags="$1" current_flags="$2"
    local flags_to_propose="$default_flags"
    [[ -n "$current_flags" ]] && flags_to_propose="$current_flags"
    
    GAMESCOPE_FLAGS_TO_USE="$flags_to_propose" 
    if ! gum confirm "Gamescope flags: ($flags_to_propose)?" --affirmative="Use These" --negative="Edit"; then
        local custom_flags
        custom_flags=$(gum input --placeholder="-W 1920 -H 1080 etc." --value="$flags_to_propose")
        GAMESCOPE_FLAGS_TO_USE=${custom_flags:-$default_flags} 
    fi
}

get_custom_input() {
    local current_input="$1"
    CUSTOM_INPUT=$(gum input --placeholder="DXVK_HUD=1 -someflag..." --prompt "Custom Env/Args: " --value="$current_input")
    CUSTOM_INPUT=$(echo "$CUSTOM_INPUT" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
}

get_universal_prefix_name_for_game() {
    local current_prefix_name="$1"
    local default_prefix_name="$DEFAULT_UNIVERSAL_PREFIX_NAME" 

    local chosen_prefix_name
    chosen_prefix_name=$(gum input --placeholder="$default_prefix_name" --value="${current_prefix_name:-$default_prefix_name}" --prompt "Wine Prefix Name: ")
    UNIVERSAL_PREFIX_NAME=$(echo "${chosen_prefix_name:-$default_prefix_name}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [[ -z "$UNIVERSAL_PREFIX_NAME" ]] && UNIVERSAL_PREFIX_NAME="$default_prefix_name" 
}

configure_environment_and_command() {
    local gamescope_prefix=() gamemode_prefix=() custom_args=()
    declare -A LAUNCH_ENV
    LAUNCH_ENV["PROTONPATH"]="$SELECTED_PROTON_PATH"
    LAUNCH_ENV["GAMEID"]="$UNIVERSAL_PREFIX_NAME"

    local gs_enabled=0 gm_enabled=0 mh_enabled=0 nv_enabled=0 dx_async_enabled=0 vk_rt_enabled=0 vk_validate_enabled=0

    for opt in "${SELECTED_OPTIONS[@]}"; do
        case "$opt" in
            *"Gamescope"*) ;; 
            *"MangoHud"*) [[ "$mangohud_available" -eq 1 ]] && { LAUNCH_ENV["MANGOHUD"]="1"; mh_enabled=1; };;
            *"GameMode"*) [[ "$gamemode_available" -eq 1 ]] && { gamemode_prefix=("gamemoderun"); gm_enabled=1; };;
            *"NVAPI"*) LAUNCH_ENV["PROTON_ENABLE_NVAPI"]="1"; LAUNCH_ENV["DXVK_ENABLE_NVAPI"]="1"; nv_enabled=1;;
            *"DXVK Async"*) LAUNCH_ENV["DXVK_ASYNC"]="1"; dx_async_enabled=1;;
            *"VKD3D RT"*) LAUNCH_ENV["VKD3D_CONFIG"]="dxr11,dxr"; vk_rt_enabled=1;;
            *"Vulkan Validation"*) LAUNCH_ENV["VK_INSTANCE_LAYERS"]="VK_LAYER_KHRONOS_validation"; vk_validate_enabled=1;;
        esac
    done

    if [[ "$GAMESCOPE_SELECTED" -eq 1 && -n "$GAMESCOPE_FLAGS_TO_USE" ]]; then
        read -r -a gs_flags <<< "$GAMESCOPE_FLAGS_TO_USE"
        gamescope_prefix=("gamescope" "${gs_flags[@]}" "--")
        gs_enabled=1
    fi

    local sync_method_name="None"
    case "$SELECTED_SYNC_METHOD" in
        "Fsync"*) LAUNCH_ENV["WINEFSYNC"]="1"; sync_method_name="Fsync";;
        "Esync"*) LAUNCH_ENV["WINEESYNC"]="1"; sync_method_name="Esync";;
        "Ntsync"*) LAUNCH_ENV["PROTON_USE_NTSYNC"]="1"; sync_method_name="Ntsync";;
    esac

    if [[ -n "$CUSTOM_INPUT" ]]; then
        read -r -a custom_tokens <<< "$CUSTOM_INPUT"
        for token in "${custom_tokens[@]}"; do
            if [[ "$token" == *"="* ]]; then LAUNCH_ENV["${token%%=*}"]="${token#*=}";
            else custom_args+=("$token"); fi
        done
    fi

    local core_command=("env")
    for key in "${!LAUNCH_ENV[@]}"; do core_command+=("${key}=${LAUNCH_ENV[$key]}"); done
    core_command+=("umu-run" "$GAME_BASENAME" "${custom_args[@]}")

    FINAL_COMMAND=()
    [[ ${#gamemode_prefix[@]} -gt 0 ]] && FINAL_COMMAND+=("${gamemode_prefix[@]}")
    [[ ${#gamescope_prefix[@]} -gt 0 ]] && FINAL_COMMAND+=("${gamescope_prefix[@]}")
    FINAL_COMMAND+=("${core_command[@]}")

    _SUMMARY_GAMESCOPE_ENABLED=$gs_enabled; _SUMMARY_GAMEMODE_ENABLED=$gm_enabled
    _SUMMARY_MANGOHUD_ENABLED=$mh_enabled; _SUMMARY_NVAPI_ENABLED=$nv_enabled
    _SUMMARY_DXVK_ASYNC_ENABLED=$dx_async_enabled; _SUMMARY_VKD3D_RT_ENABLED=$vk_rt_enabled
    _SUMMARY_VK_VALIDATE_ENABLED=$vk_validate_enabled; _SUMMARY_SYNC_METHOD_NAME=$sync_method_name
}

execute_game_directly() {
    if [[ "$IS_QUICK_LAUNCHING" -eq 1 ]]; then
        gum_log SUCCESS_STYLE_ARGS "Quick launching $GAME_BASENAME with saved configuration..."
    else
        gum_log SUCCESS_STYLE_ARGS "Launching $GAME_BASENAME..."
    fi

    local safe_basename="${GAME_BASENAME//[^a-zA-Z0-9._-]/_}"
    local log_file="$LOG_DIR/${safe_basename}_$(date +%Y%m%d_%H%M%S).log"
    local cmd_str_for_log="" 
    for item in "${FINAL_COMMAND[@]}"; do 
        if [[ "$item" == *" "* || "$item" == *"="* || "$item" == "--" ]]; then cmd_str_for_log+=" '$item'"; 
        else cmd_str_for_log+=" $item"; fi; 
    done
    cmd_str_for_log="${cmd_str_for_log# }"

    gum_log INFO_STYLE_ARGS "Log: $log_file"
    echo "--- Launch Command ---" > "$log_file"
    echo "$cmd_str_for_log" >> "$log_file"
    echo -e "\n\n--- Game Output ---" >> "$log_file"
    
    (cd "$GAME_DIR" && set -o pipefail && "${FINAL_COMMAND[@]}" 2>&1 | tee -a "$log_file")
    local exit_code=${PIPESTATUS[0]}

    if [ $exit_code -ne 0 ]; then
        gum_log WARNING_STYLE_ARGS "$GAME_BASENAME exited with code: $exit_code"
    else
        gum_log SUCCESS_STYLE_ARGS "$GAME_BASENAME exited successfully."
    fi
}

display_summary_and_launch() {
    local summary_lines=("$(echo "Launch Summary" | gum style --bold --align center)")
    summary_lines+=(" ")
    add_summary_line() {
        local label_styled=$(echo "$1:" | gum style --foreground "240") 
        local value_styled=$(echo "$2" | gum style --foreground "250") 
        summary_lines+=("$label_styled $value_styled")
    }
    s_status() { [[ "$1" -eq 1 ]] && echo "On" || echo "Off"; }

    add_summary_line "Game" "$GAME_BASENAME"
    add_summary_line "Proton" "$SELECTED_PROTON_NAME"
    add_summary_line "Prefix" "$UNIVERSAL_PREFIX_NAME"
    add_summary_line "Sync" "$_SUMMARY_SYNC_METHOD_NAME"
    summary_lines+=(" "); summary_lines+=("$(echo "--- Options ---" | gum style --foreground "240")")
    add_summary_line "GameMode" "$(s_status $_SUMMARY_GAMEMODE_ENABLED)"
    add_summary_line "Gamescope" "$(s_status $_SUMMARY_GAMESCOPE_ENABLED)$([[ $_SUMMARY_GAMESCOPE_ENABLED -eq 1 ]] && echo " ($GAMESCOPE_FLAGS_TO_USE)")"
    add_summary_line "MangoHud" "$(s_status $_SUMMARY_MANGOHUD_ENABLED)"
    add_summary_line "NVAPI" "$(s_status $_SUMMARY_NVAPI_ENABLED)"
    add_summary_line "DXVK Async" "$(s_status $_SUMMARY_DXVK_ASYNC_ENABLED)"
    add_summary_line "VKD3D RT" "$(s_status $_SUMMARY_VKD3D_RT_ENABLED)"
    add_summary_line "VK Validate" "$(s_status $_SUMMARY_VK_VALIDATE_ENABLED)"
    add_summary_line "Custom" "${CUSTOM_INPUT:-None}"
    
    local display_command_str=""
    for item in "${FINAL_COMMAND[@]}"; do
        if [[ "$item" == *" "* || "$item" == *"="* || "$item" == "--" ]]; then display_command_str+=" '$item'";
        else display_command_str+=" $item"; fi
    done
    display_command_str="${display_command_str# }" 
    summary_lines+=(" "); summary_lines+=("$(echo "Command:" | gum style --foreground "99")")
    summary_lines+=("$(echo "$display_command_str" | gum style --foreground "245")")

    printf "%s\n" "${summary_lines[@]}" | gum style --border "normal" --margin "0" --padding "0 1" --border-foreground "$HEADER_FG_COLOR"
    
    if ! gum confirm "Launch?" --affirmative="Launch!" --negative="Cancel"; then error_exit "Launch cancelled by user."; fi
    
    execute_game_directly
}

save_game_to_library() {
    local library_file_path="$1"
    local display_name="$2"
    local selected_options_json_array=$(printf '%s\n' "${SELECTED_OPTIONS[@]}" | jq -R . | jq -s .)

    local game_config_json=$(jq -n \
        --arg dn "$display_name" --arg ge "$GAME_EXECUTABLE" --arg gd "$GAME_DIR" --arg gb "$GAME_BASENAME" \
        --arg pn "$SELECTED_PROTON_NAME" --arg pp "$SELECTED_PROTON_PATH" --argjson so "$selected_options_json_array" \
        --arg gs_sel "$GAMESCOPE_SELECTED" --arg gsf "$GAMESCOPE_FLAGS_TO_USE" --arg sm "$SELECTED_SYNC_METHOD" \
        --arg ci "$CUSTOM_INPUT" --arg upn "$UNIVERSAL_PREFIX_NAME" \
        '{display_name:$dn,game_executable:$ge,game_dir:$gd,game_basename:$gb,proton_name:$pn,proton_path:$pp,selected_options:$so,gamescope_selected:$gs_sel,gamescope_flags:$gsf,sync_method:$sm,custom_input:$ci,universal_prefix_name:$upn}')

    if echo "$game_config_json" > "$library_file_path"; then
        gum_log SUCCESS_STYLE_ARGS "'$display_name' saved to library."
        echo "$library_file_path" > "$LAST_GAME_FILE" || gum_log WARNING_STYLE_ARGS "Could not update last game config path."
    else
        gum_log ERROR_STYLE_ARGS "Failed to save '$display_name' to library."
    fi
}

prompt_add_to_library() {
    if gum confirm "Add this configuration to library?" --affirmative="Yes" --negative="No"; then
        local game_display_name
        game_display_name=$(gum input --placeholder "Enter library display name" --value "${GAME_BASENAME%.*}")
        if [[ -z "$game_display_name" ]]; then
            gum_log WARNING_STYLE_ARGS "No display name entered. Not adding to library."
            return
        fi
        local safe_filename="${game_display_name//[^a-zA-Z0-9._-]/_}"
        local library_file_path="$LIBRARY_DIR/${safe_filename}.json"

        if [[ -f "$library_file_path" ]]; then
            if ! gum confirm "'$game_display_name' already exists. Overwrite?" --affirmative="Overwrite" --negative="Cancel"; then
                gum_log INFO_STYLE_ARGS "Not overwriting existing library entry."
                return
            fi
        fi
        save_game_to_library "$library_file_path" "$game_display_name"
    fi
}

load_game_from_library() {
    local game_json_file="$1"
    if [[ ! -f "$game_json_file" ]]; then
        gum_log ERROR_STYLE_ARGS "Library file not found: $game_json_file"
        return 1
    fi

    GAME_EXECUTABLE=$(jq -r '.game_executable' "$game_json_file")
    GAME_DIR=$(jq -r '.game_dir' "$game_json_file")
    GAME_BASENAME=$(jq -r '.game_basename' "$game_json_file")
    SELECTED_PROTON_NAME=$(jq -r '.proton_name' "$game_json_file")
    SELECTED_PROTON_PATH=$(jq -r '.proton_path' "$game_json_file")
    mapfile -t SELECTED_OPTIONS < <(jq -r '.selected_options[]?' "$game_json_file") 
    GAMESCOPE_SELECTED=$(jq -r '.gamescope_selected' "$game_json_file")
    GAMESCOPE_FLAGS_TO_USE=$(jq -r '.gamescope_flags' "$game_json_file")
    SELECTED_SYNC_METHOD=$(jq -r '.sync_method' "$game_json_file")
    CUSTOM_INPUT=$(jq -r '.custom_input' "$game_json_file")
    UNIVERSAL_PREFIX_NAME=$(jq -r '.universal_prefix_name' "$game_json_file")
    
    if [[ -z "$GAME_EXECUTABLE" || -z "$SELECTED_PROTON_NAME" ]]; then
        gum_log ERROR_STYLE_ARGS "Failed to load essential data from library file: $game_json_file"
        return 1
    fi
    return 0
}

list_library_games_for_chooser() {
    local game_display_names=()
    local game_file_paths=()
    
    while IFS= read -r -d $'\0' file; do
        local display_name
        display_name=$(jq -r '.display_name' "$file" 2>/dev/null || basename "${file%.json}")
        game_display_names+=("$(echo "$display_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')")
        game_file_paths+=("$file")
    done < <(find "$LIBRARY_DIR" -maxdepth 1 -name "*.json" -print0 2>/dev/null | sort -z)

    if [[ ${#game_display_names[@]} -eq 0 ]]; then
        echo "__EMPTY__" 
        return
    fi
    
    printf "%s\n" "${game_display_names[@]}"
    echo "---SEPARATOR_FOR_PATHS---" 
    printf "%s\n" "${game_file_paths[@]}"
}

run_new_game_flow() {
    IS_QUICK_LAUNCHING=0
    echo "New Game Setup" | gum style --bold --padding "0 1" --border "normal" --align center
    select_game_executable
    detect_proton_versions
    select_proton_version "" 
    select_launch_options "" 
    GAMESCOPE_FLAGS_TO_USE="" 
    if [[ "$GAMESCOPE_SELECTED" -eq 1 ]]; then
        get_gamescope_flags "$GAMESCOPE_PARAMS" "" 
    fi
    select_sync_method "" 
    get_custom_input "" 
    get_universal_prefix_name_for_game "" 

    prompt_add_to_library 
    configure_environment_and_command
    display_summary_and_launch
}

manage_library_game() {
    IS_QUICK_LAUNCHING=0
    local game_json_file="$1" 
    local game_display_name
    game_display_name=$(jq -r '.display_name' "$game_json_file" 2>/dev/null || basename "${game_json_file%.json}")
    game_display_name=$(echo "$game_display_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')


    while true; do
        clear 
        echo "Game: $game_display_name" | gum style --bold --foreground "$HEADER_FG_COLOR" --margin "1 0 0 0"
        gum_log INFO_STYLE_ARGS " (L)aunch (M)odify (V)iew (R)emove (B)ack to Library"
        local action_char
        action_char=$(gum input --prompt " > " --char-limit 1)
        
        case "$action_char" in
            l|L)
                if load_game_from_library "$game_json_file"; then
                    echo "$game_json_file" > "$LAST_GAME_FILE" || gum_log WARNING_STYLE_ARGS "Could not update last game config path."
                    configure_environment_and_command
                    display_summary_and_launch
                fi
                ;;
            m|M)
                if load_game_from_library "$game_json_file"; then
                    echo "$game_json_file" > "$LAST_GAME_FILE" || gum_log WARNING_STYLE_ARGS "Could not update last game config path for modification."
                    echo "Modifying: $game_display_name" | gum style --bold
                    detect_proton_versions 
                    select_proton_version "$SELECTED_PROTON_NAME"
                    select_launch_options "$(IFS=,; echo "${SELECTED_OPTIONS[*]}")" 
                    local prev_gamescope_flags="$GAMESCOPE_FLAGS_TO_USE"
                    if [[ "$GAMESCOPE_SELECTED" -eq 1 ]]; then
                         get_gamescope_flags "$GAMESCOPE_PARAMS" "$prev_gamescope_flags"
                    else
                        GAMESCOPE_FLAGS_TO_USE="" 
                    fi
                    select_sync_method "$SELECTED_SYNC_METHOD"
                    get_custom_input "$CUSTOM_INPUT"
                    get_universal_prefix_name_for_game "$UNIVERSAL_PREFIX_NAME"

                    if gum confirm "Update library entry with these changes?"; then
                        save_game_to_library "$game_json_file" "$game_display_name" 
                    fi
                    configure_environment_and_command
                    display_summary_and_launch
                fi
                ;;
            v|V)
                if load_game_from_library "$game_json_file"; then
                    configure_environment_and_command 
                    local summary_lines=("$(echo "Details for: $game_display_name" | gum style --bold --align center)")
                    summary_lines+=(" ")
                    s_status_local() { [[ "$1" -eq 1 ]] && echo "On" || echo "Off"; }
                    add_s_line_local() { local label_s=$(echo "$1:" | gum style --foreground "240"); local value_s=$(echo "$2" | gum style --foreground "250"); summary_lines+=("$label_s $value_s"); }
                    
                    add_s_line_local "Executable" "$GAME_EXECUTABLE"
                    add_s_line_local "Proton" "$SELECTED_PROTON_NAME"
                    add_s_line_local "Prefix" "$UNIVERSAL_PREFIX_NAME"
                    add_s_line_local "Sync" "$_SUMMARY_SYNC_METHOD_NAME"
                    summary_lines+=(" "); summary_lines+=("$(echo "--- Options ---" | gum style --foreground "240")")
                    add_s_line_local "GameMode" "$(s_status_local $_SUMMARY_GAMEMODE_ENABLED)"
                    add_s_line_local "Gamescope" "$(s_status_local $_SUMMARY_GAMESCOPE_ENABLED)$([[ $_SUMMARY_GAMESCOPE_ENABLED -eq 1 ]] && echo " ($GAMESCOPE_FLAGS_TO_USE)")"
                    add_s_line_local "MangoHud" "$(s_status_local $_SUMMARY_MANGOHUD_ENABLED)"
                    add_s_line_local "Custom" "${CUSTOM_INPUT:-None}"
                    
                    printf "%s\n" "${summary_lines[@]}" | gum style --border "normal" --margin "0" --padding "0 1" --border-foreground "$HEADER_FG_COLOR"
                    gum input --placeholder "Press Enter to continue..." > /dev/null 
                fi
                ;;
            r|R)
                if gum confirm "Are you sure you want to remove '$game_display_name' from the library?"; then
                    if rm "$game_json_file"; then
                        gum_log SUCCESS_STYLE_ARGS "'$game_display_name' removed from library."
                        if [[ -f "$LAST_GAME_FILE" && "$(<"$LAST_GAME_FILE")" == "$game_json_file" ]]; then
                            rm -f "$LAST_GAME_FILE"
                        fi
                        return 
                    else
                        gum_log ERROR_STYLE_ARGS "Failed to remove '$game_display_name'."
                    fi
                fi
                ;;
            b|B)
                return 
                ;;
            *)
                gum_log WARNING_STYLE_ARGS "Invalid action. Please use L, M, V, R, or B."
                sleep 1.5 
                ;;
        esac
    done
}

open_game_library_flow() {
    IS_QUICK_LAUNCHING=0
    while true; do
        clear
        echo "Game Library" | gum style --bold --padding "0 1" --border "normal" --align center --border-foreground "$HEADER_FG_COLOR"
        
        local list_output
        list_output=$(list_library_games_for_chooser)

        if [[ "$list_output" == "__EMPTY__" ]]; then
            gum_log INFO_STYLE_ARGS "Your game library is empty. Add games via 'New Game'."
            if gum confirm "Return to Main Menu?"; then return; else continue; fi
        fi

        local all_lines_from_list_output=()
        mapfile -t all_lines_from_list_output < <(echo "$list_output")

        local game_display_names_array=()
        local game_file_paths_array=()
        local separator_found=0
        local parsing_paths=0 

        for line in "${all_lines_from_list_output[@]}"; do
            if [[ "$line" == "---SEPARATOR_FOR_PATHS---" ]]; then
                parsing_paths=1
                separator_found=1 
                continue 
            fi

            if [[ $parsing_paths -eq 0 ]]; then
                game_display_names_array+=("$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')")
            else
                game_file_paths_array+=("$line") 
            fi
        done
        
        if [[ $separator_found -eq 0 && ${#all_lines_from_list_output[@]} -gt 0 && "$list_output" != "__EMPTY__" ]]; then
            gum_log ERROR_STYLE_ARGS "Library data is malformed (separator missing)."
            if gum confirm "Return to Main Menu?"; then return; else continue; fi
        fi

        if [[ ${#game_display_names_array[@]} -eq 0 && "$list_output" != "__EMPTY__" ]]; then 
             gum_log INFO_STYLE_ARGS "No games found in library to display (after parsing)."
             if gum confirm "Return to Main Menu?"; then return; else continue; fi
        fi
        
        if [[ $separator_found -eq 1 && ${#game_display_names_array[@]} -ne ${#game_file_paths_array[@]} ]]; then
            gum_log ERROR_STYLE_ARGS "Mismatch between game names and paths counts. Library may be corrupt."
            gum_log INFO_STYLE_ARGS "Name count: ${#game_display_names_array[@]}, Path count: ${#game_file_paths_array[@]}"
            if gum confirm "Return to Main Menu?"; then return; else continue; fi
        fi

        local choose_options=()
        for name in "${game_display_names_array[@]}"; do
            choose_options+=("$name")
        done
        choose_options+=("[Back to Main Menu]")

        local chosen_game_display_name
        chosen_game_display_name=$(printf "%s\n" "${choose_options[@]}" | gum choose \
            --header "Select Game / Action" \
            --height 15 \
            --cursor.foreground "$CURSOR_FG_COLOR" \
            --selected.foreground "$SELECTED_FG_COLOR") 

        local gum_choose_exit_code=$?

        if [[ $gum_choose_exit_code -ne 0 || "$chosen_game_display_name" == "[Back to Main Menu]" || -z "$chosen_game_display_name" ]]; then
            return 
        fi
        
        local chosen_game_display_name_trimmed
        chosen_game_display_name_trimmed=$(echo "$chosen_game_display_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        local selected_idx=-1
        for i in "${!game_display_names_array[@]}"; do
           local current_display_name_trimmed
           current_display_name_trimmed=$(echo "${game_display_names_array[$i]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
           if [[ "$current_display_name_trimmed" == "$chosen_game_display_name_trimmed" ]]; then
               selected_idx=$i
               break
           fi
        done

        if [[ $selected_idx -ne -1 && $selected_idx -lt ${#game_file_paths_array[@]} && -n "${game_file_paths_array[$selected_idx]}" ]]; then
            local game_json_path="${game_file_paths_array[$selected_idx]}"
            if [[ -f "$game_json_path" ]]; then
                manage_library_game "$game_json_path"
            else
                gum_log ERROR_STYLE_ARGS "JSON file not found at expected path: '$game_json_path' for selected game '$chosen_game_display_name'"
                sleep 3 
            fi
        else
            gum_log ERROR_STYLE_ARGS "Could not determine file for selected game: '$chosen_game_display_name'. Index: $selected_idx. Path array size: ${#game_file_paths_array[@]}"
            sleep 3 
        fi
    done
}

show_main_menu() {
    IS_QUICK_LAUNCHING=0
    while true; do
        UNIVERSAL_PREFIX_NAME="$DEFAULT_UNIVERSAL_PREFIX_NAME" 
        load_config 

        clear
        echo "UMU Launcher" | gum style --bold --padding "0 1" --border "rounded" --align center --border-foreground "$HEADER_FG_COLOR"
        local choice
        choice=$(gum choose --cursor.foreground "$CURSOR_FG_COLOR" --height 7 \
            "New Game" \
            "Game Library" \
            "Quick Launch" \
            "Exit")

        case "$choice" in
            "New Game")
                run_new_game_flow
                ;;
            "Game Library")
                open_game_library_flow
                ;;
            "Quick Launch")
                if quick_launch_load_last_game; then
                    configure_environment_and_command
                    execute_game_directly 
                else
                    gum_log WARNING_STYLE_ARGS "Quick launch failed. Returning to menu."
                fi
                ;;
            "Exit"|*) 
                gum_log INFO_STYLE_ARGS "Exiting UMU Launcher. Goodbye!"
                exit 0
                ;;
        esac
        if [[ -n "$choice" && "$choice" != "Exit" ]]; then
            echo 
            gum spin --show-output --title "Returning to menu..." -- sleep 0.3
        fi
    done
}

main() {
    CUSTOM_PROTON_DIRS=("${DEFAULT_CUSTOM_PROTON_DIRS[@]}")
    STEAM_LIB_DIRS=("${DEFAULT_STEAM_LIB_DIRS[@]}")
    STEAM_PROTON_SUBDIR="$DEFAULT_STEAM_PROTON_SUBDIR"
    GAMESCOPE_PARAMS="$DEFAULT_GAMESCOPE_PARAMS"
    UNIVERSAL_PREFIX_NAME="$DEFAULT_UNIVERSAL_PREFIX_NAME"

    load_config 
    setup_data_dirs
    check_dependencies

    if [[ "$1" == "--quick" || "$1" == "-q" ]]; then
        if quick_launch_load_last_game; then
            configure_environment_and_command
            execute_game_directly
        else
            error_exit "CLI Quick launch failed. Last game config not found or invalid."
        fi
        exit 0
    fi

    show_main_menu
    exit 0
}

main "$@"
