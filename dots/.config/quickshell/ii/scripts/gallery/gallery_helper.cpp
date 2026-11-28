// Fast native C++20 / Qt6Core+Qt6Gui scanner & parallel thumbnailer for ii Gallery.
// Build:
//   g++ -O3 -std=c++20 gallery_helper.cpp -o gallery_helper $(pkg-config --cflags --libs Qt6Gui Qt6Core) -pthread
//
// Commands (drop-in compatible with scan_gallery.py for hot paths):
//   scan --folders-json '<json>' [--show-videos 1] [--max-items 3000]
//   thumbs-batch --paths-json '<json>' [--out-dir <dir>] [--size 480]

#include <QByteArray>
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QImage>
#include <QImageReader>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QString>

#include <dirent.h>
#include <sys/stat.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace fs = std::filesystem;

static const std::unordered_set<std::string> IMAGE_EXTS = {
    ".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".avif", ".heic", ".heif", ".jfif"
};
static const std::unordered_set<std::string> VIDEO_EXTS = {
    ".mp4", ".mkv", ".webm", ".mov", ".avi", ".m4v", ".3gp", ".ogv", ".ts", ".flv", ".wmv"
};
static const std::unordered_set<std::string> SKIP_DIRS = {
    ".git", ".cache", "node_modules", "__pycache__", ".Trash", ".local", ".thumbnails",
    ".venv", "venv", "target", "dist", "build", ".next", ".nuxt", "site-packages",
    ".gradle", "android", "ios", "vendor"
};
static const std::vector<std::string> REPO_OR_THEME_MARKERS = {
    ".git", ".nomedia", "index.theme", "package.json", "Cargo.toml",
    "go.mod", "pyproject.toml", "CMakeLists.txt", "meson.build"
};

static std::string to_lower_ascii(std::string s) {
    for (char &c : s) {
        if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
    }
    return s;
}

static std::string expand_path(const std::string &raw) {
    std::string p = raw;
    if (!p.empty() && p[0] == '~') {
        const char *home = std::getenv("HOME");
        if (home) {
            if (p.size() == 1 || p[1] == '/') {
                p = std::string(home) + p.substr(1);
            }
        }
    }
    std::error_code ec;
    fs::path fp = fs::weakly_canonical(fs::path(p), ec);
    return ec ? fs::path(p).lexically_normal().string() : fp.string();
}

static std::string default_cache_dir() {
    const char *xdg = std::getenv("XDG_CACHE_HOME");
    std::string base;
    if (xdg && xdg[0] != '\0') {
        base = xdg;
    } else {
        const char *home = std::getenv("HOME");
        base = std::string(home ? home : "/tmp") + "/.cache";
    }
    return base + "/quickshell/gallery_thumbs";
}

static std::string media_thumb_path(const std::string &path, int64_t mtime_sec, const std::string &cache_dir) {
    std::string key_in = "v2:" + path + ":" + std::to_string(mtime_sec);
    QByteArray hash = QCryptographicHash::hash(
        QByteArray(key_in.data(), static_cast<qsizetype>(key_in.size())),
        QCryptographicHash::Sha1
    ).toHex();
    return cache_dir + "/" + hash.toStdString() + ".jpg";
}

struct MediaItem {
    std::string path;
    std::string file;
    std::string title;
    std::string ext;
    bool is_video = false;
    std::string root;
    std::string folder;
    bool is_sub = false;
    int64_t mtime_ms = 0;
    int64_t size = 0;
    int w = 0;
    int h = 0;
    int dur = 0;
    std::string thumb;
};

