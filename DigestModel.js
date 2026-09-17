// Pure helpers for the digest surfaces. No QML imports, no side effects, so
// the parsing and formatting rules can be reasoned about (and fixed) without
// touching either view.

.pragma library

var EMPTY = {
  schemaVersion: 1,
  generatedAt: "",
  status: "nodigest",
  degradedReason: null,
  stats: {},
  tldr: "",
  items: []
}

// A half-written or missing file must render as "nothing yet", never as a
// broken widget — the pipeline writes atomically, but a first run, a cleared
// cache or a disk error can all still land here.
function parse(raw) {
  if (!raw) return EMPTY
  try {
    var parsed = JSON.parse(raw)
    if (!parsed || typeof parsed !== "object" || !Array.isArray(parsed.items)) return EMPTY
    return parsed
  } catch (e) {
    return EMPTY
  }
}

var EMPTY_READ = { readAt: "", digestGeneratedAt: "", ids: [], pulseSeen: [] }

// What the reader has already cleared. Absent or unreadable means "nothing
// read", which errs towards showing a change twice rather than swallowing it.
function parseRead(raw) {
  if (!raw) return EMPTY_READ
  try {
    var parsed = JSON.parse(raw)
    if (!parsed || typeof parsed !== "object") return EMPTY_READ
    return {
      readAt: parsed.readAt || "",
      digestGeneratedAt: parsed.digestGeneratedAt || "",
      ids: Array.isArray(parsed.ids) ? parsed.ids : [],
      pulseSeen: Array.isArray(parsed.pulseSeen) ? parsed.pulseSeen : []
    }
  } catch (e) {
    return EMPTY_READ
  }
}

// The read record belongs to one digest. A newer digest has never been read,
// however many ids the old record happens to carry -- ids can repeat when the
// same page changes again.
function unreadItems(digest, read) {
  var items = digest.items || []
  if (!read || read.digestGeneratedAt !== (digest.generatedAt || "")) return items.slice()
  var ids = read.ids || []
  return items.filter(function (item) {
    return ids.indexOf(item.id) === -1
  })
}

var EMPTY_PULSE = { newSinceDigest: 0, health: "ok", items: [] }

// Same contract as parse(): an unreadable pulse file is "nothing new", never a
// broken widget. `items` may be absent on a file written by an older build, so
// callers fall back to the bare count.
function parsePulse(raw) {
  if (!raw) return EMPTY_PULSE
  try {
    var parsed = JSON.parse(raw)
    if (!parsed || typeof parsed !== "object") return EMPTY_PULSE
    return {
      newSinceDigest: parsed.newSinceDigest || 0,
      health: parsed.health || "ok",
      items: Array.isArray(parsed.items) ? parsed.items : null
    }
  } catch (e) {
    return EMPTY_PULSE
  }
}

// Must match pulse_key() in the pipeline: id plus timestamp, so a page edited
// again after you cleared it counts as new rather than staying dismissed.
function pulseKey(item) {
  return (item.id || "") + "@" + (item.updatedAt || "")
}

// What the reader has not cleared yet. A pulse file without items (older
// build, or one written before this feature) has nothing to filter, so the
// caller keeps using its count.
function unseenPulse(pulse, seen) {
  if (!pulse || !pulse.items) return []
  var keys = seen || []
  return pulse.items.filter(function (item) {
    return keys.indexOf(pulseKey(item)) === -1
  })
}

function unseenPulseCount(pulse, seen) {
  if (!pulse) return 0
  if (!pulse.items) return pulse.newSinceDigest || 0
  return unseenPulse(pulse, seen).length
}

function freshHeading(language) {
  return language === "nl" ? "Sinds vanochtend" : "Since this morning"
}

// Which pipeline a row came from. Rows written before Jira existed have no
// source and are wiki rows, which is what they were.
function sourceOf(item) {
  return (item && item.source) || "wiki"
}

function bySource(items, source) {
  return (items || []).filter(function (item) { return sourceOf(item) === source })
}

