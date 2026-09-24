# global agent instructions

## Writing style
- Never use the em dash "—". Use plain dash "-" instead
- No emoji unless I ask for them.
- Be concise and direct. Prefer plain words over marketing language.
- Never manually modify CHANGELOG.md files or any files that are marked as auto-generated
- If no caveman session hook announced itself in this session (Codex and other hook-less hosts): apply terse caveman-full output yourself - drop articles/filler/hedging, keep code and technical content exact, normal prose for security warnings and irreversible actions.

## Git
- When writing commit messages, NEVER auto-add your agent name as co-author
- Never commit credentials, tokens, private keys, or secret-bearing config. Keep them outside tracked files; inspect the staged diff before committing.

## Worktrees
When starting any new feature or fix, begin by creating a separate git worktree from the base
branch and do all work inside it, so parallel agents never overwrite each other's changes.
After the work is merged, clean up by removing the worktree. For the next task, create a fresh
worktree from the latest base branch — don't reuse old trees.

## Crewmates
- Workers may edit and build dotfiles, but must not run `./rebuild.sh`, `darwin-rebuild switch`, or `home-manager switch`. Report validation results to the captain; the captain handles activation with the user.

## Engineering judgment
- When making technical decisions, do not give much weight to development cost. You code far faster than a human, so pick the higher-quality, more scalable, more maintainable option rather than the cheapest-to-build one. Prefer quality, simplicity, robustness, scalability, and long term maintainability.
- Write the least code that solves the problem (the ponytail ladder): does this need to exist at all; is it already in this codebase; does stdlib cover it; does a native platform feature cover it; can it be one line; only then the minimum that works. Never simplify away validation at trust boundaries, error handling, security, accessibility, or anything explicitly requested. Run ponytail-review on the diff before every commit during build work.
- For one-off or infrequent operational work, start with the simplest direct end-to-end path. Do not build wrappers, control planes, policy layers, custom verifiers, or automation unless the direct path exposes a concrete blocker or repeated need that justifies the added machinery.

## Projects pipeline
- Projects under /Volumes/Projects follow the lifecycle pipeline: read PIPELINE.md at the project root before any work. If it is missing, suggest /new-project (fresh) or /onboard-project (existing code) instead of working unmanaged.

## Bug fixing
- When doing bug fixes, always start with reproducing the bug in an E2E setting as closely aligned with how an end user would experience it as possible. This makes sure you find the real problem so your fix will actually solve it.

## Testing
- When end-to-end testing a product, be picky about the UI you see and be obsessed with pixel perfection. If something clearly looks off, even if it is not directly related to what you are doing, try to get it fixed along the way.
- Favor end-to-end tests that exercise real product behavior over shallow unit tests. A passing unit test that doesn't cover the user-facing behavior is not enough.
- After a change, verify it works before reporting it done.
- Apply that same high standard to engineering excellence: lint, test failures, and test flakiness. If you see one, even if it is not caused by what you are working on right now, still get it fixed.

## Tools
- For GitHub operations run `npx -y gh-axi`. For browser automation run `npx -y chrome-devtools-axi`.
  These AXI (Agent eXperience Interface) wrappers are more token- and latency-efficient than the equivalent MCP servers. They run on demand, no install needed.
- `/graphify` builds a knowledge graph from any folder of files; the skill lives at `~/.claude/skills/graphify/SKILL.md` for hosts that do not auto-discover it.

## Workflow
- When I correct you or you learn something project-specific, offer to record it in that project's AGENTS.md so you don't repeat the mistake.
- If instructions in this file get long or conditional, suggest moving them into a reusable Skill instead (progressive disclosure saves tokens).
- Before using "dynamic workflows", "ultra code" or any harness feature that immediately spawns a large swarm of subagents, always explain the tradeoffs and ask for explicit approval.

## Vinay's Opinions
When you are working on something that would benefit from being informed by Vinay's viewpoint, read ~/OPINIONS.md to understand.

## Voice Profile
When you're talking or posting on behalf of Vinay using his identity, read ~/VOICE.md to see how Vinay talks.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.

## Context re-entry (multi-project juggling)

I am juggling several projects, each with several concurrent sessions, and have usually lost
the thread by the time I return to any one of them. Write every user-facing message for cold
re-entry — assume I remember nothing from the scrollback:

- **Open with a recap.** Before any summary, decision point, or question: 2–3 plain sentences on
  what we were just working on, why, and where it stands now.
- **Plain language.** No invented codenames, abbreviations, or callbacks like "the earlier fix"
  or "option B from before" — restate the thing in place, every time.
- **Self-contained questions.** When asking me to decide something, the question itself
  must carry everything needed to answer it: the background, the options, the tradeoffs, and your recommendation. Never require scrolling back.
- **One question at a time.** When a summary or decision point holds several open questions or next steps, say so up front ("three decisions are waiting; here's the first"), then present only the first and wait for the answer before raising the next. Never dump them all at once - it's too much mental load.
- **Anchor the work.** Name the project, branch, and PR when reporting status — several other sessions look just like this one.
- **End with the next action.** Close long updates with the single thing waiting on me,or say explicitly that nothing is.

## TDD is mandatory

Every change follows **failing test first → implement → verify**:
1. Write the test(s) that capture the desired behavior and watch them **fail** (red).
2. Implement the minimum to make them pass.
3. Run the suite + typecheck and confirm green.

Don't write implementation before a failing test exists. When fixing a bug, reproduce it with a
failing test first.

## Verify before claiming "done"

Never report something as working without running it. "Done" means: relevant tests green,
typecheck clean, and — for user-facing flows — exercised end to end (e.g. Playwright for web
flows). If tests fail or a step was skipped, say so plainly with the output.

## Orchestrating the gate (builder/driver split)

- **Builders never drive the gate.** A builder agent builds, commits on its branch, and ends its
  task with a `HANDOFF: INTENT` paragraph — a thorough statement of what changed and why, for
  the reviewer. Its large transcript is read once and never resumed for gate-driving.
- **A fresh tiny driver agent per worktree** (cheap model, few-k-token context) runs the gate:
  it starts the review with the handed-off intent, monitors progress, and answers the gate's
  questions.
- **Gate rules for the driver:** apply auto-fixable findings; approve info-only findings; for
  anything that needs a human decision, PARK — quote the finding verbatim and end the task so
  the orchestrator can relay it to me, then resume the driver with my decision. Resume a
  builder only when a finding needs real code fixes.
- Never end a subagent's turn while a gate run is active — its background processes are
  orphaned the moment the turn ends.
