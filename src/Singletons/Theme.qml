pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: theme

    // DMS rewrites this file whenever its theme changes; the hardcoded values below are the fallback when it is absent.
    readonly property string colorsPath: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/dms/dms-colors.json"
    property var roles: ({})

    function role(name, fallback) {
        return roles[name] || fallback;
    }

    function parse(text) {
        try {
            var d = JSON.parse(text);
            var scheme = d.colors ? (d.colors[d.mode] || d.colors.dark) : null;
            roles = scheme || {};
        } catch (e) {
            roles = {};
        }
    }

    FileView {
        path: theme.colorsPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: theme.parse(text())
        onLoadFailed: theme.roles = {}
    }

    readonly property color accent:    role("primary", "#e0563b")
    readonly property color onAccent:  role("on_primary", "#ffffff")
    readonly property color fg:        role("on_surface", "#ffffff")
    readonly property color idle:      role("on_surface_variant", "#c4ccda")
    readonly property color sep:       role("outline_variant", "#313a4d")

    readonly property color dim:        Qt.alpha(role("scrim", "#080a10"), 0.62)
    readonly property color glassBg:    Qt.alpha(role("surface_container", "#141822"), 0.92)
    readonly property color glassBorder: role("outline_variant", "#313a4d")
    readonly property color panelBg:    Qt.alpha(role("surface_container_high", "#181c26"), 0.97)
    readonly property color panelBorder: role("outline", "#3a4456")

    readonly property color dimIcon: Qt.alpha(idle, 0.55)
    readonly property color winFill: Qt.alpha(accent, 0.16)
    readonly property color hover:       Qt.alpha(fg, 0.06)
    readonly property color hoverStrong: Qt.alpha(fg, 0.10)
    readonly property color markerYellow: "#f5d020"
    readonly property color stepText: onAccent

    readonly property var swatches: [
        String(accent), "#ffffff", "#1a1a1a", "#e23b3b", "#f2c14e", "#5bbf73", "#4f8fe0"
    ]

    readonly property string monoFamily: pick(
        ["JetBrains Mono", "JetBrainsMono Nerd Font", "DejaVu Sans Mono", "Liberation Mono"],
        "monospace")
    readonly property string sansFamily: pick(
        ["Inter", "Inter Display", "Noto Sans", "DejaVu Sans", "Liberation Sans"],
        "sans-serif")

    /**
     * Returns the first installed family from prefs, or the generic fallback
     * when none are present. Lets rishot ship without bundling fonts.
     */
    function pick(prefs, fallback) {
        var fams = Qt.fontFamilies();
        for (var i = 0; i < prefs.length; i++)
            if (fams.indexOf(prefs[i]) !== -1) return prefs[i];
        return fallback;
    }
}