// The section headings, keyed by the row index they sit above.
//
// The two sources only get named when both are on screen: a heading that never
// has a sibling is decoration, and this surface has no room for decoration. The
// "since this morning" divider is a time boundary, not a source one, so it is
// always drawn when there is a tail to head.
function headings(wikiCount, jiraCount, freshCount, language) {
  var map = {}
  if (wikiCount > 0 && jiraCount > 0) {
    map[0] = { title: "Wiki", note: "" }
    map[wikiCount] = { title: "Jira", note: "" }
  }
  if (freshCount > 0) {
    map[wikiCount + jiraCount] = {
      title: freshHeading(language),
      note: freshNote(language)
    }
  }
  return map
}

// The two things the overlay can be showing. Unread is the door you come in
// through; everything is the briefing itself, re-readable all day.
function modeLabel(showingAll, language) {
  var nl = language === "nl"
  if (showingAll) return nl ? "Alleen ongelezen" : "Unread only"
  return nl ? "Alles" : "Everything"
}

function modeHint(showingAll, language) {
  var nl = language === "nl"
  if (showingAll) return nl ? "d ongelezen" : "d unread"
  return nl ? "d alles" : "d everything"
}

// Points at the other view rather than just stating the obvious: an inbox that
// is empty because you read it has nowhere else to say where the day went.
function caughtUpHint(language) {
  return language === "nl" ? "d toont het volledige overzicht"
                           : "d shows the full digest"
}

// Says why these rows read differently from the ones above them, so a missing
// summary looks like a deliberate boundary rather than a failed LLM call.
function freshNote(language) {
  return language === "nl" ? "nog niet samengevat" : "not summarised yet"
}

var PRIORITY_ORDER = { high: 0, medium: 1, low: 2 }

function sorted(items) {
  var copy = (items || []).slice()
  copy.sort(function (a, b) {
    var pa = PRIORITY_ORDER[a.priority] === undefined ? 3 : PRIORITY_ORDER[a.priority]
    var pb = PRIORITY_ORDER[b.priority] === undefined ? 3 : PRIORITY_ORDER[b.priority]
    if (pa !== pb) return pa - pb
    return (a.rank || 999) - (b.rank || 999)
  })
  return copy
}

// One glyph per action, so the eye can triage the list before reading it.
function actionGlyph(action) {
  switch (action) {
    case "blocked-on-me": return ""
    case "assist":        return ""
    case "review":        return ""
    default:              return ""
  }
}

function actionLabel(action, language) {
  var nl = language === "nl"
  switch (action) {
    case "blocked-on-me": return nl ? "wacht op jou" : "waiting on you"
    case "assist":        return nl ? "hulp mogelijk" : "you could help"
    case "review":        return nl ? "review"        : "review"
    default:              return nl ? "ter info"      : "fyi"
  }
}

function changeLabel(kind, language, source) {
  var nl = language === "nl"
  if ((source || "wiki") === "jira") {
    if (nl) return kind === "new" ? "nieuw ticket" : "ticket bijgewerkt"
    return kind === "new" ? "new ticket" : "ticket updated"
  }
  if (nl) return kind === "new" ? "nieuw" : "gewijzigd"
  return kind === "new" ? "new" : "updated"
}

// Deliberately coarse: the exact minute a colleague saved is noise, the fact
// that it was yesterday is the signal.
function relativeTime(iso, language) {
  if (!iso) return ""
  var then = new Date(iso.replace(/Z$/, "+00:00"))
  if (isNaN(then.getTime())) return ""
  var nl = language === "nl"
  var minutes = Math.round((Date.now() - then.getTime()) / 60000)
  if (minutes < 60) return nl ? "zojuist" : "just now"
  var hours = Math.round(minutes / 60)
  if (hours < 24) return hours + (nl ? " uur geleden" : "h ago")
  var days = Math.round(hours / 24)
  if (days === 1) return nl ? "gisteren" : "yesterday"
  if (days < 7) return days + (nl ? " dagen geleden" : " days ago")
  var weeks = Math.round(days / 7)
  return weeks + (nl ? " weken geleden" : "w ago")
}

