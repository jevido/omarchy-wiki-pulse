import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "DigestModel.js" as Model

// The quiet half of the plugin: a count, and nothing else.
//
// It never notifies, never animates for attention and never opens anything on
// its own. The whole point of the app is that the wiki interrupts exactly once
// a day; everything between those moments has to be glanceable and silent.
BarWidget {
  id: root
  moduleName: "jevido.wiki"

  readonly property string home: Quickshell.env("HOME")
  readonly property string dataDir: home + "/.local/share/omarchy-wiki-digest"
  readonly property string glyph: setting("glyph", "󰂺")
  // Off by default: this is the only way back into today's digest once it has
  // been dismissed, so a widget that disappears on a quiet day takes the door
  // with it. Opt in if you would rather reclaim the bar space.
  readonly property bool hideWhenEmpty: setting("hideWhenEmpty", false)

  property var digest: Model.EMPTY
  property var pulse: Model.EMPTY_PULSE
  property var read: Model.EMPTY_READ

  // Unread means two things that add up to one number: the digest rows the
  // reader has not cleared, plus anything that landed after it was built. Both
  // halves are counted the same way the overlay filters them, so the badge is
  // the length of the list the dialog opens on -- never a different number.
  readonly property int unreadDigest: Model.unreadItems(digest, read).length
  readonly property int sinceDigest: Model.unseenPulseCount(pulse, read.pulseSeen)
  readonly property int count: unreadDigest + sinceDigest
  readonly property bool stale: pulse.health === "stale"

  visible: !root.hideWhenEmpty || count > 0
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    digestFile.reload()
    pulseFile.reload()
    readFile.reload()
  }

  function openDigest() {
    if (root.bar && root.bar.shell && typeof root.bar.shell.summon === "function")
      root.bar.shell.summon("jevido.wiki", "{}")
  }

  FileView {
    id: digestFile
    path: root.dataDir + "/digest.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.digest = Model.parse(text())
    // text() is stale inside the change signal; reload first, parse in onLoaded.
    onFileChanged: reload()
    onLoadFailed: root.digest = Model.EMPTY
  }

  FileView {
    id: pulseFile
    path: root.dataDir + "/pulse.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.pulse = Model.parsePulse(text())
    onFileChanged: reload()
    onLoadFailed: root.pulse = Model.EMPTY_PULSE
  }

  FileView {
    id: readFile
    path: root.home + "/.local/state/omarchy-wiki-digest/read.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.read = Model.parseRead(text())
    onFileChanged: reload()
    onLoadFailed: root.read = Model.EMPTY_READ
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.count > 0 && !root.vertical ? root.glyph + "  " + root.count : root.glyph
    labelVisible: !root.vertical
    hasVisualContent: true
    // Three states worth telling apart at a glance: something new (full
    // strength), nothing new (present but receding), and a wiki we could not
    // reach (clearly dimmed -- a confident count we cannot back up would be
    // worse than no count).
    opacity: root.stale ? 0.4 : (root.count > 0 ? 1.0 : 0.62)
    Behavior on opacity { NumberAnimation { duration: 180 } }
    // The shortcut lives in the tooltip because that is where someone looks
    // when they wonder what this icon does.
    readonly property string shortcutHint: root.setting("shortcut", "Super+D")
    tooltipText: {
      var suffix = shortcutHint ? "  (" + shortcutHint + ")" : ""
      if (root.stale) return qsTr("Wiki unreachable — count may be out of date") + suffix
      if (root.count === 0) return qsTr("Nothing new on the wiki") + suffix
      var parts = []
      if (root.unreadDigest > 0) parts.push(root.unreadDigest + qsTr(" in today's digest"))
      if (root.sinceDigest > 0) parts.push(root.sinceDigest + qsTr(" since this morning"))
      return parts.join(", ") + suffix
    }

    onPressed: function (b) {
      if (b === Qt.RightButton) root.refresh()
      else if (b === Qt.MiddleButton) Quickshell.execDetached(["omarchy-wiki-pulse"])
      else root.openDigest()
    }
  }
}
