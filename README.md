# AI Usage Mac

A macOS menu bar app for tracking AI coding-assistant usage across Cursor, Codex, and Claude Code.

## What It Shows

- Menu bar pie icon with one segment for each provider.
- Compact popover with spend, limit, percent used, reset date, and refresh time.
- Cursor usage from the Cursor dashboard/API session.
- Claude Code spend from the Claude usage page.
- Codex weekly spend estimated from local Codex session token usage.

## Requirements

- macOS 13 or later.
- Logged-in Cursor and Claude web sessions in the app/browser WebKit store.
- Local Codex usage data in `~/.codex`.

## Build And Install

```bash
bash build_app.sh
cp -r "AI Usage Mac.app" /Applications/
open "/Applications/AI Usage Mac.app"
```

## Notes

- Codex is an estimate because local Codex data includes models and token counts, not a server-authoritative remaining balance.
- Cursor and Claude usage are read through authenticated web sessions.
- App logs are written to `~/Library/Logs/CursorUsage.log`.
