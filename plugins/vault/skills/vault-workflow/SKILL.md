---
name: vault-workflow
description: How to work with the `vault` MCP server (notes-vault-mcp) as persistent memory across sessions - session-start context, the area gate before editing, the repo log line at the end, closing notes, and search that hides the archive. Load at the start of any session where the vault server is connected, and whenever you are about to write a note.
---

# Vault workflow

The vault is a folder of markdown notes (an Obsidian vault) reached through the `vault` MCP server. The server's own instructions describe the folders, the frontmatter contract and the tag vocabulary of *this* vault; read them, they win over this skill.

## The three moments

1. **Session start.** The `session-start` hook already printed a context bundle: the system notes for the code you are in, open task notes, reference notes, and the last log lines for the repo. If it did not (no hook, another cwd), call `context` with the path you work in. Read the system note before touching code. When the bundle lists commits newer than a system note, the note may be stale: trust the code, fix the note in the same pass.
2. **Before the first edit.** The system note for the subsystem must exist and describe today's state. If it is missing, write it (folder of kind `system`, `kind: system`, a `path` list, a `summary`). Write a task note (folder of kind `task`) only when the work spans sessions or needs a decision record; it must carry `area: "[[<system note>]]"`.
3. **Session end.** Update the system note with what changed, then call `log_append` with the repo, one line, the commit shas and the area. The `stop` hook blocks the stop when commits from the last day are missing from the log. Close finished task notes with `close` (optionally `merged_into` the system note).

## Searching

`search` is indexed and cheap. It ANDs terms, expands synonyms from the schema, and hides the archive and superseded notes unless asked. A 7-40 hex query looks up notes that mention that commit. Use `include_archive=true` only when the question is about history. `read_file` returns an `etag:` line; pass it as `expected_etag` to `write_file` when overwriting a note someone else may edit.

## Writing rules

- Frontmatter is validated: required fields, allowed `status` and `kind` values, `area` outside system folders. The server sets `updated` itself.
- A note describes the current state. History belongs in the log folder and in `## Historik` lines with a date and a sha, not in prose about what used to be.
- A superseded note gets `superseded_by: "[[stem]]"` through `close(..., merged_into=...)`; do not delete history.
- Tags come from the vocabulary in the schema; the folder name is never a tag.

## Lint

`lint` reports broken frontmatter, missing fields, missing areas, unresolved links, orphans, stale task notes and archive notes with a live status. Fix what you caused before ending the session.
