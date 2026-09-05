# gronare plugins

A Claude Code plugin marketplace.

```bash
claude plugin marketplace add https://github.com/gronare/claude-plugins
claude plugin install vault@gronare
```

## vault

Your Obsidian vault as Claude's persistent memory, backed by an S3 bucket or a local folder. Bundles the [notes-vault-mcp](https://github.com/gronare/notes-vault-mcp) server, a `SessionStart` hook that prints the context for the code you are in, a `Stop` hook that keeps the repo log complete, and the `vault-workflow` skill.

At install you are asked for either a local vault folder or the S3 endpoint, bucket and keys. The server needs `uv` on the machine (`curl -LsSf https://astral.sh/uv/install.sh | sh`).

Then, once per vault:

```bash
uvx notes-vault-mcp init
```

which writes `.vault/schema.yml` and three Bases views and prints a CLAUDE.md snippet.

The plugin also ships the four Obsidian skills from [kepano/obsidian-skills](https://github.com/kepano/obsidian-skills) (obsidian-cli, obsidian-markdown, obsidian-bases, json-canvas), MIT licensed, so the agent writes correct Obsidian markdown, Bases and canvases and can drive the Obsidian CLI when the app is running.
