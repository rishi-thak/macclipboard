# ClipboardOpt

A background Mac app that keeps your last 10 text copies and, on **Cmd+Opt+V**, pastes the one that fits the field you're in. It decides on your Mac whenever it can, and asks TypeSafe's Jev model only when the field is unclear.

Design: [docs/architecture.html](docs/architecture.html)

## How a Cmd+Opt+V press works

1. No text field focused (or a password field): the keystroke is passed on untouched, so Finder's "Move Item Here" still works.
2. Read the field through Accessibility: label, placeholder, id, nearby text, and in Safari the page URL and title.
3. Job application? Checked against a list of job sites (Greenhouse, Lever, Workday, Ashby…), or Jev's saved answer for the page.
4. Decide on your Mac (`SmartPasteEngine`). A copy of the right kind made in the last 30 seconds wins; on job applications your profile value wins next; one clear match pastes right away.
5. Unclear: one Jev request with a yes/no question per candidate. A clear winner pastes, otherwise the history panel opens with the best guess first.
6. Pressing Cmd+Opt+V again within 1.5 s undoes the smart paste and opens the panel.

Panel keys: arrows, Return, 1–9/0, Esc.

## Images and plain Cmd+V

Plain Cmd+V is never intercepted. Smart paste briefly puts text on the clipboard to send Cmd+V, then restores **every item and type that was there**, byte for byte, so a copied screenshot still pastes normally. `PasteboardSnapshotTests` cover this. History is text only; image and file copies are never stored.

## Files

| Path | What |
|------|------|
| `~/Library/Application Support/ClipboardOpt/profile.json` | Your preset values (email, LinkedIn, phone…). Menu bar → Edit Profile… |
| `…/history.json` | Last 10 text copies |
| `…/.env` | `JEV_API_KEY`, copied from this folder by the install script |
| `…/last-jev-request.json` | Exact body of the most recent Jev request |

Password-manager copies (marked concealed or transient) are skipped entirely.

## Build and run

```bash
swift test                          # 32 tests
./scripts/build_app.sh              # dist/ClipboardOpt.app
./scripts/install_launch_agent.sh   # install to ~/Applications and start at login
```

Needs **Accessibility** permission (System Settings → Privacy & Security → Accessibility).

Logs: Console.app, subsystem `com.rishi.clipboardopt`. Timing lines: `local_ms`, `round_trip_ms`, `total_ms`. No clipboard content is logged.

## Uninstall

```bash
launchctl unload ~/Library/LaunchAgents/com.rishi.clipboardopt.plist
rm ~/Library/LaunchAgents/com.rishi.clipboardopt.plist
rm -rf ~/Applications/ClipboardOpt.app
```
