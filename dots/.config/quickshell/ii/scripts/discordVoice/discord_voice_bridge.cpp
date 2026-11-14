#include <iostream>
#include <string>
#include <string_view>
#include <vector>
#include <map>
#include <set>
#include <chrono>
#include <algorithm>
#include <cmath>
#include <cstring>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cctype>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>

namespace {

// Constants
static const std::string CLIENT_ID = "1493026279557042246";
static const std::string TOKEN_URL = "https://1493026279557042246.discordsays.com/.proxy/api/token";
static const double AUTHORIZATION_TIMEOUT_SEC = 15.0;
static const size_t COMPANION_READ_LIMIT = 512 * 1024;
static const int OP_HANDSHAKE = 0;
static const int OP_FRAME = 1;
static const int OP_CLOSE = 2;
static const int OP_PING = 3;
static const int OP_PONG = 4;
static const std::string VENCORD_SOCKET_NAME = "quickshell-ii-discord-voice.sock";
static const std::string VENCORD_LEGACY_SOCKET_NAME = "ii-discord-voice-vencord.sock";

static volatile sig_atomic_t g_running = 1;
static void sig_handler(int sig) {
    (void)sig;
    g_running = 0;
}

// Minimal recursive-descent JSON parser and serializer
enum class JsonType {
    Null,
    Bool,
    Number,
    String,
    Array,
    Object
};

struct JsonValue {
    JsonType type = JsonType::Null;
    bool bool_val = false;
    int64_t int_val = 0;
    double double_val = 0.0;
    bool is_integer = true;
    std::string str_val;
    std::vector<JsonValue> arr_val;
    std::vector<std::pair<std::string, JsonValue>> obj_val;

    JsonValue() : type(JsonType::Null) {}
    explicit JsonValue(JsonType t) : type(t) {}
    explicit JsonValue(bool b) : type(JsonType::Bool), bool_val(b) {}
    explicit JsonValue(int i) : type(JsonType::Number), int_val(i), double_val(i), is_integer(true) {}
    explicit JsonValue(int64_t i) : type(JsonType::Number), int_val(i), double_val(static_cast<double>(i)), is_integer(true) {}
    explicit JsonValue(double d) : type(JsonType::Number), int_val(static_cast<int64_t>(d)), double_val(d), is_integer(false) {}
    explicit JsonValue(const char* s) : type(JsonType::String), str_val(s ? s : "") {}
    explicit JsonValue(std::string s) : type(JsonType::String), str_val(std::move(s)) {}
    explicit JsonValue(std::string_view s) : type(JsonType::String), str_val(s) {}

    bool is_null() const { return type == JsonType::Null; }
    bool is_bool() const { return type == JsonType::Bool; }
    bool is_number() const { return type == JsonType::Number; }
    bool is_string() const { return type == JsonType::String; }
    bool is_array() const { return type == JsonType::Array; }
    bool is_object() const { return type == JsonType::Object; }

    bool to_bool(bool def = false) const {
        if (type == JsonType::Bool) return bool_val;
        return def;
    }

    int64_t to_int(int64_t def = 0) const {
        if (type == JsonType::Number) return int_val;
        return def;
    }

    double to_double(double def = 0.0) const {
        if (type == JsonType::Number) return double_val;
        return def;
    }

    std::string to_string(const std::string& def = "") const {
        if (type == JsonType::String) return str_val;
        return def;
    }

    bool has(std::string_view key) const {
        if (type != JsonType::Object) return false;
        for (const auto& kv : obj_val) {
            if (kv.first == key) return true;
        }
        return false;
    }

    const JsonValue* get(std::string_view key) const {
        if (type != JsonType::Object) return nullptr;
        for (const auto& kv : obj_val) {
            if (kv.first == key) return &kv.second;
        }
        return nullptr;
    }

    const JsonValue& operator[](std::string_view key) const {
        static const JsonValue null_val(JsonType::Null);
        const JsonValue* v = get(key);
        return v ? *v : null_val;
    }

    JsonValue& operator[](std::string_view key) {
        if (type != JsonType::Object) {
            type = JsonType::Object;
            obj_val.clear();
        }
        for (auto& kv : obj_val) {
            if (kv.first == key) return kv.second;
        }
        obj_val.emplace_back(std::string(key), JsonValue());
        return obj_val.back().second;
    }

    const JsonValue& operator[](size_t index) const {
        static const JsonValue null_val(JsonType::Null);
        if (type == JsonType::Array && index < arr_val.size()) {
            return arr_val[index];
        }
        return null_val;
    }

    JsonValue& operator[](size_t index) {
        if (type != JsonType::Array) {
            type = JsonType::Array;
            arr_val.clear();
        }
        if (index >= arr_val.size()) {
            arr_val.resize(index + 1);
        }
        return arr_val[index];
    }

    void erase(std::string_view key) {
        if (type != JsonType::Object) return;
        for (auto it = obj_val.begin(); it != obj_val.end(); ++it) {
            if (it->first == key) {
                obj_val.erase(it);
                return;
            }
        }
    }

    static std::string escape_string(std::string_view s, bool quotes = false) {
        std::string out;
        if (quotes) out.push_back('"');
        for (size_t i = 0; i < s.size(); ++i) {
            unsigned char c = static_cast<unsigned char>(s[i]);
            switch (c) {
                case '"': out += "\\\""; break;
                case '\\': out += "\\\\"; break;
                case '\b': out += "\\b"; break;
                case '\f': out += "\\f"; break;
                case '\n': out += "\\n"; break;
                case '\r': out += "\\r"; break;
                case '\t': out += "\\t"; break;
                default:
                    if (c < 0x20) {
                        char buf[8];
                        snprintf(buf, sizeof(buf), "\\u%04x", c);
                        out += buf;
                    } else {
                        out.push_back(static_cast<char>(c));
                    }
                    break;
            }
        }
        if (quotes) out.push_back('"');
        return out;
    }

    std::string dump(bool sort_keys = false) const {
        switch (type) {
            case JsonType::Null: return "null";
            case JsonType::Bool: return bool_val ? "true" : "false";
            case JsonType::Number: {
                if (is_integer) {
                    return std::to_string(int_val);
                } else {
                    char buf[64];
                    snprintf(buf, sizeof(buf), "%.17g", double_val);
                    return std::string(buf);
                }
            }
            case JsonType::String: return escape_string(str_val, true);
            case JsonType::Array: {
                std::string res = "[";
                for (size_t i = 0; i < arr_val.size(); ++i) {
                    if (i > 0) res += ",";
                    res += arr_val[i].dump(sort_keys);
                }
                res += "]";
                return res;
            }
            case JsonType::Object: {
                std::string res = "{";
                if (sort_keys) {
                    auto sorted = obj_val;
                    std::sort(sorted.begin(), sorted.end(), [](const auto& a, const auto& b) {
                        return a.first < b.first;
                    });
                    for (size_t i = 0; i < sorted.size(); ++i) {
                        if (i > 0) res += ",";
                        res += escape_string(sorted[i].first, true);
                        res += ":";
                        res += sorted[i].second.dump(sort_keys);
                    }
                } else {
                    for (size_t i = 0; i < obj_val.size(); ++i) {
                        if (i > 0) res += ",";
                        res += escape_string(obj_val[i].first, true);
                        res += ":";
                        res += obj_val[i].second.dump(sort_keys);
                    }
                }
                res += "}";
                return res;
            }
        }
        return "null";
    }

