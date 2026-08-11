# Karabiner — Windows-style layout for external keyboards

macOS only. Keeps years of Windows muscle memory usable on external PC
keyboards **without** touching the built-in MacBook keyboard, so both habits
survive side by side.

## What is versioned here

`assets/complex_modifications/windows-layout.json` — the rule set (4 rules,
50 manipulators), in Karabiner's importable asset format.

**Not** `karabiner.json`. Karabiner rewrites that file itself (device entries
change as keyboards connect), so symlinking it into a repo fights the app and
produces meaningless diffs. Dotbot links the asset instead; the asset is the
source of truth and `karabiner.json` is treated as machine state.

## Restore on a new machine

1. `brew install --cask karabiner-elements`, then grant the three permissions
   it asks for: **driver extension** approval, plus **Input Monitoring** *and*
   **Accessibility** for `Karabiner-Core-Service` (two separate System Settings
   panes — this cannot be scripted; TCC is SIP-protected).
2. `./install` (dotbot links the rule set into place).
3. Karabiner-Elements → *Complex Modifications* → *Add rule* → enable
   **"Windows-style layout (external keyboards only)"**.
4. Set the profile's virtual keyboard to **ISO** (`Virtual Keyboard` →
   `Keyboard type` → ISO) — without it the German layout's `<`/`>` key and
   several AltGr positions are wrong.
5. Add your keyboards' vendor/product IDs (see below) if they differ.

## Device scope

The rules only fire on these devices (`device_if`):

| Keyboard | vendor:product |
|---|---|
| HP USB Keyboard | 1121:20110 |
| Logitech G515 LS TKL (Bluetooth) | 1133:45961 |

Find a new keyboard's IDs in Karabiner-EventViewer → *Devices*.

## What it maps

| Windows habit | Becomes |
|---|---|
| `Ctrl` + letter/digit | `Cmd` + same (copy, paste, save, find, tabs …) |
| `Alt+Tab` / `Alt+F4` | `Cmd+Tab` / `Cmd+Q` |
| `Home` / `End` | `Cmd+←` / `Cmd+→` (line start/end) |
| `Ctrl+Home` / `Ctrl+End` | `Cmd+↑` / `Cmd+↓` (document start/end) |
| `Ctrl+←/→` | `Option+←/→` (word jump) |
| `Ctrl+Backspace` / `Ctrl+Delete` | `Option+…` (delete word) |
| AltGr (right Option) + `q 7 8 9 0 ß < +` | `@ { [ ] } \ | ~` — German positions |

**Deliberately not mapped:** `Ctrl+H`, `Ctrl+M`, `Ctrl+Q`. On macOS those
become hide / minimise / quit — a Windows user hits them by reflex and the
window vanishes into a state they cannot recover.

**Excluded applications:** every terminal (Ghostty, Terminal, iTerm2, kitty,
Alacritty, WezTerm, cmux) and VS Code. `Ctrl+C` must stay SIGINT in a shell.
VS Code instead uses the `smcpeak.default-keys-windows` extension, which is
context-aware: its editor copies with Ctrl+C while its integrated terminal
keeps SIGINT.

## Gotcha

A Bluetooth keyboard already connected when the Karabiner grabber starts is
*seen but not grabbed* — the log says it found the device, yet no mapping
fires. Power-cycle the keyboard. To restart the services:

```bash
launchctl kickstart -k gui/$UID/org.pqrs.service.agent.karabiner_console_user_server
launchctl kickstart -k gui/$UID/org.pqrs.service.agent.Karabiner-Core-Service-rev2
```

The `-rev2` suffix is part of the label; without it launchctl reports
"Could not find service". Daemon log: `/var/log/karabiner/core_service.log`.
