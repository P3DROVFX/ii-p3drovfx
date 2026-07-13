pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property alias loading: repoProc.running
    readonly property alias commits: commitsModel

    readonly property string repoPath: FileUtils.trimFileProtocol(Quickshell.shellPath(""))

    ListModel {
        id: commitsModel
    }

    Component.onCompleted: {
        refresh();
    }

    function load() {}

    function refresh() {
        repoProc.running = true;
    }

    function generateSmartId(hash, title) {
        let lowerTitle = title.toLowerCase().trim();
        let prefix = "G";

        if (lowerTitle.startsWith("feat") || lowerTitle.includes("feat")) {
            prefix = "A";
        } else if (lowerTitle.startsWith("fix") || lowerTitle.includes("fix") || lowerTitle.includes("bug")) {
            prefix = "B";
        } else if (lowerTitle.startsWith("refactor") || lowerTitle.includes("refactor") || lowerTitle.includes("perf")) {
            prefix = "C";
        } else if (lowerTitle.startsWith("style") || lowerTitle.includes("style") || lowerTitle.includes("ui") || lowerTitle.includes("theme") || lowerTitle.includes("layout") || lowerTitle.includes("color")) {
            prefix = "D";
        } else if (lowerTitle.startsWith("docs") || lowerTitle.includes("docs") || lowerTitle.includes("readme") || lowerTitle.includes("wiki")) {
            prefix = "E";
        } else if (lowerTitle.startsWith("chore") || lowerTitle.includes("chore") || lowerTitle.startsWith("build") || lowerTitle.startsWith("ci") || lowerTitle.startsWith("test")) {
            prefix = "F";
        }

        let suffix = hash.substring(0, 4).toUpperCase();
        return prefix + "-" + suffix;
    }

    function parseCommits(text, model) {
        model.clear();
        if (!text || text.trim() === "") {
            return;
        }

        let commitsRaw = text.split("\u001e");
        for (let i = 0; i < commitsRaw.length; i++) {
            let raw = commitsRaw[i];
            if (raw.trim() === "")
                continue;

            let parts = raw.split("\u001f");
            if (parts.length < 3)
                continue;

            let hash = parts[0].trim();
            let title = parts[1].trim();
            let date = parts[2].trim();
            let desc = parts.length > 3 ? parts[3].trim() : "";

            let smartId = generateSmartId(hash, title);

            model.append({
                "hash": hash,
                "title": title,
                "description": desc,
                "smartId": smartId,
                "date": date
            });
        }
    }

    Process {
        id: repoProc
        command: ["bash", "-c", "ACTIVE_REMOTE=\"\"; " + "if [ -f \"$HOME/.config/quickshell/ii/.active-remote\" ]; then " + "  ACTIVE_REMOTE=$(cat \"$HOME/.config/quickshell/ii/.active-remote\" 2>/dev/null); " + "fi; " + "MATCHED_DIR=\"\"; " + "for dir in \"" + root.repoPath + "\" \"$HOME/Downloads/ii-vynx\" \"$HOME/.local/share/ii-vynx\" \"$HOME/dotfiles\"; do " + "  if git -C \"$dir\" rev-parse --is-inside-work-tree >/dev/null 2>&1; then " + "    MATCHED_DIR=\"$dir\"; " + "    break; " + "  fi; " + "done; " + "OWNER_REPO=\"vaguesyntax/ii-vynx\"; " + "if [ -n \"$ACTIVE_REMOTE\" ]; then " + "  OWNER_REPO=$(echo \"$ACTIVE_REMOTE\" | sed -E 's/.*github\\.com[\\/:]//; s/\\.git$//'); " + "elif [ -n \"$MATCHED_DIR\" ]; then " + "  REMOTE_URL=$(git -C \"$MATCHED_DIR\" remote get-url origin 2>/dev/null); " + "  if [ -n \"$REMOTE_URL\" ]; then " + "    OWNER_REPO=$(echo \"$REMOTE_URL\" | sed -E 's/.*github\\.com[\\/:]//; s/\\.git$//'); " + "  fi; " + "fi; " + "API_URL=\"https://api.github.com/repos/$OWNER_REPO/commits?per_page=10\"; " + "API_DATA=$(curl -s --connect-timeout 3 --max-time 5 \"$API_URL\"); " + "if [ -n \"$API_DATA\" ] && echo \"$API_DATA\" | python3 -c ' " + "import sys, json, datetime " + "try: " + "    data = json.load(sys.stdin) " + "    if not isinstance(data, list): sys.exit(1) " + "    for item in data[:10]: " + "        sha = item[\"sha\"][:8] " + "        message = item[\"commit\"][\"message\"] or \"\" " + "        parts = message.splitlines() " + "        title = parts[0].strip() if parts else \"\" " + "        body = chr(10).join(parts[1:]).strip() if len(parts) > 1 else \"\" " + "        iso_str = item[\"commit\"][\"author\"][\"date\"] " + "        dt = datetime.datetime.strptime(iso_str, \"%Y-%m-%dT%H:%M:%SZ\").replace(tzinfo=datetime.timezone.utc) " + "        now = datetime.datetime.now(datetime.timezone.utc) " + "        diff = now - dt " + "        diff_sec = int(diff.total_seconds()) " + "        diff_min = diff_sec // 60 " + "        diff_hr = diff_min // 60 " + "        diff_day = diff_hr // 24 " + "        diff_wk = diff_day // 7 " + "        diff_mon = diff_day // 30 " + "        if diff_sec < 60: date_str = \"just now\" " + "        elif diff_min < 60: date_str = str(diff_min) + (\" minute ago\" if diff_min == 1 else \" minutes ago\") " + "        elif diff_hr < 24: date_str = str(diff_hr) + (\" hour ago\" if diff_hr == 1 else \" hours ago\") " + "        elif diff_day < 7: date_str = \"yesterday\" if diff_day == 1 else str(diff_day) + \" days ago\" " + "        elif diff_wk < 4: date_str = \"1 week ago\" if diff_wk == 1 else str(diff_wk) + \" weeks ago\" " + "        else: date_str = \"1 month ago\" if diff_mon <= 1 else str(diff_mon) + \" months ago\" " + "        sys.stdout.write(sha + chr(31) + title + chr(31) + date_str + chr(31) + body + chr(30)) " + "except Exception as e: " + "    sys.exit(1) " + "' 2>/dev/null; then " + "  exit 0; " + "fi; " + "if [ -n \"$MATCHED_DIR\" ]; then " + "  git -C \"$MATCHED_DIR\" log -n 10 --pretty=\"format:%h%x1f%s%x1f%ar%x1f%b%x1e\"; " + "else " + "  git log -n 10 --pretty=\"format:%h%x1f%s%x1f%ar%x1f%b%x1e\" 2>/dev/null; " + "fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.parseCommits(text, commitsModel);
            }
        }
    }
}
