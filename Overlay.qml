import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.Commons
import qs.Ui
import "DigestModel.js" as Model

// The once-a-day fullscreen digest.
//
// Deliberately the only interruption this plugin ever makes, and deliberately
// modal: click-outside is not wired to dismiss, because clearing the morning
// briefing should take a real action rather than a stray click. Escape and the
// footer button are the two ways out.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  // Driven by the theme, never hardcoded, so `omarchy theme set` restyles the
  // digest live while it is on screen.
  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color scrim: Color.menu.scrim
  readonly property color accent: Color.accent
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))

  // One digest, two ways of reading it. Unread is what the overlay opens on --
  // an inbox, so the door you come in through never shows you the same change
  // twice. Everything is the briefing itself: the whole window the 09:00 run
  // covered, re-readable all day however much of it you have already cleared.
  property var digest: Model.EMPTY
  property var read: Model.EMPTY_READ
  property var pulse: Model.EMPTY_PULSE
  property bool showingAll: false

  // Which sources are on screen: both, jira, wiki. A view rather than a
  // setting -- the digest still collects everything, this only decides what
  // you are reading right now. The bar widget hands in the opening value; the
  // morning summon carries no payload and so always opens on everything.
  property string sourceView: "both"
  readonly property bool showWiki: root.sourceView !== "jira"
  readonly property bool showJira: root.sourceView !== "wiki"

  // Whether Jira is in play at all, read off the unfiltered digest rather than
  // off the config -- this surface only ever sees the files, and a digest with
  // no tickets in it has no second source worth naming.
  readonly property bool hasJira: Model.bySource(root.digest.items, "jira").length > 0
                                  || Model.bySource(root.pulse.items, "jira").length > 0

  // Both halves of the window. The digest is the summarised part; the pulse
  // rows are what landed after it was built, which belongs to the same day
  // even though no model has read them.
  readonly property var digestItems: Model.sorted(digest.items)
  readonly property var pulseItems: root.pulse.items || []
  readonly property var unreadDigest: Model.sorted(Model.unreadItems(root.digest, root.read))
  readonly property var unreadPulse: Model.unseenPulse(root.pulse, root.read.pulseSeen)

  // The summarised half, split by source: the wiki block, then the Jira block.
  // Ranking still happens across both in the model -- the split is about where
  // the eye lands, not about which change matters more.
  readonly property var summarisedAll: root.showingAll ? root.digestItems : root.unreadDigest
  readonly property var wikiRows: root.showWiki ? Model.bySource(root.summarisedAll, "wiki") : []
  readonly property var jiraRows: root.showJira ? Model.bySource(root.summarisedAll, "jira") : []
  // The tail keeps the same order, but it stays one section: that divider is a
  // time boundary, and splitting it by source would claim these rows were
  // triaged when nothing has read them.
  readonly property var freshAll: root.showingAll ? root.pulseItems : root.unreadPulse
  readonly property var freshRows: (root.showWiki ? Model.bySource(root.freshAll, "wiki") : [])
                             .concat(root.showJira ? Model.bySource(root.freshAll, "jira") : [])

  // The list the whole view derives from -- the numeral, the keyboard, the
  // cards and the empty state all read this one property, so they cannot
  // disagree about what is on screen.
  readonly property var rows: root.wikiRows.concat(root.jiraRows).concat(root.freshRows)
  // Section headings, keyed by the row index they sit above.
  readonly property var headings: Model.headings(root.wikiRows.length, root.jiraRows.length,
                                                 root.freshRows.length, root.language,
                                                 root.sourceView !== "both")
  // Nothing left to read, but the day was not empty -- the one state that has
  // somewhere else to point.
  readonly property bool caughtUp: !root.showingAll
                                   && root.rows.length === 0
                                   && root.digestItems.length + root.pulseItems.length > 0
  property string emptyArt: ""

  // The illustration ships as a plain SVG with colour placeholders. Qt's SVG
  // renderer has no notion of `currentColor`, so the tokens are substituted
  // here and the result handed to Image as a data URI — which keeps the art
  // editable as a file *and* theme-aware.
  readonly property string emptyArtUri: {
    if (!emptyArt) return ""
    var fg = root.foreground, bg = root.background
    var dim = Qt.rgba(bg.r + (fg.r - bg.r) * 0.45,
                      bg.g + (fg.g - bg.g) * 0.45,
                      bg.b + (fg.b - bg.b) * 0.45, 1)
    var svg = emptyArt.replace(/{{accent}}/g, String(root.accent))
                      .replace(/{{fg}}/g, String(fg))
                      .replace(/{{bg}}/g, String(bg))
                      .replace(/{{dim}}/g, String(dim))
    return "data:image/svg+xml;base64," + Qt.btoa(svg)
  }
  property string language: "nl"
  property bool animate: true
  property int selectedIndex: -1

  readonly property string home: Quickshell.env("HOME")
  readonly property string dataDir: home + "/.local/share/omarchy-wiki-digest"

  // The counter rolls up from zero on open; `counter` is what the label reads.
  property real counter: 0

  function open(payloadJson) {
    digestFile.reload()
    pulseFile.reload()
    readFile.reload()
    // The bar widget passes the view it is configured for. Anything else --
    // the 09:00 summon, a hotkey, an IPC call -- opens on everything, because
    // a briefing that silently hid half of itself would be worse than one
    // that shows a section you skip.
    root.sourceView = Model.normalisedSourceView(Model.openSource(payloadJson))
    // Always opens on the unread view; the full briefing is somewhere you go,
    // not a state you can get stuck in.
    root.showingAll = false
    root.opened = true
    root.restage()
    root.selectedIndex = -1
    root.counter = 0
    if (root.animate) counterAnim.restart()
    else root.counter = root.rows.length
    Qt.callLater(root.grabKeyboard)
  }

  function close() {
    root.opened = false
    root.revealItems = false
  }

  // Only the surface on the focused monitor holds the grab, so the focus call
  // has to find that one rather than whichever was built first.
  signal grabRequested()

  // Scrolling the list has to be asked for the same way, and for the same
  // reason: the Flickable lives inside the per-monitor delegate, and an id
  // declared in there is not visible out here. Reaching for it directly throws
  // -- which is exactly what selection-follows-keyboard did, silently, on
  // every arrow press. A signal crosses the boundary; an id does not.
  signal revealRequested(int index)

  function grabKeyboard() {
    root.grabRequested()
  }

  function dismiss() {
    root.opened = false
    markRead()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "jevido.wiki")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // Clearing the badge is the pipeline's job, not the view's — it owns the
  // state directory, and routing through it keeps one writer per file.
  function markRead() {
    Quickshell.execDetached(["omarchy-wiki-digest", "mark-read"])
  }

  // One row, rather than the whole briefing: the way you clear the two things
  // you have dealt with and leave the rest for after lunch.
  function markItem(index) {
    if (index < 0 || index >= root.rows.length) return
    var id = root.rows[index].id
    if (!id) return
    Quickshell.execDetached(["omarchy-wiki-digest", "mark-read", "--item", id])
    // In the unread view the row is about to disappear from under the cursor.
    // Staying at this index lands on whatever followed it, which is where the
    // eye already is; falling to the end of a shorter list would not be.
    if (!root.showingAll)
      root.selectedIndex = Math.min(index, root.rows.length - 2)
  }

  function openItem(index) {
    if (index < 0 || index >= root.rows.length) return
    var url = root.rows[index].url
    if (!url) return
    Quickshell.execDetached(["xdg-open", url])
    root.dismiss()
  }

  function move(delta) {
    if (root.rows.length === 0) return
    var next = root.selectedIndex + delta
    if (next < 0) next = 0
    if (next >= root.rows.length) next = root.rows.length - 1
    root.selectedIndex = next
    root.revealRequested(next)
  }

  function reload(raw) {
    root.digest = Model.parse(raw)
  }

  // Cards animate in on reveal, so a digest swap has to drop and retake the
  // flag -- otherwise the new delegates are built with it already true and
  // snap into place without the stagger.
  property bool revealItems: false

  Timer {
    id: restager
    interval: 16
    onTriggered: {
      root.revealItems = true
      // A new list starts at the top. Without this, switching views keeps the
      // old scroll offset and drops you into the middle of a list you have not
      // read a word of.
      root.revealRequested(0)
    }
  }

  function restage() {
    root.revealItems = false
    restager.restart()
  }

  function toggleAll() {
    root.showingAll = !root.showingAll
    root.restageView()
  }

  function cycleSource() {
    root.sourceView = Model.nextSourceView(root.sourceView)
    root.restageView()
  }

  // What both view switches have to do: the list underneath is a different
  // list, so the cursor and the stagger start over.
  //
  // The numeral does not. Rolling it up from zero is an arrival flourish, and
  // arrival happens once -- re-running it on every d and s press leaves the
  // number climbing through values that are not the answer for most of a
  // second, beside a word that changed instantly. A title that contradicts
  // itself is worse than one that does not animate. The running animation is
  // stopped first, or it would keep writing over the value on its way to a
  // target it was given before the list changed.
  function restageView() {
    root.selectedIndex = -1
    counterAnim.stop()
    root.counter = root.rows.length
    root.restage()
  }

  FileView {
    id: digestFile
    path: root.dataDir + "/digest.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.reload(text())
    // `text()` is stale inside the change signal itself, so both paths route
    // through reload() → onLoaded and always parse fresh content.
    onFileChanged: reload()
    onLoadFailed: root.reload("")
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

  // What separates the two views: without this everything is unread, which is
  // the safe direction to fail in.
  FileView {
    id: readFile
    path: root.home + "/.local/state/omarchy-wiki-digest/read.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.read = Model.parseRead(text())
    onFileChanged: reload()
    onLoadFailed: root.read = Model.EMPTY_READ
  }

  FileView {
    id: emptyArtFile
    path: String(Qt.resolvedUrl("empty.svg")).replace("file://", "")
    printErrors: false
    onLoaded: root.emptyArt = text()
  }

  FileView {
    id: configFile
    path: root.home + "/.config/omarchy/wiki-digest.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        root.language = JSON.parse(text()).language || "nl"
      } catch (e) {
        root.language = "nl"
      }
    }
    onFileChanged: reload()
  }

  NumberAnimation {
    id: counterAnim
    target: root
    property: "counter"
    from: 0
    to: root.rows.length
    duration: 620
    easing.type: Easing.OutCubic
  }

  // One surface per monitor. A digest that lands on the other screen is a
  // digest that gets missed, which is the one thing this app may not do -- so
  // it renders everywhere and only the focused monitor takes the keyboard.
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      readonly property bool primary: !Hyprland.focusedMonitor
                                      || Hyprland.focusedMonitor.name === modelData.name
      readonly property int cardWidth: Math.min(Style.space(1100), modelData.width - Style.gapsOut * 8)
      readonly property int cardHeight: Math.min(Style.space(820), modelData.height - Style.gapsOut * 8)

      screen: modelData
      visible: root.opened
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      WlrLayershell.namespace: "omarchy-wikipulse"
      WlrLayershell.layer: WlrLayer.Overlay
      // Two surfaces cannot both hold an exclusive grab; the focused one wins.
      WlrLayershell.keyboardFocus: root.opened && primary
                                   ? WlrKeyboardFocus.Exclusive
                                   : WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      Rectangle {
        anchors.fill: parent
        color: root.scrim
        opacity: root.opened ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      }

      BorderSurface {
        id: card
        width: panel.cardWidth
        // On a quiet day the card is two lines of text; framing that with a
        // screen of empty panel would read as a broken layout, not as calm.
        height: root.rows.length === 0
                ? content.implicitHeight + card.contentTopInset + card.contentBottomInset
                  + footer.height + Style.space(14)
                : panel.cardHeight
        Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        radius: Style.cornerRadius
        anchors.centerIn: parent
        color: root.background
        borderSpec: root.borderSpec
        padding: Style.spacing.panelPadding

        scale: root.opened ? 1.0 : 0.96
        opacity: root.opened ? 1 : 0
        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
        Behavior on opacity { NumberAnimation { duration: 180 } }

        Item {
          id: keyCatcher
          anchors.fill: parent
          focus: panel.primary
          Keys.priority: Keys.BeforeItem

          Connections {
            target: root
            function onGrabRequested() {
              if (panel.primary) keyCatcher.forceActiveFocus()
            }
          }

          Keys.onPressed: function (event) {
            if (event.key === Qt.Key_Escape) {
              root.dismiss()
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
              root.move(1)
            } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
              root.move(-1)
            } else if (event.key === Qt.Key_D) {
              root.toggleAll()
            } else if (event.key === Qt.Key_S) {
              root.cycleSource()
            } else if (event.key === Qt.Key_G) {
              root.markItem(root.selectedIndex < 0 ? 0 : root.selectedIndex)
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.openItem(root.selectedIndex < 0 ? 0 : root.selectedIndex)
            } else {
              return
            }
            event.accepted = true
          }
        }

        Column {
          id: content
          anchors.fill: parent
          anchors.topMargin: card.contentTopInset
          anchors.rightMargin: card.contentRightInset
          anchors.bottomMargin: card.contentBottomInset
          anchors.leftMargin: card.contentLeftInset
          spacing: Style.spacing.md

          // ---- header -------------------------------------------------------
          Item {
            width: parent.width
            height: headerCol.implicitHeight + Style.space(10)

            Column {
              id: headerCol
              width: parent.width
              spacing: Style.space(4)

              Row {
                spacing: Style.space(12)

                Text {
                  text: Math.round(root.counter)
                  visible: root.rows.length > 0
                  color: root.accent
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.displayLarge
                  font.bold: true
                }

                Column {
                  spacing: Style.space(2)
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    text: Model.headlineFor(root.digest, root.language, root.rows.length,
                                            root.sourceView, root.hasJira)
                    color: root.foreground
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.heading
                    font.bold: true
                  }

                  // The full view names the window it covers; the unread list
                  // is "what is left", which no start date describes -- so it
                  // says that instead. Either way the line answers the same
                  // question the headline half-answers: which of these am I
                  // reading?
                  Text {
                    visible: text !== ""
                    text: root.showingAll ? Model.coverageFor(root.digest, root.language)
                                          : Model.unreadLine(root.language)
                    color: root.accent
                    opacity: 0.9
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    text: Model.subtitleFor(root.digest, root.language)
                    visible: text !== "" && root.showingAll && root.rows.length > 0
                    color: root.foreground
                    opacity: 0.6
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }

            // The sweep is the one piece of pure decoration here: it reads as
            // "this just arrived" without another colour or another word.
            Rectangle {
              anchors.left: parent.left
              anchors.bottom: parent.bottom
              height: Math.max(2, Style.space(2))
              radius: height / 2
              color: root.accent
              width: root.opened ? parent.width : 0
              Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
            }
          }

          // ---- tldr ---------------------------------------------------------
          Text {
            width: parent.width
            visible: text !== ""
            // The tl;dr summarises the whole digest, so it belongs to the
            // view that shows the whole digest.
            text: root.showingAll && root.rows.length > 0 ? (root.digest.tldr || "") : ""
            color: root.foreground
            opacity: root.opened ? 0.92 : 0
            wrapMode: Text.WordWrap
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.subtitle
            lineHeight: 1.35
            Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
          }

          Text {
            width: parent.width
            visible: text !== ""
            text: Model.degradedNotice(root.digest, root.language)
            color: root.accent
            opacity: 0.85
            wrapMode: Text.WordWrap
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }

          // A quiet day deserves a picture, not a blank panel: it says "you are
          // caught up" faster than the sentence does, and makes the empty state
          // feel like an outcome rather than a failure to load.
          Item {
            width: parent.width
            height: root.rows.length === 0 ? Style.space(190) : 0
            visible: root.rows.length === 0

            Column {
              anchors.centerIn: parent
              spacing: Style.space(14)

              Image {
                id: art
                source: root.emptyArtUri
                visible: source !== ""
                width: Style.space(200)
                height: Style.space(150)
                sourceSize.width: width * 2
                sourceSize.height: height * 2
                fillMode: Image.PreserveAspectFit
                smooth: true
                anchors.horizontalCenter: parent.horizontalCenter

                // Breathes rather than sits. Slow enough to register as calm.
                transform: Translate { id: bob; y: 0 }
                SequentialAnimation {
                  running: root.opened && root.animate && art.visible
                  loops: Animation.Infinite
                  NumberAnimation { target: bob; property: "y"; to: -6; duration: 1900; easing.type: Easing.InOutSine }
                  NumberAnimation { target: bob; property: "y"; to: 0;  duration: 1900; easing.type: Easing.InOutSine }
                }
              }

              Text {
                text: Model.emptyHeadline(root.sourceView, root.language)
                color: root.foreground
                opacity: 0.75
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.title
                horizontalAlignment: Text.AlignHCenter
                anchors.horizontalCenter: parent.horizontalCenter
              }

              // An inbox empty because you read it, one empty because nothing
              // happened, and one empty because you filtered it all out look
              // identical -- and the first two are the only ones the
              // illustration was drawn for. The filter speaks first: it is the
              // one the reader can undo on the spot.
              Text {
                visible: root.sourceView !== "both" || root.caughtUp
                text: root.sourceView !== "both"
                      ? Model.filteredHint(root.sourceView, root.language)
                      : Model.caughtUpHint(root.language)
                color: root.accent
                opacity: 0.7
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                horizontalAlignment: Text.AlignHCenter
                anchors.horizontalCenter: parent.horizontalCenter
              }
            }
          }

          // ---- items --------------------------------------------------------
          NumberAnimation {
            id: scrollTo
            target: scroller
            property: "contentY"
            duration: 200
            easing.type: Easing.OutCubic
          }

          // Inside the delegate, where `scroller` is actually in scope. Every
          // monitor's copy scrolls, so the digest on the second screen does not
          // sit on a viewport the keyboard has long since left behind.
          Connections {
            target: root
            function onRevealRequested(index) {
              scroller.ensureVisible(index)
            }
          }

          Flickable {
            id: scroller
            width: parent.width
            // Nothing tall on an empty day: the card shrinks to its text
            // instead of framing a screen of void.
            height: root.rows.length === 0
                    ? 0
                    : Math.max(0, parent.height - y - footer.height - Style.space(10))
            contentHeight: itemColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            // Keeps the selected row on screen, and keeps it *readable*: a
            // row's worth of margin either side, so the selection never sits
            // flush against the fold with its next line hidden. Animated,
            // because a list that teleports makes you re-find your place --
            // the point of arrowing down is that the eye can follow.
            function ensureVisible(index) {
              if (index < 0 || index >= itemRepeater.count) return
              var entry = itemRepeater.itemAt(index)
              if (!entry) return
              var pad = Style.space(28)
              var target = contentY
              if (entry.y - pad < contentY)
                target = entry.y - pad
              else if (entry.y + entry.height + pad > contentY + height)
                target = entry.y + entry.height + pad - height
              // Clamped here rather than left to the Flickable: an unclamped
              // target animates past the end and snaps back.
              target = Math.max(0, Math.min(target, Math.max(0, contentHeight - height)))
              if (Math.abs(target - contentY) < 1) return
              scrollTo.to = target
              scrollTo.restart()
            }

            Column {
              id: itemColumn
              width: scroller.width
              spacing: Style.space(8)

              // One repeater over the combined list rather than two, so an
              // index means the same thing to the keyboard, the scroller and
              // the delegate. The divider rides on the first pulse row.
              Repeater {
                id: itemRepeater
                model: root.rows

                Column {
                  id: row
                  required property int index
                  required property var modelData

                  // Null on every row that does not start a section, which is
                  // most of them.
                  readonly property var heading: root.headings[index] || null

                  width: itemColumn.width
                  spacing: Style.space(8)

                  // Names each block: where the wiki stops and Jira starts, and
                  // where the summarised digest stops and the raw tail begins --
                  // so a row without a summary reads as a boundary rather than
                  // as a half-loaded card.
                  Item {
                    width: parent.width
                    height: row.heading ? divider.implicitHeight + Style.space(12) : 0
                    visible: row.heading !== null

                    Row {
                      id: divider
                      anchors.bottom: parent.bottom
                      spacing: Style.space(8)

                      Text {
                        text: row.heading ? row.heading.title : ""
                        color: root.foreground
                        opacity: 0.55
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                      }

                      Text {
                        text: "· " + (row.heading ? row.heading.note : "")
                        visible: row.heading && row.heading.note !== ""
                        color: root.foreground
                        opacity: 0.35
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.caption
                        anchors.verticalCenter: parent.verticalCenter
                      }
                    }
                  }

                  DigestCard {
                    width: parent.width
                    entry: row.modelData
                    position: row.index
                    language: root.language
                    selected: root.selectedIndex === row.index
                    animate: root.animate
                    revealed: root.revealItems
                    onActivated: root.openItem(row.index)
                    onHovered: root.selectedIndex = row.index
                  }
                }
              }
            }
          }
        }

        // ---- footer ---------------------------------------------------------
        // A hard cut at the fold hides that there is more; this says so without
        // adding a scrollbar to a surface meant to be read, not operated.
        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: footer.top
          anchors.leftMargin: card.contentLeftInset
          anchors.rightMargin: card.contentRightInset
          height: Style.space(30)
          visible: scroller.contentHeight > scroller.height + 2
          opacity: scroller.atYEnd ? 0 : 1
          Behavior on opacity { NumberAnimation { duration: 160 } }
          gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: root.background }
          }
        }

        Row {
          id: footer
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.rightMargin: card.contentRightInset
          anchors.bottomMargin: card.contentBottomInset
          spacing: Style.space(10)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: {
              var nl = root.language === "nl"
              var base = nl ? "↑↓ kiezen · ⏎ openen" : "↑↓ select · ⏎ open"
              return base + " · " + Model.markHint(root.language)
                          + " · " + Model.sourceHint(root.sourceView, root.language)
                          + " · " + Model.modeHint(root.showingAll, root.language)
            }
            color: root.foreground
            opacity: 0.45
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }

          // Always offered, even on a day with nothing unread -- that is
          // exactly when you want to see what the briefing said.
          Button {
            text: Model.modeLabel(root.showingAll, root.language)
            onClicked: root.toggleAll()
          }

          Button {
            text: root.language === "nl" ? "Gezien" : "Got it"
            onClicked: root.dismiss()
          }
        }
      }
    }
  }

  IpcHandler {
    target: "jevido.wiki"
    function open(): void { root.open("{}") }
    function close(): void { root.close() }
    function show(): void { root.open("{}") }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { digestFile.reload(); pulseFile.reload(); readFile.reload() }
    // Lets a keybinding drop straight into the full briefing, and makes the
    // toggle testable without synthesising a keypress.
    function everything(): void { root.toggleAll() }
    // Lets a keybinding drop straight into one source, without walking the
    // cycle to get there.
    function source(view: string): void {
      root.sourceView = Model.normalisedSourceView(view)
      root.restageView()
    }
  }
}
