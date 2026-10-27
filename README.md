# claude-code-account-switcher

`cc-switch` - switch between multiple [Claude Code](https://docs.claude.com/en/docs/claude-code) accounts on Windows without running `/login` every time.

A single `.cmd` file, no dependencies: it runs on the built-in Windows PowerShell 5.1 (or `pwsh` 7 when installed), needs no `ExecutionPolicy` changes and no install step.

```
> cc-switch
Select account (Up/Down, Enter = switch, Esc = cancel):
> work             john@company.com                 Company Inc.  (active)
  john             john@gmail.com                   john@gmail.com's Organization
```

## Install

Copy `cc-switch.cmd` to any folder on your `PATH`. The Claude Code native installer already puts `%USERPROFILE%\.local\bin` on `PATH`, so that is a good place:

```powershell
Copy-Item cc-switch.cmd "$HOME\.local\bin\"
```

Open a new terminal afterwards.

## Usage

| Command | What it does |
|---|---|
| `cc-switch` | Interactive picker, the active account is preselected |
| `cc-switch <name>` | Save the active account and switch to `<name>` |
| `cc-switch list` | List saved accounts (`*` = active) |
| `cc-switch save` | Save the active account |
| `cc-switch remove <name>` | Remove a saved account |

`<name>` is the part of the account's e-mail address before `@`.

Switching refuses to run while Claude Code is running, because a running session may write its own tokens back later. Add `-Force` to switch anyway, then restart your sessions.

### Adding accounts

1. Log in to the first account as usual and run `cc-switch save`.
2. In Claude Code run `/login` with the second account, close Claude Code and run `cc-switch save` again.
3. From now on switch with `cc-switch` only.

## How it works

Claude Code keeps the login in two places:

| File | Key | Content |
|---|---|---|
| `~/.claude.json` | `oauthAccount` | account info (e-mail, organization, plan) |
| `~/.claude/.credentials.json` | `claudeAiOauth` | OAuth tokens - the actual login |

`cc-switch` stores a copy of both for each account in `~/.claude.json` as `oauthAccount_<name>` and `claudeAiOauth_<name>` (Claude Code keeps unknown keys in that file). When switching, it first saves the active account into its slot - the refresh token rotates, so an old copy would stop working - and then copies the selected account into `oauthAccount` and `claudeAiOauth`.

Settings, history, memory, MCP servers and MCP logins (`mcpOAuth`) stay shared between accounts.

The single-file trick: the first lines are a cmd header that starts PowerShell and tells it to run the content of the same file; to PowerShell that header is just a block comment.

## Notes

- Windows only. On macOS Claude Code keeps credentials in the Keychain, not in `.credentials.json`.
- The saved tokens are stored in `~/.claude.json` in plain text, just like the active ones in `.credentials.json`. Treat that file accordingly.
- Account-specific caches in `~/.claude.json` (usage, model access) refresh on their own after a switch.
- If a saved account stops working (e.g. its token was revoked), run `/login` with it once and `cc-switch save`.
- Not affiliated with Anthropic. Relies on Claude Code's internal file layout, which may change.

## License

MIT
