#include "mpvitem.h"

#include <QCoreApplication>
#include <QGuiApplication>
#include <QOpenGLContext>
#include <QOpenGLFramebufferObject>
#include <QQuickWindow>
#include <QUrl>
#include <QtGui/qguiapplication_platform.h>

#include <mpv/client.h>
#include <mpv/render_gl.h>

#include <clocale>

namespace {

void *glProcAddress(void *, const char *name)
{
    QOpenGLContext *context = QOpenGLContext::currentContext();
    return context ? reinterpret_cast<void *>(context->getProcAddress(name)) : nullptr;
}

// Runs `fn` on the GUI thread if the item still exists. mpv calls back from its
// own threads, and the item may be gone by the time the call lands.
template<typename Fn>
void postToItem(MpvCore *core, Fn fn)
{
    QPointer<QQuickItem> item = core->item;
    QMetaObject::invokeMethod(qApp, [item, fn] {
        if (auto *mpvItem = qobject_cast<MpvItem *>(item.data()))
            fn(mpvItem);
    }, Qt::QueuedConnection);
}

void setOption(mpv_handle *mpv, const char *name, const char *value)
{
    if (mpv_set_option_string(mpv, name, value) < 0)
        qWarning("MpvWallpaper: rejected option %s=%s", name, value);
}

} // namespace

MpvCore::~MpvCore()
{
    if (ctx)
        mpv_render_context_free(ctx);
    if (mpv)
        mpv_terminate_destroy(mpv);
}

class MpvRenderer : public QQuickFramebufferObject::Renderer {
public:
    explicit MpvRenderer(std::shared_ptr<MpvCore> core) : m_core(std::move(core)) {}

    ~MpvRenderer() override
    {
        // Render thread, GL context current: the only safe place to free it.
        // If the item is still alive it rebuilds the context (and reloads the
        // file) the next time a renderer is created.
        if (m_core->ctx) {
            mpv_render_context_free(m_core->ctx);
            m_core->ctx = nullptr;
        }
    }

    QOpenGLFramebufferObject *createFramebufferObject(const QSize &size) override
    {
        if (!m_core->ctx && m_core->mpv)
            createContext();
        return QQuickFramebufferObject::Renderer::createFramebufferObject(size);
    }

    void render() override
    {
        if (!m_core->ctx)
            return;
        QOpenGLFramebufferObject *fbo = framebufferObject();
        QQuickWindow *window = m_window.data();
        if (window)
            window->beginExternalCommands();
        mpv_opengl_fbo target{static_cast<int>(fbo->handle()), fbo->width(), fbo->height(), 0};
        int flipY = 0;
        mpv_render_param params[] = {
            {MPV_RENDER_PARAM_OPENGL_FBO, &target},
            {MPV_RENDER_PARAM_FLIP_Y, &flipY},
            {MPV_RENDER_PARAM_INVALID, nullptr},
        };
        mpv_render_context_render(m_core->ctx, params);
        if (window)
            window->endExternalCommands();
    }

    void synchronize(QQuickFramebufferObject *item) override
    {
        m_window = item->window();
    }

private:
    void createContext()
    {
        mpv_opengl_init_params glInit{glProcAddress, nullptr};
        mpv_render_param params[] = {
            {MPV_RENDER_PARAM_API_TYPE, const_cast<char *>(MPV_RENDER_API_TYPE_OPENGL)},
            {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &glInit},
            {MPV_RENDER_PARAM_INVALID, nullptr},
            {MPV_RENDER_PARAM_INVALID, nullptr},
        };
#if QT_CONFIG(wayland)
        // vaapi interop (Intel/AMD) needs the Wayland display; nvdec does not.
        if (auto *wayland = qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>()) {
            if (wl_display *display = wayland->display())
                params[2] = {MPV_RENDER_PARAM_WL_DISPLAY, display};
        }
#endif
        if (mpv_render_context_create(&m_core->ctx, m_core->mpv, params) < 0) {
            m_core->ctx = nullptr;
            postToItem(m_core.get(), [](MpvItem *item) {
                item->setError(QStringLiteral("could not create the mpv OpenGL render context"));
            });
            return;
        }
        mpv_render_context_set_update_callback(m_core->ctx, [](void *data) {
            auto *core = static_cast<MpvCore *>(data);
            if (core->updateQueued.exchange(true))
                return;
            postToItem(core, [](MpvItem *item) {
                item->core()->updateQueued = false;
                item->update();
            });
        }, m_core.get());
        // A file loaded before the context existed has no video output, so
        // (re)load now that it does.
        postToItem(m_core.get(), [](MpvItem *item) {
            QMetaObject::invokeMethod(item, "loadSource", Qt::DirectConnection);
        });
    }

    std::shared_ptr<MpvCore> m_core;
    QPointer<QQuickWindow> m_window;
};

