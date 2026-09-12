# DeepSeek Harness pilot

A pinned, local-only pilot of [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)
(`dsh`). It is **not** a replacement for OpenCode, Claude Code, Codex, or ae, and
it has no ae profile. OpenCode with GLM 5.3 Flash remains the stable default.

> **Developer preview.** Upstream states it plainly: *"DeepSeek Harness is in
> developer preview and iterating rapidly. THERE WILL BE COMPATIBILITY-BREAKING
> CHANGES."* Nothing here floats: the release candidate is pinned, and
> `scripts/harness-update.sh` only ever reports on it.

## Running it

```sh
dsh
```

Plain `dsh` with no arguments enters the interactive terminal harness. The
wrapper (`bin/dsh`) owns exactly one token, the first, and rewrites a surface
name into the `--profile` the official launcher wants:

| Invocation | Behaviour |
|---|---|
| `dsh` | the managed `dsh-tui` terminal profile |
| `dsh tui [args…]` | the same, arguments preserved |
| `dsh headless <task…>` | the official one-shot profile: answer, print, exit |
| `dsh web [args…]` | the official Web alias, forwarded verbatim |
| `dsh --profile <name> …` | official launcher passthrough, verbatim |
| `dsh plugin …` | official launcher passthrough, with the pinned pnpm on PATH |
| `dsh --help`, `dsh --version` | official launcher passthrough, verbatim |
| anything else | concise usage on stderr, exit 2 |

Web used to be the zero-argument default, which is how a terminal-first harness
ended up opening a browser server nobody asked for. It is now reachable only by
naming it, and `dsh web` is forwarded untouched — an explicit request for the
browser surface is the one case where opening a browser is the point.

The Web surface serves its UI on loopback and prints a URL carrying a startup
access token; without that token the API answers `401`. Whether that token is
single-use was never tested, so treat it as a bearer secret for the life of the
process rather than assuming it is spent on first use. There is no daemon,
launch agent, or autostart — you start it when you want it and stop it when you
are done.

Flags for the app go **after** the profile selection. The obvious-looking
`dsh --profile web … web --no-open` is rejected with *"web takes none of parent
--profile …"*.

## Which model, and which key

Every surface runs one model: `@preset/deepseek-v41-flash-us-zdr`, a DeepSeek
V4.1 Flash preset reached through OpenRouter. The preset id — not the bare
`deepseek/deepseek-v4.1-flash` — is what carries the provider preference order
wafer → modal → fireworks with `allow_fallbacks:false`,
`require_parameters:true` and `zdr:true`. The route has no field for
OpenRouter's `provider` object, so the preset is the only place those
constraints can live. If `dsh` ever cannot address a preset id, that is a stop
and a report, never a fallback to the bare model.

Two home-layer rows make that happen, and both are needed:

| Row | Decides |
|---|---|
| `llm-pi-ai` | what the OpenRouter provider route **can reach** — one model, because a `models` list replaces the served catalog |
| `agent-default-model` | what a freshly created agent **actually starts on** |

They are separate services, and the pilot shipped for a day with only the first.
Every profile composed the OpenRouter route, every fresh agent selected the
shipped `deepseek-official` / `deepseek-flash` default anyway, and the first
thing `dsh headless` said was that it wanted `DEEPSEEK_API_KEY`. A route nobody
selects is invisible to file-shape checks, which is why the daily gate now
counts the default as well as the route.

