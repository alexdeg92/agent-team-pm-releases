# Agent Team PM

A Claude Code skill that coordinates role-named coding agents in [herdr](https://herdr.dev):
plan phases, assign work across providers, track reports, review changes and recover sessions.
This repository contains released skill files and installation tools only.

## Install from GitHub

Requires Node.js 18 or later, npm and git:

```sh
npx github:alexdeg92/agent-team-pm-releases#v0.1.0 install
npx github:alexdeg92/agent-team-pm-releases#v0.1.0 doctor
```

For a global command:

```sh
npm i -g github:alexdeg92/agent-team-pm-releases#v0.1.0
agent-team-pm install
agent-team-pm doctor
```

No npm registry package has been published. The GitHub release also provides
`agent-team-pm-0.1.0.tgz` for `npm install -g` and its SHA256 checksum.

## Install with curl

Requires Node.js 18 or later, curl, tar and shasum (or sha256sum):

```sh
curl -fsSL https://raw.githubusercontent.com/alexdeg92/agent-team-pm-releases/v0.1.0/install.sh -o /tmp/agent-team-pm-install.sh
bash /tmp/agent-team-pm-install.sh install
```

The script downloads the versioned release package, verifies its SHA256 and runs
the same installer. Inspect the script before running it if desired.

## Install with Homebrew

```sh
brew tap alexdeg92/agent-team-pm-releases https://github.com/alexdeg92/agent-team-pm-releases.git
brew install alexdeg92/agent-team-pm-releases/agent-team-pm
agent-team-pm install
agent-team-pm doctor
```

The formula installs the command only. Run `agent-team-pm install` to copy the skill
into your own home directory.

## What gets installed

The installer copies the skill into `~/.claude/skills/agent-team-pm` and links
`team` into `~/.local/bin`. Add `~/.local/bin` to PATH. Use `install --dir <skills dir>`
for another skill location. It reports local edits and requires `--force` before
replacing a modified copy.

The skill requires herdr, jq, git, Python 3, bash, perl and rsync, plus at least two
coding-agent CLIs installed and authenticated. `doctor` checks local prerequisites;
it does not authenticate providers or start agents. Agent spawning uses the CLIs'
no-approval modes, so use it only in projects where those agents are authorized.
`agent-usage.py` needs Linux `/proc`; on macOS use provider usage dashboards.

## Use the skill

Start Claude Code in herdr in your project, then ask:

> Act as PM for this project. Discover the available agents, plan the work and
> coordinate a team across providers with independent review.

The skill creates a project workspace and role-named agents. Read [SKILL.md](SKILL.md)
for the workflow, [references](references/) for allocation and failure handling,
and [templates](templates/) for briefs and reviewer charters.

## Uninstall

```sh
npx github:alexdeg92/agent-team-pm-releases#v0.1.0 uninstall
```

Or use `agent-team-pm uninstall` with a globally installed command. Then remove the
command with `npm uninstall -g agent-team-pm` or `brew uninstall agent-team-pm`, as
appropriate. Uninstall protects modified skill files and removes only its own team link.

MIT licensed. See [LICENSE](LICENSE).