MpvItem::MpvItem(QQuickItem *parent)
    : QQuickFramebufferObject(parent)
    , m_core(std::make_shared<MpvCore>())
{
    m_core->item = this;

    // libmpv refuses to run unless numbers parse with a C locale.
    std::setlocale(LC_NUMERIC, "C");
    mpv_handle *mpv = mpv_create();
    if (!mpv) {
        setError(QStringLiteral("mpv_create failed"));
        return;
    }
    m_core->mpv = mpv;

    // A wallpaper: no audio, no input, no OSD, no user config or scripts.
    setOption(mpv, "config", "no");
    setOption(mpv, "load-scripts", "no");
    setOption(mpv, "ytdl", "no");
    setOption(mpv, "terminal", "no");
    setOption(mpv, "input-default-bindings", "no");
    setOption(mpv, "input-vo-keyboard", "no");
    setOption(mpv, "osc", "no");
    setOption(mpv, "osd-level", "0");
    setOption(mpv, "audio", "no");
    setOption(mpv, "vo", "libmpv");
    setOption(mpv, "hwdec", "auto-safe");
    setOption(mpv, "loop-file", "inf");
    // Fill the item and crop the overflow, like PreserveAspectCrop.
    setOption(mpv, "keepaspect", "yes");
    setOption(mpv, "panscan", "1.0");
    // Local files only: a tiny demuxer buffer is plenty and saves RAM.
    setOption(mpv, "cache", "no");
    setOption(mpv, "demuxer-max-bytes", "8MiB");
    setOption(mpv, "demuxer-max-back-bytes", "0");
    // Cheapest scaling path; the wallpaper is usually blurred or moving anyway.
    setOption(mpv, "interpolation", "no");
    setOption(mpv, "scale", "bilinear");
    setOption(mpv, "dscale", "bilinear");
    setOption(mpv, "cscale", "bilinear");
    setOption(mpv, "deband", "no");
    setOption(mpv, "dither-depth", "no");
    setOption(mpv, "correct-downscaling", "no");
    setOption(mpv, "linear-downscaling", "no");
    setOption(mpv, "sigmoid-upscaling", "no");
    setOption(mpv, "hdr-compute-peak", "no");
    const QByteArray logFile = qgetenv("MPV_WALLPAPER_LOG_FILE");
    if (!logFile.isEmpty())
        setOption(mpv, "log-file", logFile.constData());

    if (mpv_initialize(mpv) < 0) {
        setError(QStringLiteral("mpv_initialize failed"));
        return;
    }
    mpv_request_log_messages(mpv, "error");
    mpv_observe_property(mpv, 0, "hwdec-current", MPV_FORMAT_STRING);
    mpv_set_wakeup_callback(mpv, [](void *data) {
        postToItem(static_cast<MpvCore *>(data), [](MpvItem *item) { item->drainEvents(); });
    }, m_core.get());
}

MpvItem::~MpvItem()
{
    if (m_core->mpv)
        mpv_set_wakeup_callback(m_core->mpv, nullptr, nullptr);
    // The renderer may still hold the core; it then finishes the teardown.
}

QQuickFramebufferObject::Renderer *MpvItem::createRenderer() const
{
    return new MpvRenderer(m_core);
}

void MpvItem::setSource(const QString &source)
{
    if (source == m_source)
        return;
    m_source = source;
    setHasVideo(false);
    setError(QString());
    if (m_core->ctx)
        loadSource();
    emit sourceChanged();
}

void MpvItem::loadSource()
{
    if (!m_core->mpv)
        return;
    if (m_source.isEmpty()) {
        const char *args[] = {"stop", nullptr};
        mpv_command_async(m_core->mpv, 0, args);
        return;
    }
    const QByteArray file = m_source.startsWith(QStringLiteral("file://"))
        ? QUrl(m_source).toLocalFile().toUtf8()
        : m_source.toUtf8();
    const char *args[] = {"loadfile", file.constData(), nullptr};
    mpv_command_async(m_core->mpv, 0, args);
}

void MpvItem::setPaused(bool paused)
{
    if (paused == m_paused)
        return;
    m_paused = paused;
    if (m_core->mpv) {
        int flag = paused ? 1 : 0;
        mpv_set_property_async(m_core->mpv, 0, "pause", MPV_FORMAT_FLAG, &flag);
    }
    emit pausedChanged();
}

void MpvItem::setMpvProperty(const QString &name, const QString &value)
{
    if (m_core->mpv)
        mpv_set_property_string(m_core->mpv, name.toUtf8().constData(), value.toUtf8().constData());
}

void MpvItem::drainEvents()
{
    if (!m_core->mpv)
        return;
    while (true) {
        mpv_event *event = mpv_wait_event(m_core->mpv, 0);
        if (event->event_id == MPV_EVENT_NONE)
            break;
        switch (event->event_id) {
        case MPV_EVENT_PLAYBACK_RESTART:
            setHasVideo(true);
            break;
        case MPV_EVENT_END_FILE: {
            auto *end = static_cast<mpv_event_end_file *>(event->data);
            if (end->reason == MPV_END_FILE_REASON_ERROR) {
                setHasVideo(false);
                setError(QString::fromUtf8(mpv_error_string(end->error)));
            }
            break;
        }
        case MPV_EVENT_PROPERTY_CHANGE: {
            auto *property = static_cast<mpv_event_property *>(event->data);
            if (qstrcmp(property->name, "hwdec-current") == 0) {
                const QString value = property->format == MPV_FORMAT_STRING
                    ? QString::fromUtf8(*static_cast<char **>(property->data))
                    : QString();
                if (value != m_hwdec) {
                    m_hwdec = value;
                    emit hwdecChanged();
                }
            }
            break;
        }
        case MPV_EVENT_LOG_MESSAGE: {
            auto *message = static_cast<mpv_event_log_message *>(event->data);
            qWarning("MpvWallpaper: [%s] %s", message->prefix, QByteArray(message->text).trimmed().constData());
            break;
        }
        default:
            break;
        }
    }
}

void MpvItem::setHasVideo(bool value)
{
    if (value == m_hasVideo)
        return;
    m_hasVideo = value;
    emit hasVideoChanged();
}

void MpvItem::setError(const QString &error)
{
    if (error == m_error)
        return;
    m_error = error;
    if (!error.isEmpty())
        qWarning("MpvWallpaper: %s", qUtf8Printable(error));
    emit errorStringChanged();
}
