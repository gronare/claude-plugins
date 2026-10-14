---
name: review-split
description: Open a herdr split to review the repo's changes before commit — filterable file list, unified diffs in nvim, comments sent back to this Claude pane, read marks that hold until a file changes. Use only when the user runs /review-split or asks for a review split.
argument-hint: "[base]"
disable-model-invocation: true
---

# Review split

1. Stop if `HERDR_ENV` is not `1`: say the review split only works inside herdr. Stop too if any of `fzf`, `nvim`, `jq` is missing from `PATH`, and name the missing ones.
2. From the repo being reviewed, run `sh "${CLAUDE_SKILL_DIR}/../../scripts/review.sh" split $ARGUMENTS`. Without a base it reviews uncommitted changes against `HEAD`, or the unpushed commits when the tree is clean. A base such as `origin/master` or `HEAD~3` is passed through.
3. Reply with a short review guide, no more than a few lines per file: list the changed files (`git diff --stat <base>` plus untracked files), and for each non-spec file say what changed and which choice is worth a look. Do not repeat the diff.
4. Add one line on the controls: type to filter (`!spec/` is prefilled to hide specs), Enter opens the unified diff in nvim; there c comments, w toggles line wrap, r marks the file read, q or Esc goes back. In the list ctrl-r toggles read and ctrl-h shows or hides read files; a read file returns when its contents change. Comments are not sent until the user presses Enter here.

When comments arrive as `path:line — text` lines (`(before)` means the line number is in the old version), answer each one; change code only where a comment asks for it.
