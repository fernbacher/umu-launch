# UMU-Launch: TUI Launcher for non-steam games.

Launches Windows games on Linux using umu-launcher.

This script provides a Terminal User Interface (TUI) built with [gum](https://github.com/charmbracelet/gum) to easily launch portable Windows games on Linux using [umu-launcher](https://github.com/Open-Wine-Components/umu-launcher) and proton.

**Features:**

* **Game Selection:** Browse your filesystem to select the game's `.exe` file.
* **Proton Detection & Selection:** Automatically finds Proton versions in common Steam compatibility tool directories and lets you choose which one to use.
* **Custom Input:** Add extra environment variables (e.g., `DXVK_HUD=1`) or command-line arguments specific to a launch.
* **Universal Prefix:** Uses a single Wine prefix named `umu-default` for all games launched via the script.
* **Automatic Logging:** Creates timestamped log files in `~/.local/share/umu-launch-gum/logs/` containing the executed command and the game's terminal output for debugging.

**Requirements:**

* `bash`
* `gum`
* `umu-launcher`
* `coreutils` (for `realpath`, `date`, `tee`, `mkdir`, `sort`)
* Installed Proton version(s) in one of the standard Steam `compatibilitytools.d` directories.
* Optional: `gamemode`, `gamescope`, `mangohud` (will be detected if installed).

**Usage:**

1.  Make the script executable: `chmod +x umu-launch.sh`
2.  Run it: `./umu-launch-gum.sh`

<video controls src="./preview.mp4" title="Script Preview">
  Sorry, your browser doesn't support embedded videos, but you can <a href="./preview.mp4">download it</a>.
</video>

This project was vibecoded using [pieces](https://pieces.app/).
