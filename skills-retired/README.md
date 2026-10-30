# skills-retired

Skills taken out of every harness catalog but kept in the repo so they can come back. Contents are byte-identical to the last active version, with git history intact (`git log --follow -- skills-retired/<name>/SKILL.md`).

Nothing here is linked, installed or scanned: `install.conf.yaml` has no mappings for it, and `scripts/lint-skills.sh`, `scripts/eval-skills.py` and the skill CI only read `skills/`.

## Restore

Prefer reverting the whole group commit that retired the skill: it restores the directories, their `install.conf.yaml` mappings and the references and routing fixtures changed with them. It is not a guaranteed clean rollback. Later retirements can overlap, so a group revert may need conflict resolution and caller repairs: a restored skill can still name siblings that stay retired, and reverting the first group also removes this guide (keep it). Audit the restored references, then restore the sibling groups they need or repair their callers. Find the commit with `git log --diff-filter=R --format=%h -- skills-retired/<name>`, then `git revert <sha>`.

Restoring a single skill from a group is a manual change. Before it goes live:

1. `git mv skills-retired/<name> skills/<name>`.
2. Repair what it touches: references from other skills and docs, routing fixtures, and any call into a skill that is still retired.
3. Add both mappings to `install.conf.yaml`: `~/.claude/skills/<name>: skills/<name>` and `~/.agents/skills/<name>: skills/<name>`.
4. Run `./scripts/lint-skills.sh skills/` and get the cross-provider review that `manage-skills` ("Lifecycle order") requires.
5. Only then run `./install`.