    static bool parse(std::string_view input, JsonValue& out) {
        size_t pos = 0;
        skip_ws(input, pos);
        if (!parse_value(input, pos, out)) return false;
        skip_ws(input, pos);
        return pos == input.size();
    }

private:
    static void skip_ws(std::string_view s, size_t& pos) {
        while (pos < s.size() && (s[pos] == ' ' || s[pos] == '\t' || s[pos] == '\n' || s[pos] == '\r')) {
            pos++;
        }
    }

    static bool parse_value(std::string_view s, size_t& pos, JsonValue& val) {
        skip_ws(s, pos);
        if (pos >= s.size()) return false;
        char c = s[pos];
        if (c == 'n') return parse_null(s, pos, val);
        if (c == 't' || c == 'f') return parse_bool(s, pos, val);
        if (c == '"') return parse_string(s, pos, val);
        if (c == '[') return parse_array(s, pos, val);
        if (c == '{') return parse_object(s, pos, val);
        if (c == '-' || (c >= '0' && c <= '9')) return parse_number(s, pos, val);
        return false;
    }

    static bool parse_null(std::string_view s, size_t& pos, JsonValue& val) {
        if (s.substr(pos, 4) == "null") {
            pos += 4;
            val = JsonValue(JsonType::Null);
            return true;
        }
        return false;
    }

    static bool parse_bool(std::string_view s, size_t& pos, JsonValue& val) {
        if (s.substr(pos, 4) == "true") {
            pos += 4;
            val = JsonValue(true);
            return true;
        }
        if (s.substr(pos, 5) == "false") {
            pos += 5;
            val = JsonValue(false);
            return true;
        }
        return false;
    }

    static bool parse_string(std::string_view s, size_t& pos, JsonValue& val) {
        std::string str;
        if (!parse_raw_string(s, pos, str)) return false;
        val = JsonValue(std::move(str));
        return true;
    }

    static bool parse_raw_string(std::string_view s, size_t& pos, std::string& out) {
        if (pos >= s.size() || s[pos] != '"') return false;
        pos++;
        out.clear();
        while (pos < s.size()) {
            char c = s[pos++];
            if (c == '"') {
                return true;
            }
            if (c == '\\') {
                if (pos >= s.size()) return false;
                char esc = s[pos++];
                switch (esc) {
                    case '"': out.push_back('"'); break;
                    case '\\': out.push_back('\\'); break;
                    case '/': out.push_back('/'); break;
                    case 'b': out.push_back('\b'); break;
                    case 'f': out.push_back('\f'); break;
                    case 'n': out.push_back('\n'); break;
                    case 'r': out.push_back('\r'); break;
                    case 't': out.push_back('\t'); break;
                    case 'u': {
                        if (pos + 4 > s.size()) return false;
                        uint32_t cp = 0;
                        for (int i = 0; i < 4; ++i) {
                            char h = s[pos++];
                            cp <<= 4;
                            if (h >= '0' && h <= '9') cp |= static_cast<uint32_t>(h - '0');
                            else if (h >= 'a' && h <= 'f') cp |= static_cast<uint32_t>(h - 'a' + 10);
                            else if (h >= 'A' && h <= 'F') cp |= static_cast<uint32_t>(h - 'A' + 10);
                            else return false;
                        }
                        if (cp >= 0xD800 && cp <= 0xDBFF) {
                            if (pos + 6 <= s.size() && s[pos] == '\\' && s[pos + 1] == 'u') {
                                size_t saved = pos;
                                pos += 2;
                                uint32_t lo = 0;
                                bool ok = true;
                                for (int i = 0; i < 4; ++i) {
                                    char h = s[pos++];
                                    lo <<= 4;
                                    if (h >= '0' && h <= '9') lo |= static_cast<uint32_t>(h - '0');
                                    else if (h >= 'a' && h <= 'f') lo |= static_cast<uint32_t>(h - 'a' + 10);
                                    else if (h >= 'A' && h <= 'F') lo |= static_cast<uint32_t>(h - 'A' + 10);
                                    else { ok = false; break; }
                                }
                                if (ok && lo >= 0xDC00 && lo <= 0xDFFF) {
                                    cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                                } else {
                                    pos = saved;
                                }
                            }
                        }
                        if (cp <= 0x7F) {
                            out.push_back(static_cast<char>(cp));
                        } else if (cp <= 0x7FF) {
                            out.push_back(static_cast<char>(0xC0 | (cp >> 6)));
                            out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
                        } else if (cp <= 0xFFFF) {
                            out.push_back(static_cast<char>(0xE0 | (cp >> 12)));
                            out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
                            out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
                        } else if (cp <= 0x10FFFF) {
                            out.push_back(static_cast<char>(0xF0 | (cp >> 18)));
                            out.push_back(static_cast<char>(0x80 | ((cp >> 12) & 0x3F)));
                            out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
                            out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
                        }
                        break;
                    }
                    default:
                        return false;
                }
            } else {
                out.push_back(c);
            }
        }
        return false;
    }

    static bool parse_number(std::string_view s, size_t& pos, JsonValue& val) {
        size_t start = pos;
        if (s[pos] == '-') pos++;
        if (pos >= s.size()) return false;
        if (s[pos] == '0') {
            pos++;
        } else if (s[pos] >= '1' && s[pos] <= '9') {
            while (pos < s.size() && s[pos] >= '0' && s[pos] <= '9') pos++;
        } else {
            return false;
        }

        bool has_fraction = false;
        if (pos < s.size() && s[pos] == '.') {
            has_fraction = true;
            pos++;
            if (pos >= s.size() || s[pos] < '0' || s[pos] > '9') return false;
            while (pos < s.size() && s[pos] >= '0' && s[pos] <= '9') pos++;
        }

        bool has_exponent = false;
        if (pos < s.size() && (s[pos] == 'e' || s[pos] == 'E')) {
            has_exponent = true;
            pos++;
            if (pos < s.size() && (s[pos] == '+' || s[pos] == '-')) pos++;
            if (pos >= s.size() || s[pos] < '0' || s[pos] > '9') return false;
            while (pos < s.size() && s[pos] >= '0' && s[pos] <= '9') pos++;
        }

        std::string num_str(s.substr(start, pos - start));
        if (!has_fraction && !has_exponent) {
            long long i = std::strtoll(num_str.c_str(), nullptr, 10);
            val = JsonValue(static_cast<int64_t>(i));
            return true;
        } else {
            double d = std::strtod(num_str.c_str(), nullptr);
            val = JsonValue(d);
            return true;
        }
    }

    static bool parse_array(std::string_view s, size_t& pos, JsonValue& val) {
        if (pos >= s.size() || s[pos] != '[') return false;
        pos++;
        val = JsonValue(JsonType::Array);
        skip_ws(s, pos);
        if (pos < s.size() && s[pos] == ']') {
            pos++;
            return true;
        }
        while (pos < s.size()) {
            JsonValue elem;
            if (!parse_value(s, pos, elem)) return false;
            val.arr_val.push_back(std::move(elem));
            skip_ws(s, pos);
            if (pos >= s.size()) return false;
            if (s[pos] == ']') {
                pos++;
                return true;
            }
            if (s[pos] != ',') return false;
            pos++;
        }
        return false;
    }

