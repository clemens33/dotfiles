// Bounded, model-free status probe for the MCP servers the harness will
// actually mount.
//
// DSH rc.1 ships no health command and no API that lists MCP tools without a
// session, so this reads the preset, starts each configured server the same way
// the harness would, and reports how many tools it synchronizes.
//
// It answers one question: would each row give the model its tools right now.
// It never calls a model and never touches credentials.
//
// Usage:  node deepseek-harness/mcp-status.mjs [--timeout-ms N] [--json]
// Exit:   0 every row reachable · 1 one or more degraded · 2 cannot probe
//
// --timeout-ms bounds the WHOLE run, not each server: the rows are probed
// concurrently against one shared deadline, so the command cannot take longer
// than the budget however many rows the preset carries. A cold machine
// resolving four npx/uvx packages at once needs a larger budget than a warm
// one, which is why the updater passes an explicit value.
//
// A degraded row is NOT a harness failure. OpenDesign in particular only
// answers while its loopback container runs, which is why its preset row sets
// failOnStartupError:false — the harness boots without it and loses that
// server's tools, nothing more.

import { createRequire } from 'node:module'
import { lstatSync, readFileSync, realpathSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const TRACKED_PRESET = join(HERE, 'presets', 'dotfiles', 'agent.cordis.yml')
const PREFIX = process.env.DSH_PREFIX || join(process.env.HOME ?? '', '.local', 'share', 'dsh')
const DSH_HOME = process.env.DSH_HOME || join(process.env.HOME ?? '', '.dsh')
// The path DSH itself scans. Probing the repo copy instead would happily report
// four healthy servers while the harness mounts none, because the managed copy
// is missing or carries something else.
const LIVE_PRESET = join(DSH_HOME, '.agent-presets', 'dotfiles', 'agent.cordis.yml')

const args = process.argv.slice(2)
const asJson = args.includes('--json')
const timeoutIndex = args.indexOf('--timeout-ms')
const TIMEOUT_MS = timeoutIndex === -1 ? 30000 : Number(args[timeoutIndex + 1])

const die = (code, ...lines) => {
  for (const line of lines) process.stderr.write(`mcp-status: ${line}\n`)
  process.exit(code)
}

if (!Number.isFinite(TIMEOUT_MS) || TIMEOUT_MS <= 0) {
  die(2, '--timeout-ms needs a positive number')
}

// Everything comes from the pinned runtime rather than a global install, so
// this probe speaks the same protocol version as the harness AND scrubs the
// child environment with the harness's own definition.
let yaml
let Client
let StdioClientTransport
let scrubbedParentEnv
try {
  const require = createRequire(join(PREFIX, 'package.json'))
  yaml = require('js-yaml')
  ;({ Client } = await import(
    new URL(`file://${join(PREFIX, 'node_modules/@modelcontextprotocol/sdk/dist/esm/client/index.js')}`)
  ))
  ;({ StdioClientTransport } = await import(
    new URL(`file://${join(PREFIX, 'node_modules/@modelcontextprotocol/sdk/dist/esm/client/stdio.js')}`)
  ))
  // The single source of truth for what a harness child may inherit: it drops
  // anything matching KEY|PASSWORD|SECRET|TOKEN and every DSH_* name, while
  // keeping PATH, HOME, locale and proxy settings. Importing it — rather than
  // reimplementing it — is what keeps this probe honest about what the harness
  // really hands its servers.
  ;({ scrubbedParentEnv } = await import(
    new URL(`file://${join(PREFIX, 'node_modules/@deepseek-ai/dsh-subprocess/lib/index.js')}`)
  ))
} catch (err) {
  die(
    2,
    `runtime prefix not usable at ${PREFIX}`,
    err.message,
    'run ./install to provision it',
  )
}

if (typeof scrubbedParentEnv !== 'function') {
  die(2, 'the pinned runtime does not export scrubbedParentEnv - refusing to guess')
}

// The composition carries `!!js` gate expressions. They are irrelevant here —
// no MCP row uses one — but the parser still has to accept the tag.
const schema = yaml.DEFAULT_SCHEMA.extend([
  new yaml.Type('tag:yaml.org,2002:js', { kind: 'scalar', construct: (data) => ({ js: data }) }),
])

// Probe the LIVE preset, and refuse to report at all unless it is the managed
// one. A drifted or hand-edited live preset means these numbers would not
// describe what the harness mounts.
let livePreset
let trackedPreset
// A symlink compares byte-equal to the tracked file and is still wrong: every
// managed input is a COPY on purpose. DSH reloads these files live, so a link
// would publish a half-finished repo edit straight into a running harness, and
// the comparison below would report the repo to itself. Reject the shape before
// reading anything, and do it with lstat so the link itself is what is stat'd.
let liveStat
try {
  liveStat = lstatSync(LIVE_PRESET)
} catch (err) {
  die(
    2,
    `the harness does not have the managed preset at ${LIVE_PRESET}`,
    err.message,
    'run ./install to place the managed copy',
  )
}
if (liveStat.isSymbolicLink()) {
  let target = '(unresolvable)'
  try {
    target = realpathSync(LIVE_PRESET)
  } catch {
    /* dangling link; the message is about the shape, not the target */
  }
  die(
    2,
    `the live preset at ${LIVE_PRESET} is a symlink, not a managed copy`,
    `it resolves to ${target}`,
    'managed inputs are copies because DSH reloads them live - a link would',
    'republish an in-progress edit into a running harness',
    'remove it and run ./install to place the managed copy',
  )
}
if (!liveStat.isFile()) {
  die(
    2,
    `the live preset at ${LIVE_PRESET} is not a regular file`,
    'remove it and run ./install to place the managed copy',
  )
}
try {
  livePreset = readFileSync(LIVE_PRESET, 'utf8')
} catch (err) {
  die(2, `cannot read the live preset at ${LIVE_PRESET}`, err.message)
}
try {
  trackedPreset = readFileSync(TRACKED_PRESET, 'utf8')
} catch (err) {
  die(2, `cannot read the tracked preset at ${TRACKED_PRESET}`, err.message)
}
if (livePreset !== trackedPreset) {
  let resolved = LIVE_PRESET
  try {
    resolved = realpathSync(LIVE_PRESET)
  } catch {
    /* the read above succeeded, so this only fails on a race; keep the path */
  }
  die(
    2,
    'the live preset does not match the tracked one - these numbers would not',
    `describe what the harness mounts. live: ${resolved}`,
    `tracked: ${TRACKED_PRESET}`,
    'run ./install, or reconcile the two deliberately',
  )
}

let rows
try {
  const doc = yaml.load(livePreset, { schema })
  if (!Array.isArray(doc)) throw new Error('composition is not a top-level list')
  rows = doc.filter((row) => row && row.name === '@deepseek-ai/dsh-mcp-client')
} catch (err) {
  die(2, `cannot parse ${LIVE_PRESET}: ${err.message}`)
}

if (rows.length === 0) {
  die(2, 'the preset configures no MCP servers')
}

// One deadline for the whole run, shared by every row. Racing each row against
// its own timer would let a preset of four rows take four timeouts; racing them
// all against this one caps the command at the budget the caller asked for.
const deadline = new Promise((_, reject) =>
  setTimeout(() => reject(new Error(`timed out after ${TIMEOUT_MS}ms`)), TIMEOUT_MS).unref(),
)
// Nothing may be racing it at the moment it fires, and an unobserved rejection
// is a warning on stderr that would look like a probe failure.
deadline.catch(() => {})

const probe = async (row) => {
  const { serverName, command, args: argv = [], env = {} } = row.config ?? {}
  const started = Date.now()
  const transport = new StdioClientTransport({
    command,
    args: argv,
    // Exactly the harness's own buildChildEnv: the scrubbed parent environment
    // with the row's explicit env merged on top. A probe that forwarded the
    // full environment would pass when the harness would not, and would leak
    // this shell's secrets into every server it starts.
    env: { ...scrubbedParentEnv(), ...env },
    stderr: 'ignore',
  })
  const client = new Client({ name: 'dotfiles-mcp-status', version: '1.0.0' }, { capabilities: {} })
  try {
    await Promise.race([client.connect(transport), deadline])
    const listed = await Promise.race([client.listTools(), deadline])
    return { serverName, ok: true, tools: listed.tools.length, ms: Date.now() - started }
  } catch (err) {
    return { serverName, ok: false, reason: err.message, ms: Date.now() - started }
  } finally {
    await client.close().catch(() => {})
    await transport.close().catch(() => {})
  }
}

// Concurrent, but reported in preset order: Promise.all resolves positionally,
// so the output is the same whichever server answers first. Deterministic
// output is what lets the updater classify a line by server name.
const results = await Promise.all(rows.map(probe))

if (asJson) {
  process.stdout.write(`${JSON.stringify({ prefix: PREFIX, preset: LIVE_PRESET, results }, null, 2)}\n`)
} else {
  for (const r of results) {
    if (r.ok) {
      process.stdout.write(`mcp ${r.serverName} OK ${r.tools} tool(s) in ${r.ms}ms\n`)
    } else {
      process.stdout.write(`mcp ${r.serverName} DEGRADED ${r.reason}\n`)
    }
  }
}

// A stuck child must not hold the probe open after its verdict is printed.
process.exit(results.every((r) => r.ok) ? 0 : 1)
