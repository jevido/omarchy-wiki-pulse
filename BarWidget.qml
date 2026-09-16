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
  readonly property string glyph: setting("glyph", "󰖝")
  readonly property bool hideWhenEmpty: setting("hideWhenEmpty", true)

  property var digest: Model.EMPTY
  property var pulse: ({ newSinceDigest: 0, health: "ok" })
  property var readIds: []
  property string readAt: ""

  // Unread means two different things that add up to one number: a digest the
  // reader has not cleared yet, plus anything that landed since it was built.
  readonly property int unreadDigest: {
    if (!digest.generatedAt) return 0
    if (readAt && readAt >= digest.generatedAt) return 0
    return (digest.items || []).length
  }
  readonly property int sinceDigest: pulse.newSinceDigest || 0
  readonly property int count: unreadDigest + sinceDigest
  readonly property bool stale: pulse.health === "stale"

  visible: root.hideWhenEmpty ? count > 0 : true
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
    onLoaded: {
      try {
        root.pulse = JSON.parse(text())
      } catch (e) {
        root.pulse = { newSinceDigest: 0, health: "stale" }
      }
    }
    onFileChanged: reload()
    onLoadFailed: root.pulse = { newSinceDigest: 0, health: "ok" }
  }

  FileView {
    id: readFile
    path: root.home + "/.local/state/omarchy-wiki-digest/read.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        root.readAt = JSON.parse(text()).readAt || ""
      } catch (e) {
        root.readAt = ""
      }
    }
    onFileChanged: reload()
    onLoadFailed: root.readAt = ""
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.count > 0 ? root.glyph + "  " + root.count : root.glyph
    labelVisible: !root.vertical
    hasVisualContent: true
    // A greyed badge is honest about a wiki we could not reach; a confident
    // count we cannot back up would be worse than no count.
    opacity: root.stale ? 0.45 : 1.0
    tooltipText: {
      if (root.stale) return qsTr("Wiki unreachable — count may be out of date")
      if (root.count === 0) return qsTr("Nothing new on the wiki")
      var parts = []
      if (root.unreadDigest > 0) parts.push(root.unreadDigest + qsTr(" in today's digest"))
      if (root.sinceDigest > 0) parts.push(root.sinceDigest + qsTr(" since this morning"))
      return parts.join(", ")
    }

    onPressed: function (b) {
      if (b === Qt.RightButton) root.refresh()
      else if (b === Qt.MiddleButton) Quickshell.execDetached(["omarchy-wiki-pulse"])
      else root.openDigest()
    }
  }
}
