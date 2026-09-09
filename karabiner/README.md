# Karabiner — Windows-style layout for external keyboards

macOS only. Keeps years of Windows muscle memory usable on external PC
keyboards **without** touching the built-in MacBook keyboard, so both habits
survive side by side.

## What is versioned here

`assets/complex_modifications/windows-layout.json` — the rule set (6 rules,
52 manipulators), in Karabiner's importable asset format.

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
| Logitech G515 LS TKL (USB cable) | 1133:50005 |

Find a new keyboard's IDs in Karabiner-EventViewer → *Devices*, or list what is
attached with `ioreg -c IOHIDDevice -r -d1 | grep -E '"(Product|VendorID|ProductID)"'`
— that also prints the product *name*, which EventViewer's ID columns do not.

**A wireless keyboard has different USB ids.** The G515 reports `1133:45961`
over Bluetooth but `1133:50005` on the cable, so plugging it in silently drops
it out of `device_if` scope and the whole Windows layout stops firing — Ctrl+C
goes back to being Ctrl+C. Both ids are listed above for that reason. Any new
keyboard needs *every* transport it will be used on.

**Check the product name before adding an id.** `1133:49271` was scoped in here
as a second G515 cable id until 2026-08-20; it is actually the Logitech *USB
Optical Mouse*. Harmless (a mouse emits no key events) but it made the scope
claim something untrue. Vendor 1133 is every Logitech device on the desk.


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
| `Win+Shift+S` | `⌘⌃⇧4` — select area, **to clipboard** (same key as Windows) |
| `Win+H` | Dictation (same key as Windows) |

**These two use the physical Windows key, not Ctrl** — matching Windows
exactly, where the snip is `Win+Shift+S` and dictation is `Win+H`. A PC
keyboard's Win key arrives on macOS as `command`, so the rules read
`mandatory: [command, shift]` and `mandatory: [command]`.

Using the Win key rather than Ctrl buys two things:

- **`Ctrl+Shift+S` stays free** and falls through to the `Ctrl+key → Cmd+key`
  rule, which forwards the optional `shift` and emits `⌘⇧S` = **Save As** —
  which is what `Ctrl+Shift+S` does on Windows too. An earlier version of this
  rule set claimed `Ctrl+Shift+S` for the screenshot and silently cost Save As.
- **`Cmd+H` (Hide window) gets shadowed on external keyboards**, which is a
  feature here: `Ctrl+H/M/Q` are deliberately unmapped below precisely because
  hide/minimise/quit make windows vanish irrecoverably for a Windows user.

Neither rule carries a terminal exclusion — screenshotting or dictating into a
terminal is a normal thing to want, and neither combo has a shell meaning. To
save a screenshot *file* instead of copying to the clipboard, drop `control`
from the screenshot rule's `to` modifiers (`⌘⇧4`).

**Why dictation needs a rule at all.** macOS triggers dictation from the
dedicated mic key that lives on `F5` of *Apple* keyboards, which emits the
`dictation` consumer usage — not a key combination. A PC keyboard has no such
key, and its `Fn` is handled in the keyboard's own firmware and never reaches
macOS, so `Fn+F5` is physically unsendable from an external board. This rule
emits `consumer_key_code: dictation` directly, i.e. exactly what the MacBook's
F5 sends. The native alternative, which needs no rule and works on both
keyboards, is System Settings → Keyboard → Dictation → *Shortcut* →
**Press Control Key Twice**.

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