`reasoningEffort` is deliberately absent from the default row: the plugin
accepts only `provider` and `model`, by design — an effort in composition would
be re-inherited after a saved selection cleared it. The route's `reasoning:
high` is the daily default-effort source instead.

The route also pins `compat.maxTokensField: max_tokens`. Headless supplies a
bounded output budget, but pi-ai otherwise serializes that budget for an
OpenRouter route as `max_completion_tokens`. OpenRouter's V4.1 Flash endpoint
catalog advertises `max_tokens` — and not `max_completion_tokens` — for Wafer,
Modal and Fireworks. With the preset's `require_parameters:true`, the inferred
spelling filters out all three before inference. This compatibility override
changes only the wire name; it does not relax the preset's routing constraints
or change the budget value.

Measured live baseline, 2026-09-12: a fresh headless canary with prompt
`Reply exactly OK` finished with `stop` through Modal, position 2 in that
preference order. OpenRouter record `gen-1789207616-cV6uHGP6Y78ch4A6R8lb`
reported normalized prompt/completion tokens `16772/1`, native tokens
`16050/4`, and cost `USD 0.0048198`. This is a point-in-time operating sample,
not a guarantee that position 1 serves every request or that future cost stays
the same.

### Selection precedence

The composed default is a **base**, not a lock. From weakest to strongest, for a
newly created agent:

1. `agent-default-model` in `~/.dsh/cordis.patch.yml` — the composed default,
   the same on TUI, Web, headless, ACP and the SDK entry points.
2. An `agent-default-model:` section saved in `~/.dsh/settings.yaml`. Once
   written, that becomes the live source and every later agent reads it instead
   of the composition. The Web Models page writes it.
3. Terminal only: a successful `/model` pick, persisted as
   `~/.dsh-tui/model.json`. The TUI creates that file lazily on the first pick,
   so its absence before then is expected. It beats the harness default for
   **new** TUI sessions.

Sessions that already exist are not re-resolved: a resumed session continues on
the route its own log recorded. So after a `/model` pick, a fresh `dsh` and an
older resumed session can legitimately run different models.

The community TUI keeps its preferences and history under `~/.dsh-tui`, separate
from the harness state in `~/.dsh`. Its writers use mixed permission policies.
On the live 2026-09-12 installation the directory is mode `0755`;
`history.jsonl`, `session-index.json`, and `effect-ledger.jsonl` are `0600`,
while `last-used.json`, `migrations.json`, and `resume.txt` are `0644`.
`model.json` is written without an explicit mode, so the current `022` umask
will create it as `0644` after the first successful `/model` pick. These are
observed/current implementation facts, not a hardened runtime policy.

### The credential

The route resolves `apiKeyEnv: OPENROUTER_API_KEY` through the credentials
plugin, whose first source is the launching environment. `bin/dsh` fills that
variable from the OpenRouter key the OpenCode auth store already holds
(`~/.local/share/opencode/auth.json`, or `$OPENCODE_AUTH_FILE`), so this machine
keeps one copy of the secret rather than a second one in
`~/.dsh/.credentials.yaml`.

The key is read at launch, handed to that one process, and to nothing else: no
file under `$DSH_HOME`, no log line, and never an argv word — argv is
world-readable in `ps`. A missing store, a store with no `openrouter` record, an
OAuth rather than API record, and a malformed file all leave the variable unset,
so `dsh` reports its own `MISSING_CREDENTIAL` instead of the wrapper inventing
an error about a file nobody configured.

**An exported `OPENROUTER_API_KEY` wins, and it is never touched.** That is the
escape hatch and the footgun in one: an explicit export is a deliberate choice
of account, so a key exported from somewhere else silently moves both the model
selection available to the route and the spend onto that other OpenRouter
account. Unset the variable to go back to the OpenCode store.

Tool children never see the credential either way. The subprocess seam scrubs
ambient names matching `/KEY|PASSWORD|SECRET|TOKEN/i` and ambient `DSH_*` names
before spawning, and MCP servers, the bash tool and terminal sessions all share
that one definition. `tests/test-deepseek-harness.sh` composes the real bash
tool over the real subprocess provider and reads the child's environment rather
than trusting the prose.

## The terminal surface is community code

`@deepseek-harness-tui/dsh-tui` is **not** a DeepSeek package. The official
`@deepseek-ai/dsh` release ships Web, ACP, headless and SDK profiles and no
first-party TUI, so the terminal surface here is a community bundle composed
over the official runtime. The npm scope reads like a sibling of the official
one and is not: publisher `chimney`, repository
[`ccch1mneyyy/dsh-TUI`](https://github.com/ccch1mneyyy/dsh-TUI), MIT.

It is beta code holding agent-host authority — terminal, filesystem, shell,
sessions, model credentials, skills and MCP servers. That is accepted
deliberately for a local pilot. **Standing boundary: never point this surface at
MIC or customer code.**

Provenance for `0.10.1`, the exact version pinned here:

| | |
|---|---|
| Integrity | `sha512-xnwLON+c28zt1Yg5nrI2fNHysUEF63TsIC7XndtIJIiDOBEomcSfydnc9DrT+Xzx7p2/qAi6d7+GFB0eSyJ2uw==` |
| Attestation | SLSA provenance, GitHub-hosted builder |
| Repository | `https://github.com/ccch1mneyyy/dsh-TUI` |
| Tag | `refs/tags/v0.10.1` |
| Workflow | `.github/workflows/publish.yml` |

