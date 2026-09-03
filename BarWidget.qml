import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "tiho.omagemba"

  readonly property var omagembaService: bar?.shell?.serviceFor(root.moduleName)
  readonly property bool serviceLoading: !omagembaService || !omagembaService.ready
  readonly property bool unavailable: !serviceLoading && omagembaService.loadError
  readonly property int todayCount: !serviceLoading && !unavailable ? omagembaService.todayCount : 0
  readonly property bool hasCountermeasure: !serviceLoading && !unavailable
    && omagembaService && omagembaService.activeCountermeasure !== null
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "" : "󰀦 3M "
      + (root.serviceLoading ? "-" : (root.unavailable ? "!" : root.todayCount))
    labelVisible: !root.vertical
    hasVisualContent: true
    fixedWidth: root.vertical ? -1 : Style.space(86)
    fixedHeight: root.vertical ? Style.bar.iconSlot * 2 : -1
    active: root.hasCountermeasure
    activeColor: Color.accent
    tooltipText: root.serviceLoading
      ? "OmaGemba: loading local state"
      : root.unavailable
      ? "OmaGemba: local state unavailable"
      : root.todayCount === 0
      ? "OmaGemba: no friction observed today"
      : "OmaGemba: " + root.todayCount + " observation" + (root.todayCount === 1 ? "" : "s") + " today"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }

    Column {
      visible: root.vertical
      anchors.fill: parent

      Repeater {
        model: [
          "󰀦",
          root.serviceLoading ? "-" : (root.unavailable ? "!" : String(root.todayCount))
        ]

        OpticalGlyph {
          required property string modelData
          width: button.width
          height: Style.bar.iconSlot
          text: modelData
          fontFamily: button.fontFamily
          fontSize: button.fontSize
          color: root.hasCountermeasure ? button.activeColor : button.foreground
        }
      }
    }
  }
}
