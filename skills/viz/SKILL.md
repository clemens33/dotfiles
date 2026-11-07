---
name: viz
description: >
  Add Mermaid diagrams to markdown (ADRs, architecture overviews, READMEs,
  runbooks, design notes) where they render inline and diff cleanly. Also the
  recipe for a compact self-contained HTML report or visual for the human.
  Use when a diagram belongs inside a versioned text document, or when
  findings for the human are substantial (structure, flow, comparison,
  numbers). Not for editable .drawio canvases, hand-placed layout,
  slide-ready export, or PM artifacts such as WBS, Gantt or RACI.
metadata:
  category: capability

---

# Viz

Lightweight visualization for markdown documentation. Mermaid is the default: it renders natively on GitHub/GitLab, lives inside the markdown, and is easy for humans and agents to edit.

## When to use

- Adding a diagram inside an ADR, architecture overview, README, or runbook
- Sketching a quick flow during a design discussion
- Replacing prose paragraphs that describe structure or sequence with a diagram
- Anywhere the diagram needs to live next to the text, be diff-able, and survive without a toolchain

When **not** to use Mermaid:

- Pixel-perfect layout matters (a slide deck, a vendor pitch) → not Mermaid's job (hand-placed layout)
- The visualization is data-driven (charts, dashboards) → not Mermaid's job
- The diagram would expose secrets, internal hostnames, private network ranges, customer-identifying flows, or non-public topology — unless the doc is explicitly internal. Diagrams leak structure more visibly than prose; treat them with the same care as logs.

## Pick the right diagram type

Match the *thing being shown* to the diagram type:

| You are documenting… | Use | Mermaid keyword |
|---|---|---|
| System / service / module boundaries | C4 Container or Component | `flowchart` with `subgraph` |
| Deployment / runtime topology (k8s, cloud, network zones) | C4 Deployment-style | `flowchart` with nested `subgraph` |
| Request / RPC / async message flow | Sequence | `sequenceDiagram` |
| Lifecycle, state machine, status transitions | State | `stateDiagram-v2` |
| Data model, entities, relationships | ER | `erDiagram` |
| Branching control flow, decision tree | Flowchart | `flowchart` |
| Class hierarchy, interfaces, inheritance | Class | `classDiagram` |
| Project timeline, milestones (in-doc only; PM/deck Gantt is out of scope) | Gantt | `gantt` |
| Branching / release strategy | Git graph | `gitGraph` |
| User journey, UX flow | Journey | `journey` |

If you can't decide between flowchart and sequence: **flowchart for static structure, sequence for what happens over time**.

## C4 model — the framework, not the tool

C4 picks the *zoom level*; it is not a Mermaid alternative. Use it to decide what is in your diagram:

1. **System Context** — your system + external actors and systems. One box for "us". Use sparingly; usually obvious.
2. **Container** — runnable units inside your system: services, databases, queues, frontends. **This is where most ADR diagrams live.**
3. **Component** — pieces inside a single container. Useful when an ADR is about an internal boundary.
4. **Code** — class diagrams. Rarely worth drawing — read the code.

When in doubt for an ADR, draw the **Container** level. It captures the "what talks to what and how" that decisions usually hinge on.

## Syntax rules that bite

- Sequence diagrams take no `LR`/`TD`/`BT` direction. Their layout follows the **declaration order** of `actor`/`participant` (left to right).
- Direction modifiers are for `flowchart` only: `TD`/`TB` (top-down), `LR` (left-right), `BT`, `RL`. Prefer `LR` for request flows and `TD` for hierarchies and decision trees.

## Reports for the human (read on demand)

For substantial content for Clemens (structure, flow, comparison, numbers), a Mermaid block in a markdown file is the wrong delivery: he cannot render it in chat. Read `references/human-report.md` before building the file. It covers the visual, the layout, the self-contained offline file, rendering the diagram instead of sending Mermaid source, and the hand-over message.

## Templates and syntax reference (read on demand)

`references/templates.md` holds Mermaid skeletons (container, sequence, state, ER, flowchart), the fenced-block embedding snippet and a keyword cheat sheet. Read it for a starting skeleton or a syntax reminder; the table, C4 levels and rules here are enough to choose and review a diagram.

## Rules

- **Diagram before prose, not after.** If you wrote three paragraphs about what calls what, replace them with a Container diagram.
- **Label the edges.** The arrow direction is the easy part — the *kind* of call (HTTP/gRPC/queue/SQL) is what readers come for.
- **One concept per diagram.** Don't combine a sequence diagram with a state machine because they share an actor.
- **Keep it small.** Past 15 nodes the diagram is already wrong — split it, use C4 zoom levels, or move detail into prose.
- **Match the diagram to the doc's lifespan.** ADRs live forever; don't put per-deploy specifics inside one.
- **No decoration.** Colors, fonts, line styles encode meaning or are not used. Mermaid's defaults are fine.

## Anti-patterns

- **Inventing components, services, or protocols not evidenced by the repo or conversation.** A diagram that "looks plausible" but adds a fictional cache layer or message queue is worse than no diagram. Verify every node and edge against actual code or explicit user input before drawing it.
- ASCII art for diagrams that should be Mermaid (it doesn't render, doesn't scale, and is harder for agents to update)
- Diagrams that just rephrase the surrounding text (the diagram should carry information the prose doesn't)

## Boundary with other skills

- **`adr`**: ADRs should include at least one diagram by default. This skill is the technique; ADR is the container.
- **`scope`**: scoping output is text-first. Add a diagram only when the phases or change surface span multiple systems.
