# Wiki Pulse

A daily digest of what your colleagues wrote on an [Outline](https://www.getoutline.com)
wiki and moved in [Jira](https://www.atlassian.com/software/jira), for the
[Omarchy](https://omarchy.org) bar.

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
                          ┌─► Outline API ─► local diff ──┐
systemd timer ─┐          │                               │
               ├─► omarchy-wiki-digest                    ├─► claude -p ─► digest.json
post-boot hook ┘          │                               │                   │
                          └─► Jira API ─► transitions,  ──┘                   ▼
                                          comments, new     Quickshell overlay + badge
```

- **Change detection is a watermark, not a time window.** Away for five days,
  you get one digest covering five days.
- **Each source carries its own cursor.** Jira being unreachable costs you the
  tickets, never the wiki half of the briefing — and never the day, because the
  Jira watermark only advances on a run that actually reached it.
- **Diffs are computed locally** against the text as it stood when you last saw
  it, so the model reads what changed rather than the whole wiki — and the
  baseline is *your last digest*, not the previous revision.
- **The model never emits identifiers.** Documents go in as `D1`…`D40` and
  tickets as `J1`…`J25`; titles, URLs, authors and issue keys are joined back
  from local data, so a hallucinated link cannot reach the widget.
- **Jira is filtered down to what a colleague would tell you.** New tickets,
  status transitions and new comments. A re-estimate, a label or a sprint move
  is real work, but it is not something you need read to you at nine.
- **The watermark, the baselines and the daily stamp commit together or not at
  all.** Any failure leaves the cursor untouched and the next retry sees the
  identical change set.

## Requirements

Omarchy 4+, `python3`, `jq`, and the [Claude Code](https://claude.com/claude-code)
CLI signed in (`claude setup-token` for a long-lived headless token). An Outline
API token with read access. Jira is optional: leave the `jira` block out and
nothing in the pipeline so much as resolves a token for it.

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
  "bootstrapDays": 7,
  "jira": {
    "baseUrl": "https://example.atlassian.net",
    "email": "you@example.com",
    "tokenCommand": "echo $JIRA_API_TOKEN",
    "jql": "",
    "maxItems": 25,
    "includeOwnChanges": false,
    "bootstrapDays": 7
  }
}
```

`tokenCommand` is run through `bash -c`; point it at `pass`, a file, an
environment variable, whatever you already use. The token is read at exec time
and never written to the digest or the log.

`persona` and `language` go into the prompt — they are what make the relevance
line about *you*.

### Jira

Create an [API token](https://id.atlassian.com/manage-profile/security/api-tokens)
and pair it with the account's `email`; the two are sent as Basic auth. On a
Data Center instance, leave `email` empty and hand `tokenCommand` a personal
access token — it goes as a bearer instead.

Atlassian issues two kinds, and they are reached differently. A **classic**
token authenticates against the site itself. A **scoped** token is rejected
there with a bare 401 and only works through `api.atlassian.com`, which
addresses the site by cloud id rather than by hostname — so the first 401 makes
the pipeline ask the site for its own id (`/_edge/tenant_info`), cache it, and
route through the gateway from then on. Set `cloudId` yourself only if this
machine cannot reach that endpoint. `baseUrl` stays the site either way, so
ticket links are always ones a browser can open.

Scopes, if you are asked for them: `read:jira-work` and `read:jira-user`.
Nothing else, and never a write scope — the digest only reads.

`jql` narrows what the digest watches, and everything your account can see is
the default. It is ANDed with the watermark bound, so write only the filter:

```json
"jql": "project in (PLAT, OPS)"
"jql": "project = PLAT AND component = billing"
"jql": "'Team[Team]' = engineering"
```

`includeOwnChanges` is `false`, so your own transitions and comments do not come
back to you — a ticket you moved still appears when someone else comments on it.

## Verifying

```bash
omarchy-wiki-digest run --window P7D --dry-run   # proves both credentials and the diffing, no LLM call
omarchy-wiki-digest run --window P7D             # a real digest
omarchy-wiki-digest status                       # cursors, last run, failure count
```

`--dry-run` prints the exact payload, so the `J` blocks are where you check
that your JQL selects what you meant it to.

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
| Jira unreachable or its token rejected | The wiki half of the digest, with a line saying the tickets are missing. Deliberately *not* treated as degraded: the day is still briefed, and the overlay does not reopen on every retry until the credential is fixed. Jira's cursor stays put, so nothing is lost. |
| Claude unavailable or times out | Real titles, authors, collections and links, without summaries. The retry upgrades it in place. |
| Nothing changed | A short "a quiet day" card. This is a success, not an error. |
| Too many changes | The newest `maxItems` are summarised; the rest are still marked seen so the backlog cannot loop. |
| Credentials rejected | After three consecutive days, one critical notification. This is the only notification this plugin ever sends — a silently dead token is exactly how the last one rotted unnoticed. |

Logs: `journalctl --user -u omarchy-wiki-digest.service`, plus
`~/.local/state/omarchy-wiki-digest/digest.log` and `last-payload.txt` (the
exact model input, for when a summary looks wrong).

## Files it owns

```
~/.config/omarchy/wiki-digest.json              config (yours, never overwritten)
~/.local/share/omarchy-wiki-digest/digest.json  what the overlay renders
~/.local/share/omarchy-wiki-digest/pulse.json   changes since that digest was built
~/.local/state/omarchy-wiki-digest/             watermarks, baselines, ticket cursor, daily stamp, log
```

## Between digests

The digest is built once. What lands after it is picked up by `pulse`, which
counts the changes *and* records them, so the badge and the overlay always
describe the same thing — a count the dialog cannot show would just read as a
broken app. Those rows appear under a "Since this morning" divider, without
summaries: summarising is the morning run's job, and pulse never calls the
model. Dismissing the overlay clears them from the badge; a page or ticket
touched again afterwards comes back.

Pulse is deliberately a reader — it touches neither the watermark, the
baselines nor the daily stamp, so it can never swallow a change the morning
digest still owes you.

## The widget

The bar icon is always there, so today's digest is always one click away — left
click reopens it, right click refreshes the count, middle click runs a pulse. When something is new the
icon carries a count and brightens; when the wiki cannot be reached it dims,
because a confident count we cannot back up is worse than no count.

Set `hideWhenEmpty` to `true` in the layout entry if you would rather it
disappear on a quiet day and reclaim the bar space.

### Keyboard shortcut

There is no shortcut out of the box — bind one yourself, since which keys are
free is personal. See [hypr/](hypr/) for the binding and the layer rule that
stops the compositor fading the overlay on top of its own animation.

On a quiet day the digest shows an illustration rather than a blank panel.
`empty.svg` is an ordinary SVG with `{{accent}}`, `{{fg}}`, `{{bg}}` and
`{{dim}}` placeholders, substituted at load, so swapping the art for your own
is editing one file.

## Wiki and Jira

Both sources go into one model call, ranked against each other, and then land in
the overlay as two blocks: the wiki first, Jira under it. The ranking is what
decides priority; the split is only about where the eye lands.

A ticket row carries the project, its current status and whoever last touched it,
so a row is recognisable as a ticket without a badge. Enter opens it in
`/browse/KEY`.

The "since this morning" tail stays one section, mixed. That divider marks a
boundary in time, not in source, and splitting it would imply those rows had been
triaged when nothing has read them.

## Two views

The overlay opens on what you have **not read yet** — the digest rows you never
cleared, plus anything the pulse found afterwards. Read it, dismiss it, open it
again an hour later and you get what arrived in that hour, not the same seven
pages a second time.

**Everything** (and `d`) is the briefing itself: the whole window the morning
run covered, read or not, summary and all. That is where you go when you
cleared the digest at 09:02 and want to know at four o'clock what the day
actually said. The header names the window it covers — watermark-based, so
after a week away it says last Tuesday rather than pretending it is always a
day.

An inbox that is empty because you read it looks exactly like one that is empty
because nothing happened, so the first says where the day went.

Each run still keeps the digest it replaced as `digest.prev.json`, which is
worth having when a summary reads wrong — but nothing in the overlay opens it.

## Keys

`↑`/`↓` or `j`/`k` to move, `Enter` to open in the browser, `d` to switch
between unread and everything, `Esc` or **Got it** to dismiss. Clicking outside
does *not* dismiss — clearing the morning briefing should take a real action.

`d` pairs with whatever you bound to open the overlay: bind `SUPER + D` and the
same finger opens it, switches view, and — because the compositor's binding
wins over the overlay's keyboard grab — `SUPER + D` again closes it.

Scriptable too: `omarchy-shell jevido.wiki everything` opens straight into the
full briefing.
