# gronare plugins

A Claude Code plugin marketplace.

## vault

Your Obsidian vault as Claude's persistent memory, backed by an S3 bucket or a local folder. The plugin bundles the [notes-vault-mcp](https://github.com/gronare/notes-vault-mcp) server, a `SessionStart` hook that prints the context for the code you are in, a `Stop` hook that keeps the repo log complete, the `vault-workflow` skill, and the four Obsidian skills from [kepano/obsidian-skills](https://github.com/kepano/obsidian-skills) (obsidian-cli, obsidian-markdown, obsidian-bases, json-canvas, MIT licensed).

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