The TUI reports the version skew itself on every start:

> ⚠ The dsh engine (0.1.5-rc.2) is newer than the 0.1.5-rc.1 this UI is
> validated against, so issues are possible.

That is accurate and expected. Its 29 peer ranges cap at `0.1.5-rc.1` while the
official `0.1.5-rc.1` umbrella resolves `rc.2` internals. Every one of those
peers is declared **optional**, so the profile installs none of them and the
single `@deepseek-ai` plane stays in the runtime prefix where it belongs. Do not
"fix" the warning by pinning those packages back to rc.1: that replaces the
official plane and invalidates every gate this directory carries.

### What the pin does not cover

The lockfile carries 98 entries, every one with an integrity hash. Two things
sit outside that guarantee, and both are accepted for a local pilot rather than
overlooked.

**Eight packages ship inside the TUI tarball.** `@dsh-std/{core,command,storage,
manifest,messages,connection,presentation}` and `@deepseek-harness-tui/dsh-auth`
are `bundledDependencies`: the lock names them but records no `resolution` and no
integrity of their own, because they are not registry resolutions at all. They
are covered transitively by the TUI tarball's single hash and by nothing else.
An auditor reading the lock for per-package provenance will not find it for
these eight, and `dsh-auth` is the one that handles credentials.

**One transitive dependency is unscoped and unattested.** `dsh-working-activity`
at `0.4.0` is a direct dependency of the TUI bundle, so it loads in the harness
process; its peer set (`@deepseek-ai/cordis`, `dsh-agent`, `dsh-session`,
`dsh-system-prompt`, `schemastery`) is a host-plane plugin's, not a render
helper's. Checked 2026-09-12:

| | |
|---|---|
| Registry signature | present (2) — integrity matches the lock |
| SLSA attestation | **none** (`dist.attestations: null`), unlike the TUI itself |
| Maintainers | 1 — `ccchimneyyy`, the same person who publishes the TUI |
| Name | unscoped, so the name was first-come on the public registry |
| Age | first published 2026-08-13, 13 versions, last modified 2026-08-30 |
| Weekly downloads | 5,515 |
| License | BSD-3-Clause, repository `ccch1mneyyy/working-activity` |

So the TUI's own attested build does not extend to this dependency, and a single
compromised publisher account would reach the harness process through it. That
is the concrete shape of "community code with host authority", and it is the
reason for the standing boundary above: **never point this surface at MIC or
customer code.** Re-check these rows whenever the pin moves.

## What this directory owns

