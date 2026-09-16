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

function parseIds(raw) {
  try {
    var parsed = JSON.parse(raw)
    return Array.isArray(parsed.ids) ? parsed.ids : []
  } catch (e) {
    return []
  }
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

function changeLabel(kind, language) {
  if (language === "nl") return kind === "new" ? "nieuw" : "gewijzigd"
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
// repeat it -- "7  7 wijzigingen" reads as a bug.
function headlineFor(digest, language) {
  var nl = language === "nl"
  if (digest.status === "empty") return nl ? "Rustig op de wiki" : "Quiet on the wiki"
  if (digest.status === "nodigest") return nl ? "Nog geen overzicht" : "No digest yet"
  var n = (digest.items || []).length
  if (nl) return n === 1 ? "wijziging" : "wijzigingen"
  return n === 1 ? "change" : "changes"
}

function subtitleFor(digest, language) {
  var nl = language === "nl"
  var stats = digest.stats || {}
  if (digest.status === "empty") {
    return nl ? "Niemand heeft iets aangepast sinds je vorige overzicht."
              : "Nobody touched the wiki since your last digest."
  }
  var bits = []
  if (stats.authors) bits.push(stats.authors + (nl ? " collega's" : " colleagues"))
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
    default:
      return ""
  }
}
