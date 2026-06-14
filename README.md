# claude-crate

Run Claude Code with `--dangerously-skip-permissions` inside a Docker container,
scoped to a single project directory. The container can only touch the mounted
project dir, a dedicated config dir, and `~/.aws` (for Bedrock auth) — not the
rest of your machine.

## How it works

- **Model backend:** AWS Bedrock by default. Set `CLAUDE_CRATE_BEDROCK_ENABLED=0`
  to use the direct Anthropic API instead — the launcher skips all SSO/AWS
  handling and forwards `ANTHROPIC_API_KEY` from the host.
- **Auth (Bedrock):** no static keys. `~/.aws` is mounted read-write and
  `AWS_PROFILE` forwarded, so botocore auto-refreshes role creds from the cached
  SSO token. The launcher re-logs in if the session is expired or expires within
  the hour.
- **Config:** a dedicated, backend-specific config dir, seeded on first run and
  kept separate from your real `~/.claude` — `~/.claude-crate` (Bedrock, ARN
  models) vs `~/.claude-crate-api` (API, plain model names), so the two never
  pollute each other. It persists across runs (sessions, memory, plans).
- **Per-project history:** each project is mounted at its *real host path*, so
  history is scoped per project — use `--continue` / `--resume` to reopen it.

## One-time setup

Add a `claude-crate` profile to `~/.aws/config`, backed by a modern
`[sso-session]` block (refresh-token capable). Replace the placeholders with
your org's SSO start URL, region, account ID, and role:

```ini
[sso-session my-sso]
sso_start_url = https://your-org.awsapps.com/start
sso_region = <region>
sso_registration_scopes = sso:account:access

[profile claude-crate]
sso_session = my-sso
sso_account_id = <account-id>
sso_role_name = <role-name>
region = <region>
output = json
```

Create your settings seed from the example and fill in your Bedrock model ARNs
(this file is gitignored — it holds your account-specific inference-profile
ARNs):

```bash
cp settings.seed.json.example settings.seed.json
# then edit settings.seed.json: set <region>, <account-id>, and the
# inference-profile IDs for each model.
```

For Anthropic-API mode (`CLAUDE_CRATE_BEDROCK_ENABLED=0`), create its seed the
same way — rename the example, then adjust the default model if you like:

```bash
cp settings.seed.api.json.example settings.seed.api.json
```

Build the base image:

```bash
cd claude-crate
docker build -t claude-crate:base .
# or: ./claude-crate --workdir <project> --build   (builds base + any overlay)
```

## Install to PATH (optional)

Symlink the launcher onto your `PATH` (a symlink, not a copy, so edits and seed
resolution keep working):

```bash
ln -s "$PWD/claude-crate" ~/.local/bin/claude-crate   # or /usr/local/bin
```

## Usage

`--workdir` is required (the command errors if omitted).

```bash
./claude-crate --workdir ~/code/myproject              # run against a project
./claude-crate --workdir ~/code/myproject --continue   # reopen most recent session
./claude-crate --workdir ~/code/myproject --resume     # pick a prior session
./claude-crate --workdir ~/code/myproject --version    # extra args → claude
./claude-crate --workdir ~/code/myproject --build      # rebuild image first
./claude-crate --workdir ~/code/myproject --overlay python   # run a language/project overlay
```

Multiple instances can run on the same project at once (container names get a
PID suffix). They share the same project mount, so coordinate file edits
(e.g. separate branches) to avoid clobbering.

The launcher runs `aws sso login` automatically if needed. SSO login opens a
browser on the host.

### Image overlays (per-language / per-project deps)

The base image (`claude-crate:base`) is deliberately language-agnostic — node,
claude-code, awscli, git, nothing else. Language toolchains and project-specific
system libs live in **overlays**, split by kind and composed in three tiers:

```
base                                       # claude-crate:base — runtime essentials
 └ overlays/languages/python               # claude-crate:python — uv + CPython 3.12
    └ overlays/projects/myproject          # + project-specific system libs
```

`overlays/languages/` is tracked in git (shared, reusable); `overlays/projects/`
is **gitignored**, so private per-project configs and deps never get committed.

Each overlay sets its parent via `FROM claude-crate:<parent>`. Launch with
`--overlay <name>` (looked up under `projects/` then `languages/`): the launcher
walks the `FROM` chain, builds it base-first (with `--build`), and runs
`claude-crate:<name>`. With no `--overlay`, the base image runs.

```bash
./claude-crate --workdir ~/code/myproject \
  --overlay myproject --build              # builds base → python → project, runs it
```

**Add a new project:** create `overlays/projects/<project>/Dockerfile` starting
from a language layer (e.g. `FROM claude-crate:python`) and add its `apt-get`
deps. **Add a new language:** create `overlays/languages/<lang>/Dockerfile` as
`FROM claude-crate:base`. No wrapper changes needed — selection is by name.

### Python projects (container-only venv)

A host-built `.venv` has absolute symlinks (e.g. into `/opt/homebrew`) that are
useless in a Linux container. So the launcher masks `<project>/.venv` with a
**named Docker volume** — the container gets its own Linux-native venv that
persists per project, and the host's copy stays untouched and invisible.

The `python` overlay ships `uv` + CPython 3.12 (Debian's is only 3.11). Build
the venv with `uv` inside the crate:

```bash
uv venv --python 3.12 .venv
. .venv/bin/activate && uv pip install -r requirements.txt   # or: uv sync
```

Reset it with `docker volume rm claude-crate-venv-<munged-path>`
(`docker volume ls` to find the name).

### Postgres / docker-compose test DB (`--with-compose`)

For tests needing a Postgres from the project's `docker-compose.yml`, start the
DB **on the host** and have the crate join that compose network — the crate
never gets Docker access, so the blast radius is unchanged.

```bash
# on the host, from the project:
docker compose up -d db
docker network ls                       # find the network, e.g. myproject_default

# then launch the crate attached to it:
./claude-crate --workdir ~/code/myproject --with-compose myproject_default
```

Inside the crate, connect by compose service name (e.g.
`postgresql://user:pass@db:5432/dbname`), not `localhost`. `psql` ships in
overlays that need it (add it to your project overlay), not the base image. The
launcher errors if the named network doesn't exist. The agent can't start/stop
the DB itself — control its lifecycle from the host.

### Environment overrides

- `CLAUDE_CRATE_BEDROCK_ENABLED` (default `1`; set `0` for the Anthropic API + `ANTHROPIC_API_KEY`)
- `AWS_PROFILE` (default `claude-crate`; Bedrock mode only)
- `AWS_REGION` (default `eu-central-1`; Bedrock mode only)

## Files

| File                    | Purpose                                          |
|-------------------------|--------------------------------------------------|
| `Dockerfile`            | base image: node:22 + claude-code + awscli (language- and auth-agnostic) |
| `overlays/languages/<name>/Dockerfile` | shared language overlays (tracked), chained via `FROM claude-crate:<parent>` |
| `overlays/projects/<name>/Dockerfile` | private per-project overlays (**gitignored**) |
| `claude-crate`          | host launcher (auth pre-flight + overlay resolver + `docker run`) |
| `settings.seed.json[.example]` | Bedrock seed — copy the `.example`, fill in ARNs (real file gitignored) |
| `settings.seed.api.json[.example]` | Anthropic-API seed — copy the `.example`, plain model names (real file gitignored) |
| `claude-json.seed.json` | onboarding/theme state seeded into the config dir |

## Notes

- macOS: the project dir, `~/.aws`, and config dirs must be under paths Docker
  Desktop is allowed to share (your home dir is by default).
- Egress is unrestricted in v1 (default Docker networking).