| File | Role |
|---|---|
| `package.json` | The exact dependency `@deepseek-ai/dsh` at `0.1.5-rc.1`, plus the npm `allowScripts` policy |
| `package-lock.json` | Pins the complete plugin graph and every published integrity hash |
| `.npmrc` | Makes `strict-allow-scripts=true` project-local, so the guard does not depend on this machine |
| `cordis.patch.yml` | Home-plane layer: the pilot's model route **and** the default a fresh agent starts on, applied to every profile that composes `dsh-base` (all but `sdk-minimal`) |
| `profiles/web/cordis.patch.yml` | Web's own layer: selects the managed preset on the `agent-presets` row |
| `profiles/dsh-tui/cordis.patch.yml` | The terminal profile's layer: the same selection on the scoped `dsh-tui-agent-presets` row |
| `profiles/dsh-tui/package.json` | The exact dependency `@deepseek-harness-tui/dsh-tui` at `0.10.1` and the bundle layer stack |
| `profiles/dsh-tui/pnpm-lock.yaml` | Pins that profile's graph: 98 entries, every one with an integrity hash |
| `profiles/dsh-tui/pnpm-workspace.yaml` | `nodeLinker: hoisted` and `autoInstallPeers: false`, verbatim from the shipped template |
| `pnpm/` | A tool-only project pinning the exact pnpm the profile installer needs |
| `presets/dotfiles/` | The agent preset: a pinned copy of shipped `standard` plus four MCP servers |
| `mcp-status.mjs` | Bounded, model-free probe reporting each MCP server's synchronized tool count |

Everything else is machine-local and never committed: `~/.local/share/dsh` is
the runtime prefix, and `~/.dsh` holds profiles, sessions, the credential store,
and the rendered contract.

## Why a whole copied preset

**Both** surfaces disable the model-facing rows on the host plane —
instructions, skills, shell and filesystem tools — and mount a per-session
*agent preset* instead. The Web bundle says so: *"the agent plane moves behind
agent presets … the Web surface disables them here and lets each session mount a
preset instead."* The TUI bundle mirrors it: *"the model-facing plugin set moves
INTO the agent-presets roster … so a minimal agent does not leak host-layer
tools."* The same preset therefore serves both, and the terminal profile was
verified to mount it rather than assumed to.

MCP clients register model-facing tools, so they belong in a preset. A row in
any host-plane patch connects its server and exposes nothing to the model. The
terminal profile's composed tree carries no MCP row at all, which is the
strongest form of that argument.

The two profiles select the preset on **different rows**, and this is the one
thing that does not survive copy-paste between them. The Web bundle mounts the
roster as `agent-presets`; the TUI bundle mounts its own as
`dsh-tui-agent-presets` and self-disables when an official row is already
present. A patch naming an id its profile lacks is skipped with a warning, so
the Web row dropped into the terminal profile would log `patch: entry
"agent-presets" not found` on every boot and silently fall back to `standard`.

Release candidate 0.1.5 has no preset inheritance: *"Authoring is copy-only …
there is no patch semantics at this layer to express 'standard plus one
change'."* So `presets/dotfiles/agent.cordis.yml` is a byte-for-byte copy of the
shipped `standard` composition with the MCP rows appended after a marker
comment. `scripts/harness-update.sh --only dsh --check` compares the copied
prefix against the installed `standard` and fails visibly when upstream moves
it. Refresh it deliberately, as part of a version bump, then re-append the MCP
block.

The snapshot region is delimited by one exact marker line, and everything before
it must be the installed `standard` byte for byte — which catches a shipped file
that grew, shrank, or changed anywhere. An earlier version compared the tracked
file's first N lines, N taken from the shipped file, and so silently accepted
upstream deleting rows from the end.

The preset gets its own id rather than reusing `standard`, because the shipped
root is scanned first and wins duplicate ids.

## MCP servers

Four servers, with the same pins the other five clients share. Bump all six
together.

| Server | Pin |
|---|---|
| Serena | commit `949a27ef1e5fda1a6e7b561e777bcece345c6ffd` |
| Context7 | `@upstash/context7-mcp@4.0.5` |
| Chrome DevTools | `chrome-devtools-mcp@1.8.0` plus both privacy flags |
| OpenDesign | `open-design-mcp` |

Tools reach the model as `mcp__<serverName>__<rawName>`.

