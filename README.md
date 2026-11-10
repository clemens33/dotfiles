# dotfiles

Personal dotfiles for Ubuntu WSL2 with fish shell + AI coding tool configuration (Claude Code, Codex CLI, OpenCode, Gemini). Uses [Dotbot](https://github.com/anishathalye/dotbot) for symlink management.

Two-layer setup:

- **Public layer** (this repo): shell/editor/git config, AI tool settings, the generic skills, operating doctrine (`shared/AGENTS.md`, `WORKFLOW.md`, `KNOWLEDGE.md`).
- **Private overlay** (`dotfiles-mic/`, optional git submodule): org-specific skills + agents + private git/shell config. Only fetched on machines with auth to the private repo.

## Prerequisites

```bash
# CLI tools (apt or nix): ripgrep, delta, tmux, jq

# WSL clipboard helper
curl -sLo /tmp/win32yank.zip https://github.com/equalsraf/win32yank/releases/download/v0.1.1/win32yank-x64.zip
cd /tmp && unzip -o win32yank.zip win32yank.exe && chmod +x win32yank.exe && mv win32yank.exe ~/.local/bin/
```

## Bootstrap

Public install — no private overlay:

```bash
git clone https://github.com/clemens33/dotfiles.git ~/projects/clemens33/dotfiles
cd ~/projects/clemens33/dotfiles
./install
```

The install script initializes only the public `dotbot` submodule. The private `dotfiles-mic` submodule is **not** auto-initialized — public clones work without auth to the private repo.

### Optional: enable the private overlay

If you have access to the private `dotfiles-mic` repo:

```bash
cd ~/projects/clemens33/dotfiles
git submodule update --init dotfiles-mic
./install
```

The wrapper install script detects the overlay submodule and runs its Dotbot pass automatically when present.

## Commands (just)

[`just`](https://github.com/casey/just) is the entry point for checks and maintenance. `just` alone lists the recipes. Every recipe runs under bash, not under the login shell.

| Recipe | What it does | Network / writes |
|---|---|---|
| `just check` | Runs `lint`, `contract` and `test`, names each failed gate, exits 1 if any failed. CI runs exactly this | none, temp dirs only |
| `just lint` | Shell syntax, fish syntax, shellcheck, parse of tracked JSON / JSONC / TOML / YAML and `gitconfig`, skill lint | none |
| `just test` | `tests/test-*.sh` and `scripts/*-test.sh`, serially | none, temp dirs only |
| `just contract` | Renders the contract into a temp HOME, then compares the installed harness files | none |
| `just versions` | Installed harness versions (`<tool> --version` only, never `muse`); informational | none |
| `just outdated` | Installed versus latest harness versions (`scripts/harness-update.sh --check`) | network, a log in `~/.local/state` |
| `just update [args]` | Updates the harnesses, harness-only: arguments go to `scripts/harness-update.sh` (`--only TOOL`, `--check`, `--include-ae`) | network, installs |
| `just brew` | macOS only: `brew bundle --file macos/Brewfile` | network, installs |
| `just install [args]` | `./install` | symlinks, fetches the dotbot submodule |

`check`, `lint`, `test`, `contract` and `versions` never write tracked files and never call the network. `update`, `brew`, `install` and `outdated` run only when you name them.

Requirements:

- `just`, `bash`, `git`, `jq` (`brew install just`, or `sudo apt install just` on Ubuntu 24.04 and newer).
- `python3` with PyYAML, and `tomllib` (Python 3.11+) or `tomli`. The recipes pick the first of `$PYTHON`, `python3`, `/opt/homebrew/bin/python3`, `/usr/bin/python3` that has both. If none does, run `uv run --no-project --python 3.12 --with pyyaml==6.0.3 just check`.
- Optional, a step prints `SKIP` when missing: `shellcheck`, `fish`.
- Optional submodules: `tests/test-install-blocks.sh` needs `git submodule update --init dotbot`. `tests/test-render-contract.sh` and `scripts/eval-skills-test.sh` need the private overlay (`git submodule update --init dotfiles-mic`). Without them the test prints `SKIP`.

`render-contract.sh --check` writes the absolute source path into each installed header. From a worktree or another clone, `just contract` therefore compares body and mode, and reports `SKIP (known limit)` when only the header path differs. Body or mode drift fails with the target name. Fix drift with `./install`. The same recipe checks the rendered profile settings: a symlink to this repo's `claude/settings.json` (the state before the first `./install` of the renderer) reports `SKIP (legacy symlink, run ./install)`; a stale regular file or a foreign symlink fails with the differing key paths.

## What's included

| Config | Source | Symlinks to |
|---|---|---|
| Fish shell | `config.fish`, `fish/functions/` | `~/.config/fish/` |
| tmux | `tmux.conf` | `~/.tmux.conf` |
| Git | `gitconfig` | `~/.gitconfig` |
| Vim | `vimrc` | `~/.vimrc` |
| Bash aliases | `bash_aliases` | `~/.bash_aliases` |
| Claude Code | `claude/settings.json`, `claude/mcpServers.json` | `~/.claude/`; `~/.claude-p/` and `~/.claude-mic/` get a rendered `settings.json` (see below) |
| Browser MCP servers (opt-in) | `claude/browser-mcp.json` | `~/.config/ae/browser-mcp.json` (symlink; see [Browser MCP servers](#browser-mcp-servers-off-by-default)) |
| GitHub Copilot CLI | Native settings command + rendered instructions + merged MCP; auth/preferences remain CLI-owned | `${COPILOT_HOME:-~/.copilot}/` |
| Codex CLI | `codex/config.toml` | `~/.codex/config.toml` |
| OpenCode 2 | `opencode/opencode.jsonc` | `~/.config/opencode/opencode.jsonc` |
| Antigravity CLI (`agy`) | `antigravity/settings.json` | `~/.gemini/antigravity-cli/settings.json` |
| OpenDesign | `open-design/compose.yaml`, `open-design/Dockerfile`, `bin/open-design` | `~/.config/open-design/compose.yaml`, `~/.config/open-design/Dockerfile`, `~/.local/bin/open-design{,-mcp}` |
| `jobs-budget` | `bin/jobs-budget` | `~/.local/bin/jobs-budget` — prints how many parallel jobs a test/build run should use from the CPU free right now (`pytest -n "$(jobs-budget)"`); an idle machine yields every core minus a reserve (default `floor(ncpu / 8)` clamped to 1–4, or 0 on one or two CPUs, so 2 on 18 cores; `JOBS_BUDGET_RESERVE=<n>` overrides, `0` gives every core back). `jobs-budget --max` prints that cap with no 1 s sample; `config.fish` uses it to default `CARGO_BUILD_JOBS` and `NEXTEST_TEST_THREADS` when unset |
| AI skills | `skills/<name>/` | `~/.claude/skills/<name>/`, `~/.agents/skills/<name>/` |

The AI contract is the one exception: it is **rendered**, not symlinked. See
[How the contract reaches each tool](#how-the-contract-reaches-each-tool).

## AI operating doctrine

- **`shared/AGENTS.md`** — the contract: rules to never break (auto-loaded by every tool).
- **`WORKFLOW.md`** — triage (S/M/L bucket mandates), anti-patterns, skill cross-reference.
- **`KNOWLEDGE.md`** — field knowledge, source-tiered references; the header gives its refresh date. Older model history is in `KNOWLEDGE-CHANGELOG.md`.

See the `manage-skills` skill for the two-layer model — when to add a generic skill here vs. a domain-specific skill in the private overlay.

### Where doctrine lives

| File | Role | Visibility |
|---|---|---|
| `shared/AGENTS.md` | Contract — rules to never break | Rendered, not linked: `scripts/render-contract.sh` concatenates `shared/AGENTS.md` with the private overlay's `AGENTS-MIC.md` into the global instruction file of Claude Code / Codex / OpenCode / Antigravity / GitHub Copilot CLI (`${COPILOT_HOME:-$HOME/.copilot}/copilot-instructions.md`). Grok via its own short pointer + Claude compatibility; Muse imports `~/.claude/CLAUDE.md` with project → Claude Code → Codex precedence |
| `WORKFLOW.md` | Doctrine — how to approach a task | Read on demand by any tool via absolute path (`~/projects/clemens33/dotfiles/WORKFLOW.md`) |
| `KNOWLEDGE.md` | Field knowledge — the current state of the field; `KNOWLEDGE-CHANGELOG.md` holds archived model history | Read on demand by any tool via absolute path (`~/projects/clemens33/dotfiles/KNOWLEDGE.md`) |
| `skills/large-feature/SKILL.md` | Full-rigor L playbook | Claude Code / OpenCode via `~/.claude/skills/`; Codex and Muse via `~/.agents/skills/` per-skill links; Grok reads `~/.claude/skills/` natively; Antigravity via `~/.gemini/config/skills` → `~/.claude/skills` |
| `skills/diagnose/SKILL.md` | Bug-shaped task loop | Same visibility as above |
| `skills/*/SKILL.md` (many skills) | Operational recipes + doctrine-shaped playbooks | Same discovery paths as above; all public/overlay skills linked per-skill for Claude Code and Codex via their Dotbot manifests; Codex-managed `~/.codex/skills/.system` stays separate |
| `agents/*.md` | Claude Code-specific subagent definitions (domain-specific, typically supplied by a private overlay) | Claude Code only via `~/.claude/agents/` symlink; not available to Codex / OpenCode / Antigravity without explicit per-tool support (Grok reads ~/.claude/agents/ natively) |

### How the contract reaches each tool

`scripts/render-contract.sh` concatenates `shared/AGENTS.md` with the private
overlay's `dotfiles-mic/AGENTS-MIC.md`, when that submodule is checked out, and
writes the result as a **regular file** into every harness identity:

```
~/.claude/CLAUDE.md       ~/.codex/AGENTS.md
~/.claude-p/CLAUDE.md     ~/.config/opencode/AGENTS.md
~/.claude-mic/CLAUDE.md   ~/.gemini/config/plugins/dotfiles/rules/AGENTS.md
~/.copilot/copilot-instructions.md
```

`./install` runs the renderer; nothing links to `shared/AGENTS.md` any more. The
renderer creates no identity of its own — it skips any whose directory is
missing. `./install` is what provisions them: the public pass creates
`~/.claude-p` and `${COPILOT_HOME:-$HOME/.copilot}`, the private overlay's pass creates `~/.claude-mic`. So
a public-only clone has no `~/.claude-mic`, and the renderer simply skips it.

Concatenation rather than a second file, because it is the only portable
option. Measured 2026-09-09: of the five harnesses, only Claude Code reads an
instruction file one level *above* a git root, and only under the name
`CLAUDE.md`; Codex, Grok, `agy` and OpenCode read nothing above the repo root.
Directory-scoped org rules therefore cannot be made to work everywhere, so the
org half ships inside the file each tool already loads.

- **Regenerate**: `./install`, or `scripts/render-contract.sh` on its own. The
  private overlay's Dotbot pass runs the renderer a second time on purpose:
  `~/.claude-mic` is created *in* that pass, so only the second call can reach
  it. Do not "tidy" that duplicate away — a clean machine would then need two
  `./install` runs. Re-rendering the other six targets is a no-op.
- **Check for drift**: `scripts/render-contract.sh --check` lists stale targets,
  exits 1, and writes nothing. The daily harness updater runs it as its
  `contract` step and only reports — it never re-renders behind your back.
- **Never edit a target.** Each one opens with a generated-file header; edits
  are lost on the next install. Edit the source, then re-run `./install`.
- **Without the private overlay** the render is public-only. A public clone
  installs and works with no missing pieces.
- **Grok is unchanged**: `grok/AGENTS.md` → `~/.grok/AGENTS.md` stays a symlink
  because of grok's 10k-char rules cap, and grok picks the full contract up
  through its Claude-compatible read of `~/.claude/CLAUDE.md`.
- **Profile settings are rendered too** (`claude-p`, `claude-mic`). Claude Code
  loads `~/.claude/CLAUDE.md` as the ancestor project file of `$HOME`, so a
  profile session would load the contract twice. `scripts/render-claude-settings.sh`
  writes `~/.claude-p/settings.json` and `~/.claude-mic/settings.json` as regular
  files: `claude/settings.json` plus a `claudeMdExcludes` entry for that one path.
  Claude Code reads the file from `$CLAUDE_CONFIG_DIR`, so it covers every launcher,
  including `ae`, which bypasses the fish functions. Plain `~/.claude/settings.json`
  stays a symlink. The exclude would drop the contract from plain `claude`, where `~/.claude/CLAUDE.md` is the user memory.
  `./install` overwrites runtime changes made inside a profile (a plugin toggle,
  a model choice) and prints `WARN` with the differing key paths. To keep such a
  change, promote it into `claude/settings.json` first; `scripts/render-claude-settings.sh --check`
  and `just contract` show the same diff before you install. An edit to
  `claude/settings.json` reaches the profiles only after `./install`.

## GitHub Copilot CLI

The public install renders the complete shared contract into
`${COPILOT_HOME:-$HOME/.copilot}/copilot-instructions.md` and reconciles the
public MCP servers (none by default) into that home's `mcp-config.json`. Copilot discovers
existing `~/.agents/skills` natively; no duplicate skill tree is installed.
Existing repository instructions remain in effect alongside the personal contract.

The MCP adapter converts Claude `stdio` definitions to native `local` entries
with `tools: ["*"]`. It owns no name at present: the managed source
`claude/mcpServers.json` is `{}` and a source that declares a server fails the
closed schema. The retired names Serena, Context7, OpenDesign and Chrome DevTools
are only deleted: an entry left in the native file is removed on the next
install; machine-local servers and unrelated fields survive. The Claude and Muse
merges keep the same kind of retired-name list (Serena, retired 2026-11-07;
Context7, OpenDesign and Chrome DevTools, retired 2026-11-09), so an old
installed entry disappears on the next install. Invalid managed schema fails without rewriting the
target. The resulting regular file is mode0600. Tool discovery does not add
blanket tool, path or URL permissions.

Authentication/state `config.json` and other preferences stay CLI-owned. Install
sets only `copilot config includeCoAuthoredBy false`, matching the commit metadata
contract. Both that command and generated targets honor `COPILOT_HOME`.

The scheduled updater includes `copilot update stable` under its existing deadline
and retries. `--only copilot --check` compares the active CLI with GitHub's latest
stable release and does not run update; an older active version returns nonzero.
The npm loader manifest can be older than the active downloaded native package
and is not the installed-version oracle. A successful install/update records
`~/.local/state/harness-update/copilot-installed`: if Copilot later disappears
(for example after a mise Node change), the updater fails with a restore message.
A fresh host without a CLI or marker skips. Check mode writes only routine updater
logs, never the installed marker, native settings or update cache. Native
`autoUpdate` remains at the user's existing value (default true).

The optional private overlay supplies gateway entries and a per-launch shim.
Its accepted key-inheritance boundary is documented in the overlay README.
Legacy Fish `g`/`ghg`/`gitg` aliases still use the retired `gh copilot suggest -t`
interface; this integration does not redesign them. Invoke `copilot` directly.

## OpenDesign

The public install wires a persistent local [OpenDesign](https://github.com/nexu-io/open-design)
daemon and web UI. It builds no image and starts no container. Install and start
it explicitly — `open-design install` builds the local image first, so a clean
machine never starts against a missing one:

```bash
./install
open-design install
open-design open
```

Open `http://127.0.0.1:7456`. This trusted local setup disables OpenDesign's API
authentication and binds the published port strictly to `127.0.0.1`; it is not
reachable on the LAN. Do not change the bind address without restoring
authentication and TLS in front of the service.

Common operations:

```bash
open-design build       # build the local image from the pinned base digest
open-design start       # create/start and wait until healthy
open-design stop        # stop; keep container and data
open-design restart     # recreate and wait until healthy
open-design status
open-design logs --tail 100
open-design health
open-design version
open-design down        # remove container/network; keep both named volumes
```

### Installing a design-system package

`sync-package` installs a finished OpenDesign design-system package — a
directory holding `manifest.json`, `DESIGN.md` and `tokens.css` — into the
daemon's persistent storage:

```bash
open-design sync-package /path/to/package
open-design cli design-systems show user:<id>
```

The command is generic: the id, and everything else about the package, comes
from its `manifest.json`. It streams the directory into the container (no repo
is ever mounted), places it under `/app/.od/design-system-sources/<id>`, and on
the first run asks OpenDesign's own local-install API to add it to the catalog.
Later runs replace the files in place, so the catalog entry and its id survive.

It only ever touches a package it installed itself. A source directory without
its marker file, or a catalog entry pointing somewhere else, is refused rather
than overwritten. If the transfer, the install call, or the post-install
validation fails, the previous package is moved back and the catalog entry this
run created is removed.

This is a **pinned-version compatibility surface**. The package format belongs
to the OpenDesign release named above, not to a stable interchange standard:
`manifest.json` is validated against that release's
`design-systems/_schema/manifest.schema.ts`. When the pinned digest moves,
re-validate a package before trusting a sync.

`import-design-system` is a different thing and stays as it was: it runs
OpenDesign's own importer, which scans a source tree and emits its own canonical
package. Use it for a foreign project; use `sync-package` when you already have
a package you want installed verbatim.

### Image, updates, and data

The container image is a thin local derivative, `open-design-vela:0.21.1-vela0.0.33`,
built by `open-design/Dockerfile` from release `0.21.1` pinned by immutable
multi-architecture index digest
`sha256:441daca881e699657bacf28e0c27b16cd6be551dfff4bd63368dd74bec581f39`.
The Dockerfile is COPY-free and builds with no build context at all: a Docker
build context cannot follow the Dotbot symlink that installs it, and widening
the context to this checkout would ship the whole repo to the daemon.

It is deliberately outside `scripts/harness-update.sh`. To update or roll back,
change the `FROM` digest in `open-design/Dockerfile`, then run
`open-design build && open-design restart`. Nothing is pulled by tag and no
lifecycle command rebuilds, so the running image only ever changes when you
build it.

Two named Docker volumes hold all state and both survive `open-design down`:

| Volume | Holds |
|---|---|
| `open-design_open_design_data` | Projects, artifacts, design systems (`/app/.od`) |
| `open-design_open_design_vela_data` | The container home, including the Vela sign-in (`/home/open-design`) |

Full data deletion is intentionally not wrapped. After separately confirming
data loss, stop the stack and explicitly remove the exact volume you mean, e.g.
`docker volume rm open-design_open_design_data`. Sign out in the UI before
deleting the Vela volume — see below.

### Vela sign-in

Upstream's published image ships the daemon but never bundles the Vela CLI, so
on the official image the UI's **Sign in to OpenDesign** fails with
`vela binary not found; install vela or configure VELA_BIN`
(nexu-io/open-design issue #5700; Docker/Compose is only partially supported
upstream). `open-design/Dockerfile` is the local answer: it adds Alpine
`gcompat` plus the exact `@powerformer/vela-cli` 0.0.33 that tag 0.21.1 pins,
and fails the build if `vela --version` is not `0.0.33`.

Signing in is still a human device activation. OpenDesign prints an activation
URL and user code; opening the link and approving it happens on your own device,
and nothing in this repo logs in for you. The container is headless, so its own
attempt to open a browser fails by design — use the URL the UI shows.

The resulting session is a bearer credential on disk in the container home —
the daemon reports its config at `/home/open-design/.amr/config.json` — inside
`open-design_open_design_vela_data`. Treat that volume as secret material: do
not export, back up, or copy it, and do not move it between machines.
`open-design down` deliberately leaves the authenticated session in place so a
restart does not force a new sign-in. When retiring it, sign out in the UI
first, then remove the volume explicitly.

Import one local design-system package without mounting a repository or home
directory:

```bash
open-design import-design-system ./path/to/brand --name "Brand" --json
```

The wrapper streams only that directory to a unique container `/tmp` path,
imports it in `hybrid` mode, then removes the exact temporary path. A current
package centers on `DESIGN.md` and can add `manifest.json`, compiled
`tokens.css`, component fixtures, assets, and provenance/evidence. Legacy
directories containing only `DESIGN.md` remain compatible.

The OpenDesign MCP bridge (`open-design-mcp`) has not been a managed MCP server
since 2026-11-09: its 22 tools cost about 7k tokens of definitions whenever a
harness loads them eagerly, and only design sessions use them. The bridge itself
stays installed and runnable. Every `./install` deletes a user-level
`open-design` entry from each Claude identity's `.claude.json` that exists, from
Muse, from Copilot and from Antigravity (`scripts/agy-mcp-retire.sh`). Codex and
OpenCode link to a source that no longer lists it, and Grok copies one. Enable
the bridge on demand, in a scope the install never touches.

OpenDesign 0.21.1 does not support Docker/Compose MCP snippets or shared HTTP
transport upstream, so the bridge is a locally tested `docker exec -i` stdio
compatibility command. It needs the running container (`open-design start`).
Muse Code 1.0.3 exposes no MCP client configuration and is not integrated.

Direction matters: a host harness can call OpenDesign's MCP to read projects and
write artifacts. The isolated container cannot launch host Claude/Codex/OpenCode
binaries. Generation initiated in the OpenDesign UI therefore needs its own BYOK
provider configured in OpenDesign; host subscriptions and credentials are not
mounted or copied into it.

### Enable the MCP on demand

Run `open-design start` first. Each command below was run against the installed
CLI (versions under the table) in a throwaway `HOME` or config directory.
"Not verified" means it could not be shown to work.

| Harness | Scope and command | Verified |
|---|---|---|
| Claude Code | One project, private (stored under `projects["<cwd>"].mcpServers` in the identity's `.claude.json`): `claude mcp add --scope local open-design -- open-design-mcp`. Undo: `claude mcp remove open-design --scope local`. | yes |
| Claude Code | Shared project file `./.mcp.json`: `claude mcp add --scope project open-design -- open-design-mcp` | yes (file written; the approval prompt on first use is not exercised) |
| Codex | One session: `codex -c 'mcp_servers.open-design.command="open-design-mcp"'`. Do not use `codex mcp add`: it writes `~/.codex/config.toml`, which links into this repo. | yes (`codex -c … mcp list` shows it enabled) |
| Grok | One project, `./.grok/config.toml`: `grok mcp add --scope project open-design open-design-mcp`. The default `--scope user` is replaced by the next install. | yes (`grok mcp list` shows `(project)`) |
| OpenCode | One project, `./opencode.json`: `opencode mcp add open-design -- open-design-mcp`. Do not add `--global`: it writes `~/.config/opencode/opencode.json`, which the install never cleans, so the server would stay on everywhere. | file written in the managed `mcp.servers` shape; server load not verified (`opencode mcp list` could not start beside the running service) |
| Antigravity (`agy`) | Machine-wide only, no project scope: `agy mcp add open-design open-design-mcp`, then `agy mcp disable open-design` or `remove`. The next `./install` removes it again. | yes (`add`, `list`, `remove`) |
| Copilot CLI | Workspace file `./.mcp.json` (or `./.github/mcp.json`) with `{"mcpServers":{"open-design":{"type":"local","command":"open-design-mcp","args":[],"env":{},"tools":["*"]}}}`. Copilot reads it only in a trusted folder (`trustedFolders` in `~/.copilot/config.json`). `copilot mcp add` is user-level and removed by the next install. `--additional-mcp-config` is per session by `copilot --help` ("for this session"), but `copilot mcp list` never shows its servers. | discovery verified (`copilot mcp list` shows it under "Workspace servers" in a trusted folder); launch not exercised; `--additional-mcp-config` not verified |
| Muse Code | No MCP client configuration. | not applicable |

Versions checked: Claude Code 2.1.319, Codex 0.167.0, Grok 1.0.77, OpenCode 2.2.6,
Antigravity 1.5.3, Copilot CLI 1.0.107.

To remove the app, run `open-design down`, delete the two named volumes
according to the data-retention choice above (sign out in the UI before retiring
the Vela volume) and drop the `open-design` links from `install.conf.yaml`.

#### Browser MCP servers: off by default

`chrome-devtools` and `playwright` start no process unless a seat opts in
(2026-11-09: dozens of idle `chrome-devtools-mcp` and `playwright-mcp` processes
and an `npx` registry check at every agent start). `./install` removes a stale
user-level `chrome-devtools` from the three Claude homes, Muse, Copilot and
Antigravity, and links `claude/browser-mcp.json` to
`~/.config/ae/browser-mcp.json`. That file holds the pinned entries
`chrome-devtools-mcp@1.8.0` (with `--no-usage-statistics --no-performance-crux`)
and `@playwright/mcp@0.0.84`. Bump the pin in that file, in `codex/config.toml`,
in `opencode/opencode.jsonc` and in the commands below together.
`chrome-devtools` needs Chrome with the DevTools port 9222 (`chrome-debug`);
`playwright` launches its own browser.

Playwright is also off where a project `.mcp.json` declares it: `claude/settings.json`
sets `disabledMcpjsonServers: ["playwright"]` for all three Claude homes. The
assistant repo's `.mcp.json` stays as it is. The ae profiles `sonnet55x-web`,
`sonnet55x-p-web` and `opus55h-mic-web` (both servers, through `--mcp-config`)
and `sol61h-web` (chrome-devtools only, through `-c`) opt in at spawn; they
live in `~/.ae/config`, not in this repo. `./install` must have created the
symlink before the first `-web` seat starts.

Each command was run against the installed CLIs (versions under the table) in a
throwaway `HOME`, config directory or project. No real `chrome-devtools-mcp` or
`@playwright/mcp` server was started to check them. "Not verified" means it could
not be shown to work.

| Harness | Opt-in command | Verified |
|---|---|---|
| Claude Code | `claude --mcp-config=$HOME/.config/ae/browser-mcp.json` (both servers). Keep the `=`: the option is variadic, so a space lets it swallow the next word. | yes, with stub servers in a temp `CLAUDE_CONFIG_DIR`: the file adds to the user and project servers, and a same-named `playwright` from the file connects while `disabledMcpjsonServers` lists it |
| Codex | `codex -c mcp_servers.chrome-devtools.enabled=true` (chrome-devtools only) | yes (`codex mcp list`: `disabled` by default, `enabled` with the flag) |
| OpenCode | `OPENCODE_CONFIG_CONTENT='{"mcp":{"servers":{"chrome-devtools":{"type":"local","command":["npx","-y","chrome-devtools-mcp@1.8.0","--browser-url=http://127.0.0.1:9222","--no-usage-statistics","--no-performance-crux"],"disabled":false}}}}' opencode --standalone`. The default is `"disabled": true`: OpenCode 2 has no `enabled` key and drops it. | default: `opencode debug config --standalone` keeps `disabled: true` for the repo file. Opt-in: not verified: a stub server never showed as connected (`opencode mcp list` exits first), and the opt-in value overriding the file value is not shown |
| Grok | In the project: `grok mcp add --scope project chrome-devtools -- npx -y chrome-devtools-mcp@1.8.0 --browser-url=http://127.0.0.1:9222 --no-usage-statistics --no-performance-crux`. The default `--scope user` is replaced by the next install. | `./.grok/config.toml` written as expected; server start not exercised |
| Antigravity (`agy`) | Machine-wide only: `agy mcp add chrome-devtools npx -y chrome-devtools-mcp@1.8.0 --browser-url=http://127.0.0.1:9222 --no-usage-statistics --no-performance-crux`, then `agy mcp remove chrome-devtools`. The next `./install` removes it again. | `mcp_config.json` written as expected; server start not exercised |
| Copilot CLI | Workspace file `./.mcp.json` with `{"mcpServers":{"chrome-devtools":{"type":"local","command":"npx","args":["-y","chrome-devtools-mcp@1.8.0","--browser-url=http://127.0.0.1:9222","--no-usage-statistics","--no-performance-crux"],"env":{},"tools":["*"]}}}` in a trusted folder. | not verified for this server: the workspace-file mechanism is the one the OpenDesign row above verified, but listing it would start chrome-devtools; `--additional-mcp-config` not verified |
| Muse Code | No on-demand route documented; `./install` removes a user-level `chrome-devtools` from `~/.config/muse/settings.json`. | not verified |

Versions checked: Claude Code 2.1.319, Codex 0.167.0, Grok 1.0.77, OpenCode 2.2.6,
Antigravity 1.5.3, Copilot CLI 1.0.107.

## Automatic harness updates

`scripts/harness-update.sh` updates installed Claude Code, Codex, GitHub Copilot CLI, Antigravity
(`agy`), Grok, and OpenCode CLIs. Each tool is isolated: one failed update does
not skip the rest. It runs daily at 06:30 local time and writes dated logs to
`~/.local/state/harness-update/` (last 14 retained).

```bash
# Inspect current and latest versions without changing anything
scripts/harness-update.sh --check

# Update everything installed, or one tool
scripts/harness-update.sh
scripts/harness-update.sh --only codex

# Report instruction files and profile settings that drifted from their rendered source
scripts/harness-update.sh --only contract
scripts/harness-update.sh --only settings
```

`contract` is a step, not a CLI: it runs `render-contract.sh --check` and names
any target that no longer matches. `settings` does the same for the claude-p and
claude-mic profile settings with `render-claude-settings.sh --check`; a legacy
symlink alone reports `SKIP`. Neither renders — `./install` does that.

`ae` is excluded by default because session glue is version-pinned. Its
checksum-verified upgrader remains opt-in and requires an explicit calver:

```bash
AE_VERSION=YYYY.M.D scripts/harness-update.sh --include-ae
```

On macOS, `./install` links and loads the launch agent. Reload or unload it with:

```bash
launchctl bootstrap gui/$(id -u) "$HOME/Library/LaunchAgents/at.clemens.harness-update.plist"
launchctl bootout gui/$(id -u)/at.clemens.harness-update
```

On Linux with systemd, `./install` links and enables the user timer. WSL
installations without systemd skip it.

```bash
systemctl --user daemon-reload
systemctl --user enable --now harness-update.timer
```

Native installers replace versioned files atomically, so already-running CLI
processes keep their old executable until restarted. On macOS, OpenCode is
updated in the mise-managed Node LTS global; Linux also supports the default
fnm/nvm Node alias. Switching Node versions leaves that global install behind
and requires reinstalling it for the new version.
