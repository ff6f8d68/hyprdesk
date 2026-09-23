// Hexglass — SDDM theme via HTML exact clone (WebEngineView)
// sci_fi_welcome_screen(3).html is the reference; this QML just hosts it.
// No fallback — HTML is the theme. Fallback.qml is kept as .bak for reference only.
import QtQuick 2.15
import QtWebEngine 1.10
import QtWebChannel 1.0

Rectangle {
    id: root
    width: 1920; height: 1080; color: "#0a0715"

    // SDDM context properties (injected by GreeterApp.cpp):
    // sddm: SddmGreeter, userModel: UserModel, sessionModel: SessionModel, keyboard: Keyboard
    // We expose them to JS via WebChannel as "sddm", "userModel", "sessionModel"
    // The HTML loads qrc:///qtwebchannel/qwebchannel.js and does:
    //   new QWebChannel(qt.webChannelTransport, ch => { window.sddm = ch.objects.sddm; ... })

    QtObject {
        id: sddmBridge
        WebChannel.id: "sddm"
        // SDDM greeter API
        property bool canSuspend: sddm ? sddm.canSuspend : false
        property bool canReboot: sddm ? sddm.canReboot : false
        property bool canPowerOff: sddm ? sddm.canPowerOff : false
        function login(user, password, sessionIndex) {
            if (sddm) sddm.login(user, password, sessionIndex)
            else console.log("sddm.login stub", user, sessionIndex)
        }
        function suspend() { if (sddm && sddm.canSuspend) sddm.suspend() }
        function reboot()  { if (sddm && sddm.canReboot) sddm.reboot() }
        function powerOff(){ if (sddm && sddm.canPowerOff) sddm.powerOff() }
        signal loginSucceeded()
        signal loginFailed()
        // Forward SDDM signals to WebChannel
        Component.onCompleted: {
            if (typeof sddm !== "undefined") {
                // Qt5 SDDM signals are loginSucceeded/loginFailed (not onLogin...)
                // Connect via Connections
                sddm.loginSucceeded.connect(function(){ sddmBridge.loginSucceeded() })
                sddm.loginFailed.connect(function(){ sddmBridge.loginFailed() })
            }
        }
    }

    QtObject {
        id: sessionBridge
        WebChannel.id: "sessionModel"
        // Expose session list as JSON-friendly properties
        // QML Repeater already proves model.name works, but for JS we provide arrays
        property int count: sessionModel ? sessionModel.rowCount() : 0
        property int lastIndex: sessionModel ? sessionModel.lastIndex : 0
        function nameAt(i) {
            if (!sessionModel || i < 0 || i >= sessionModel.rowCount()) return ""
            var idx = sessionModel.index(i, 0)
            // role 260 is display name (LXQt Desktop, Hyprland, Ubuntu, ...)
            var v = sessionModel.data(idx, 260)
            return v ? String(v) : ""
        }
        function fileAt(i) {
            if (!sessionModel) return ""
            var idx = sessionModel.index(i, 0)
            var v = sessionModel.data(idx, 258)
            return v ? String(v) : ""
        }
    }

    QtObject {
        id: userBridge
        WebChannel.id: "userModel"
        property int count: userModel ? userModel.rowCount() : 0
        property string lastUser: userModel ? userModel.lastUser : ""
        property int lastIndex: userModel ? userModel.lastIndex : -1
        function nameAt(i) {
            if (!userModel || i < 0 || i >= userModel.rowCount()) return ""
            var idx = userModel.index(i, 0)
            var v = userModel.data(idx, 257)
            return v ? String(v) : ""
        }
    }

    WebChannel {
        id: channel
        registeredObjects: [sddmBridge, sessionBridge, userBridge]
    }

    WebEngineView {
        id: view
        anchors.fill: parent
        webChannel: channel
        // Try dev HTML first (source theme), fallback to installed path
        // dev:  ~/.config/hypr/hexglass/sddm/hexglass_web.html
        // prod: /usr/share/sddm/themes/hexglass/hexglass_web.html
        url: "file://@HYPRDESK_HOME@/.config/hypr/hexglass/sddm/hexglass_web.html"
        onLoadingChanged: {
            if (loadRequest.status === WebEngineView.LoadFailedStatus) {
                console.log("hexglass WebEngine load failed", loadRequest.errorString, "trying installed path")
                if (String(url) !== "file:///usr/share/sddm/themes/hexglass/hexglass_web.html")
                    url = "file:///usr/share/sddm/themes/hexglass/hexglass_web.html"
            }
            if (loadRequest.status === WebEngineView.LoadSucceededStatus) {
                console.log("hexglass WebEngine loaded", url)
                // Inject session/user data via JS after load
                var sessions = []
                for (var i=0;i<sessionBridge.count;i++) sessions.push(sessionBridge.nameAt(i))
                var users = []
                for (var i=0;i<userBridge.count;i++) users.push(userBridge.nameAt(i))
                // Escape JSON for JS string literal
                var js = "if(window.injectSddmData) window.injectSddmData("
                       + JSON.stringify(sessions) + ","
                       + JSON.stringify(users) + ","
                       + JSON.stringify(userBridge.lastUser) + ","
                       + JSON.stringify(sessionBridge.lastIndex) + ","
                       + JSON.stringify(userBridge.lastIndex) + ","
                       + JSON.stringify(sddmBridge.canSuspend) + ","
                       + JSON.stringify(sddmBridge.canReboot) + ","
                       + JSON.stringify(sddmBridge.canPowerOff) + ");"
                runJavaScript(js)
            }
        }
        onJavaScriptConsoleMessage: function(level, message, lineNumber, sourceId) { console.log("WebEngine JS:", level, message, lineNumber, sourceId) }
    }

    // Forward SDDM signals to HTML via runJavaScript
    Connections {
        target: sddm
        function onLoginSucceeded() {
            view.runJavaScript("if(window.onSddmLoginSucceeded) window.onSddmLoginSucceeded();")
        }
        function onLoginFailed() {
            view.runJavaScript("if(window.onSddmLoginFailed) window.onSddmLoginFailed();")
        }
    }

    Component.onCompleted: console.log("hexglass Main.qml loaded, WebEngineView url", view.url)
}