**Every row sets `failOnStartupError: false`, and that uniformity is
deliberate.** Phase 1 proved a `true` row whose server cannot connect aborts the
whole profile at boot, so one unavailable MCP server would cost the entire
harness. No single outage may do that. The severity judgement lives in the daily
updater instead, where it can be made per server.
Serena, Context7 and Chrome DevTools are the core set, and losing one fails the
step; losing only OpenDesign is explicit and nonfatal. Resilient startup here,
honest reporting there.

OpenDesign is the row that is optional in practice as well: it only answers
while its loopback container runs, so start it with `open-design up`.

Startup and tool discovery have no DSH-owned timeout. The client's settings are
transport, server name, command, arguments, environment, working directory,
tool-call timeout, the startup-failure switch and the reconnect policy — and
`toolCallTimeoutMs` bounds tool calls only. Connecting and listing tools are
bounded solely by the MCP SDK's own 60-second request default. There is no knob
to turn.

Check any time, without calling a model:

```sh
node deepseek-harness/mcp-status.mjs
```

It prints a tool count or an explicit degraded reason per server, and exits
non-zero if any server is degraded. The rows are probed concurrently against one
shared deadline, so `--timeout-ms` bounds the whole run rather than each server.

**What the count proves.** It proves each server started and synchronized its
tool catalog — not that the thing behind the server is usable. Chrome DevTools
is the clearest case: pointed at a dead port it still completes initialize and
`tools/list` and advertises all 29 tools. So it stays in the core set, because
the server itself is reliable, but a green line says the tool catalog is
present, not that a browser is attached.

It probes the **live** preset at `~/.dsh/.agent-presets/dotfiles`, not the copy
in this repo, and refuses to report at all (exit 2) unless that path resolves
and matches the tracked file. Probing the repo copy would cheerfully report four
healthy servers while the harness mounted none, because the managed copy was
missing or carried something else. It also refuses (exit 2) when that path is a
symlink or any other non-regular file, because a link would compare byte-equal
to the tracked preset while aiming the live harness at this repo. Child processes get the harness's own
scrubbed environment — it imports `scrubbedParentEnv` from the pinned runtime
rather than reimplementing it — so a server that only works because your shell
exported a secret fails here exactly as it would in a session.

## Why pnpm is pinned here

`dsh plugin` forwards to whatever `pnpm` it finds on PATH, and pnpm is not a
preference here — it is the only installer that keeps **one** `@deepseek-ai`
plane. Both alternatives were measured against the exact versions this directory
pins:

| Shape | Result |
|---|---|
| TUI added to the runtime project (`npm`) | hard `ERESOLVE`, exit 1, no lock. npm enforces an optional peer's range whenever the peer is in the tree, and the umbrella's rc.2 plane cannot satisfy ranges capped at rc.1. Clearing it needs `--force` or `--legacy-peer-deps`. |
| TUI installed profile-locally with `npm` | exits 0, and that is the trap: it silently materialises a 13-package `0.1.0-rc.8` second plane in the profile, including `cordis`, `dsh-agent`, `dsh-llm` and `dsh-session`. |
| TUI installed profile-locally with `pnpm`, `autoInstallPeers: false` | 73 packages linked on darwin-arm64, **zero** `@deepseek-ai`. The lock holds 98 entries; the rest are other platforms' optional binaries. |

Two copies of a plane package mean two Cordis and plugin class identities in one
process: double registration, and failures that look like anything but a
packaging problem. That is why `autoInstallPeers: false` is copied verbatim from
the shipped template and must never be flipped to silence a peer warning, and
why both `./install` and the daily updater fail outright on a single
`@deepseek-ai` package in the profile or in the pnpm prefix.

The helper lives in `pnpm/` as a tool-only project with its own lock, integrity
hashes and `strict-allow-scripts` guard. pnpm's own lifecycle scripts are
**denied**: they exist to swap a shipped placeholder for the native binary, and
pnpm's `install.js` documents that with scripts blocked the placeholder stays
and `bin/pnpm.mjs` runs the same native binary — which arrives as a locked
optional dependency, not a download. Corepack enters through that same file for
the same reason. `./install` generates a one-line shim onto it, and `bin/dsh`
puts that shim's directory on PATH for `dsh plugin` and for nothing else.

