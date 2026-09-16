# Wiki Pulse

A daily digest of what your colleagues wrote on an [Outline](https://www.getoutline.com)
wiki, for the [Omarchy](https://omarchy.org) bar.

It is built around one constraint: **it may interrupt you exactly once a day.**
At 09:00 — or at boot, whichever comes first — it takes over the screen with a
ranked, summarised digest that you have to dismiss. The rest of the day it is a
silent count in the bar. No notifications, ever, with one deliberate exception
noted below.

The summaries answer *"where could I help, and what should I prioritise?"*, not
*"what changed"*. Every item carries a line about why it concerns you
specifically — and says plainly when it does not, rather than inventing a
connection.

## How it works

```
systemd timer ─┐
               ├─► omarchy-wiki-digest ─► Outline API ─► local diff ─► claude -p ─► digest.json
post-boot hook ┘                                                                      │
                                                                                      ▼
                                                                        Quickshell overlay + badge
```

- **Change detection is a watermark, not a time window.** Away for five days,
  you get one digest covering five days.
- **Diffs are computed locally** against the text as it stood when you last saw
  it, so the model reads what changed rather than the whole wiki — and the
  baseline is *your last digest*, not the previous revision.
- **The model never emits identifiers.** Documents go in as `D1`…`D40`; titles,
  URLs and authors are joined back from local data, so a hallucinated link
  cannot reach the widget.
- **The watermark, the baselines and the daily stamp commit together or not at
  all.** Any failure leaves the cursor untouched and the next retry sees the
  identical change set.

## Requirements

Omarchy 4+, `python3`, `jq`, and the [Claude Code](https://claude.com/claude-code)
CLI signed in (`claude setup-token` for a long-lived headless token). An Outline
API token with read access.

## Install

```bash
omarchy plugin add https://github.com/jevido/omarchy-wiki-pulse --enable
~/.config/omarchy/plugins/jevido.wiki/bin/setup
```

`bin/setup` is a separate step on purpose: `omarchy plugin add` deliberately
never runs plugin code, and quietly installing systemd units behind that warning
would be a poor way to repay the trust. It prints what it will write first.

Then edit `~/.config/omarchy/wiki-digest.json`:

```json
{
  "baseUrl": "https://wiki.example.com",
  "tokenCommand": "echo $OUTLINE_API_KEY",
  "language": "en",
  "persona": "senior backend engineer",
  "maxItems": 40,
  "includeOwnEdits": false,
  "bootstrapDays": 7
}
```

`tokenCommand` is run through `bash -c`; point it at `pass`, a file, an
environment variable, whatever you already use. The token is read at exec time
and never written to the digest or the log.

`persona` and `language` go into the prompt — they are what make the relevance
line about *you*.

## Verifying

```bash
omarchy-wiki-digest run --window P7D --dry-run   # proves auth and diffing, no LLM call
omarchy-wiki-digest run --window P7D             # a real digest
omarchy-wiki-digest status                       # cursor, last run, failure count
```

To test the once-a-day trigger without waiting for tomorrow:

```bash
date -d yesterday +%F > ~/.local/state/omarchy-wiki-digest/last-success
systemctl --user start omarchy-wiki-digest.service   # generates and opens
systemctl --user start omarchy-wiki-digest.service   # exits in milliseconds
```

## When things break

Every failure degrades to *"yesterday's digest, retried within the hour"* —
never to a blank or corrupt widget.

| Failure | What you see |
|---|---|
| Wiki unreachable | Previous digest stays; badge greys out. Retries hourly until 13:00. |
| Claude unavailable or times out | Real titles, authors, collections and links, without summaries. The retry upgrades it in place. |
| Nothing changed | A short "quiet on the wiki" card. This is a success, not an error. |
| Too many changes | The newest `maxItems` are summarised; the rest are still marked seen so the backlog cannot loop. |
| Credentials rejected | After three consecutive days, one critical notification. This is the only notification this plugin ever sends — a silently dead token is exactly how the last one rotted unnoticed. |

Logs: `journalctl --user -u omarchy-wiki-digest.service`, plus
`~/.local/state/omarchy-wiki-digest/digest.log` and `last-payload.txt` (the
exact model input, for when a summary looks wrong).

## Files it owns

```
~/.config/omarchy/wiki-digest.json              config (yours, never overwritten)
~/.local/share/omarchy-wiki-digest/digest.json  what the overlay renders
~/.local/state/omarchy-wiki-digest/             watermark, baselines, daily stamp, log
```

## Keys

`↑`/`↓` or `j`/`k` to move, `Enter` to open in the browser, `Esc` or **Got it**
to dismiss. Clicking outside does *not* dismiss — clearing the morning briefing
should take a real action.