    static bool parse_object(std::string_view s, size_t& pos, JsonValue& val) {
        if (pos >= s.size() || s[pos] != '{') return false;
        pos++;
        val = JsonValue(JsonType::Object);
        skip_ws(s, pos);
        if (pos < s.size() && s[pos] == '}') {
            pos++;
            return true;
        }
        while (pos < s.size()) {
            skip_ws(s, pos);
            std::string key;
            if (!parse_raw_string(s, pos, key)) return false;
            skip_ws(s, pos);
            if (pos >= s.size() || s[pos] != ':') return false;
            pos++;
            JsonValue elem;
            if (!parse_value(s, pos, elem)) return false;
            val.obj_val.emplace_back(std::move(key), std::move(elem));
            skip_ws(s, pos);
            if (pos >= s.size()) return false;
            if (s[pos] == '}') {
                pos++;
                return true;
            }
            if (s[pos] != ',') return false;
            pos++;
        }
        return false;
    }
};

// Filesystem and path helpers
static void mkdir_parents(const std::string& path) {
    size_t pos = 0;
    while ((pos = path.find('/', pos + 1)) != std::string::npos) {
        std::string sub = path.substr(0, pos);
        if (!sub.empty()) {
            mkdir(sub.c_str(), 0700);
        }
    }
}

static std::string get_token_path() {
    const char* state_home = getenv("XDG_STATE_HOME");
    if (state_home && state_home[0] != '\0') {
        return std::string(state_home) + "/quickshell/user/discord_voice_token.json";
    }
    const char* home = getenv("HOME");
    if (home && home[0] != '\0') {
        return std::string(home) + "/.local/state/quickshell/user/discord_voice_token.json";
    }
    return "/tmp/quickshell_discord_voice_token.json";
}

static std::string get_legacy_cache_token_path() {
    const char* cache_home = getenv("XDG_CACHE_HOME");
    if (cache_home && cache_home[0] != '\0') {
        return std::string(cache_home) + "/quickshell-ii/discord-voice-token.json";
    }
    const char* home = getenv("HOME");
    if (home && home[0] != '\0') {
        return std::string(home) + "/.cache/quickshell-ii/discord-voice-token.json";
    }
    return "";
}

static std::string get_runtime_dir() {
    const char* r = getenv("XDG_RUNTIME_DIR");
    if (r && r[0] != '\0') return r;
    return "/tmp";
}

static std::string vencord_socket_path() {
    return get_runtime_dir() + "/" + VENCORD_SOCKET_NAME;
}

static std::string vencord_legacy_socket_path() {
    return get_runtime_dir() + "/" + VENCORD_LEGACY_SOCKET_NAME;
}

static std::vector<std::string> get_candidate_socket_paths(const std::set<std::string>& failed_paths) {
    std::vector<std::string> base_roots;
    auto add_root = [&](const char* env_var) {
        if (!env_var) return;
        const char* val = getenv(env_var);
        if (val && val[0] != '\0') {
            base_roots.push_back(val);
        }
    };

    add_root("XDG_RUNTIME_DIR");
    base_roots.push_back("/run/user/" + std::to_string(getuid()));
    add_root("TMPDIR");
    add_root("TMP");
    add_root("TEMP");
    base_roots.push_back("/tmp");

    const std::vector<std::string> subdirs = {
        "",
        "/.flatpak/com.discordapp.Discord/xdg-run",
        "/app/com.discordapp.Discord",
        "/snap.discord"
    };

    std::vector<std::string> discovered;
    std::set<std::string> seen;

    for (const auto& base : base_roots) {
        for (const auto& sub : subdirs) {
            std::string dir = base + sub;
            for (int i = 0; i <= 9; ++i) {
                std::string full = dir + "/discord-ipc-" + std::to_string(i);
                if (seen.insert(full).second) {
                    struct stat st;
                    if (stat(full.c_str(), &st) == 0 && S_ISSOCK(st.st_mode)) {
                        discovered.push_back(full);
                    }
                }
            }
        }
    }

    std::vector<std::string> result;
    for (const auto& p : discovered) {
        if (failed_paths.find(p) == failed_paths.end()) {
            result.push_back(p);
        }
    }
    for (const auto& p : discovered) {
        if (failed_paths.find(p) != failed_paths.end()) {
            result.push_back(p);
        }
    }
    return result;
}

} // anonymous namespace

class Bridge {
public:
    Bridge() {
        settings = JsonValue(JsonType::Object);
        settings["mute"] = JsonValue(false);
        settings["deaf"] = JsonValue(false);
        settings["mode"] = JsonValue("");
        settings["shortcut"] = JsonValue("");
    }

    ~Bridge() {
        cleanup();
    }

    void emit(const std::string& kind, const std::vector<std::pair<std::string, JsonValue>>& fields = {}) {
        JsonValue root(JsonType::Object);
        root["type"] = JsonValue(kind);
        root["event"] = JsonValue(kind);
        for (const auto& kv : fields) {
            root[kv.first] = kv.second;
        }
        std::string line = root.dump(false);
        line.push_back('\n');
        ssize_t w = write(STDOUT_FILENO, line.data(), line.size());
        (void)w;
        fflush(stdout);
    }

    std::string token() {
        auto try_file = [](const std::string& p) -> std::string {
            if (p.empty()) return "";
            struct stat st;
            if (stat(p.c_str(), &st) != 0) return "";
            chmod(p.c_str(), 0600);
            int fd = open(p.c_str(), O_RDONLY);
            if (fd < 0) return "";
            std::string content;
            char buf[512];
            ssize_t n;
            while ((n = read(fd, buf, sizeof(buf))) > 0) {
                content.append(buf, n);
            }
            close(fd);
            JsonValue val;
            if (JsonValue::parse(content, val) && val.is_object()) {
                return val["access_token"].to_string();
            }
            return "";
        };

        std::string tok = try_file(get_token_path());
        if (!tok.empty()) return tok;
        return try_file(get_legacy_cache_token_path());
    }

    void save_token(const std::string& tok) {
        std::string path = get_token_path();
        mkdir_parents(path);
        int fd = open(path.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0600);
        if (fd >= 0) {
            std::string content = "{\"access_token\":\"" + JsonValue::escape_string(tok) + "\"}";
            ssize_t w = write(fd, content.data(), content.size());
            (void)w;
            close(fd);
            chmod(path.c_str(), 0600);
        }
    }

    void clear_token() {
        unlink(get_token_path().c_str());
        std::string leg = get_legacy_cache_token_path();
        if (!leg.empty()) {
            unlink(leg.c_str());
        }
    }

    std::string next_nonce() {
        nonce_counter++;
        return std::to_string(nonce_counter);
    }

    bool send_discord_frame(const JsonValue& payload, uint32_t opcode = OP_FRAME) {
        if (discord_fd < 0) return false;
        std::string body = payload.dump(false);
        uint32_t len = static_cast<uint32_t>(body.size());
        uint8_t header[8];
        header[0] = static_cast<uint8_t>(opcode & 0xFF);
        header[1] = static_cast<uint8_t>((opcode >> 8) & 0xFF);
        header[2] = static_cast<uint8_t>((opcode >> 16) & 0xFF);
        header[3] = static_cast<uint8_t>((opcode >> 24) & 0xFF);
        header[4] = static_cast<uint8_t>(len & 0xFF);
        header[5] = static_cast<uint8_t>((len >> 8) & 0xFF);
        header[6] = static_cast<uint8_t>((len >> 16) & 0xFF);
        header[7] = static_cast<uint8_t>((len >> 24) & 0xFF);

        std::vector<uint8_t> packet;
        packet.insert(packet.end(), header, header + 8);
        packet.insert(packet.end(), body.begin(), body.end());

        size_t written = 0;
        while (written < packet.size()) {
            struct pollfd pfd;
            pfd.fd = discord_fd;
            pfd.events = POLLOUT;
            pfd.revents = 0;
            int ret = poll(&pfd, 1, 2000);
            if (ret <= 0) {
                close_discord();
                users.clear();
                channel = JsonValue(JsonType::Null);
                emit("disconnected");
                return false;
            }
            ssize_t n = send(discord_fd, packet.data() + written, packet.size() - written, MSG_NOSIGNAL);
            if (n <= 0) {
                close_discord();
                users.clear();
                channel = JsonValue(JsonType::Null);
                emit("disconnected");
                return false;
            }
            written += static_cast<size_t>(n);
        }
        return true;
    }