## Installing and reinstalling

`./install` does this in an order that matters:

1. Creates `~/.dsh` **before** the contract render, because the renderer skips
   an identity directory that does not exist, and `~/.dsh/AGENTS.md` is its
   seventh target. It also creates `~/.dsh/.agent-presets`, which the harness
   itself never creates.
2. Copies `.npmrc`, `package.json`, and `package-lock.json` into
   `~/.local/share/dsh` and runs `npm ci` there. They are **copied, not
   linked**: npm writes into its project directory, and a symlink would let it
   write through into this repo. Success is recorded in a `.npm-ci-ok` stamp
   holding a fingerprint of those three inputs, cleared before the attempt and
   written only after it succeeds. Without it a failed install would leave a
   partial `node_modules` that looks complete to the next run, and the repair
   would never happen.
3. Installs the pinned pnpm into its own prefix, `~/.local/share/dsh-pnpm`,
   with its own `.npm-ci-ok` stamp. Separate from the runtime on purpose: the
   official graph has to stay byte-identical to what it was gated against.
4. Runs `dsh --profile web --dump-config` once so the harness builds
   `~/.dsh/profiles/web` itself, then refuses to continue if that directory is
   missing.
5. Provisions `~/.dsh/profiles/dsh-tui` from its three tracked inputs and runs
   `pnpm install --frozen-lockfile` there. `dsh-tui` is not a shipped template,
   so nothing materialises it the way step 4 materialises `web` — those files
   *are* the profile. The step then fails outright if a single `@deepseek-ai`
   package appears in that `node_modules`.
6. Only then installs the home patch into `~/.dsh`, each profile patch into its
   own profile, and the preset into `~/.dsh/.agent-presets`. Doing it earlier
   would let Dotbot create a plain directory where the harness needs its own
   tree.

Patch files are written **atomically** — a temp file in the same directory, then
`mv`. Both profiles use `patchReload: live`, so DSH watches these files and
recomposes the running tree when one changes; a plain `cp` can hand that watcher
a half-written YAML document.

Both are **managed copies, never symlinks**, for the same reason the npm inputs
are copied and one that is stronger: a link there aims the harness at this
working tree, so anything writing through it — the Web UI's own edit surfaces, a
future copy-a-preset call, a half-written file — lands in the repo. Copying onto
a symlink writes through it, so an existing link is removed before the copy
rather than overwritten. The preset directory is mirrored in both directions, so
a file retired from this checkout is removed from the runtime copy instead of
being quietly composed. Drift is shown before it is replaced, and
`scripts/harness-update.sh --only dsh --check` reports a runtime copy that
differs from its tracked original, or has become a symlink again.

To reinstall the runtime by hand:

```sh
cd ~/.local/share/dsh && npm ci
```

### The lifecycle-script policy

This machine runs npm with `strict-allow-scripts=true`, so an install fails
closed until every package with install scripts is explicitly reviewed. Five
qualify here:

| Package | Decision | Why |
|---|---|---|
| `koffi@3.2.1` | allow | Native FFI build |
| `node-pty@1.2.0-beta.15` | allow | Native PTY, required by the shell tools |
| `@deepseek-ai/dsh-subprocess-local@0.1.5-rc.2` | allow | The harness's own spawn helper |
| `@google/genai@1.52.0` | deny | The script is literally `echo 'preinstall: no-op'` |
| `protobufjs@7.6.6` | deny | Not needed by this install |

The decisions live in `package.json`, and that placement is forced: npm's
`.npmrc` `allow-scripts[]` list can only ever **allow**, while a **deny** is
expressible only as a `package.json` `allowScripts` boolean. Precedence is CLI,
then `package.json`, then `.npmrc`, and the first layer with any value wins
outright for the whole install.

The practical consequence is why this is a project and not a global install:
`npm install -g` never reads a project `package.json`, so under a global install
the minimum policy cannot be expressed at all and both no-op packages would have
to be allowed. `~/.npmrc` stays unmanaged, and the global guard is never
disabled. Prove the guard comes from this project rather than the machine:

