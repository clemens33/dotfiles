---
name: arch-docs
description: >
  Write and maintain living architecture documentation (arc42-lite, C4 via Mermaid): what the
  system is, how it is composed and runs, its trust boundaries and invariants. Use when the user
  asks to document the architecture, create or update arch docs, or write ARCHITECTURE.md. Not
  for frozen decisions (use `adr`) or agent orientation (CLAUDE.md / AGENTS.md).
metadata:
  category: preference

---

# Arch Docs

Living architecture documentation. Describes the *current* system: what
exists, how it's composed, how it runs, what trust boundaries it has, and
what invariants must not break. Evolves with the code. Reviewable in PRs.

It is not an ADR (frozen decisions and rationale: link, don't duplicate),
not agent orientation (`CLAUDE.md` / `AGENTS.md` say how to *work in* the repo,
arch docs say what the system *is*), and not a tutorial or how-to (Diátaxis
Explanation + Reference; tutorials and runbooks live elsewhere).

## When to use

- A repo has no architecture documentation and the system is non-trivial
  (more than a single file or single-purpose CLI)
- An existing arch doc is stale (`arch:watch` paths have moved on, or
  prose references files that no longer exist)
- A new subsystem/bounded context just stabilized and deserves an L3 zoom
- A trust boundary, deployment topology, or external integration changed

## Process

### Step 1: Detect convention and recon evidence

Detect existing docs setup:

1. Check the repo for **explicit conventions** first — `CONTRIBUTING.md`,
   `AGENTS.md`, `CLAUDE.md`, `docs/AGENTS.md`, `mkdocs.yml`,
   `docusaurus.config.*`. If they prescribe a docs layout, follow it.
2. Look for existing architecture docs in this order. **Do not treat
   bare `docs/` as the arch-doc root** — it usually holds product docs,
   API reference, or generated site sources, and writing into it
   blindly will corrupt unrelated content.
   - `docs/architecture/` (most common)
   - `docs/arch/`
   - `architecture/`
   - top-level `ARCHITECTURE.md`
   - Inside `docs/`, look only for architecture-named entries:
     `docs/architecture.md`, `docs/system-design.md`,
     `docs/system-overview.md`. Other `docs/` subdirectories are not
     architecture docs unless explicitly named.
3. If both `docs/architecture/` and top-level `ARCHITECTURE.md` exist,
   treat the top-level as an entry point unless it clearly is the live
   doc.
4. **Never write to** generated/build folders: `site/`, `public/`,
   `dist/`, `build/`, `.docusaurus/`, `_site/`, `node_modules/`.
5. Default fallback (no convention, no existing docs): create
   `docs/architecture/README.md` and, when warranted,
   `docs/architecture/subsystems/<name>.md`.

Recon the actual code/config before writing:

- List the subsystems / packages / modules at the repo top level
- Find the deployment manifests (Dockerfile, k8s/Helm, `serverless.yml`,
  `*.tf`, `compose.yml`)
- Find the entry points (`main.py`, `index.ts`, `cli.py`, `cmd/`)
- Find external integrations (HTTP clients, SDK imports, MCP servers,
  message queues, databases)
- Find the auth/trust boundaries (auth middleware, JWT verification, CORS
  config, network policies)

### Step 2: Decide doc shape

Pick the smallest shape that fits:

- **Overview only** — one `README.md` (or `ARCHITECTURE.md`). Default for
  small/medium repos, libraries, single-service apps.
- **Overview + subsystems** — when the system has 2+ stable bounded
  contexts that each warrant their own L3 zoom. Subsystem files live in
  `docs/architecture/subsystems/<name>.md`.
- **Overview + invariants** — add `docs/architecture/invariants.md` (or
  preserve an existing `agent-context.md`) when there are repo-wide rules
  that aren't obvious from grepping the code (cache TTLs, ordering
  guarantees, idempotency contracts, regulatory invariants).

Subsystem rule: a subsystem doc maps to a **bounded context / ownership
boundary**, not mechanically to a C4 Container. One deployable can host
several subsystems; one subsystem can span multiple deployables. Create a
subsystem doc only when the L3 component zoom is non-obvious AND the
overview's L2 view doesn't carry it.

### Step 3: Write or update the docs

Use the templates in `references/templates.md` (overview, subsystem, invariants) as the
starting point. Adapt sections to what the repo actually has — don't
invent sections you can't fill with real content.

If updating an existing doc, **preserve its current structure** unless
the user explicitly asks to restructure. Match the existing tone and
section names.

### Step 4: Add `arch:watch` markers and run staleness check

Every architecture doc gets a marker at the bottom listing the source
paths it documents:

```markdown
<!-- arch:watch
- src/orders/service/**
- src/orders/resource/**
- dev.config.yaml
- helm/values.yaml
-->
```

Globs and directories are allowed. Watch the **smallest set** that, if
changed, would invalidate the doc.

