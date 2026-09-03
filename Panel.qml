import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "tiho.omagemba"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var settings: ({})
  property string page: "today"
  property string selectedType: "muda"
  property int selectedImpact: 5
  property bool abandonArmed: false

  readonly property var omagembaService: bar?.shell?.serviceFor(root.moduleName)
  readonly property bool serviceReady: omagembaService ? omagembaService.ready : false
  readonly property bool dataAvailable: serviceReady && !omagembaService.loadError
  readonly property var state: serviceReady ? omagembaService.state : Model.defaultState()
  readonly property string todayKey: serviceReady ? omagembaService.todayKey : Model.dateKey(new Date())
  readonly property var today: serviceReady ? omagembaService.today : Model.aggregate(state, todayKey, 1)
  readonly property var week: serviceReady ? omagembaService.week : Model.aggregate(state, todayKey, 7)
  readonly property var recurring: Model.recurringIssues(state, todayKey, 7, 3)
  readonly property var activeCountermeasure: state.activeCountermeasure || null
  readonly property string activeCountermeasureId: activeCountermeasure ? activeCountermeasure.id : ""
  readonly property var countermeasureProgress: serviceReady
    ? omagembaService.countermeasureProgress
    : Model.countermeasureProgress(state)
  readonly property var wins: state.wins ? state.wins.slice().reverse() : []
  readonly property bool storageBlocked: serviceReady
    && (!omagembaService.canMutate || omagembaService.writeError)
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var barIdentity: hostWidget || root

  onActiveCountermeasureIdChanged: {
    root.abandonArmed = false
    resolutionField.text = ""
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onPageChanged: scroll.contentY = 0

  function typeIcon(type) {
    if (type === "muda") return "󰩹"
    if (type === "mura") return "󰥛"
    return "󰖡"
  }

  function typeColor(type) {
    if (type === "muda") return Style.selectedStateColor(root.contentForeground, Color.accent)
    if (type === "mura") return Qt.rgba(0.34, 0.66, 0.81, 1)
    return Color.urgent
  }

  function guidance(type) {
    if (type === "muda") return "Remove unnecessary steps, waiting, movement, or rework."
    if (type === "mura") return "Level demand, timing, handoffs, or workload variation."
    return "Reduce load, parallel work, pressure, or unsafe effort."
  }

  function pageLabel() {
    if (root.page === "map") return "3M MAP"
    if (root.page === "countermeasures") return "COUNTERMEASURES"
    if (root.page === "wins") return "WINS"
    return "TODAY"
  }

  function open() {
    root.controller.show()
    root.abandonArmed = false
    scroll.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.abandonArmed = false
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function showPage(nextPage) {
    root.page = nextPage
    root.abandonArmed = false
    scroll.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function revealControl(item) {
    if (!item || !scroll || !contentColumn) return
    var point = item.mapToItem(contentColumn, 0, 0)
    var margin = Style.space(8)
    var top = Math.max(0, point.y - margin)
    var bottom = point.y + item.height + margin
    if (top < scroll.contentY) scroll.contentY = top
    else if (bottom > scroll.contentY + scroll.height)
      scroll.contentY = Math.min(
        Math.max(0, scroll.contentHeight - scroll.height),
        bottom - scroll.height
      )
  }

  function logDraft() {
    if (!root.serviceReady || root.storageBlocked || observationField.text.trim() === "") return
    if (!root.omagembaService.logObservation(root.selectedType, observationField.text, root.selectedImpact)) return
    observationField.text = ""
    keyCatcher.forceActiveFocus()
  }

  function quickLog(issueKey) {
    if (!root.serviceReady || root.storageBlocked) return
    if (root.omagembaService.quickLog(issueKey))
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function targetIssue(issueKey) {
    if (!root.serviceReady || root.storageBlocked || root.activeCountermeasure) return
    if (!root.omagembaService.startCountermeasure(issueKey)) return
    root.showPage("countermeasures")
  }

  function resolveActive() {
    if (!root.serviceReady || root.storageBlocked || !root.activeCountermeasure) return
    if (!root.omagembaService.resolveCountermeasure(
      resolutionField.text,
      root.activeCountermeasure.id
    )) return
    resolutionField.text = ""
    root.showPage("wins")
  }

  function abandonActive() {
    if (!root.serviceReady || root.storageBlocked || !root.activeCountermeasure) return
    if (!root.abandonArmed) {
      root.abandonArmed = true
      return
    }
    if (!root.omagembaService.abandonCountermeasure(root.activeCountermeasure.id)) return
    root.abandonArmed = false
    resolutionField.text = ""
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Shortcut {
    sequence: "Escape"
    enabled: root.opened && !observationField.activeFocus && !resolutionField.activeFocus
    onActivated: root.close()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.cappedContentHeight(Style.space(560))

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.onPressed: function(event) {
        if (!keyCatcher.activeFocus) return
        if (event.key === Qt.Key_Escape) {
          root.close()
          event.accepted = true
        } else if (event.key === Qt.Key_Backtab) {
          root.switchPanel(-1)
          event.accepted = true
        }
      }

      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        Column {
          id: contentColumn
          width: scroll.width
          spacing: Style.space(14)

          Row {
            width: parent.width
            spacing: Style.space(10)

            Text {
              id: headerIcon
              text: "󰀦"
              color: root.typeColor(root.week.dominantType || "muda")
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.heading
            }

            Text {
              anchors.baseline: headerIcon.baseline
              text: "OMAGEMBA"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              font.letterSpacing: 3
            }

            Item {
              width: Math.max(Style.space(8), parent.width - headerIcon.width - pageTitle.width - Style.space(125))
              height: 1
            }

            Text {
              id: pageTitle
              width: Style.space(125)
              anchors.baseline: headerIcon.baseline
              text: root.pageLabel()
              color: Qt.darker(root.contentForeground, 1.5)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
              horizontalAlignment: Text.AlignRight
              elide: Text.ElideRight
            }
          }

          Rectangle {
            width: parent.width
            height: Style.spacing.hairline
            color: root.contentForeground
            opacity: 0.12
          }

          Text {
            visible: !root.serviceReady
            width: parent.width
            text: "Loading local observations..."
            color: Qt.darker(root.contentForeground, 1.5)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
          }

          Rectangle {
            visible: root.serviceReady && root.omagembaService.loadError
            width: parent.width
            height: loadErrorText.implicitHeight + Style.space(18)
            radius: Style.cornerRadius
            color: Style.normalFillFor(root.contentForeground, Color.urgent)

            Text {
              id: loadErrorText
              anchors.fill: parent
              anchors.margins: Style.space(9)
              text: "OmaGemba could not safely read its state. The file was left unchanged."
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }

          Button {
            visible: root.serviceReady && root.omagembaService.writeError
            width: parent.width
            text: "State write failed / Retry"
            bordered: true
            focusable: enabled
            onActiveFocusChanged: if (activeFocus) root.revealControl(this)
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onClicked: root.omagembaService.retryWrite()
          }

          Column {
            visible: root.dataAvailable && root.page === "today"
            width: parent.width
            spacing: Style.space(12)

            Text {
              width: parent.width
              text: "WHAT DISRUPTED THE FLOW?"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              text: "Observe the work. Classify the cause. Improve the system."
              color: Qt.darker(root.contentForeground, 1.5)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Text {
              text: "CHOOSE A 3M LENS"
              color: Qt.darker(root.contentForeground, 1.35)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              font.letterSpacing: 1
            }

            Row {
              id: typeRow
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: Model.TYPES

                Button {
                  required property string modelData
                  width: (typeRow.width - typeRow.spacing * 2) / 3
                  iconText: root.typeIcon(modelData)
                  text: Model.typeName(modelData)
                  selected: root.selectedType === modelData
                  bordered: true
                  focusable: true
                  onActiveFocusChanged: if (activeFocus) root.revealControl(this)
                  foreground: root.contentForeground
                  accent: root.typeColor(modelData)
                  fontFamily: root.contentFontFamily
                  tooltipText: Model.typeMeaning(modelData)
                  onClicked: root.selectedType = modelData
                }
              }
            }

            Text {
              text: Model.typeMeaning(root.selectedType)
              color: root.typeColor(root.selectedType)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1
            }

            TextField {
              id: observationField
              width: parent.width
              placeholderText: "What happened?"
              foreground: root.contentForeground
              accent: root.typeColor(root.selectedType)
              font.family: root.contentFontFamily
              maximumLength: 60
              onActiveFocusChanged: if (activeFocus) root.revealControl(this)
              onAccepted: root.logDraft()
              Keys.onEscapePressed: {
                keyCatcher.forceActiveFocus()
                event.accepted = true
              }
            }

            Row {
              id: impactRow
              width: parent.width
              spacing: Style.space(6)
              readonly property real cellWidth: (width - spacing * 3) / 5

              Repeater {
                model: Model.IMPACTS

                Button {
                  required property int modelData
                  width: impactRow.cellWidth
                  text: modelData + " min"
                  selected: root.selectedImpact === modelData
                  bordered: true
                  focusable: true
                  onActiveFocusChanged: if (activeFocus) root.revealControl(this)
                  foreground: root.contentForeground
                  accent: root.typeColor(root.selectedType)
                  fontFamily: root.contentFontFamily
                  fontSize: Style.font.bodySmall
                  onClicked: root.selectedImpact = modelData
                }
              }

              Button {
                width: impactRow.cellWidth * 2
                text: "+ Log observation"
                bordered: true
                focusable: enabled
                onActiveFocusChanged: if (activeFocus) root.revealControl(this)
                enabled: observationField.text.trim() !== "" && !root.storageBlocked
                foreground: root.contentForeground
                accent: root.typeColor(root.selectedType)
                fontFamily: root.contentFontFamily
                onClicked: root.logDraft()
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: Model.TYPES

                Rectangle {
                  required property string modelData
                  width: (parent.width - parent.spacing * 2) / 3
                  height: Style.space(72)
                  radius: Style.cornerRadius
                  color: Qt.rgba(root.typeColor(modelData).r, root.typeColor(modelData).g, root.typeColor(modelData).b, 0.08)
                  border.width: Style.spacing.hairline
                  border.color: Qt.rgba(root.typeColor(modelData).r, root.typeColor(modelData).g, root.typeColor(modelData).b, 0.35)

                  Column {
                    anchors.fill: parent
                    anchors.margins: Style.space(9)
                    spacing: Style.space(3)

                    Text {
                      text: Model.typeName(modelData)
                      color: root.typeColor(modelData)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                      font.letterSpacing: 1
                    }
                    Text {
                      text: root.today.byType[modelData].count
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.title
                      font.bold: true
                    }
                    Text {
                      text: Model.formatMinutes(root.today.byType[modelData].impactMinutes) + " impact"
                      color: Qt.darker(root.contentForeground, 1.55)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }

            Row {
              width: parent.width

              Text {
                text: "FLOW SIGNAL / 7 DAYS"
                color: Qt.darker(root.contentForeground, 1.35)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                font.letterSpacing: 1
              }
              Item { width: parent.width - parent.children[0].width - weekImpact.width; height: 1 }
              Text {
                id: weekImpact
                text: Model.formatMinutes(root.week.totalImpactMinutes) + " impact"
                color: root.week.dominantType ? root.typeColor(root.week.dominantType) : Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
            }

            Row {
              width: parent.width
              height: Style.space(7)
              spacing: 0

              Repeater {
                model: Model.TYPES

                Rectangle {
                  required property string modelData
                  width: root.week.totalImpactMinutes > 0
                    ? parent.width * root.week.byType[modelData].impactMinutes / root.week.totalImpactMinutes
                    : (modelData === "muda" ? parent.width : 0)
                  height: parent.height
                  color: root.week.totalImpactMinutes > 0 ? root.typeColor(modelData) : Qt.darker(root.contentForeground, 2.2)
                }
              }
            }

            Text {
              visible: root.recurring.length === 0
              width: parent.width
              text: "Your recurring friction will appear here after the first observation."
              color: Qt.darker(root.contentForeground, 1.6)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Repeater {
              model: root.recurring

              Rectangle {
                required property var modelData
                readonly property bool activeIssue: root.activeCountermeasure
                  && root.activeCountermeasure.issueKey === modelData.issueKey
                width: contentColumn.width
                height: Style.space(64)
                radius: Style.cornerRadius
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.04)
                border.width: Style.spacing.hairline
                border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Rectangle {
                  anchors.left: parent.left
                  width: Style.space(4)
                  height: parent.height
                  radius: parent.radius
                  color: root.typeColor(modelData.type)
                }

                Column {
                  anchors.left: parent.left
                  anchors.right: actionButtons.left
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(14)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(3)

                  Text {
                    width: parent.width
                    text: modelData.title
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    elide: Text.ElideRight
                  }
                  Text {
                    text: Model.typeName(modelData.type) + " / " + modelData.count + " hits / "
                      + Model.formatMinutes(modelData.impactMinutes)
                      + (modelData.status === "returned" ? " / RETURNED" : "")
                    color: modelData.status === "returned"
                      ? root.typeColor(modelData.type)
                      : Qt.darker(root.contentForeground, 1.55)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Row {
                  id: actionButtons
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(4)

                  Button {
                    text: "+ Log"
                    bordered: true
                    enabled: !root.storageBlocked
                    focusable: enabled
                    onActiveFocusChanged: if (activeFocus) root.revealControl(this)
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                    fontSize: Style.font.caption
                    onClicked: root.quickLog(modelData.issueKey)
                  }
                  Button {
                    visible: !root.activeCountermeasure
                    text: "Target"
                    bordered: true
                    enabled: !root.storageBlocked
                    focusable: enabled
                    onActiveFocusChanged: if (activeFocus) root.revealControl(this)
                    foreground: root.contentForeground
                    accent: root.typeColor(modelData.type)
                    fontFamily: root.contentFontFamily
                    fontSize: Style.font.caption
                    onClicked: root.targetIssue(modelData.issueKey)
                  }
                  Text {
                    visible: activeIssue
                    text: "ACTIVE"
                    color: root.typeColor(modelData.type)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1
                  }
                }
              }
            }
          }

          Column {
            visible: root.dataAvailable && root.page === "map"
            width: parent.width
            spacing: Style.space(12)

            Text {
              text: "YOUR 3M MAP"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }
            Text {
              width: parent.width
              text: root.week.fromDay + " through " + root.week.throughDay + " / "
                + root.week.observationCount + " observations / " + Model.formatMinutes(root.week.totalImpactMinutes)
              color: Qt.darker(root.contentForeground, 1.5)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Repeater {
              model: Model.TYPES

              Rectangle {
                required property string modelData
                width: contentColumn.width
                height: Style.space(78)
                radius: Style.cornerRadius
                color: Qt.rgba(root.typeColor(modelData).r, root.typeColor(modelData).g, root.typeColor(modelData).b, 0.07)
                border.width: Style.spacing.hairline
                border.color: Qt.rgba(root.typeColor(modelData).r, root.typeColor(modelData).g, root.typeColor(modelData).b, 0.32)

                Row {
                  anchors.fill: parent
                  anchors.margins: Style.space(12)
                  spacing: Style.space(12)

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.typeIcon(modelData)
                    color: root.typeColor(modelData)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.displayLarge
                  }
                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(3)
                    Text {
                      text: Model.typeName(modelData) + " / " + Model.typeMeaning(modelData)
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }
                    Text {
                      text: root.week.byType[modelData].count + " observations / "
                        + Model.formatMinutes(root.week.byType[modelData].impactMinutes) + " impact"
                      color: Qt.darker(root.contentForeground, 1.5)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.bodySmall
                    }
                  }
                }
              }
            }

            Text {
              text: "RANKED BY IMPACT"
              color: Qt.darker(root.contentForeground, 1.35)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              font.letterSpacing: 1
            }

            Text {
              visible: root.week.issues.length === 0
              width: parent.width
              text: "No observations in this seven-day window."
              color: Qt.darker(root.contentForeground, 1.6)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
            }

            Repeater {
              model: root.week.issues.slice(0, 10)

              Rectangle {
                required property var modelData
                width: contentColumn.width
                height: Style.space(58)
                radius: Style.cornerRadius
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.04)

                Rectangle {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(8)
                  height: width
                  radius: width / 2
                  color: root.typeColor(modelData.type)
                }
                Column {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(30)
                  anchors.right: mapActions.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  Text {
                    width: parent.width
                    text: modelData.title
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    elide: Text.ElideRight
                  }
                  Text {
                    text: modelData.count + " hits / " + Model.formatMinutes(modelData.impactMinutes)
                    color: Qt.darker(root.contentForeground, 1.55)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
                Row {
                  id: mapActions
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(6)

                  Text {
                    visible: modelData.status === "returned"
                    anchors.verticalCenter: parent.verticalCenter
                    text: "RETURNED"
                    color: root.typeColor(modelData.type)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1
                  }
                  Button {
                    visible: !root.activeCountermeasure
                    text: Model.actionLabel(modelData.type)
                    bordered: true
                    enabled: !root.storageBlocked
                    focusable: enabled
                    onActiveFocusChanged: if (activeFocus) root.revealControl(this)
                    foreground: root.contentForeground
                    accent: root.typeColor(modelData.type)
                    fontFamily: root.contentFontFamily
                    fontSize: Style.font.caption
                    onClicked: root.targetIssue(modelData.issueKey)
                  }
                }
              }
            }
          }

          Column {
            visible: root.dataAvailable && root.page === "countermeasures"
            width: parent.width
            spacing: Style.space(12)

            Text {
              text: "ONE COUNTERMEASURE"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }
            Text {
              width: parent.width
              text: "Target one recurring cause. Keep observing while you change the system."
              color: Qt.darker(root.contentForeground, 1.5)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Column {
              visible: !root.activeCountermeasure
              width: parent.width
              spacing: Style.space(10)

              Rectangle {
                width: parent.width
                height: Style.space(110)
                radius: Style.cornerRadius
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.04)
                border.width: Style.spacing.hairline
                border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Column {
                  anchors.centerIn: parent
                  width: parent.width - Style.space(24)
                  spacing: Style.space(6)
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "󰓾"
                    color: Qt.darker(root.contentForeground, 1.4)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.heading
                  }
                  Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "No countermeasure is active."
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "Choose a recurring issue from Today or the 3M Map."
                    color: Qt.darker(root.contentForeground, 1.55)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              Button {
                visible: root.week.topIssue !== null
                width: parent.width
                iconText: root.week.topIssue ? root.typeIcon(root.week.topIssue.type) : ""
                text: root.week.topIssue
                  ? Model.actionLabel(root.week.topIssue.type) + " top issue"
                  : ""
                tooltipText: root.week.topIssue ? root.week.topIssue.title : ""
                bordered: true
                enabled: !root.storageBlocked
                focusable: enabled
                onActiveFocusChanged: if (activeFocus) root.revealControl(this)
                foreground: root.contentForeground
                accent: root.week.topIssue ? root.typeColor(root.week.topIssue.type) : Color.accent
                fontFamily: root.contentFontFamily
                onClicked: if (root.week.topIssue) root.targetIssue(root.week.topIssue.issueKey)
              }
            }

            Column {
              visible: root.activeCountermeasure !== null
              width: parent.width
              spacing: Style.space(12)

              Rectangle {
                width: parent.width
                height: activeContent.implicitHeight + Style.space(24)
                radius: Style.cornerRadius
                color: root.activeCountermeasure
                  ? Qt.rgba(root.typeColor(root.activeCountermeasure.type).r,
                    root.typeColor(root.activeCountermeasure.type).g,
                    root.typeColor(root.activeCountermeasure.type).b, 0.08)
                  : "transparent"
                border.width: Style.spacing.hairline
                border.color: root.activeCountermeasure
                  ? Qt.rgba(root.typeColor(root.activeCountermeasure.type).r,
                    root.typeColor(root.activeCountermeasure.type).g,
                    root.typeColor(root.activeCountermeasure.type).b, 0.4)
                  : "transparent"

                Column {
                  id: activeContent
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.margins: Style.space(12)
                  spacing: Style.space(5)

                  Text {
                    text: root.activeCountermeasure
                      ? root.typeIcon(root.activeCountermeasure.type) + "  "
                        + Model.actionLabel(root.activeCountermeasure.type)
                      : ""
                    color: root.activeCountermeasure
                      ? root.typeColor(root.activeCountermeasure.type)
                      : root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    font.letterSpacing: 1
                  }
                  Text {
                    width: parent.width
                    text: root.activeCountermeasure ? root.activeCountermeasure.title : ""
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                    wrapMode: Text.WordWrap
                  }
                  Text {
                    width: parent.width
                    text: root.activeCountermeasure ? root.guidance(root.activeCountermeasure.type) : ""
                    color: Qt.darker(root.contentForeground, 1.4)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    wrapMode: Text.WordWrap
                  }
                  Text {
                    text: root.activeCountermeasure
                      ? "Since " + root.activeCountermeasure.startedLocalDay + " / "
                        + root.countermeasureProgress.count + " recurrences / "
                        + Model.formatMinutes(root.countermeasureProgress.impactMinutes)
                      : ""
                    color: Qt.darker(root.contentForeground, 1.6)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              Text {
                text: "WHAT CHANGED?"
                color: Qt.darker(root.contentForeground, 1.35)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                font.letterSpacing: 1
              }
              TextField {
                id: resolutionField
                width: parent.width
                placeholderText: "Optional evidence or lesson"
                foreground: root.contentForeground
                accent: root.activeCountermeasure ? root.typeColor(root.activeCountermeasure.type) : Color.accent
                font.family: root.contentFontFamily
                maximumLength: 240
                onActiveFocusChanged: if (activeFocus) root.revealControl(this)
                onAccepted: root.resolveActive()
                Keys.onEscapePressed: {
                  keyCatcher.forceActiveFocus()
                  event.accepted = true
                }
              }
              Button {
                width: parent.width
                iconText: "󰄬"
                text: root.activeCountermeasure
                  ? Model.actionLabel(root.activeCountermeasure.type) + " and record win"
                  : "Record win"
                bordered: true
                enabled: !root.storageBlocked
                focusable: enabled
                onActiveFocusChanged: if (activeFocus) root.revealControl(this)
                foreground: root.contentForeground
                accent: root.activeCountermeasure ? root.typeColor(root.activeCountermeasure.type) : Color.accent
                fontFamily: root.contentFontFamily
                onClicked: root.resolveActive()
              }
              Button {
                width: parent.width
                text: root.abandonArmed ? "Confirm abandon / No win will be recorded" : "Abandon countermeasure"
                bordered: root.abandonArmed
                enabled: !root.storageBlocked
                focusable: enabled
                onActiveFocusChanged: if (activeFocus) root.revealControl(this)
                foreground: root.contentForeground
                accent: Color.urgent
                fontFamily: root.contentFontFamily
                onClicked: root.abandonActive()
              }
            }
          }

          Column {
            visible: root.dataAvailable && root.page === "wins"
            width: parent.width
            spacing: Style.space(10)

            Text {
              text: "SYSTEM WINS"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }
            Text {
              width: parent.width
              text: "Waste eliminated, variation stabilized, and overload relieved."
              color: Qt.darker(root.contentForeground, 1.5)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Text {
              visible: root.wins.length === 0
              width: parent.width
              text: "Resolve a countermeasure to record the first win."
              color: Qt.darker(root.contentForeground, 1.6)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Repeater {
              model: root.wins

              Rectangle {
                required property var modelData
                readonly property bool latestResolution: Model.isLatestResolution(root.state, modelData.id)
                readonly property string lifecycleStatus: latestResolution
                  ? Model.issueStatus(root.state, modelData.issueKey)
                  : ""
                width: contentColumn.width
                height: winContent.implicitHeight + Style.space(22)
                radius: Style.cornerRadius
                color: Qt.rgba(root.typeColor(modelData.type).r, root.typeColor(modelData.type).g, root.typeColor(modelData.type).b, 0.07)
                border.width: Style.spacing.hairline
                border.color: Qt.rgba(root.typeColor(modelData.type).r, root.typeColor(modelData.type).g, root.typeColor(modelData.type).b, 0.3)

                Row {
                  anchors.fill: parent
                  anchors.margins: Style.space(11)
                  spacing: Style.space(11)

                  Text {
                    text: "󰔸"
                    color: root.typeColor(modelData.type)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.heading
                  }
                  Column {
                    id: winContent
                    width: parent.width - parent.children[0].width - parent.spacing
                      - (winAction.visible ? winAction.width + parent.spacing : 0)
                    spacing: Style.space(3)
                    Text {
                      width: parent.width
                      text: Model.winLabel(modelData.type) + " / " + modelData.title
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                      wrapMode: Text.WordWrap
                    }
                    Text {
                      visible: modelData.note !== ""
                      width: parent.width
                      text: modelData.note
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.bodySmall
                      wrapMode: Text.WordWrap
                    }
                    Text {
                      text: modelData.startedLocalDay + " to " + modelData.resolvedLocalDay
                      color: Qt.darker(root.contentForeground, 1.6)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                  Row {
                    id: winAction
                    visible: latestResolution
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(6)

                    Text {
                      visible: lifecycleStatus === "returned"
                      anchors.verticalCenter: parent.verticalCenter
                      text: "RETURNED"
                      color: root.typeColor(modelData.type)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                      font.letterSpacing: 1
                    }
                    Button {
                      visible: lifecycleStatus === "resolved"
                      text: "Log recurrence"
                      bordered: true
                      enabled: !root.storageBlocked
                      focusable: enabled
                      onActiveFocusChanged: if (activeFocus) root.revealControl(this)
                      foreground: root.contentForeground
                      accent: root.typeColor(modelData.type)
                      fontFamily: root.contentFontFamily
                      fontSize: Style.font.caption
                      onClicked: root.quickLog(modelData.issueKey)
                    }
                  }
                }
              }
            }
          }

          Rectangle {
            visible: root.dataAvailable
            width: parent.width
            height: Style.spacing.hairline
            color: root.contentForeground
            opacity: 0.12
          }

          Row {
            visible: root.dataAvailable
            width: parent.width
            spacing: Style.space(5)

            Button {
              width: (parent.width - parent.spacing * 3) / 4
              text: "Today"
              selected: root.page === "today"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              fontSize: Style.font.caption
              focusable: enabled
              onActiveFocusChanged: if (activeFocus) root.revealControl(this)
              onClicked: root.showPage("today")
            }
            Button {
              width: (parent.width - parent.spacing * 3) / 4
              text: "3M Map"
              selected: root.page === "map"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              fontSize: Style.font.caption
              focusable: enabled
              onActiveFocusChanged: if (activeFocus) root.revealControl(this)
              onClicked: root.showPage("map")
            }
            Button {
              width: (parent.width - parent.spacing * 3) / 4
              text: "Target"
              selected: root.page === "countermeasures"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              fontSize: Style.font.caption
              focusable: enabled
              onActiveFocusChanged: if (activeFocus) root.revealControl(this)
              onClicked: {
                root.showPage("countermeasures")
              }
            }
            Button {
              width: (parent.width - parent.spacing * 3) / 4
              text: "Wins " + root.wins.length
              selected: root.page === "wins"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              fontSize: Style.font.caption
              focusable: enabled
              onActiveFocusChanged: if (activeFocus) root.revealControl(this)
              onClicked: root.showPage("wins")
            }
          }
        }
      }
    }
  }
}
