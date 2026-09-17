import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "DigestModel.js" as Model

// The quiet half of the plugin: a count, and nothing else.
//
// It never notifies, never animates for attention and never opens anything on
// its own. The whole point of the app is that work interrupts you exactly once
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
  // Which sources the overlay opens on. Stored here rather than in the
  // overlay because it is a preference, not a view state: the overlay's own
  // `s` still switches freely once you are in there.
  readonly property string sourceFilter: Model.normalisedSourceView(setting("sourceFilter", "both"))
  property bool settingsOpen: false

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
      root.bar.shell.summon("jevido.wiki", JSON.stringify({ source: root.sourceFilter }))
  }

  // Applied locally first so the popup redraws on the click itself; the
  // shell.json write comes back through the bar as the same value. With no
  // writable entry it stays a session preference rather than doing nothing.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function runDigest() {
    Quickshell.execDetached(["omarchy-wiki-digest", "run", "--force", "--no-show"])
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
    // strength), nothing new (present but receding), and a source we could not
    // reach (clearly dimmed -- a confident count we cannot back up would be
    // worse than no count).
    opacity: root.stale ? 0.4 : (root.count > 0 ? 1.0 : 0.62)
    Behavior on opacity { NumberAnimation { duration: 180 } }
    // The shortcut lives in the tooltip because that is where someone looks
    // when they wonder what this icon does.
    readonly property string shortcutHint: root.setting("shortcut", "Super+D")
    tooltipText: {
      var suffix = shortcutHint ? "  (" + shortcutHint + ")" : ""
      if (root.stale) return qsTr("A source was unreachable — count may be out of date") + suffix
      if (root.count === 0) return qsTr("Nothing new to read") + suffix
      var parts = []
      if (root.unreadDigest > 0) parts.push(root.unreadDigest + qsTr(" in today's digest"))
      if (root.sinceDigest > 0) parts.push(root.sinceDigest + qsTr(" since this morning"))
      return parts.join(", ") + suffix
    }

    onPressed: function (b) {
      // Right click used to reload the three files behind the badge, which is
      // something you would only ever do while suspecting a bug. The settings
      // are what someone actually reaches for, and the reload is a button in
      // there.
      if (b === Qt.RightButton) root.settingsOpen = !root.settingsOpen
      else if (b === Qt.MiddleButton) Quickshell.execDetached(["omarchy-wiki-pulse"])
      else root.openDigest()
    }
  }

  PopupCard {
    id: settingsPopup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.settingsOpen
    contentWidth: settingsPopup.fittedContentWidth(Style.space(340))
    contentHeight: settingsPopup.fittedContentHeight(settingsColumn.implicitHeight)

    readonly property color ink: Color.popups.text

    Column {
      id: settingsColumn
      anchors.fill: parent
      spacing: Style.space(12)

      Text {
        text: qsTr("OPENS ON")
        color: Qt.darker(settingsPopup.ink, 1.5)
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.bodySmall
        font.letterSpacing: 1
      }

      ButtonGroup {
        width: parent.width
        options: [
          { value: "both", label: qsTr("Both") },
          { value: "jira", label: "Jira" },
          { value: "wiki", label: qsTr("Wiki") }
        ]
        value: root.sourceFilter
        foreground: settingsPopup.ink
        fontFamily: Style.font.menuFamily
        onChanged: function (value) { root.persistSettings({ sourceFilter: value }) }
      }

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: qsTr("Which sources the digest opens on. `s` cycles them once you are in it.")
        color: Qt.darker(settingsPopup.ink, 2.0)
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        text: qsTr("BAR")
        color: Qt.darker(settingsPopup.ink, 1.5)
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.bodySmall
        font.letterSpacing: 1
      }

      Row {
        width: parent.width
        spacing: Style.space(8)

        TextField {
          id: glyphField
          width: parent.width - glyphApply.width - Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: root.glyph
          placeholderText: "󰂺"
          foreground: settingsPopup.ink
          font.family: Style.font.menuFamily
          Keys.onPressed: function (event) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.persistSettings({ glyph: glyphField.text })
              event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
              glyphField.text = root.glyph
              event.accepted = true
            }
          }
        }

        Button {
          id: glyphApply
          anchors.verticalCenter: parent.verticalCenter
          text: qsTr("Apply")
          bordered: true
          foreground: settingsPopup.ink
          fontFamily: Style.font.menuFamily
          onClicked: root.persistSettings({ glyph: glyphField.text })
        }
      }

      Toggle {
        width: parent.width
        label: qsTr("Hide when there is nothing new")
        description: qsTr("Off by default: this is the only way back into today\u2019s digest")
        checked: root.hideWhenEmpty
        foreground: settingsPopup.ink
        fontFamily: Style.font.menuFamily
        onClicked: root.persistSettings({ hideWhenEmpty: !root.hideWhenEmpty })
      }

      Text {
        text: qsTr("ACTIONS")
        color: Qt.darker(settingsPopup.ink, 1.5)
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.bodySmall
        font.letterSpacing: 1
      }

      Button {
        width: parent.width
        text: qsTr("Refresh the count now")
        bordered: true
        leftAlign: true
        foreground: settingsPopup.ink
        fontFamily: Style.font.menuFamily
        onClicked: Quickshell.execDetached(["omarchy-wiki-pulse"])
      }

      Button {
        width: parent.width
        text: qsTr("Rebuild the digest")
        bordered: true
        leftAlign: true
        foreground: settingsPopup.ink
        fontFamily: Style.font.menuFamily
        onClicked: root.runDigest()
      }

      // Tokens, JQL and persona stay in the file. They are secrets and
      // long-lived choices, and a popup that can be summoned over a shared
      // screen is the wrong place to keep either readable.
      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: qsTr("Tokens, JQL and persona live in ~/.config/omarchy/wiki-digest.json")
        color: Qt.darker(settingsPopup.ink, 2.0)
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