// The count is rendered as its own large numeral, so the headline must not
// repeat it -- "7  7 wijzigingen" reads as a bug. `count` is what is actually
// on screen, which depends on the view: the status words describe the day, and
// a day with seven changes you have already read is not a quiet one.
function headlineFor(digest, language, count) {
  var nl = language === "nl"
  var n = count || 0
  if (n === 0) {
    if (digest.status === "nodigest") return nl ? "Nog geen overzicht" : "No digest yet"
    if (digest.status === "empty") return nl ? "Rustig vandaag" : "A quiet day"
    return nl ? "Alles gelezen" : "All caught up"
  }
  if (nl) return n === 1 ? "wijziging" : "wijzigingen"
  return n === 1 ? "change" : "changes"
}

function subtitleFor(digest, language) {
  var nl = language === "nl"
  var stats = digest.stats || {}
  if (digest.status === "empty") {
    return nl ? "Niemand heeft iets aangepast sinds je vorige overzicht."
              : "Nobody touched anything since your last digest."
  }
  var bits = []
  if (stats.authors) bits.push(stats.authors + (nl ? " collega's" : " colleagues"))
  if (stats.documentsSummarized) bits.push(stats.documentsSummarized + (nl ? " pagina's" : " pages"))
  if (stats.issuesSummarized) bits.push(stats.issuesSummarized + (nl ? " tickets" : " tickets"))
  if (stats.collections) bits.push(stats.collections + (nl ? " collecties" : " collections"))
  if (stats.daysCovered > 1) bits.push(stats.daysCovered + (nl ? " dagen" : " days"))
  return bits.join(" · ")
}

function degradedNotice(digest, language) {
  var nl = language === "nl"
  switch (digest.degradedReason) {
    case "llm_unavailable":
    case "llm_timeout":
      return nl ? "Samenvattingen zijn nu niet beschikbaar — dit is de kale lijst."
                : "Summaries unavailable — this is the plain list."
    case "truncated":
      return nl ? "Te veel wijzigingen om allemaal samen te vatten; de rest staat niet in deze lijst."
                : "Too many changes to summarise; the remainder is not listed."
    case "wiki_unreachable":
      return nl ? "De wiki was niet bereikbaar; dit is het vorige overzicht."
                : "The wiki was unreachable; this is the previous digest."
    case "auth_failed":
      return nl ? "Aanmelden bij de wiki is geweigerd — controleer je API-token."
                : "The wiki rejected our credentials — check the API token."
    // Jira failing costs you the tickets, not the morning: the wiki half below
    // is complete, so this says what is missing rather than crying failure.
    case "jira_unreachable":
      return nl ? "Jira was niet bereikbaar; deze briefing gaat alleen over de wiki."
                : "Jira was unreachable; this briefing covers the wiki only."
    case "jira_auth_failed":
      return nl ? "Jira weigerde je inloggegevens — controleer het API-token."
                : "Jira rejected our credentials — check the API token."
    default:
      return ""
  }
}

// "woensdag 16 september, 09:00" -- enough to tell two digests apart at a
// glance without turning the header into a timestamp.
function digestDate(digest, language) {
  return formatMoment(digest && digest.generatedAt, language)
}

// Where the briefing starts. Watermark-based, so after a week away this says
// last Tuesday rather than pretending the window is always a day.
function coverageFor(digest, language) {
  var when = formatMoment(digest && digest.coversSince, language)
  if (!when) return ""
  return (language === "nl" ? "sinds " : "since ") + when
}

function formatMoment(raw, language) {
  if (!raw) return ""
  var d = new Date(raw)
  if (isNaN(d.getTime())) return ""
  var nl = language === "nl"
  var days = nl ? ["zondag","maandag","dinsdag","woensdag","donderdag","vrijdag","zaterdag"]
               : ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]
  var months = nl ? ["januari","februari","maart","april","mei","juni","juli",
                     "augustus","september","oktober","november","december"]
                  : ["January","February","March","April","May","June","July",
                     "August","September","October","November","December"]
  var hh = ("0" + d.getHours()).slice(-2)
  var mm = ("0" + d.getMinutes()).slice(-2)
  return days[d.getDay()] + " " + d.getDate() + " " + months[d.getMonth()] + ", " + hh + ":" + mm
}
