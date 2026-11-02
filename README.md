# X-Notch for Omarchy

A little X (Twitter) notch for your desktop, built for [Omarchy](https://omarchy.org) (Arch + Hyprland) with Quickshell.

**Credit:** X-Notch was originally created by Patrick ([@journeydeck](https://x.com/journeydeck)) as a Mac app. This is the Omarchy edition, inspired by his original idea and design.

## Features

- **Hover pill**: a small pill at the top of the screen that expands when you hover it
- **Avatar row**: the accounts you follow, as avatars
- **Live feeds**: recent posts for the selected account via the X API v2 (cached 10 min)
- **CLI**: `xnotch add <handle>`, `xnotch remove <handle>`, `xnotch list`
- **'+' button**: add an account right from the notch
- **Right-click remove**: right-click an avatar to remove it
- **Live reload**: edits to `~/.config/xnotch/accounts.json` show up instantly

## Requirements

- `quickshell`
- `curl`
- `jq`
- An X API bearer token from [console.x.com](https://console.x.com) (pay-per-use; X-Notch only does read-only calls)

## Install

```bash
git clone https://github.com/gregstriblin1988-cpu/x-notch.git
cd x-notch
./install.sh
```

The installer copies the widget to `~/.config/quickshell/xnotch`, the scripts to `~/.local/bin`, and a starter `accounts.json` to `~/.config/xnotch`. It never overwrites an existing token or accounts file.

To autostart, add this to `~/.config/hypr/autostart.lua`:

```lua
o.launch_on_start("quickshell -n -p " .. os.getenv("HOME") .. "/.config/quickshell/xnotch")
```

## Token setup

```bash
mkdir -p ~/.config/xnotch
nano ~/.config/xnotch/token     # paste your bearer token (see config/token.example)
chmod 600 ~/.config/xnotch/token
```

Never commit your token.

## Usage

```bash
xnotch on | off | toggle   # start/stop the widget
xnotch add omarchy         # add an account
xnotch remove omarchy      # remove an account
xnotch list                # list accounts
```

## License

MIT, see [LICENSE](LICENSE).