static int cmd_scan(const std::string &folders_json, bool show_videos, int max_items) {
    QJsonParseError err{};
    QJsonDocument doc = QJsonDocument::fromJson(QByteArray::fromStdString(folders_json), &err);
    if (err.error != QJsonParseError::NoError || !doc.isArray()) {
        std::cout << R"({"error":"invalid folders json","items":[],"folderCounts":{}})" << "\n";
        return 1;
    }

    const std::string cache_dir = default_cache_dir();
    std::error_code ec;
    fs::create_directories(cache_dir, ec);

    std::vector<MediaItem> items;
    items.reserve(2048);
    std::unordered_set<std::string> seen_paths;
    seen_paths.reserve(4096);
    std::unordered_map<std::string, int> folder_counts;

    const QJsonArray folders = doc.array();
    for (const QJsonValue &val : folders) {
        const QJsonObject fobj = val.toObject();
        const std::string raw_path = fobj.value("path").toString().trimmed().toStdString();
        if (raw_path.empty()) continue;

        std::string root_name = fobj.value("name").toString().trimmed().toStdString();
        if (root_name.empty()) {
            fs::path rp(raw_path);
            root_name = rp.filename().string();
            if (root_name.empty()) root_name = raw_path;
        }
        const std::string abs_root = expand_path(raw_path);
        folder_counts[root_name] = 0;

        if (!fs::is_directory(abs_root, ec)) continue;

        std::vector<std::pair<std::string, std::string>> stack;
        stack.emplace_back(abs_root, "");

        while (!stack.empty()) {
            auto [dirpath, rel_dir] = std::move(stack.back());
            stack.pop_back();

            if (!rel_dir.empty()) {
                bool skip = false;
                struct stat mst{};
                for (const auto &m : REPO_OR_THEME_MARKERS) {
                    if (::lstat((dirpath + "/" + m).c_str(), &mst) == 0) {
                        skip = true;
                        break;
                    }
                }
                if (skip) continue;
            }

            const bool is_sub = !rel_dir.empty();
            const std::string rel_folder = is_sub ? (root_name + "/" + rel_dir) : root_name;

            DIR *dir = ::opendir(dirpath.c_str());
            if (!dir) continue;

            struct dirent *de = nullptr;
            while ((de = ::readdir(dir)) != nullptr) {
                const char *cname = de->d_name;
                if (cname[0] == '.') continue;
                const std::string name(cname);
                const std::string full_path = dirpath + "/" + name;

                bool is_dir = false;
                bool is_reg = false;
                struct stat st{};
                bool have_stat = false;

                if (de->d_type == DT_DIR) {
                    is_dir = true;
                } else if (de->d_type == DT_REG) {
                    is_reg = true;
                } else if (de->d_type == DT_UNKNOWN) {
                    if (::lstat(full_path.c_str(), &st) != 0) continue;
                    have_stat = true;
                    is_dir = S_ISDIR(st.st_mode);
                    is_reg = S_ISREG(st.st_mode);
                } else {
                    continue;
                }

                if (is_dir) {
                    if (SKIP_DIRS.find(name) == SKIP_DIRS.end()) {
                        stack.emplace_back(full_path, is_sub ? (rel_dir + "/" + name) : name);
                    }
                    continue;
                }
                if (!is_reg) continue;

                const auto dot = name.rfind('.');
                if (dot == std::string::npos || dot == 0) continue;
                const std::string ext = to_lower_ascii(name.substr(dot));
                const bool is_img = IMAGE_EXTS.find(ext) != IMAGE_EXTS.end();
                const bool is_vid = !is_img && (VIDEO_EXTS.find(ext) != VIDEO_EXTS.end());
                if (!is_img && !(is_vid && show_videos)) continue;

                if (!seen_paths.insert(full_path).second) continue;

                if (!have_stat && ::lstat(full_path.c_str(), &st) != 0) continue;
                const int64_t fsize = static_cast<int64_t>(st.st_size);
                if (fsize <= 0) continue;

                const int64_t mtime_sec = static_cast<int64_t>(st.st_mtim.tv_sec);
                const int64_t mtime_ms = mtime_sec * 1000 + static_cast<int64_t>(st.st_mtim.tv_nsec / 1000000);

                const std::string tp = media_thumb_path(full_path, mtime_sec, cache_dir);
                struct stat tst{};
                std::string thumb = (::stat(tp.c_str(), &tst) == 0 && S_ISREG(tst.st_mode)) ? tp : "";
                int dur = 0, vw = 0, vh = 0;
                if (is_vid) {
                    const std::string mp = tp + ".meta";
                    if (FILE *mf = std::fopen(mp.c_str(), "r")) {
                        if (std::fscanf(mf, "%d,%d,%d", &dur, &vw, &vh) < 1) {
                            dur = 0; vw = 0; vh = 0;
                        }
                        std::fclose(mf);
                    }
                }

                std::string stem = name.substr(0, dot);
                for (char &c : stem) {
                    if (c == '_' || c == '-') c = ' ';
                }
                auto first = stem.find_first_not_of(' ');
                auto last = stem.find_last_not_of(' ');
                std::string title = (first == std::string::npos) ? name : stem.substr(first, last - first + 1);

                std::string ext_up = ext.substr(1);
                for (char &c : ext_up) {
                    if (c >= 'a' && c <= 'z') c = static_cast<char>(c - 'a' + 'A');
                }

                MediaItem mi;
                mi.path = full_path;
                mi.file = name;
                mi.title = std::move(title);
                mi.ext = std::move(ext_up);
                mi.is_video = is_vid;
                mi.root = root_name;
                mi.folder = rel_folder;
                mi.is_sub = is_sub;
                mi.mtime_ms = mtime_ms;
                mi.size = fsize;
                mi.w = vw;
                mi.h = vh;
                mi.dur = dur;
                mi.thumb = std::move(thumb);
                items.push_back(std::move(mi));
                folder_counts[root_name] += 1;
            }
            ::closedir(dir);
        }
    }

    std::sort(items.begin(), items.end(), [](const MediaItem &a, const MediaItem &b) {
        return a.mtime_ms > b.mtime_ms;
    });
    if (max_items > 0 && static_cast<int>(items.size()) > max_items) {
        items.resize(static_cast<size_t>(max_items));
    }

    QJsonArray arr;
    for (const auto &it : items) {
        QJsonObject o;
        o.insert("id", QString::fromStdString(it.path));
        o.insert("path", QString::fromStdString(it.path));
        o.insert("file", QString::fromStdString(it.file));
        o.insert("title", QString::fromStdString(it.title));
        o.insert("ext", QString::fromStdString(it.ext));
        o.insert("type", it.is_video ? "video" : "photo");
        o.insert("root", QString::fromStdString(it.root));
        o.insert("folder", QString::fromStdString(it.folder));
        o.insert("isSub", it.is_sub);
        o.insert("mtime", static_cast<double>(it.mtime_ms));
        o.insert("size", static_cast<double>(it.size));
        o.insert("w", it.w);
        o.insert("h", it.h);
        o.insert("dur", it.dur);
        o.insert("thumb", QString::fromStdString(it.thumb));
        arr.append(o);
    }

    QJsonObject fc;
    for (const auto &kv : folder_counts) {
        fc.insert(QString::fromStdString(kv.first), kv.second);
    }

    QJsonObject root;
    root.insert("items", arr);
    root.insert("folderCounts", fc);
    root.insert("cacheDir", QString::fromStdString(cache_dir));

    const QByteArray out = QJsonDocument(root).toJson(QJsonDocument::Compact);
    std::fwrite(out.constData(), 1, static_cast<size_t>(out.size()), stdout);
    std::fputc('\n', stdout);
    return 0;
}