Staleness check (run on every invocation in a repo with existing arch
docs, over the whole file, not only the section you touched):

1. **Soft signal — git history.** For each doc, compare the last commit
   touching any watched path vs the last commit touching the doc. If
   watched paths moved on, warn.

   For each entry in `arch:watch`:

   a. **Literal path or directory** (e.g. `dev.config.yaml`,
      `src/orders/service`):
      ```bash
      git log -1 --format=%ct -- <path>
      ```

   b. **Glob pattern** (e.g. `src/orders/service/**`,
      `helm/values-*.yaml`): expand against tracked files first, then
      compare. Don't pass globs directly to `git log` — shell expansion
      is unreliable.
      ```bash
      git ls-files -- 'src/orders/service/**'
      # then run git log against the resulting list, or against the
      # common parent directory:
      git log -1 --format=%ct -- src/orders/service
      ```

   c. **Watched path that doesn't match any tracked file**: report as
      `arch:watch entry "<pattern>" matched no tracked files` — likely
      stale marker (path was renamed/deleted). Don't silently skip.

   d. **Untracked watched path that exists on disk** (e.g. a generated
      file watched intentionally): report as `untracked watched path,
      git history unavailable` — exclude from the timestamp comparison
      but acknowledge in the report.

   Then compare the doc's last commit time:
   ```bash
   git log -1 --format=%ct -- docs/architecture/README.md
   ```

   Warn (don't block) when any watched path's last-commit time is more
   recent than the doc's last-commit time.

   Do **not** use filesystem mtimes — they break on clone, checkout,
   rebase, branch switches, and shallow clones.

2. **Hard signal — broken references.** Scan the doc's prose and Mermaid
   diagrams for references that no longer exist:
   - **Path references** (any token matching a file path pattern, e.g.
     `src/orders/foo.py`, `docs/adr/0007-*.md`): use `git ls-files`
     to verify each path exists. Hard-flag missing paths.
   - **Service / component references** (a node in a diagram that isn't
     a path): require the node to be evidenced by one of:
     deployment manifests (`*.yaml` in `k8s/`/`helm/`/`compose*.yml`),
     a package/workspace name in `package.json`/`pyproject.toml`/
     `Cargo.toml`, an entrypoint module, an SDK import (`import
     anthropic`, `boto3.client('s3')`), an env var key (`STRIPE_KEY`),
     or explicit user input. If a node has no such evidence, flag as
     "unverified component" — either label it `external` and tie to
     its evidence (SDK/env/config), or remove it.

   Hard signals require fixing the doc or escalating to the user — they
   indicate real rot, not just timing drift.

### Step 5: Validate and report

Before finishing:

- Validate Mermaid in this order; report which level was reached:
  1. If `mmdc` (mermaid-cli) is on PATH, render each block to a temp
     file. Hard-flag syntax errors.
  2. Else if a docs build exists and renders Mermaid (MkDocs with
     `mermaid2`, Docusaurus, etc.) and runs in under ~30s, run it.
  3. Else fall back to static checks: every fenced block opens with
     ` ```mermaid` and closes; no `LR`/`TD`/`BT` direction in
     `sequenceDiagram` blocks (sequence diagrams ignore those — see
     `viz` skill); each `flowchart` declares a direction.
- Check that every path mentioned in `arch:watch` actually exists (or
  matches a tracked file via `git ls-files` for globs)
- If the repo has a docs build (MkDocs, Docusaurus), suggest running it;
  don't run it automatically unless trivially fast
- Report:
  - Files created/updated
  - Watched paths and any stale warnings
  - Suggested next steps (link from `AGENTS.md`/`README.md`, link related
    ADRs, MkDocs nav update if applicable)
  - Anything you couldn't validate

Committing follows the repository's standing authorization, not a rule in
this skill. If the session or the repo's `AGENTS.md` / `CLAUDE.md` already
authorizes committing completed work, commit the docs you wrote and say so in
the report. Otherwise leave them uncommitted and report the proposed message.
Stage only the files this skill created or updated — never the user's
unrelated work in progress.

## Templates (read on demand)

`references/templates.md` holds the overview template (`README.md` / `ARCHITECTURE.md`), the subsystem template (`subsystems/<name>.md`), the invariants template (`invariants.md`) and the `### AI architecture` section skeleton, with their size targets and library/no-deployment escapes. Read it before writing or restructuring any architecture doc; the Rules below keep the limits and the escape wording so a doc can be reviewed without it.

## Optional addendum: AI systems

Opt-in. Add an `### AI architecture` section to the overview (skeleton in
`references/templates.md`) only when recon finds at least one strong signal
or two weak ones. For non-AI repos it is noise.

**Strong signals (one is enough):**
- LLM/agent SDK imports: `anthropic`, `openai`, `litellm`, `langchain`,
  `langgraph`, `@anthropic-ai/sdk`, `openai-agents`, `instructor`
- An MCP config file: `mcp.json`, `.mcp.json`
- A `.github/agents/`, `agents/` directory with `*.agent.md` files, or
  a `skills/` directory with `SKILL.md` files
- Langfuse, Helicone, Arize Phoenix, or W&B Weave SDK imports
- A model gateway or router (e.g. LiteLLM proxy, Bedrock/Vertex SDKs in
  inference-path code, not just infra)

**Weak signals (need two together):**
- A `prompts/` directory or `*.prompt.md` files (could be UI/shell
  prompts in non-AI repos)
- Mentions of "agent", "tool calling", "retrieval", "embedding" in code
  comments or docs
- A vector DB client (`pinecone`, `weaviate`, `qdrant`, `chroma`,
  `pgvector`)

The word "prompt" alone is not a signal: generic prompt files in shell tools,
UI code, or documentation do not make a repo an AI system.

## Mermaid conventions for arch-docs

(See the `viz` skill for full technique.)

- Use **`flowchart` with `subgraph`** for C4 diagrams. Mermaid has a C4
  beta syntax — don't use it unless the repo already does. Flowchart is
  more portable and widely renderable.
- Label every edge with the protocol or intent (`HTTPS`, `SQL`,
  `enqueue`, `OIDC`).
- Mark trust boundaries with `subgraph` named after the boundary
  (e.g. `subgraph dmz [DMZ]`, `subgraph internal [Internal network]`).

## Rules

- **Code is truth.** If the doc contradicts the source, fix the doc or
  supersede it. Never the other way around.
- **Evidence-backed.** Every node, edge, and prose claim traces to a
  real file, service, or config. No invented infrastructure. List the files
  you inspected when reporting.
- **Current state only.** Planned features go to roadmap or scope
  documents, not architecture docs. If documenting a migration in
  progress, label `Current` and `Target` explicitly.
- **Lean by default.** Overview ~200 lines (350 hard cap). Subsystems
  ~150 (250 hard cap). Diagrams ≤15 nodes (more means the wrong zoom
  level: split). Runtime scenarios ≤3. Split a growing doc by bounded context.
- **Include diagrams by default.** L1 (or Consumer Context for
  libraries), L2, Deployment (when applicable), and up to 2-3 sequence
  diagrams for critical flows. Per `viz` skill rules. Library/SDK
  escapes (`No L1: library package`, `No deployment view`) defined in
  the overview template (`references/templates.md`) are valid; use them, don't ignore them.
- **ADR linkage rule.** Link related ADRs; do not repeat the decision
  rationale. If current architecture contradicts an Accepted ADR, flag
  it and suggest a superseding ADR.
- **Status field discipline.** A doc is `Current`, `Migrating to X`, or
  `Stale`. If you can't honestly mark it `Current`, fix it or note the
  gaps.
- **Do not leak topology in public docs.** Internal hostnames, IPs,
  network ranges and customer flows in a public README are a security
  smell.
- **No AI/co-author trailers** in commits or files.

## Anti-patterns

- **Auto-generated UML/class diagrams from code.** Nobody reads them,
  they don't capture what matters. Reference OpenAPI/protobuf specs,
  don't dump them inline.
- **Architecture-as-wiki.** Docs that read like a tour ("first this
  happens, then that…") instead of a reference. Architecture docs are
  for skimming and lookup, not narrative.
- **Diagram spam.** A diagram per paragraph. Use a diagram when it
  carries information prose can't.
- **Documenting trivial structure.** "The `utils/` folder contains
  utility functions" — not architecture, just labels.

## Boundary with other skills

- **`adr`**: frozen decisions and why they were made. Link from arch
  docs. If architecture contradicts an Accepted ADR, that's an
  ADR-superseding event.
- **`viz`**: Mermaid technique. arch-docs is the *what to draw* and
  *where it lives*; viz is the *how to draw it*.
- **`scope`**: implementation plan for upcoming work. arch-docs is
  current state: a scoped change can refer to arch docs as "current" and
  describe the "target", and the arch docs update happens after the change
  ships.
- **`init` / `CLAUDE.md` / `AGENTS.md`**: agent orientation. `AGENTS.md`
  may link to `docs/architecture/README.md` as a one-line "see also".
  arch-docs should not rewrite agent instructions.

## Notes on detection edge cases

- If a repo already has a docs framework (MkDocs, Docusaurus,
  Read the Docs), respect its file layout. Suggest a nav update only
  if the framework already uses a manual nav. Never introduce a docs
  framework as part of this skill.
- If `ARCHITECTURE.md` exists at the repo root and is short, update
  it in place. If it's already large, suggest splitting into
  `docs/architecture/` rather than letting it grow.
- If a repo's existing arch docs use a different framework (4+1,
  Nygard, freeform prose), match that style — don't impose
  arc42-lite. The skill's job is to make the docs better, not to
  migrate frameworks.
- If the user has only one application file (e.g. a single-script CLI
  tool), the architecture doc is the README. Don't create
  `docs/architecture/` for trivial repos.
