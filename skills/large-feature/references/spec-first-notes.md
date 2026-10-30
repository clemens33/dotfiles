# Large feature — spec-first notes

Relocated verbatim from `SKILL.md` (Stage 3, "Spec-first acceptance tests"). The canonical, always-loaded contract is `shared/AGENTS.md` → Universal principles → **Spec-first for M/L**; this file keeps the playbook's original elaboration of it.

Contract shape (`shared/AGENTS.md`) — local doctrine, not experimental:

- 🅛 **Cross-model authoring (default)** — different-provider agent writes+freezes acceptance test strictly from acceptance contract + domain docs, before impl; by default same agent then reviews impl (no extra seat). **Separate author** (≠ impl reviewer) allowed for parallel slices / high blast radius. Implementer never edits frozen tests; disputed spec goes back with evidence. Isolation risk: imagined behavior / accidental API shape (Hora et al.) — challenge impl-shape tests.
- 🅡 **Cross-model test review** — author's impl verdict doesn't gate own tests: another-provider seat reviews frozen tests vs requirements (behavior vs impl shape). Byte-identical installation allowed.
