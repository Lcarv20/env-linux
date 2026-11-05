import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services

QtObject {
    id: root

    property var pluginService: null
    property string trigger: "!"
    property string defaultEngine: "google"

    signal itemsChanged()

    readonly property var engines: ({
        "google": { name: "Google", url: "https://www.google.com/search?q=", home: "https://www.google.com", icon: "material:search" },
        "bing": { name: "Bing", url: "https://www.bing.com/search?q=", home: "https://www.bing.com", icon: "material:search" },
        "brave": { name: "Brave", url: "https://search.brave.com/search?q=", home: "https://search.brave.com", icon: "material:search" },
        "yahoo": { name: "Yahoo", url: "https://search.yahoo.com/search?p=", home: "https://search.yahoo.com", icon: "material:search" },
        "duckduckgo": { name: "DuckDuckGo", url: "https://www.duckduckgo.com/?q=", home: "https://duckduckgo.com", icon: "material:travel_explore" },
        "startpage": { name: "Startpage", url: "https://www.startpage.com/do/search?q=", home: "https://www.startpage.com", icon: "material:travel_explore" },
        "yandex": { name: "Yandex", url: "https://yandex.ru/yandsearch?text=", home: "https://yandex.ru", icon: "material:search" },
        "github": { name: "GitHub", url: "https://github.com/search?q=", home: "https://github.com", icon: "material:code" },
        "baidu": { name: "Baidu", url: "https://www.baidu.com/s?wd=", home: "https://www.baidu.com", icon: "material:search" },
        "ecosia": { name: "Ecosia", url: "https://www.ecosia.org/search?q=", home: "https://www.ecosia.org", icon: "material:eco" },
        "goodreads": { name: "Goodreads", url: "https://www.goodreads.com/search?q=", home: "https://www.goodreads.com", icon: "material:book" },
        "qwant": { name: "Qwant", url: "https://www.qwant.com/?q=", home: "https://www.qwant.com", icon: "material:search" },
        "givero": { name: "Givero", url: "https://www.givero.com/search?q=", home: "https://www.givero.com", icon: "material:search" },
        "stackoverflow": { name: "Stack Overflow", url: "https://stackoverflow.com/search?q=", home: "https://stackoverflow.com", icon: "material:code" },
        "wolframalpha": { name: "WolframAlpha", url: "https://www.wolframalpha.com/input/?i=", home: "https://www.wolframalpha.com", icon: "material:calculate" },
        "archive": { name: "Wayback Machine", url: "https://web.archive.org/web/*/", home: "https://web.archive.org", icon: "material:history" },
        "scholar": { name: "Google Scholar", url: "https://scholar.google.com/scholar?q=", home: "https://scholar.google.com", icon: "material:school" },
        "ask": { name: "Ask.com", url: "https://www.ask.com/web?q=", home: "https://www.ask.com", icon: "material:help" },
        "youtube": { name: "YouTube", url: "https://www.youtube.com/results?search_query=", home: "https://www.youtube.com", icon: "material:smart_display" },
        "grok": { name: "Grok", url: "https://grok.com/c?q=", home: "https://grok.com", icon: "material:smart_toy" },
        "google-ai": { name: "Google AI", url: "https://www.google.com/search?udm=50&source=searchlabs&q=", home: "https://www.google.com", icon: "material:neurology" },
        "twitter": { name: "X / Twitter", url: "https://x.com/search?q=", home: "https://x.com", icon: "material:chat" },
        "chatgpt": { name: "ChatGPT", url: "https://chatgpt.com/?q=", home: "https://chatgpt.com", icon: "material:smart_toy" },
        "mistral": { name: "Mistral AI", url: "https://chat.mistral.ai/chat?q=", home: "https://chat.mistral.ai", icon: "material:smart_toy" }
    })

    readonly property var aliases: ({
        "bing": "bing",
        "brs": "brave",
        "brave": "brave",
        "google": "google",
        "g": "google",
        "yahoo": "yahoo",
        "ddg": "duckduckgo",
        "duckduckgo": "duckduckgo",
        "sp": "startpage",
        "startpage": "startpage",
        "yandex": "yandex",
        "github": "github",
        "gh": "github",
        "baidu": "baidu",
        "ecosia": "ecosia",
        "goodreads": "goodreads",
        "qwant": "qwant",
        "givero": "givero",
        "stackoverflow": "stackoverflow",
        "so": "stackoverflow",
        "wolframalpha": "wolframalpha",
        "wa": "wolframalpha",
        "archive": "archive",
        "scholar": "scholar",
        "ask": "ask",
        "youtube": "youtube",
        "yt": "youtube",
        "grok": "grok",
        "grk": "grok",
        "twitter": "twitter",
        "tw": "twitter",
        "x": "twitter",
        "google-ai": "google-ai",
        "gai": "google-ai",
        "chatgpt": "chatgpt",
        "gpt": "chatgpt",
        "mistral": "mistral",
        "mist": "mistral"
    })

    Component.onCompleted: {
        if (!pluginService)
            return;
        trigger = pluginService.loadPluginData("localWebSearch", "trigger", "!");
        defaultEngine = pluginService.loadPluginData("localWebSearch", "defaultEngine", "google");
    }

    onTriggerChanged: {
        if (!pluginService)
            return;
        pluginService.savePluginData("localWebSearch", "trigger", trigger);
    }

    function getItems(query) {
        let raw = query ? query.trim() : "";
        if (raw.startsWith("!")) {
            raw = raw.substring(1).trim();
        }

        if (raw.length === 0) {
            return [{
                name: "Web Search",
                comment: "Type '! query' for default engine, or use bangs (!brs, !yt, !g, !gh, etc.)",
                icon: "material:travel_explore",
                action: "",
                categories: ["Web Search"]
            }];
        }

        // Split the query into the first token and remaining query text
        const spaceIdx = raw.search(/\s/);
        let firstToken = "";
        let remaining = "";

        if (spaceIdx === -1) {
            firstToken = raw.toLowerCase();
            remaining = "";
        } else {
            firstToken = raw.substring(0, spaceIdx).toLowerCase();
            remaining = raw.substring(spaceIdx + 1).trim();
        }

        let engineKey = null;
        let searchQuery = "";

        if (firstToken in aliases) {
            engineKey = aliases[firstToken];
            searchQuery = remaining;
        } else {
            // Not a recognized bang: treat the whole text as query for the default engine
            engineKey = (defaultEngine in engines) ? defaultEngine : "google";
            searchQuery = raw;
        }

        const engine = engines[engineKey] || engines["google"];

        if (searchQuery.length === 0) {
            return [{
                name: engine.name,
                comment: "Type query to search " + engine.name + " (or press Enter to open homepage)",
                icon: engine.icon || "material:search",
                action: "url:" + engine.home,
                categories: ["Web Search"]
            }];
        }

        return [{
            name: engine.name + ": \"" + searchQuery + "\"",
            comment: "Press Enter to search on " + engine.name,
            icon: engine.icon || "material:search",
            action: "url:" + engine.url + encodeURIComponent(searchQuery),
            categories: ["Web Search"]
        }];
    }

    function executeItem(item) {
        if (!item || !item.action || !item.action.startsWith("url:"))
            return;
        const targetUrl = item.action.substring(4);
        Quickshell.execDetached(["xdg-open", targetUrl]);
    }
}
