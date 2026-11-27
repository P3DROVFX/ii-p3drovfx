import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import "EmailIconRules.js" as IconRules

Item {
    id: root
    property string subject: ""
    property string sender: ""
    property string snippet: ""

    // Manual icon override (if provided, skip classification)
    property string icon: ""

    property bool unread: false
    property real iconSize: 24
    property bool isPressed: false
    property color color: isPressed ? Appearance.colors.colOnSurface : Appearance.colors.colOnSurfaceVariant

    // Internal icon state: use manual override or classify from content
    readonly property string activeIcon: icon !== "" ? icon : IconRules.classify(subject, sender, snippet)

    readonly property var nfMap: ({
            // Brands & Companies
            "google": "\uf1a0",
            "github": "\uf09b",
            "gitlab": "\uf296",
            "discord": "\uf392",
            "microsoft": "\uf3f1",
            "apple": "\uf179",
            "amazon": "\uf270",
            "facebook": "\uf09a",
            "twitter": "\ue61b",
            "instagram": "\uf16d",
            "linkedin": "\uf08c",
            "spotify": "\uf1bc",
            "steam": "\uf1b6",
            "twitch": "\uf1e8",
            "dropbox": "\uf16b",
            "slack": "\uf198",
            "reddit": "\uf1a1",
            "stackoverflow": "\uf16c",
            "codepen": "\uf1cb",
            "bitbucket": "\uf171",
            "paypal": "\uf1ed",
            "stripe": "\uf08f1",
            "visa": "\uf1f0",
            "mastercard": "\uf1f1",
            "bitcoin": "\uf15a",
            "ethereum": "\ue217",

            // Dev Languages
            "python": "\ue235",
            "javascript": "\ue781",
            "typescript": "\ue628",
            "rust": "\ue7a8",
            "go": "\ue627",
            "java": "\ue256",
            "php": "\ue73d",
            "ruby": "\ue21e",
            "lua": "\ue620",
            "cpp": "\ue61d",
            "csharp": "\ue648",
            "swift": "\ue755",
            "kotlin": "\ue634",

            // Dev Tools & Infrastructure
            "docker": "\uf308",
            "kubernetes": "\uf30f",
            "aws": "\uf323",
            "azure": "\uf322",
            "google_cloud": "\ue7b2",
            "firebase": "\ue7af",
            "cloudflare": "\uf320",
            "digitalocean": "\uf30c",
            "vercel": "\ue6d5",
            "netlify": "\ue6d6",
            "heroku": "\ue77b",
            "npm": "\ue71e",
            "yarn": "\ue71d",
            "pnpm": "\ue6b3",
            "vite": "\ue6c3",
            "nextjs": "\ue6d4",
            "react": "\ue7ba",
            "vue": "\ue6a0",
            "angular": "\ue731",
            "tailwind": "\uf0672",
            "bootstrap": "\ue756",

            // Databases
            "postgresql": "\ue76e",
            "mysql": "\ue704",
            "mongodb": "\ue7a4",
            "redis": "\ue76d",
            "sqlite": "\ue7dd",
            "supabase": "\ue6d9",

            // Operating Systems / Distros
            "linux": "\uf31a",
            "ubuntu": "\uf31b",
            "arch": "\uf303",
            "debian": "\uf306",
            "fedora": "\uf30a",
            "gentoo": "\uf30d",
            "nixos": "\uf313",
            "kali": "\uf310",
            "centos": "\uf304",

            // Communication & Productivity
            "whatsapp": "\uf232",
            "telegram": "\uf2c6",
            "signal": "\uf08f0",
            "zoom": "\ue62c",
            "teams": "\uf321",
            "skype": "\uf17e",
            "trello": "\uf181",
            "jira": "\uf311",
            "confluence": "\uf312",
            "notion": "\ue6d8",
            "evernote": "\ue711",
            "slack_legacy": "\uf198",

            // Streaming & Media
            "netflix": "\ue216",
            "disneyplus": "\ue6d3",
            "hbo": "\ue6d2",
            "primevideo": "\ue6d1",
            "hulu": "\ue6d0",
            "crunchyroll": "\ue6cf",
            "youtube_music": "\ue6ce",

            // Education & Courses
            "udemy": "\uf19d",
            "coursera": "\uf474",
            "edx": "\uf474",
            "duolingo": "\ue6c5",
            "khanacademy": "\uf19d",
            "pluralsight": "\ue232",
            "skillshare": "\uf19d",

            // Marketplaces & Global Shopping
            "amazon": "\uf270",
            "ebay": "\uf2d1",
            "aliexpress": "\uf290",
            "etsy": "\uf2d7",
            "shopee": "\uf290",
            "mercadolivre": "\uf07a",
            "wish": "\uf07a",
            "temu": "\uf290",
            "magalu": "\uf07a",
            "casasbahia": "\uf07a",

            // Social Media & Video
            "youtube": "\uf16a",
            "instagram": "\uf16d",
            "facebook": "\uf09a",
            "tiktok": "\uf03d",
            "snapchat": "\uf2ab",
            "pinterest": "\uf0d2",
            "twitter": "\ue61b",
            "linkedin": "\uf08c",
            "threads": "\ue61b",

            // Finance & Crypto
            "nubank": "\uf19c",
            "inter": "\uf19c",
            "binance": "\ue217",
            "coinbase": "\ue217",
            "kraken": "\ue217",
            "paypal": "\uf1ed",

            // Travel & Lifestyle
            "airbnb": "\uef93",
            "booking": "\uf26b",
            "expedia": "\ue6b5",
            "tripadvisor": "\uf262",
            "uber": "\ued31",
            "lyft": "\uf3c3"
        })

    readonly property bool isNerd: nfMap[activeIcon] !== undefined

    MaterialSymbol {
        anchors.centerIn: parent
        visible: !root.isNerd
        text: root.activeIcon || "person"
        fill: root.unread ? 1 : 0
        iconSize: root.iconSize
        color: root.color
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        Behavior on fill {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    StyledText {
        anchors.centerIn: parent
        visible: root.isNerd
        text: nfMap[activeIcon] || ""
        font.family: Appearance.font.family.iconNerd
        font.pixelSize: root.iconSize
        color: root.color
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }
}