```sh
cd ~/.local/share/dsh && npm config get strict-allow-scripts --userconfig /dev/null   # -> true
```

## Contract and skills

Both discovery paths are the harness's own defaults, so nothing custom is
configured:

- `~/.dsh/AGENTS.md` is the user-global instruction file. It is **generated** by
  `scripts/render-contract.sh` as the seventh target; editing it is pointless
  because the next `./install` overwrites it. Edit `shared/AGENTS.md`.
- `~/.agents/skills` is the shared skill root, the same one Codex uses. There is
  no second skill tree.

## Updating

```sh
scripts/harness-update.sh --only dsh --check
```

`dsh` is check-only in both modes; the updater never upgrades a developer
preview on its own — neither the release candidate nor the TUI. It reports the
pinned release candidate, the pinned pnpm and the pinned TUI version, whether
each runtime copy still matches its tracked source, whether the managed preset
still matches the installed `standard`, and the per-server MCP status. It also
fails on a single `@deepseek-ai` package in the TUI profile or the pnpm prefix.

It then composes every shipped profile and checks what came out. Both home-layer
rows must appear exactly once in `dsh-tui`, `web`, `headless`, `acp` and `sdk`,
each with empty stderr: the OpenRouter route, and the preset default a fresh
agent starts on. Counting only the route was not enough — the pilot shipped for
a day with the route composed on all five surfaces and every fresh agent still
selecting `deepseek-official`, which is a state every static check calls
healthy.

`sdk-minimal` is the deliberate exception: it is the one shipped template built
without `dsh-base`, so it has neither row for the home layer to target and emits
exactly two warnings —

```
dsh: [~/.dsh/cordis.patch.yml] patch: entry "llm-pi-ai" not found
dsh: [~/.dsh/cordis.patch.yml] patch: entry "agent-default-model" not found
```

Both lines are pinned by text, each expected exactly once. *Changed* text across
the same two lines is reported as DEGRADED with the lines quoted; a third line,
a missing one, the same warning twice, an unexpected route or default count, or
any warning on the other five profiles is a failure. The patch format has no
optional target — a non-insert patch whose id matches nothing always warns — so
this is pinned rather than engineered away.

To bump deliberately: edit the version in `package.json`, run
`npm install --package-lock-only` here, re-run `./install`, refresh the preset
copy against the new shipped `standard`, and re-verify. For the TUI, edit
`profiles/dsh-tui/package.json`, regenerate `pnpm-lock.yaml` with the pinned
pnpm, and re-run every gate — it is community code with host authority, so a
version bump is a review, not a chore.

Pinning the umbrella package is weaker than it looks. Under `0.1.5-rc.1` several
agent-plane packages resolve at `0.1.5-rc.2` — the MCP client, the skill
scanner, the instruction loader, and the preset roster among them. Only the
committed lockfile pins those, which is why it is tracked.

## Rolling back

Stop the server, then remove the managed copies by explicit path:

```sh
rm -r ~/.dsh/cordis.patch.yml ~/.dsh/profiles/web/cordis.patch.yml \
      ~/.dsh/profiles/dsh-tui ~/.dsh/.agent-presets/dotfiles \
      ~/.local/bin/dsh ~/.local/share/dsh-pnpm
```

Sessions record the preset they were composed from, so removing the preset while
keeping `~/.dsh` means those sessions will no longer resume. Remove
`~/.local/share/dsh` only for a full uninstall. `~/.dsh` is preserved by default
because it holds sessions and credentials; once it is gone, the contract
renderer reports the seventh target as skipped, which is the intended behaviour
for an optional identity.

Rollback and runtime uninstall also preserve `~/.dsh-tui`, including terminal
history, the session index, and saved preferences. To remove that TUI state as
well, stop the TUI and server, then explicitly remove `~/.dsh-tui`; this
irreversibly deletes those local records.