static std::string make_photo_thumb(const std::string &path, const std::string &cache_dir, int target_size) {
    std::error_code ec;
    const QFileInfo fi(QString::fromStdString(path));
    if (!fi.isFile()) return "";
    const int64_t mtime_sec = fi.lastModified().toSecsSinceEpoch();
    const std::string out_path = media_thumb_path(path, mtime_sec, cache_dir);
    if (fs::is_regular_file(out_path, ec)) return out_path;

    QImageReader reader(QString::fromStdString(path));
    reader.setAutoTransform(true);
    const QSize orig = reader.size();
    if (orig.isValid() && (orig.width() > target_size || orig.height() > target_size)) {
        // Use QImageReader scaled decode (leverages libjpeg DCT scaling for massive speedup)
        QSize scaled = orig.scaled(target_size, target_size, Qt::KeepAspectRatio);
        if (scaled.width() > 0 && scaled.height() > 0) {
            reader.setScaledSize(scaled);
        }
    }

    QImage img = reader.read();
    if (img.isNull()) return "";

    if (img.width() > target_size || img.height() > target_size) {
        img = img.scaled(target_size, target_size, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    }
    if (img.format() != QImage::Format_RGB888 && img.format() != QImage::Format_RGB32) {
        img = img.convertToFormat(QImage::Format_RGB888);
    }

    const std::string tmp_path = out_path + "." + std::to_string(std::hash<std::thread::id>{}(std::this_thread::get_id())) + ".tmp.jpg";
    if (img.save(QString::fromStdString(tmp_path), "JPG", 90)) {
        std::error_code rec;
        fs::rename(tmp_path, out_path, rec);
        if (!rec) return out_path;
        fs::remove(tmp_path, rec);
    }
    return "";
}

static int cmd_thumbs_batch(const std::string &paths_json, const std::string &out_dir, int size) {
    QJsonParseError err{};
    QJsonDocument doc = QJsonDocument::fromJson(QByteArray::fromStdString(paths_json), &err);
    if (err.error != QJsonParseError::NoError || !doc.isArray()) {
        std::cout << R"({"ok":false,"error":"invalid paths json","thumbs":{}})" << "\n";
        return 1;
    }

    const std::string cache_dir = out_dir.empty() ? default_cache_dir() : expand_path(out_dir);
    std::error_code ec;
    fs::create_directories(cache_dir, ec);
    const int target_size = std::clamp(size, 128, 768);

    std::vector<std::string> paths;
    for (const QJsonValue &v : doc.array()) {
        const std::string p = v.toString().toStdString();
        if (!p.empty()) paths.push_back(expand_path(p));
    }

    std::atomic<size_t> next_idx{0};
    std::mutex out_mtx;
    QJsonObject thumbs;

    const unsigned hw = std::thread::hardware_concurrency();
    const unsigned num_threads = std::min<unsigned>(8, std::max<unsigned>(2, hw ? hw : 4));
    std::vector<std::thread> pool;
    pool.reserve(num_threads);

    for (unsigned t = 0; t < num_threads; ++t) {
        pool.emplace_back([&]() {
            while (true) {
                const size_t i = next_idx.fetch_add(1);
                if (i >= paths.size()) break;
                const std::string tp = make_photo_thumb(paths[i], cache_dir, target_size);
                if (!tp.empty()) {
                    std::lock_guard<std::mutex> lk(out_mtx);
                    thumbs.insert(QString::fromStdString(paths[i]), QString::fromStdString(tp));
                }
            }
        });
    }
    for (auto &th : pool) th.join();

    QJsonObject root;
    root.insert("ok", true);
    root.insert("thumbs", thumbs);
    const QByteArray out = QJsonDocument(root).toJson(QJsonDocument::Compact);
    std::fwrite(out.constData(), 1, static_cast<size_t>(out.size()), stdout);
    std::fputc('\n', stdout);
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        std::cerr << "usage: gallery_helper <scan|thumbs-batch> ...\n";
        return 1;
    }
    const std::string cmd = argv[1];
    auto get_arg = [&](const std::string &flag, const std::string &def = "") -> std::string {
        for (int i = 2; i < argc - 1; ++i) {
            if (flag == argv[i]) return argv[i + 1];
        }
        return def;
    };

    if (cmd == "scan") {
        const std::string fj = get_arg("--folders-json", "[]");
        const bool show_videos = get_arg("--show-videos", "1") != "0";
        const int max_items = std::atoi(get_arg("--max-items", "3000").c_str());
        return cmd_scan(fj, show_videos, max_items);
    }
    if (cmd == "thumbs-batch") {
        // Initialize Qt image plugins only for thumbnail decoding
        QCoreApplication app(argc, argv);
        const std::string pj = get_arg("--paths-json", "[]");
        const std::string out_dir = get_arg("--out-dir", "");
        const int size = std::atoi(get_arg("--size", "480").c_str());
        return cmd_thumbs_batch(pj, out_dir, size);
    }

    std::cerr << "unknown command: " << cmd << "\n";
    return 1;
}
