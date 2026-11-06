# Human report — visual first, one file, little text

Read this when you deliver substantial content to Clemens: structure, flow, architecture, a comparison of options, numbers or trends, or more than about one screen of prose. The rule itself is in the always-loaded contract ("Reports to Clemens"). This file is the recipe.

Deliver two things: 2-5 lines of text that give the whole answer, and ONE self-contained local file with its absolute path. A reader on a phone, who cannot open the file, must still get the answer from the text. The file is the extra for later reading in a desktop browser. Do not publish it to a hosted page (claude.ai, ChatGPT or similar) and do not send the file. A routine short answer needs neither.

## Pick the form

| Content | Visual |
|---|---|
| Structure, flow, architecture, sequence | Diagram as inline SVG (see "Diagrams" below) |
| Comparison of options | Table with the verdict column first; add a diagram only if it shows structure |
| Numbers, trends | Inline SVG chart: labelled axes, values on the marks |
| Long reasoning | Summary on top; the rest in collapsed sections |

One diagram that carries the whole answer can ship alone as `.svg` or `.png`. Anything with evidence behind it ships as `.html`. A verbal analogy never replaces a visual when a visual explains the point better.

## Layout, top to bottom

1. Title (a name, 2-4 words) and the answer in one line: the result, the recommendation or the decision needed.
2. Summary, 2-5 lines. The chat message repeats it, so the answer never depends on the file.
3. One to three visuals. One idea each, with a one-sentence caption that says what to look at.
4. Evidence in `<details><summary>`: sources, raw numbers, commands, logs. Closed by default. Each summary line says what is inside.
5. Footer: date and the source paths or commands.

No slide deck, no decoration. Colour and shape must carry meaning.

## Self-contained and offline

- One file. Inline CSS and inline SVG. Small images as `data:` URIs (keep the file under about 300 KB).
- The page must read fully with no network and with scripts off. No external fonts, stylesheets or images. Every visual is static inline SVG.
- A script is an optional convenience (filter, expand all). Keep it inline and tiny. A library is a last resort: embed it inline. A CDN script is allowed only at an exact pinned version with an integrity hash, and only if the page is complete without it. A pin does not make a page offline.
- Evidence links may point to local files or URLs. They are links, not loads.
- Write the file where it is not tracked (the session scratchpad or `.local/`). Do not commit it unless asked.
- The absolute path has no spaces. Example: `/Users/name/project/.local/reports/20261106-queue-options.html`.
- Treat a report like a log: no secrets, tokens or customer data.

## Light and dark

- Define colours as custom properties on `:root`; redefine them under `@media (prefers-color-scheme: dark)`. Set `color-scheme: light dark`, and an explicit `background` and `color` on `body`.
- In SVG use `currentColor` or `var(--…)`, never fixed black or white.
- Text contrast at least 4.5:1 in both modes. Never use colour alone; add a label or a pattern.
- Readable from 360 px to about 1100 px wide: `max-width` about 70ch for text, SVG with a `viewBox` and `width: 100%`.

## Diagrams

Raw Mermaid is not a deliverable in HTML: it needs a script to draw. Deliver the rendered result.

1. Preferred: write plain SVG by hand (boxes, arrows, labels) for up to about 15 nodes.
2. Or render Mermaid to SVG with the Mermaid CLI at a pinned version (`mmdc -i in.mmd -o out.svg`), then paste the SVG inline. If the tool is not available offline, use option 1.
3. Keep the `.mmd` source in a `<details>` block only when Clemens may want to edit the diagram.

Label every edge with what it carries. Do not invent components: each node and edge must come from code or from the conversation.

## Check before you send

- Open the file in a browser or headless screenshot. Check light and dark, and 360 px width without a horizontal scroll.
- `grep -nE '(src|href)="https?:' file.html` finds nothing that the page loads.
- The numbers in the summary match the numbers in the evidence.

## Chat message

Answer first, then the one or two numbers that matter, then the path. A message that only points at the file is not acceptable. Write it as the "Writing for Clemens" guide in the always-loaded contract says.

> Option B costs 40% less and ships in two weeks. Option A needs a migration that we cannot staff. I recommend B. The report has the diagram, the cost table and the sources.
> /Users/name/project/.local/reports/20261106-queue-options.html

## Skeleton

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Queue options</title>
<style>
  :root { color-scheme: light dark; --bg:#fff; --fg:#1b1f24; --muted:#59636e; --accent:#0b5fff; --line:#d0d7de; }
  @media (prefers-color-scheme: dark) { :root { --bg:#12161b; --fg:#e6edf3; --muted:#9aa4af; --accent:#6ea8ff; --line:#30363d; } }
  body { margin:0 auto; padding:16px; max-width:70ch; background:var(--bg); color:var(--fg); font:16px/1.5 system-ui, sans-serif; }
  figure { margin:16px 0; }
  svg { width:100%; height:auto; color:var(--fg); }
  details { border-top:1px solid var(--line); padding:8px 0; }
  figcaption, footer { color:var(--muted); font-size:14px; }
</style>
</head>
<body>
<h1>Queue options</h1>
<p><strong>Use option B.</strong> It costs 40% less and ships in two weeks.</p>
<figure>
  <svg viewBox="0 0 400 80" role="img" aria-label="Producer sends to queue, queue sends to worker">
    <defs><marker id="a" markerWidth="8" markerHeight="8" refX="6" refY="4" orient="auto"><path d="M0 0L8 4L0 8z" fill="currentColor"/></marker></defs>
    <g fill="none" stroke="currentColor"><rect x="4" y="20" width="96" height="40" rx="6"/><rect x="152" y="20" width="96" height="40" rx="6"/><rect x="300" y="20" width="96" height="40" rx="6"/>
      <path d="M100 40h50" marker-end="url(#a)"/><path d="M248 40h50" marker-end="url(#a)"/></g>
    <g fill="currentColor" text-anchor="middle"><text x="52" y="45">Producer</text><text x="200" y="45">Queue</text><text x="348" y="45">Worker</text></g>
  </svg>
  <figcaption>Producers write once. Workers read at their own pace.</figcaption>
</figure>
<details><summary>Cost table and sources</summary>…</details>
<footer>2026-11-06 · sources: docs/queue-notes.md</footer>
</body>
</html>
```