    void command(const std::string& name, const JsonValue* args = nullptr) {
        std::string n = next_nonce();
        pending[n] = name;
        JsonValue payload(JsonType::Object);
        payload["cmd"] = JsonValue(name);
        payload["nonce"] = JsonValue(n);
        if (args) {
            payload["args"] = *args;
        }
        send_discord_frame(payload);
    }

    void subscribe(const std::string& event, const std::string& channel_id = "") {
        std::string n = next_nonce();
        pending[n] = "SUB_" + event;
        JsonValue payload(JsonType::Object);
        payload["cmd"] = JsonValue("SUBSCRIBE");
        payload["evt"] = JsonValue(event);
        payload["nonce"] = JsonValue(n);
        if (!channel_id.empty()) {
            JsonValue args(JsonType::Object);
            args["channel_id"] = JsonValue(channel_id);
            payload["args"] = args;
        }
        send_discord_frame(payload);
    }

    void close_discord() {
        if (discord_fd >= 0) {
            close(discord_fd);
            discord_fd = -1;
        }
        discord_rx_buf.clear();
        current_path.clear();
    }

    bool connect_discord() {
        if (vencord_active && vencord_client_fd >= 0) return true;
        if (discord_fd >= 0) return true;

        std::vector<std::string> paths = get_candidate_socket_paths(authorization_failed_paths);
        for (const auto& path : paths) {
            int fd = socket(AF_UNIX, SOCK_STREAM, 0);
            if (fd < 0) continue;

            struct sockaddr_un addr;
            memset(&addr, 0, sizeof(addr));
            addr.sun_family = AF_UNIX;
            strncpy(addr.sun_path, path.c_str(), sizeof(addr.sun_path) - 1);

            if (connect(fd, reinterpret_cast<struct sockaddr*>(&addr), sizeof(addr)) < 0) {
                close(fd);
                continue;
            }

            struct timeval tv;
            tv.tv_sec = 2;
            tv.tv_usec = 0;
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

            // Handshake
            JsonValue handshake(JsonType::Object);
            handshake["v"] = JsonValue(static_cast<int64_t>(1));
            handshake["client_id"] = JsonValue(CLIENT_ID);
            std::string hs_body = handshake.dump(false);
            uint32_t hs_len = static_cast<uint32_t>(hs_body.size());
            uint32_t hs_op = OP_HANDSHAKE;

            uint8_t packet[8];
            packet[0] = static_cast<uint8_t>(hs_op & 0xFF);
            packet[1] = static_cast<uint8_t>((hs_op >> 8) & 0xFF);
            packet[2] = static_cast<uint8_t>((hs_op >> 16) & 0xFF);
            packet[3] = static_cast<uint8_t>((hs_op >> 24) & 0xFF);
            packet[4] = static_cast<uint8_t>(hs_len & 0xFF);
            packet[5] = static_cast<uint8_t>((hs_len >> 8) & 0xFF);
            packet[6] = static_cast<uint8_t>((hs_len >> 16) & 0xFF);
            packet[7] = static_cast<uint8_t>((hs_len >> 24) & 0xFF);

            if (send(fd, packet, 8, MSG_NOSIGNAL) != 8 ||
                send(fd, hs_body.data(), hs_body.size(), MSG_NOSIGNAL) != static_cast<ssize_t>(hs_body.size())) {
                close(fd);
                continue;
            }

            uint8_t resp_hdr[8];
            ssize_t r = recv(fd, resp_hdr, 8, MSG_WAITALL);
            if (r != 8) {
                close(fd);
                continue;
            }
            uint32_t resp_op = resp_hdr[0] | (resp_hdr[1] << 8) | (resp_hdr[2] << 16) | (resp_hdr[3] << 24);
            uint32_t resp_len = resp_hdr[4] | (resp_hdr[5] << 8) | (resp_hdr[6] << 16) | (resp_hdr[7] << 24);

            if (resp_op == static_cast<uint32_t>(OP_CLOSE) || resp_len > 10 * 1024 * 1024) {
                close(fd);
                continue;
            }

            std::string resp_body(resp_len, '\0');
            r = recv(fd, resp_body.data(), resp_len, MSG_WAITALL);
            if (r != static_cast<ssize_t>(resp_len)) {
                close(fd);
                continue;
            }

            JsonValue ready_json;
            if (!JsonValue::parse(resp_body, ready_json) || !ready_json.is_object() || ready_json["evt"].to_string() != "READY") {
                close(fd);
                continue;
            }

            tv.tv_sec = 0;
            tv.tv_usec = 0;
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
            fcntl(fd, F_SETFD, FD_CLOEXEC);
            fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK);

            discord_fd = fd;
            current_path = path;
            discord_rx_buf.clear();

            emit("backend", {{"backend", JsonValue("discord")}});
            emit("connected", {{"socket", JsonValue(path)}});

            std::string tok = token();
            if (!tok.empty()) {
                authenticate(tok);
            } else {
                emit("auth_required");
            }
            return true;
        }

