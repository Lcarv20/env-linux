import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services

QtObject {
    id: root

    property var pluginService: null
    property string trigger: "="
    property string currentQuery: ""
    property string asyncResult: ""

    signal itemsChanged()

    property Timer debounceTimer: Timer {
        interval: 100
        repeat: false
        onTriggered: {
            if (root.currentQuery.length > 0) {
                const p = qalcComponent.createObject(root, { queryText: root.currentQuery });
                p.running = true;
            }
        }
    }

    Component.onCompleted: {
        if (!pluginService)
            return;
        trigger = pluginService.loadPluginData("simpleCalc", "trigger", "=");
    }

    onTriggerChanged: {
        if (!pluginService)
            return;
        pluginService.savePluginData("simpleCalc", "trigger", trigger);
    }

    function evalJS(expr) {
        try {
            let s = expr.replace(/\^/g, "**");
            s = s.replace(/\b(sin|cos|tan|sqrt|abs|log|round|floor|ceil)\b/gi, "Math.$1");
            s = s.replace(/\bpi\b/gi, "Math.PI");
            s = s.replace(/\be\b/gi, "Math.E");
            if (/^[\d\s\.\,\+\-\*\/\%\(\)\^Math\.\w]+$/.test(s)) {
                const val = Function("return (" + s + ")")();
                if (val !== undefined && !isNaN(val) && typeof val === "number") {
                    // Avoid floating point inaccuracies like 0.1 + 0.2 = 0.30000000000000004
                    return String(Math.round(val * 1e10) / 1e10);
                }
            }
        } catch (e) {}
        return null;
    }

    function getItems(query) {
        let raw = query ? query.trim() : "";
        const hasTrigger = raw.startsWith("=");
        let text = hasTrigger ? raw.substring(1).trim() : raw;

        if (text.length === 0) {
            root.currentQuery = "";
            root.asyncResult = "";
            if (hasTrigger) {
                return [{
                    name: "Calculator",
                    comment: "Type an equation (e.g. '= 15 * 4' or '= 50 EUR to USD')",
                    icon: "material:calculate",
                    action: "",
                    categories: ["Calculator"]
                }];
            }
            return [];
        }

        // In general search (without '='), only evaluate if input starts with a number or math symbol
        if (!hasTrigger) {
            if (!/^[0-9\(\.\-\+]/.test(text)) {
                return [];
            }
        }

        // Try instant synchronous JS evaluation first
        const fastResult = evalJS(text);
        let displayResult = fastResult;

        // If JS didn't evaluate or query changed, trigger qalc for units/complex math
        if (text !== root.currentQuery) {
            root.currentQuery = text;
            root.asyncResult = "";
            // Only trigger qalc if user used '=' or expression contains math/unit symbols
            if (hasTrigger || /[\+\-\*\/\^\%\(\)]|\b(to|in)\b/i.test(text)) {
                debounceTimer.restart();
            }
        } else if (!displayResult && root.asyncResult) {
            displayResult = root.asyncResult;
        }

        // In general search without '=', don't suggest if result is identical to the input (e.g. plain "123")
        if (!hasTrigger && displayResult === text) {
            return [];
        }

        if (displayResult) {
            return [{
                name: "= " + displayResult,
                comment: text + " (Press Enter to copy to clipboard)",
                icon: "material:calculate",
                action: "copy:" + displayResult,
                categories: ["Calculator"]
            }];
        }

        // Only show placeholder if user explicitly requested calculator mode with '='
        if (hasTrigger) {
            return [{
                name: "...",
                comment: "Calculating " + text + "...",
                icon: "material:calculate",
                action: "",
                categories: ["Calculator"]
            }];
        }

        // Otherwise remain silent in general search
        return [];
    }

    function executeItem(item) {
        if (!item || !item.action || !item.action.startsWith("copy:"))
            return;
        const val = item.action.substring(5);

        Quickshell.execDetached(["wl-copy", "--", val]);
        if (typeof ToastService !== "undefined") {
            ToastService.showInfo("Calculator", "Copied " + val + " to clipboard");
        }
    }

    property Component qalcComponent: Component {
        Process {
            id: proc
            property string queryText: ""
            running: false
            command: ["qalc", "-t", queryText]
            stdout: StdioCollector {
                onStreamFinished: {
                    const out = text ? text.trim() : "";
                    if (out.length > 0 && root.currentQuery === proc.queryText) {
                        root.asyncResult = out;
                        root.itemsChanged();
                    }
                    proc.destroy();
                }
            }
            onExited: exitCode => {
                proc.destroy();
            }
        }
    }
}
