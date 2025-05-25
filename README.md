# UMU-Launch-Gum: TUI Launcher for Windows Games on Linux

A script providing a Terminal User Interface (TUI) using `gum` to launch Windows games on Linux via `umu-launcher`.

![Preview](preview.gif)

## Features

* Select game `.exe` files using a file browser for new game setups.
* **Enhanced Game Library:**
    * Save game configurations (Proton version, environment variables, launch options, etc.) for easy launching.
    * **Search and filter** your game library for quick access.
    * Dedicated **"Edit Configuration"** option to modify saved games without launching.
    * Manage library entries (Launch, Edit, View Details, Delete).
* Detects and allows selection of Proton/Wine-GE versions (Steam official & custom).
* Set environment variables (e.g., `DXVK_HUD=1`) or command-line arguments per launch, saved with library entries.
* Integrates with Gamescope, Gamemode, and MangoHud if installed (optional).
* Uses a configurable shared Wine prefix (default: `umu-default`), which can be overridden per game in the library.
* Customizable TUI Colors: Personalize the look of the launcher via the configuration file.
* Logs launch commands and game output to `~/.local/share/umu-launch-gum/logs/`.
* **Quick launch mode** (`--quick` or `-q`): Launches the last game played from the library with its exact saved configuration.

## Requirements

**Required:**

* `bash`
* `gum`
* `umu-launcher`
* `jq` (for JSON processing of the game library)
* `coreutils` (provides `realpath`, `date`, `tee`, `mkdir`, `sort`)
* Installed Proton or Wine-GE version(s).

**Optional:**

* `gamemode`
* `gamescope`
* `mangohud`

## Usage

1.  Make the script executable:
    ```bash
    chmod +x umu-launch-gum.sh
    ```

2.  Run the script:
    ```bash
    ./umu-launch-gum.sh
    ```

3.  The main menu will appear:
    * **New Game**: Select an executable and configure its launch options. You can then add it to your library.
    * **Game Library**: Search, filter, view, manage (Launch, Edit, View Details, Delete), and launch games you've previously saved.
    * **Quick Launch**: Launch the last game you played from the library using its saved settings.
    * **Exit**: Close the launcher.
4.  Follow the TUI prompts to select the game, Proton version, and options.

5.  Optionally create an alias for the tool in your shell configuration file for easier access.

## Configuration (Optional)

Customize default behavior by creating a configuration file.

### Config File Location

The script checks for a configuration file at: `~/.config/umu-launch-gum/config.conf`

If this file doesn't exist, the script uses built-in defaults.

### Config File Format

* Use `VARIABLE_NAME="value"` format, one per line.
* Lines starting with `#` are comments and are ignored.
* Blank lines are ignored.
* For multiple paths (e.g., `CUSTOM_PROTON_DIRS`), separate them with a space within the double quotes (`" "`).

### Configurable Variables

#### `CUSTOM_PROTON_DIRS`

* **Purpose**: Specify directories containing custom Proton/Wine-GE builds (e.g., `compatibilitytools.d` folders).
* **Format**: Full paths separated by spaces, within double quotes.
* **Example**:
    ```bash
    CUSTOM_PROTON_DIRS="$HOME/.steam/root/compatibilitytools.d /mnt/data/proton-builds"
    ```

#### `STEAM_LIB_DIRS`

* **Purpose**: Specify Steam library root directories to find official Proton versions (looks in `steamapps/common`).
* **Format**: Full paths separated by spaces, within double quotes.
* **Example**:
    ```bash
    STEAM_LIB_DIRS="$HOME/.local/share/Steam /mnt/ssd/SteamLibrary"
    ```

#### `STEAM_PROTON_SUBDIR`

* **Purpose**: The sub-directory within Steam libraries where official Proton versions are located. Changing this is rarely needed.
* **Format**: Folder name (quotes usually not needed).
* **Default**: `steamapps/common`
* **Example**:
    ```bash
    STEAM_PROTON_SUBDIR="steamapps/common"
    ```

#### `DEFAULT_GAMESCOPE_PARAMS`

* **Purpose**: Set default flags for Gamescope when enabled. You can override these defaults at launch time or per library game.
* **Format**: Flags within double quotes.
* **Example**:
    ```bash
    DEFAULT_GAMESCOPE_PARAMS="-W 1920 -H 1080 -f -b --backend wayland"
    ```

#### `UNIVERSAL_PREFIX_NAME`

* **Purpose**: Define the name for the default shared Wine prefix when adding new games. This can be overridden per game in the library.
* **Format**: Name string (quotes only needed if it contains spaces).
* **Default**: `umu-default`
* **Example**:
    ```bash
    UNIVERSAL_PREFIX_NAME="umu_shared_games"
    ```

#### TUI Color Configuration

Customize the appearance of the TUI. Values are typically [ANSI color codes](https://en.wikipedia.org/wiki/ANSI_escape_code#Colors).

* `HEADER_FG_COLOR`: Foreground color for headers. (Default: `"28"`)
* `SELECTED_FG_COLOR`: Foreground color for selected items in lists/menus. (Default: `"205"`)
* `CURSOR_FG_COLOR`: Foreground color for the cursor in input fields/choosers. (Default: `"28"`)
* `INFO_FG`: Foreground color for informational messages. (Default: `"99"`)
* `SUCCESS_FG`: Foreground color for success messages. (Default: `"40"`)
* `WARNING_FG`: Foreground color for warning messages. (Default: `"214"`)
* `ERROR_FG`: Foreground color for error messages. (Default: `"196"`)
* `DEP_LABEL_FG`: Foreground color for dependency check labels. (Default: `"240"`)
* `DEP_FOUND_FG`: Foreground color for "Found" status in dependency checks. (Default: `"40"`)
* `DEP_MISSING_FG`: Foreground color for "Missing" status in dependency checks. (Default: `"196"`)

### Example `config.conf`

```bash
# Custom Proton location
CUSTOM_PROTON_DIRS="$HOME/.local/share/Steam/compatibilitytools.d"

# Steam library locations
STEAM_LIB_DIRS="$HOME/.local/share/Steam /mnt/nvme/SteamLibrary"

# Default Gamescope flags
DEFAULT_GAMESCOPE_PARAMS="-b --backend wayland --grab"

# Custom shared prefix name (for new games, can be overridden in library)
UNIVERSAL_PREFIX_NAME="umu_shared_prefix"

# --- TUI Color Customization Examples ---
# HEADER_FG_COLOR="33" # A nice blue
# SELECTED_FG_COLOR="220" # A bright yellow for selections
# INFO_FG="245" # A lighter grey for info messages
```
Data Files

    Game Library: Configurations for saved games are stored as JSON files in ~/.local/share/umu-launch-gum/library/.
    Last Played Game (for Quick Launch): The path to the last launched game's library configuration is stored in ~/.local/share/umu-launch-gum/last_game_config.jsonpath.
    Logs: Launch logs are stored in ~/.local/share/umu-launch-gum/logs/.
