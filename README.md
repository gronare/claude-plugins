# gronare plugins

A Claude Code plugin marketplace.

## vault

Your Obsidian vault as Claude's persistent memory, backed by an S3 bucket or a local folder. The plugin bundles the [notes-vault-mcp](https://github.com/gronare/notes-vault-mcp) server, a `SessionStart` hook that prints the context for the code you are in, a `Stop` hook that keeps the repo log complete, the `vault-workflow` skill, and three Obsidian skills from [kepano/obsidian-skills](https://github.com/kepano/obsidian-skills) (obsidian-markdown, obsidian-bases, json-canvas, MIT licensed) so the agent writes correct Obsidian markdown, Bases and canvases through the server. The Obsidian CLI is not bundled: notes go through the server, never through the app.

### Requirements

- Claude Code.
- `uv` on the machine; the server runs through `uvx`:

  ```bash
  curl -LsSf https://astral.sh/uv/install.sh | sh
  ```

- A vault: either a folder on disk, or an S3 bucket (MinIO works) with a key that can list, get, put and delete in it.

### Install

```bash
claude plugin marketplace add https://github.com/gronare/claude-plugins
claude plugin install vault@gronare
```

The install asks for the plugin's settings. Fill in **one** of the two columns:

| Setting | S3 vault | Local vault |
| --- | --- | --- |
| Local vault folder | leave empty | absolute path to the folder |
| S3 endpoint | `https://minio.example.com` | leave empty |
| S3 bucket | the bucket, e.g. `obsidian` | leave empty |
| S3 access key | the key | leave empty |
| S3 secret key | its secret | leave empty |

The same values can be passed on the command line instead of the prompts:

```bash
claude plugin install vault@gronare \
  --config s3_endpoint=https://minio.example.com \
  --config s3_bucket=obsidian \
  --config s3_access_key=vault-mcp \
  --config s3_secret_key=...
```

The settings live in `~/.claude/settings.json` and are handed to the server and the hooks as environment variables every time they start. Nothing needs to be set in the shell.

### Change the settings later

Inside Claude Code: `/plugin` → Installed → vault → Configure. Or run the install again with `--config`.

### Set the vault up, once per vault

Start Claude Code and run:

```
/vault:init
```

It writes `.vault/schema.yml` and the Obsidian Bases views into the vault's root through the server the plugin already configured, and keeps whatever is there; `/vault:init --force` overwrites them with the defaults. The workflow rules the agent needs come with the plugin's `vault-workflow` skill, so nothing goes into CLAUDE.md.

### Check that it works

Start Claude Code in any git repo. The session-start hook prints a context bundle from the vault before the first prompt, and `claude mcp list` shows `plugin:vault:vault` as connected.

### Commands

| Command | What it does |
| --- | --- |
| `/vault:init [--force]` | Sets the vault up, see above. |
| `/vault:backlog [area]` | Shows the backlog by priority then age, for one area when given. |
| `/vault:log [line]` | Writes this session's line in the repo log now, with the commits it produced, instead of waiting for the stop hook. |
| `/vault:lint` | Reports drift across the vault: broken frontmatter, missing fields, unresolved wikilinks, orphans, stale open tasks, archive mismatches. |

### Update

Every notes-vault-mcp release moves the plugin's pin to the new server version. On each machine:

```bash
claude plugin update vault@gronare
```

then restart Claude Code. Claude Code caches a plugin per version number under `~/.claude/plugins/cache/gronare/vault/<version>/` and never refetches a version it already has; if an update seems to change nothing, remove that folder and update again.

### Two vaults on two machines

Each machine holds one configuration, so a work machine points at its own bucket with its own key:

```bash
claude plugin install vault@gronare \
  --config s3_endpoint=https://minio.example.com \
  --config s3_bucket=obsidian-work \
  --config s3_access_key=vault-mcp-work \
  --config s3_secret_key=...
```

and gets its own `init` with the same values.

## herdr-review

Review a repo's changes in a [herdr](https://herdr.dev) split next to the Claude pane, and send comments back to Claude without leaving the diff.

### Requirements

Claude Code running inside herdr, plus `fzf`, `nvim` 0.10 or later, `jq` and `git` on `PATH`; `tig` for the history split.

### Install

```bash
claude plugin marketplace add https://github.com/gronare/claude-plugins
claude plugin install herdr-review@gronare
```

### Use

`/herdr-review:review-split [base or what to review]` opens a split with the files of the work under review. Claude works out the scope first: the files it changed in this session, or, for work from elsewhere, what the unpushed commits, uncommitted changes and any project notes say belongs to it, asking when that is unclear. The list shows those files in the order of Claude's numbered review guide; other changes in the repo are one key away. Ask for everything and you get every change against the base.

| Where | Key | What it does |
| --- | --- | --- |
| list | type | filter; `!spec/ ` is prefilled to hide specs |
| list | Enter | open the file's unified diff in nvim |
| list | ctrl-r | mark the file read, or unread |
| list | ctrl-h | show or hide read files |
| list | ctrl-o | show or hide changes outside the work under review |
| list | ? | show every key in the preview pane |
| list | ctrl-c | close the split (Esc does nothing, so it cannot close it by accident) |
| diff | c | comment on the line or visual selection |
| diff | o | open the real file over the diff, at that line |
| diff | - | open the file's folder over the diff (neo-tree's float if installed, else netrw) |
| diff | u | reload the diff after the file changed |
| diff | w | toggle line wrap |
| diff | r | mark the file read and go back to the list |
| diff | q, Esc | back to the list |
| opened file | leader m | comment on the line or visual selection |
| opened file | ctrl-q | back to the diff |

Files opened with `o` or `-` show in a float over the diff, and everything else in it is your usual nvim: jump around, search, edit. When you go back to the diff, files you saved are reported to Claude as `path:lines — edited by me during the review`, and unsaved edits ask to be saved or discarded first.

A comment is typed into Claude's input box as `path:line — text`, not submitted, so several pile up until you press Enter there. A read file stays out of the list until its contents change; marks live in `~/.local/state/herdr-review/`, one file per repo.

The list follows the repo by itself: it reloads when files change, keeping your filter and cursor. An open diff marks itself `changed on disk` instead of moving under you; `u` reloads it.

### Live review (optional)

With the plugin setting **Open the review pane automatically** on, Claude's first file edit in a session opens the review split next to it without taking focus. Files that were already changed before that edit count as other changes (behind ctrl-o); everything changed after it is in scope, newest first. Close the pane from herdr and it stays closed for that session; `/herdr-review:review-split` brings it back, or rescopes the open one to Claude's guide.

The setting is off by default. Turn it on in Claude Code under `/plugin` → Installed → herdr-review → Configure, or at install:

```bash
claude plugin install herdr-review@gronare --config auto_open=true
```

`/herdr-review:history-split` opens tig in a split for the branch's history.
