#pragma once

#include <QPointer>
#include <QQuickFramebufferObject>
#include <QtQml/qqmlregistration.h>

#include <atomic>
#include <memory>

struct mpv_handle;
struct mpv_render_context;

// State shared between the item (GUI thread) and its renderer (render thread).
// Whichever of the two goes last tears mpv down, so the render context is
// always freed on the render thread, before the core it belongs to.
struct MpvCore {
    ~MpvCore();
    mpv_handle *mpv = nullptr;
    mpv_render_context *ctx = nullptr;
    QPointer<QQuickItem> item;
    // At most one frame notification queued on the GUI thread: each posted
    // event runs through every application event filter (the KDE platform
    // theme installs several), so they are worth coalescing.
    std::atomic_bool updateQueued{false};
};

// A looping, muted video rendered by libmpv straight into the scene graph.
// Decoded frames stay on the GPU (nvdec/vaapi interop), and the item is an
// ordinary QQuickItem: layers, MultiEffect and transforms apply to it.
class MpvItem : public QQuickFramebufferObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(bool paused READ paused WRITE setPaused NOTIFY pausedChanged)
    // True once the current file has produced a frame.
    Q_PROPERTY(bool hasVideo READ hasVideo NOTIFY hasVideoChanged)
    Q_PROPERTY(QString hwdec READ hwdec NOTIFY hwdecChanged)
    Q_PROPERTY(QString errorString READ errorString NOTIFY errorStringChanged)

public:
    explicit MpvItem(QQuickItem *parent = nullptr);
    ~MpvItem() override;

    Renderer *createRenderer() const override;

    QString source() const { return m_source; }
    void setSource(const QString &source);
    bool paused() const { return m_paused; }
    void setPaused(bool paused);
    bool hasVideo() const { return m_hasVideo; }
    QString hwdec() const { return m_hwdec; }
    QString errorString() const { return m_error; }

    // Runtime mpv property, e.g. setProperty("video-zoom", "0.1").
    Q_INVOKABLE void setMpvProperty(const QString &name, const QString &value);

    std::shared_ptr<MpvCore> core() const { return m_core; }

signals:
    void sourceChanged();
    void pausedChanged();
    void hasVideoChanged();
    void hwdecChanged();
    void errorStringChanged();

private slots:
    void loadSource();
    void drainEvents();

private:
    friend class MpvRenderer;
    void setHasVideo(bool value);
    void setError(const QString &error);

    std::shared_ptr<MpvCore> m_core;
    QString m_source;
    bool m_paused = false;
    bool m_hasVideo = false;
    QString m_hwdec;
    QString m_error;
};