        emit("unavailable", {{"message", JsonValue("Discord is not running or RPC is unavailable")}});
        return false;
    }

    bool start_vencord_server() {
        std::string path = vencord_socket_path();
        struct stat existing;
        if (lstat(path.c_str(), &existing) == 0) {
            if (!S_ISSOCK(existing.st_mode) || existing.st_uid != getuid()) {
                emit("companion_error", {{"message", JsonValue("Refusing unsafe Vesktop companion socket path")}});
                return false;
            }
            unlink(path.c_str());
        }

        mode_t prev_umask = umask(0177);
        int fd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (fd < 0) {
            umask(prev_umask);
            return false;
        }

        struct sockaddr_un addr;
        memset(&addr, 0, sizeof(addr));
        addr.sun_family = AF_UNIX;
        strncpy(addr.sun_path, path.c_str(), sizeof(addr.sun_path) - 1);

        if (bind(fd, reinterpret_cast<struct sockaddr*>(&addr), sizeof(addr)) < 0) {
            close(fd);
            umask(prev_umask);
            return false;
        }

        if (listen(fd, 5) < 0) {
            close(fd);
            unlink(path.c_str());
            umask(prev_umask);
            return false;
        }
        umask(prev_umask);

        chmod(path.c_str(), 0600);

        struct stat st;
        if (stat(path.c_str(), &st) == 0) {
            vencord_socket_inode = st.st_ino;
        }

        fcntl(fd, F_SETFD, FD_CLOEXEC);
        fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK);
        vencord_server_fd = fd;

        std::string leg_path = vencord_legacy_socket_path();
        if (leg_path != path) {
            struct stat leg_st;
            if (lstat(leg_path.c_str(), &leg_st) == 0) {
                if (S_ISSOCK(leg_st.st_mode) || S_ISLNK(leg_st.st_mode)) {
                    if (leg_st.st_uid == getuid()) {
                        unlink(leg_path.c_str());
                    }
                }
            }
            if (symlink(path.c_str(), leg_path.c_str()) == 0) {
                legacy_symlink_created = true;
            }
        }

        return true;
    }

    void shutdown_vencord_client() {
        if (vencord_client_fd >= 0) {
            close(vencord_client_fd);
            vencord_client_fd = -1;
            vencord_rx_buf.clear();
        }
    }

    bool send_vencord_command(const JsonValue& command_fields) {
        if (vencord_client_fd < 0) return false;
        JsonValue payload(JsonType::Object);
        payload["type"] = JsonValue("command");
        if (command_fields.is_object()) {
            for (const auto& kv : command_fields.obj_val) {
                payload[kv.first] = kv.second;
            }
        }
        std::string line = payload.dump(false) + "\n";
        size_t written = 0;
        while (written < line.size()) {
            struct pollfd pfd;
            pfd.fd = vencord_client_fd;
            pfd.events = POLLOUT;
            pfd.revents = 0;
            int ret = poll(&pfd, 1, 2000);
            if (ret <= 0) {
                emit("companion_error", {{"message", JsonValue("Vesktop companion stopped reading")}});
                shutdown_vencord_client();
                return false;
            }
            ssize_t n = send(vencord_client_fd, line.data() + written, line.size() - written, MSG_NOSIGNAL);
            if (n <= 0) {
                emit("companion_error", {{"message", JsonValue("Vesktop companion stopped reading")}});
                shutdown_vencord_client();
                return false;
            }
            written += static_cast<size_t>(n);
        }
        return true;
    }

    void forward_vencord_event(const JsonValue& event) {
        if (!event.is_object()) return;
        std::string kind = event["kind"].to_string();
        if (kind != "dm" && kind != "mention" && kind != "message") return;
        const JsonValue& author = event["author"];

        auto clip = [](std::string_view val, size_t limit) -> std::string {
            if (val.size() <= limit) return std::string(val);
            return std::string(val.substr(0, limit));
        };

        JsonValue out_author(JsonType::Object);
        out_author["id"] = JsonValue(clip(author["id"].to_string(), 24));
        out_author["username"] = JsonValue(clip(author["username"].to_string(), 64));
        out_author["nick"] = JsonValue(clip(author["nick"].to_string(), 64));
        out_author["avatar"] = JsonValue(clip(author["avatar"].to_string(), 64));

        emit("message_notice", {
            {"kind", JsonValue(kind)},
            {"context", JsonValue(clip(event["context"].to_string(), 100))},
            {"text", JsonValue(clip(event["text"].to_string(), 200))},
            {"author", out_author}
        });
    }

    void apply_vencord_state(const JsonValue& data, bool force = false) {
        JsonValue stable(JsonType::Object);
        for (const auto& kv : data.obj_val) {
            if (kv.first != "timestamp") {
                stable[kv.first] = kv.second;
            }
        }
        std::string signature = stable.dump(true);
        if (!force && signature == vencord_signature) {
            return;
        }
        if (discord_fd >= 0) {
            close_discord();
        }
        auth_timeouts.clear();
        auth_nonce_paths.clear();
        pending.clear();
        vencord_active = true;
        vencord_signature = signature;

        JsonValue features = (data.has("features") && data["features"].is_array()) ? data["features"] : JsonValue(JsonType::Array);
        JsonValue user = (data.has("user") && data["user"].is_object()) ? data["user"] : JsonValue(JsonType::Object);
        JsonValue chan = data.has("channel") ? data["channel"] : JsonValue(JsonType::Null);
        JsonValue usrs = (data.has("users") && data["users"].is_array()) ? data["users"] : JsonValue(JsonType::Array);

        emit("backend", {
            {"backend", JsonValue("vencord")},
            {"features", features}
        });
        emit("authenticated", {
            {"user", user}
        });
        emit("voice_channel", {
            {"channel", chan},
            {"users", usrs}
        });
        emit("voice_settings", {
            {"mute", JsonValue(data["mute"].to_bool())},
            {"deaf", JsonValue(data["deaf"].to_bool())},
            {"mode", JsonValue(data["inputMode"].to_string())},
            {"shortcut", JsonValue(data["pttShortcut"].to_string())}
        });
    }

    void authenticate(const std::string& tok) {
        std::string n = next_nonce();
        pending[n] = "AUTHENTICATE";
        JsonValue args(JsonType::Object);
        args["access_token"] = JsonValue(tok);
        JsonValue payload(JsonType::Object);
        payload["cmd"] = JsonValue("AUTHENTICATE");
        payload["args"] = args;
        payload["nonce"] = JsonValue(n);
        send_discord_frame(payload);
    }

    void authorize() {
        if (vencord_active) return;
        if (discord_fd < 0 && !connect_discord()) return;

        emit("authorizing");
        std::string n = next_nonce();
        pending[n] = "AUTHORIZE";

        JsonValue scopes(JsonType::Array);
        scopes.arr_val.push_back(JsonValue("identify"));
        scopes.arr_val.push_back(JsonValue("rpc"));
        scopes.arr_val.push_back(JsonValue("rpc.voice.read"));
        scopes.arr_val.push_back(JsonValue("rpc.voice.write"));

        JsonValue args(JsonType::Object);
        args["client_id"] = JsonValue(CLIENT_ID);
        args["scopes"] = scopes;
        args["prompt"] = JsonValue("none");

        JsonValue payload(JsonType::Object);
        payload["cmd"] = JsonValue("AUTHORIZE");
        payload["args"] = args;
        payload["nonce"] = JsonValue(n);

        send_discord_frame(payload);

        auth_timeouts[n] = std::chrono::steady_clock::now() +
            std::chrono::milliseconds(static_cast<int64_t>(AUTHORIZATION_TIMEOUT_SEC * 1000));
        auth_nonce_paths[n] = current_path;
    }

    void cancel_authorization_timeout(const std::string& nonce) {
        auth_timeouts.erase(nonce);
        auth_nonce_paths.erase(nonce);
    }

    void handle_authorization_timeout(const std::string& nonce) {
        auto it = pending.find(nonce);
        if (it == pending.end() || it->second != "AUTHORIZE") return;
        pending.erase(it);
        auth_timeouts.erase(nonce);
        std::string path = auth_nonce_paths[nonce];
        auth_nonce_paths.erase(nonce);

        if (!path.empty()) {
            authorization_failed_paths.insert(path);
        }
        close_discord();
        if (connect_discord()) {
            authorize();
        } else {
            emit("error", {{"message", JsonValue(
                "The connected Discord client does not support voice authorization. "
                "Vesktop/Vencord users must install and enable the II Discord Voice companion.")}});
        }
    }

    static std::string exchange_code(const std::string& code) {
        int pipefd[2];
        if (pipe(pipefd) < 0) return "";
        pid_t pid = fork();
        if (pid < 0) {
            close(pipefd[0]);
            close(pipefd[1]);
            return "";
        }
        if (pid == 0) {
            close(pipefd[0]);
            dup2(pipefd[1], STDOUT_FILENO);
            close(pipefd[1]);
            int devnull = open("/dev/null", O_RDWR);
            if (devnull >= 0) {
                dup2(devnull, STDIN_FILENO);
                dup2(devnull, STDERR_FILENO);
                close(devnull);
            }
            std::string json_body = "{\"code\":\"" + JsonValue::escape_string(code) + "\"}";
            execlp("curl", "curl", "-sS", "--max-time", "10",
                   "-X", "POST",
                   "-H", "Content-Type: application/json",
                   "-A", "quickshell-ii/DiscordVoice",
                   "-d", json_body.c_str(),
                   TOKEN_URL.c_str(),
                   nullptr);
            _exit(127);
        }
        close(pipefd[1]);
        std::string response;
        char buf[1024];
        ssize_t n;
        while ((n = read(pipefd[0], buf, sizeof(buf))) > 0) {
            response.append(buf, static_cast<size_t>(n));
        }
        close(pipefd[0]);
        int status = 0;
        waitpid(pid, &status, 0);
        if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
            JsonValue parsed;
            if (JsonValue::parse(response, parsed) && parsed.is_object()) {
                return parsed["access_token"].to_string();
            }
        }
        return "";
    }

    static JsonValue voice_user(const JsonValue& data) {
        const JsonValue& user = data["user"];
        const JsonValue& voice = data["voice_state"];

        std::string nick = data["nick"].to_string();
        if (nick.empty()) nick = user["global_name"].to_string();
        if (nick.empty()) nick = user["username"].to_string();

        bool mute = voice["mute"].to_bool() || voice["self_mute"].to_bool();
        bool deaf = voice["deaf"].to_bool() || voice["self_deaf"].to_bool();

        double vol = 100.0;
        if (data.has("volume")) {
            vol = data["volume"].to_double(100.0);
        }
        int64_t rounded_volume = static_cast<int64_t>(std::round(vol));

        JsonValue out(JsonType::Object);
        out["id"] = user["id"];
        out["username"] = user["username"];
        out["nick"] = JsonValue(nick);
        out["avatar"] = user["avatar"];
        out["mute"] = JsonValue(mute);
        out["deaf"] = JsonValue(deaf);
        out["speaking"] = JsonValue(false);
        out["volume"] = JsonValue(rounded_volume);
        out["localMute"] = JsonValue(data["mute"].to_bool());
        return out;
    }

    void select_channel(const JsonValue& data) {
        users.clear();
        if (data.is_null() || !data.is_object() || data["id"].to_string().empty()) {
            channel = JsonValue(JsonType::Null);
            emit("voice_channel", {
                {"channel", JsonValue(JsonType::Null)},
                {"users", JsonValue(JsonType::Array)}
            });
            return;
        }

        channel = JsonValue(JsonType::Object);
        channel["id"] = data["id"];
        channel["name"] = data.has("name") && !data["name"].to_string().empty() ? data["name"] : JsonValue("Voice channel");
        channel["guild_id"] = data.has("guild_id") ? data["guild_id"] : JsonValue("");

        const JsonValue& voice_states = data["voice_states"];
        if (voice_states.is_array()) {
            for (const auto& state : voice_states.arr_val) {
                JsonValue participant = voice_user(state);
                std::string uid = participant["id"].to_string();
                if (!uid.empty()) {
                    users[uid] = participant;
                }
            }
        }

        JsonValue users_arr(JsonType::Array);
        for (const auto& kv : users) {
            users_arr.arr_val.push_back(kv.second);
        }

        emit("voice_channel", {
            {"channel", channel},
            {"users", users_arr}
        });

        std::string cid = channel["id"].to_string();
        subscribe("VOICE_STATE_CREATE", cid);
        subscribe("VOICE_STATE_UPDATE", cid);
        subscribe("VOICE_STATE_DELETE", cid);
        subscribe("SPEAKING_START", cid);
        subscribe("SPEAKING_STOP", cid);

        command("GET_VOICE_SETTINGS");
    }

    void apply_settings(const JsonValue& data) {
        const JsonValue& mode = data["mode"];
        std::string shortcut;
        if (mode.is_object() && mode["shortcut"].is_array()) {
            std::vector<std::string> keys;
            for (const auto& k : mode["shortcut"].arr_val) {
                if (k.is_object() && !k["name"].to_string().empty()) {
                    keys.push_back(k["name"].to_string());
                }
            }
            for (size_t i = 0; i < keys.size(); ++i) {
                if (i > 0) shortcut += " + ";
                shortcut += keys[i];
            }
        }

        std::string mode_type;
        if (mode.is_object() && !mode["type"].to_string().empty()) {
            mode_type = mode["type"].to_string();
        } else if (settings.has("mode")) {
            mode_type = settings["mode"].to_string();
        }

        if (shortcut.empty() && settings.has("shortcut")) {
            shortcut = settings["shortcut"].to_string();
        }

        settings = JsonValue(JsonType::Object);
        settings["mute"] = JsonValue(data["mute"].to_bool());
        settings["deaf"] = JsonValue(data["deaf"].to_bool());
        settings["mode"] = JsonValue(mode_type);
        settings["shortcut"] = JsonValue(shortcut);

        emit("voice_settings", {
            {"mute", settings["mute"]},
            {"deaf", settings["deaf"]},
            {"mode", settings["mode"]},
            {"shortcut", settings["shortcut"]}
        });
    }

    void handle_discord_response(const std::string& cmd, const JsonValue& data) {
        if (cmd == "AUTHORIZE") {
            std::string code = data["code"].to_string();
            if (code.empty()) {
                emit("error", {{"message", JsonValue("Discord authorization was not completed")}});
                return;
            }
            std::string tok = exchange_code(code);
            if (!tok.empty()) {
                save_token(tok);
                authenticate(tok);
            } else {
                emit("error", {{"message", JsonValue("Discord token exchange failed")}});
            }
        } else if (cmd == "AUTHENTICATE") {
            user_id = data["user"]["id"].to_string();
            emit("authenticated", {{"user", data["user"]}});
            subscribe("VOICE_CHANNEL_SELECT");
            subscribe("VOICE_SETTINGS_UPDATE");
            command("GET_SELECTED_VOICE_CHANNEL");
        } else if (cmd == "GET_SELECTED_VOICE_CHANNEL") {
            if (data.is_object() && !data["id"].to_string().empty()) {
                select_channel(data);
            } else {
                select_channel(JsonValue(JsonType::Null));
            }
        } else if (cmd == "GET_VOICE_SETTINGS" || cmd == "SET_VOICE_SETTINGS") {
            apply_settings(data);
        } else if (cmd == "SET_USER_VOICE_SETTINGS") {
            std::string uid = data["user_id"].to_string();
            if (users.find(uid) != users.end()) {
                if (data.has("volume")) {
                    users[uid]["volume"] = JsonValue(static_cast<int64_t>(std::round(data["volume"].to_double())));
                }
                if (data.has("mute")) {
                    users[uid]["localMute"] = JsonValue(data["mute"].to_bool());
                }
                JsonValue users_arr(JsonType::Array);
                for (const auto& kv : users) {
                    users_arr.arr_val.push_back(kv.second);
                }
                emit("voice_state", {{"users", users_arr}});
            }
        }
    }

    void handle_discord_dispatch(const std::string& event, const JsonValue& data) {
        if (event == "VOICE_CHANNEL_SELECT") {
            command("GET_SELECTED_VOICE_CHANNEL");
        } else if (event == "VOICE_STATE_CREATE" || event == "VOICE_STATE_UPDATE") {
            JsonValue participant = voice_user(data);
            std::string uid = participant["id"].to_string();
            if (users.find(uid) != users.end()) {
                participant["speaking"] = users[uid]["speaking"];
            }
            if (!uid.empty()) {
                users[uid] = participant;
            }
            JsonValue users_arr(JsonType::Array);
            for (const auto& kv : users) {
                users_arr.arr_val.push_back(kv.second);
            }
            emit("voice_state", {{"users", users_arr}});
        } else if (event == "VOICE_STATE_DELETE") {
            std::string uid = data["user"]["id"].to_string();
            users.erase(uid);
            JsonValue users_arr(JsonType::Array);
            for (const auto& kv : users) {
                users_arr.arr_val.push_back(kv.second);
            }
            emit("voice_state", {{"users", users_arr}});
        } else if (event == "SPEAKING_START" || event == "SPEAKING_STOP") {
            std::string uid = data["user_id"].to_string();
            if (users.find(uid) != users.end()) {
                users[uid]["speaking"] = JsonValue(event == "SPEAKING_START");
            }
            JsonValue users_arr(JsonType::Array);
            for (const auto& kv : users) {
                users_arr.arr_val.push_back(kv.second);
            }
            emit("voice_state", {{"users", users_arr}});
        } else if (event == "VOICE_SETTINGS_UPDATE") {
            apply_settings(data);
        }
    }

    void handle_discord_frame(const JsonValue& payload) {
        std::string nonce = payload["nonce"].to_string();
        std::string evt = payload["evt"].to_string();

        if (evt == "ERROR") {
            std::string cmd;
            auto it = pending.find(nonce);
            if (it != pending.end()) {
                cmd = it->second;
                pending.erase(it);
            }
            cancel_authorization_timeout(nonce);
            if (cmd == "AUTHENTICATE") {
                clear_token();
                emit("auth_required");
            } else {
                std::string msg = payload["data"]["message"].to_string("Discord RPC error");
                emit("error", {{"message", JsonValue(msg)}});
            }
            return;
        }

        if (!nonce.empty() && pending.find(nonce) != pending.end()) {
            std::string cmd = pending[nonce];
            pending.erase(nonce);
            cancel_authorization_timeout(nonce);
            handle_discord_response(cmd, payload["data"]);
            return;
        }

        if (payload["cmd"].to_string() == "DISPATCH") {
            handle_discord_dispatch(evt, payload["data"]);
        }
    }

    void handle_stdin_line(const std::string& line) {
        JsonValue message;
        if (!JsonValue::parse(line, message) || !message.is_object()) {
            emit("error", {{"message", JsonValue("Invalid bridge command")}});
            return;
        }
        std::string cmd = message["cmd"].to_string();
        if (cmd == "connect") {
            connect_discord();
        } else if (cmd == "authorize") {
            authorize();
        } else if (cmd == "set_voice_settings") {
            JsonValue args(JsonType::Object);
            if (message.has("mute")) args["mute"] = JsonValue(message["mute"].to_bool());
            if (message.has("deaf")) args["deaf"] = JsonValue(message["deaf"].to_bool());
            if (vencord_active) {
                send_vencord_command(args);
            } else if (discord_fd >= 0) {
                command("SET_VOICE_SETTINGS", &args);
            }
        } else if (cmd == "set_user_voice") {
            std::string uid = message["user_id"].to_string();
            JsonValue args(JsonType::Object);
            if (message.has("volume")) {
                int64_t v = static_cast<int64_t>(std::round(message["volume"].to_double()));
                if (v < 0) v = 0;
                if (v > 200) v = 200;
                args["volume"] = JsonValue(v);
            }
            if (message.has("mute")) {
                args["mute"] = JsonValue(message["mute"].to_bool());
            }
            if (!uid.empty() && !args.obj_val.empty()) {
                if (vencord_active) {
                    JsonValue uv(JsonType::Object);
                    uv["userId"] = JsonValue(uid);
                    for (const auto& kv : args.obj_val) {
                        uv[kv.first] = kv.second;
                    }
                    JsonValue cmd_obj(JsonType::Object);
                    cmd_obj["userVoice"] = uv;
                    send_vencord_command(cmd_obj);
                } else if (discord_fd >= 0) {
                    JsonValue cargs(JsonType::Object);
                    cargs["user_id"] = JsonValue(uid);
                    for (const auto& kv : args.obj_val) {
                        cargs[kv.first] = kv.second;
                    }
                    command("SET_USER_VOICE_SETTINGS", &cargs);
                }
            }
        } else if (cmd == "set_input_mode") {
            std::string mode = message["mode"].to_string();
            if (mode == "PUSH_TO_TALK" || mode == "VOICE_ACTIVITY") {
                if (vencord_active) {
                    JsonValue cmd_obj(JsonType::Object);
                    cmd_obj["inputMode"] = JsonValue(mode);
                    send_vencord_command(cmd_obj);
                } else if (discord_fd >= 0) {
                    JsonValue mode_obj(JsonType::Object);
                    mode_obj["type"] = JsonValue(mode);
                    JsonValue cargs(JsonType::Object);
                    cargs["mode"] = mode_obj;
                    command("SET_VOICE_SETTINGS", &cargs);
                }
            }
        } else if (cmd == "disconnect") {
            close_discord();
        } else {
            emit("error", {{"message", JsonValue("Invalid bridge command")}});
        }
    }

    void handle_vencord_line(const std::string& line) {
        JsonValue message;
        if (!JsonValue::parse(line, message) || !message.is_object()) return;
        std::string type = message["type"].to_string();
        if (type == "event") {
            forward_vencord_event(message["event"]);
        } else if (type == "state") {
            const JsonValue& data = message["state"];
            if (data.is_object() && data["version"].to_int() == 1 && data["backend"].to_string() == "vencord") {
                apply_vencord_state(data);
            }
        }
    }

    void run() {
        fcntl(STDIN_FILENO, F_SETFL, fcntl(STDIN_FILENO, F_GETFL, 0) | O_NONBLOCK);

        while (g_running) {
            std::vector<struct pollfd> pfds;

            // 0: STDIN
            pfds.push_back({STDIN_FILENO, POLLIN, 0});

            // Vencord server
            int vencord_server_idx = -1;
            if (vencord_server_fd >= 0) {
                vencord_server_idx = static_cast<int>(pfds.size());
                pfds.push_back({vencord_server_fd, POLLIN, 0});
            }

            // Vencord client
            int vencord_client_idx = -1;
            if (vencord_client_fd >= 0) {
                vencord_client_idx = static_cast<int>(pfds.size());
                pfds.push_back({vencord_client_fd, POLLIN, 0});
            }

            // Discord socket
            int discord_idx = -1;
            if (discord_fd >= 0) {
                discord_idx = static_cast<int>(pfds.size());
                pfds.push_back({discord_fd, POLLIN, 0});
            }

            int timeout_ms = -1;
            auto now = std::chrono::steady_clock::now();
            if (!auth_timeouts.empty()) {
                auto earliest = auth_timeouts.begin()->second;
                for (const auto& kv : auth_timeouts) {
                    if (kv.second < earliest) earliest = kv.second;
                }
                if (now >= earliest) {
                    timeout_ms = 0;
                } else {
                    int64_t diff = std::chrono::duration_cast<std::chrono::milliseconds>(earliest - now).count();
                    timeout_ms = diff < 0 ? 0 : static_cast<int>(diff);
                }
            }

            int ret = poll(pfds.data(), pfds.size(), timeout_ms);
            if (ret < 0) {
                if (errno == EINTR) {
                    if (!g_running) break;
                    continue;
                }
                break;
            }

            if (!auth_timeouts.empty()) {
                now = std::chrono::steady_clock::now();
                std::vector<std::string> expired;
                for (const auto& kv : auth_timeouts) {
                    if (now >= kv.second) {
                        expired.push_back(kv.first);
                    }
                }
                for (const auto& n : expired) {
                    handle_authorization_timeout(n);
                }
            }

            if (ret == 0) continue;

            // Stdin activity
            if (pfds[0].revents & (POLLIN | POLLHUP | POLLERR)) {
                char buf[4096];
                ssize_t n = read(STDIN_FILENO, buf, sizeof(buf));
                if (n <= 0) {
                    if (n == 0 || (errno != EAGAIN && errno != EWOULDBLOCK)) {
                        g_running = 0;
                        break;
                    }
                } else {
                    stdin_rx_buf.append(buf, static_cast<size_t>(n));
                    size_t nl;
                    while ((nl = stdin_rx_buf.find('\n')) != std::string::npos) {
                        std::string line = stdin_rx_buf.substr(0, nl);
                        stdin_rx_buf.erase(0, nl + 1);
                        while (!line.empty() && (line.back() == '\r' || line.back() == ' ')) {
                            line.pop_back();
                        }
                        if (!line.empty()) {
                            handle_stdin_line(line);
                        }
                    }
                }
            }

            // Vencord server connection
            if (vencord_server_idx >= 0 && (pfds[vencord_server_idx].revents & POLLIN)) {
                int client_fd = accept(vencord_server_fd, nullptr, nullptr);
                if (client_fd >= 0) {
                    fcntl(client_fd, F_SETFD, FD_CLOEXEC);
                    fcntl(client_fd, F_SETFL, fcntl(client_fd, F_GETFL, 0) | O_NONBLOCK);
                    if (vencord_client_fd >= 0) {
                        close(vencord_client_fd);
                    }
                    vencord_client_fd = client_fd;
                    vencord_rx_buf.clear();
                }
            }

            // Vencord client activity
            if (vencord_client_idx >= 0 && (pfds[vencord_client_idx].revents & (POLLIN | POLLHUP | POLLERR))) {
                char buf[4096];
                ssize_t n = read(vencord_client_fd, buf, sizeof(buf));
                if (n <= 0) {
                    if (n == 0 || (errno != EAGAIN && errno != EWOULDBLOCK)) {
                        close(vencord_client_fd);
                        vencord_client_fd = -1;
                        vencord_rx_buf.clear();
                        if (vencord_active) {
                            vencord_active = false;
                            vencord_signature.clear();
                            emit("disconnected", {{"reason", JsonValue("Vesktop companion stopped")}});
                            connect_discord();
                        }
                    }
                } else {
                    vencord_rx_buf.append(buf, static_cast<size_t>(n));
                    if (vencord_rx_buf.size() > COMPANION_READ_LIMIT) {
                        size_t nl = vencord_rx_buf.find('\n');
                        if (nl != std::string::npos) {
                            vencord_rx_buf.erase(0, nl + 1);
                        } else {
                            vencord_rx_buf.clear();
                        }
                    }
                    size_t nl;
                    while ((nl = vencord_rx_buf.find('\n')) != std::string::npos) {
                        std::string line = vencord_rx_buf.substr(0, nl);
                        vencord_rx_buf.erase(0, nl + 1);
                        while (!line.empty() && (line.back() == '\r' || line.back() == ' ')) {
                            line.pop_back();
                        }
                        if (!line.empty()) {
                            handle_vencord_line(line);
                        }
                    }
                }
            }

            // Discord socket activity
            if (discord_idx >= 0 && (pfds[discord_idx].revents & (POLLIN | POLLHUP | POLLERR))) {
                char buf[4096];
                ssize_t n = read(discord_fd, buf, sizeof(buf));
                if (n <= 0) {
                    if (n == 0 || (errno != EAGAIN && errno != EWOULDBLOCK)) {
                        close_discord();
                        users.clear();
                        channel = JsonValue(JsonType::Null);
                        emit("disconnected");
                    }
                } else {
                    discord_rx_buf.insert(discord_rx_buf.end(), reinterpret_cast<uint8_t*>(buf), reinterpret_cast<uint8_t*>(buf) + n);
                    while (discord_rx_buf.size() >= 8) {
                        uint32_t op = discord_rx_buf[0] | (discord_rx_buf[1] << 8) | (discord_rx_buf[2] << 16) | (discord_rx_buf[3] << 24);
                        uint32_t len = discord_rx_buf[4] | (discord_rx_buf[5] << 8) | (discord_rx_buf[6] << 16) | (discord_rx_buf[7] << 24);
                        if (discord_rx_buf.size() < 8 + len) {
                            break;
                        }
                        std::string body(reinterpret_cast<char*>(discord_rx_buf.data()) + 8, len);
                        discord_rx_buf.erase(discord_rx_buf.begin(), discord_rx_buf.begin() + 8 + len);

                        if (op == static_cast<uint32_t>(OP_PING)) {
                            JsonValue ping_payload;
                            JsonValue::parse(body, ping_payload);
                            send_discord_frame(ping_payload, OP_PONG);
                        } else if (op == static_cast<uint32_t>(OP_CLOSE)) {
                            close_discord();
                            users.clear();
                            channel = JsonValue(JsonType::Null);
                            emit("disconnected");
                            break;
                        } else if (op == static_cast<uint32_t>(OP_FRAME)) {
                            JsonValue frame_payload;
                            if (JsonValue::parse(body, frame_payload)) {
                                handle_discord_frame(frame_payload);
                            }
                        }
                    }
                }
            }
        }
    }

    void cleanup() {
        close_discord();
        if (vencord_client_fd >= 0) {
            close(vencord_client_fd);
            vencord_client_fd = -1;
        }
        if (vencord_server_fd >= 0) {
            close(vencord_server_fd);
            vencord_server_fd = -1;
        }
        std::string path = vencord_socket_path();
        if (vencord_socket_inode != 0) {
            struct stat st;
            if (stat(path.c_str(), &st) == 0 && st.st_ino == vencord_socket_inode) {
                unlink(path.c_str());
            }
        }
        if (legacy_symlink_created) {
            std::string leg = vencord_legacy_socket_path();
            unlink(leg.c_str());
        }
    }

private:
    int discord_fd = -1;
    int vencord_server_fd = -1;
    int vencord_client_fd = -1;
    ino_t vencord_socket_inode = 0;
    bool legacy_symlink_created = false;
    bool vencord_active = false;
    std::string vencord_signature;

    int64_t nonce_counter = 0;
    std::map<std::string, std::string> pending;
    std::map<std::string, std::chrono::steady_clock::time_point> auth_timeouts;
    std::map<std::string, std::string> auth_nonce_paths;
    std::set<std::string> authorization_failed_paths;

    std::map<std::string, JsonValue> users;
    JsonValue channel{JsonType::Null};
    JsonValue settings{JsonType::Object};
    std::string user_id;
    std::string current_path;

    std::string stdin_rx_buf;
    std::string vencord_rx_buf;
    std::vector<uint8_t> discord_rx_buf;
};

int main() {
    signal(SIGPIPE, SIG_IGN);
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = sig_handler;
    sigaction(SIGINT, &sa, nullptr);
    sigaction(SIGTERM, &sa, nullptr);

    Bridge bridge;
    bridge.start_vencord_server();
    bridge.emit("ready");

    bridge.run();

    bridge.cleanup();
    return 0;
}
