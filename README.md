# claude-crate

Run Claude Code with `--dangerously-skip-permissions` inside a Docker container,
scoped to a single project directory. The container can only touch the mounted
project dir, a dedicated config dir (`~/.claude-crate`), and `~/.aws` (for
Bedrock auth) — not the rest of your machine.

## How it works

- **Model backend:** AWS Bedrock (`CLAUDE_CODE_USE_BEDROCK=1`).
- **Auth:** no static keys. `~/.aws` is mounted read-write and `AWS_PROFILE` is
  forwarded, so botocore inside the container auto-refreshes short-lived role
  creds from the cached SSO token — valid until the SSO session expires, not
  ~1h. The launcher validates the session before starting and forces a re-login
  if it is expired or expires within the next hour.
- **Config:** a dedicated `~/.claude-crate` (seeded from `settings.seed.json` and
  `claude-json.seed.json` on first run), kept separate from your real
  `~/.claude` so host-only hooks/statusline/plugins don't leak in. Model
  selection lives here in `model` + `modelOverrides`, not env vars.
- **Persistent history:** `~/.claude-crate` survives across runs, so sessions,
  memory, and plans are saved. Each project is mounted at its *real host path*
  inside the container, so history is scoped per project — use `--continue` /
  `--resume` to reopen a project's prior session.

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

Build the image:

```bash
cd claude-crate
docker build -t claude-crate:latest .
# or: ./claude-crate --workdir <project> --build   (builds, then runs)
```

## Install to PATH (optional)

Symlink the launcher into a directory on your `PATH` so you can run
`claude-crate` from anywhere. Use a symlink (not a copy) so edits to the script
take effect automatically — it resolves its own directory to find the seed
files, so it keeps working through the link.

```bash
ln -s "$PWD/claude-crate" ~/.local/bin/claude-crate   # or /usr/local/bin
```

Verify (`~/.local/bin` must be on your `PATH`):

```bash
which claude-crate
claude-crate            # should print the "--workdir is required" usage error
```

## Usage

`--workdir` is required (the command errors if omitted).

```bash
./claude-crate --workdir ~/code/myproject              # run against a project
./claude-crate --workdir ~/code/myproject --continue   # reopen most recent session
./claude-crate --workdir ~/code/myproject --resume     # pick a prior session
./claude-crate --workdir ~/code/myproject --version    # extra args → claude
./claude-crate --workdir ~/code/myproject --build      # rebuild image first
```

Multiple instances can run on the same project at once (container names get a
PID suffix). They share the same project mount, so coordinate file edits
(e.g. separate branches) to avoid clobbering.

The launcher runs `aws sso login` automatically if needed. SSO login opens a
browser on the host.

### Environment overrides

- `AWS_PROFILE` (default `claude-crate`)
- `AWS_REGION` (default `eu-central-1`)

## Files

| File                    | Purpose                                          |
|-------------------------|--------------------------------------------------|
| `Dockerfile`            | node:22 + claude-code (native installer) + awscli |
| `claude-crate`          | host launcher (SSO pre-flight + `docker run`)    |
| `settings.seed.json.example` | template for the settings seed (copy → `settings.seed.json`, fill in ARNs) |
| `settings.seed.json`    | your settings seed with real Bedrock ARNs (gitignored) |
| `claude-json.seed.json` | onboarding/theme state seeded into `~/.claude-crate` |
| `.dockerignore`         | build-context excludes                           |

## Notes

- Each project is mounted at its real host path inside the container (not
  `/workspace`), so resume history stays scoped per project. The host path is
  visible inside the container; isolation is unchanged (only that one dir is
  mounted).
- macOS: the project dir, `~/.aws`, and `~/.claude-crate` must be under paths
  Docker Desktop is allowed to share (your home dir is by default).
- Egress is unrestricted in v1 (default Docker networking).
