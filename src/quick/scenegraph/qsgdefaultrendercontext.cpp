/****************************************************************************
**
** Copyright (C) 2016 The Qt Company Ltd.
** Contact: https://www.qt.io/licensing/
**
** This file is part of the QtQuick module of the Qt Toolkit.
**
** $QT_BEGIN_LICENSE:LGPL$
** Commercial License Usage
** Licensees holding valid commercial Qt licenses may use this file in
** accordance with the commercial license agreement provided with the
** Software or, alternatively, in accordance with the terms contained in
** a written agreement between you and The Qt Company. For licensing terms
** and conditions see https://www.qt.io/terms-conditions. For further
** information use the contact form at https://www.qt.io/contact-us.
**
** GNU Lesser General Public License Usage
** Alternatively, this file may be used under the terms of the GNU Lesser
** General Public License version 3 as published by the Free Software
** Foundation and appearing in the file LICENSE.LGPL3 included in the
** packaging of this file. Please review the following information to
** ensure the GNU Lesser General Public License version 3 requirements
** will be met: https://www.gnu.org/licenses/lgpl-3.0.html.
**
** GNU General Public License Usage
** Alternatively, this file may be used under the terms of the GNU
** General Public License version 2.0 or (at your option) the GNU General
** Public license version 3 or any later version approved by the KDE Free
** Qt Foundation. The licenses are as published by the Free Software
** Foundation and appearing in the file LICENSE.GPL2 and LICENSE.GPL3
** included in the packaging of this file. Please review the following
** information to ensure the GNU General Public License requirements will
** be met: https://www.gnu.org/licenses/gpl-2.0.html and
** https://www.gnu.org/licenses/gpl-3.0.html.
**
** $QT_END_LICENSE$
**
****************************************************************************/

#include "qsgdefaultrendercontext_p.h"

#include <QtGui/QGuiApplication>

#include <QtQuick/private/qsgbatchrenderer_p.h>
#include <QtQuick/private/qsgrenderer_p.h>
#include <QtQuick/private/qsgrhiatlastexture_p.h>
#include <QtQuick/private/qsgrhidistancefieldglyphcache_p.h>
#include <QtQuick/private/qsgmaterialshader_p.h>

#include <QtQuick/private/qsgcompressedtexture_p.h>

#include <QtQuick/qsgrendererinterface.h>
#include <QtQuick/qquickgraphicsconfiguration.h>

QT_BEGIN_NAMESPACE

QSGDefaultRenderContext::QSGDefaultRenderContext(QSGContext *context)
    : QSGRenderContext(context)
    , m_rhi(nullptr)
    , m_maxTextureSize(0)
    , m_rhiAtlasManager(nullptr)
    , m_currentFrameCommandBuffer(nullptr)
    , m_currentFrameRenderPass(nullptr)
    , m_useDepthBufferFor2D(true)
    , m_glyphCacheResourceUpdates(nullptr)
{
}

/*!
    Initializes the scene graph render context with the GL context \a context. This also
    emits the ready() signal so that the QML graph can start building scene graph nodes.
 */
void QSGDefaultRenderContext::initialize(const QSGRenderContext::InitParams *params)
{
    if (!m_sg)
        return;

    const InitParams *initParams = static_cast<const InitParams *>(params);
    if (initParams->sType != INIT_PARAMS_MAGIC)
        qFatal("QSGDefaultRenderContext: Invalid parameters passed to initialize()");

    m_initParams = *initParams;

    m_rhi = m_initParams.rhi;
    m_maxTextureSize = m_rhi->resourceLimit(QRhi::TextureSizeMax);
    if (!m_rhiAtlasManager)
        m_rhiAtlasManager = new QSGRhiAtlasTexture::Manager(this, m_initParams.initialSurfacePixelSize, m_initParams.maybeSurface);

    m_glyphCacheResourceUpdates = nullptr;

    m_sg->renderContextInitialized(this);

    emit initialized();
}

void QSGDefaultRenderContext::invalidateGlyphCaches()
{
    auto it = m_glyphCaches.begin();
    while (it != m_glyphCaches.end()) {
        if (!(*it)->isActive()) {
            delete *it;
            it = m_glyphCaches.erase(it);
        } else {
            ++it;
        }
    }
}

void QSGDefaultRenderContext::invalidate()
{
    if (!m_rhi)
        return;

    qDeleteAll(m_texturesToDelete);
    m_texturesToDelete.clear();

    qDeleteAll(m_textures);
    m_textures.clear();

    /* The cleanup of the atlas textures is a bit intriguing.
       As part of the cleanup in the threaded render loop, we
       do:
       1. call this function
       2. call QCoreApp::sendPostedEvents() to immediately process
          any pending deferred deletes.
       3. delete the GL context.

       As textures need the atlas manager while cleaning up, the
       manager needs to be cleaned up after the textures, so
       we post a deleteLater here at the very bottom so it gets
       deferred deleted last.

       Another alternative would be to use a QPointer in
       QSGOpenGLAtlasTexture::Texture, but this seemed simpler.
     */
    if (m_rhiAtlasManager) {
        m_rhiAtlasManager->invalidate();
        m_rhiAtlasManager->deleteLater();
        m_rhiAtlasManager = nullptr;
    }

    // The following piece of code will read/write to the font engine's caches,
    // potentially from different threads. However, this is safe because this
    // code is only called from QQuickWindow's shutdown which is called
    // only when the GUI is blocked, and multiple threads will call it in
    // sequence. (see qsgdefaultglyphnode_p.cpp's init())
    for (QSet<QFontEngine *>::const_iterator it = m_fontEnginesToClean.constBegin(),
         end = m_fontEnginesToClean.constEnd(); it != end; ++it) {
        (*it)->clearGlyphCache(m_rhi);
        if (!(*it)->ref.deref())
            delete *it;
    }
    m_fontEnginesToClean.clear();

    qDeleteAll(m_glyphCaches);
    m_glyphCaches.clear();

    releaseGlyphCacheResourceUpdates();

    m_rhi = nullptr;

    if (m_sg)
        m_sg->renderContextInvalidated(this);

    emit invalidated();
}

void QSGDefaultRenderContext::prepareSync(qreal devicePixelRatio,
                                          QRhiCommandBuffer *cb,
                                          const QQuickGraphicsConfiguration &config)
{
    m_currentDevicePixelRatio = devicePixelRatio;
    m_useDepthBufferFor2D = config.isDepthBufferEnabledFor2D();

    // we store the command buffer already here, in case there is something in
    // an updatePaintNode() implementation that leads to needing it (for
    // example, an updateTexture() call on a QSGRhiLayer)
    m_currentFrameCommandBuffer = cb;
}

void QSGDefaultRenderContext::beginNextFrame(QSGRenderer *renderer, const QSGRenderTarget &renderTarget,
                                             RenderPassCallback mainPassRecordingStart,
                                             RenderPassCallback mainPassRecordingEnd,
                                             void *callbackUserData)
{
    renderer->setRenderTarget(renderTarget);
    renderer->setRenderPassRecordingCallbacks(mainPassRecordingStart, mainPassRecordingEnd, callbackUserData);

    m_currentFrameCommandBuffer = renderTarget.cb; // usually the same as what was passed to prepareSync() but cannot count on that having been called
    m_currentFrameRenderPass = renderTarget.rpDesc;
}

void QSGDefaultRenderContext::renderNextFrame(QSGRenderer *renderer)
{
    renderer->renderScene();
}

void QSGDefaultRenderContext::endNextFrame(QSGRenderer *renderer)
{
    Q_UNUSED(renderer);
    m_currentFrameCommandBuffer = nullptr;
    m_currentFrameRenderPass = nullptr;
}

QSGTexture *QSGDefaultRenderContext::createTexture(const QImage &image, uint flags) const
{
    bool atlas = flags & CreateTexture_Atlas;
    bool mipmap = flags & CreateTexture_Mipmap;
    bool alpha = flags & CreateTexture_Alpha;

    // The atlas implementation is only supported from the render thread and
    // does not support mipmaps.
    if (m_rhi) {
        if (!mipmap && atlas && QThread::currentThread() == m_rhi->thread()) {
            QSGTexture *t = m_rhiAtlasManager->create(image, alpha);
            if (t)
                return t;
        }
    }

    QSGPlainTexture *texture = new QSGPlainTexture;
    texture->setImage(image);
    if (texture->hasAlphaChannel() && !alpha)
        texture->setHasAlphaChannel(false);

    return texture;
}

QSGRenderer *QSGDefaultRenderContext::createRenderer(QSGRendererInterface::RenderMode renderMode)
{
    return new QSGBatchRenderer::Renderer(this, renderMode);
}

QSGTexture *QSGDefaultRenderContext::compressedTextureForFactory(const QSGCompressedTextureFactory *factory) const
{
    // This is only used for atlasing compressed textures. Returning null implies no atlas.

    if (m_rhi && QThread::currentThread() == m_rhi->thread())
        return m_rhiAtlasManager->create(factory);

    return nullptr;
}

QString QSGDefaultRenderContext::fontKey(const QRawFont &font, int renderTypeQuality)
{
    QFontEngine *fe = QRawFontPrivate::get(font)->fontEngine;
    if (!fe->faceId().filename.isEmpty()) {
        QByteArray keyName =
                fe->faceId().filename + ' ' + QByteArray::number(fe->faceId().index)
                + (font.style() != QFont::StyleNormal ? QByteArray(" I") : QByteArray())
                + (font.weight() != QFont::Normal ? ' ' + QByteArray::number(font.weight()) : QByteArray())
                + ' ' + QByteArray::number(renderTypeQuality)
                + QByteArray(" DF");
        return QString::fromUtf8(keyName);
    } else {
        return QString::fromLatin1("%1_%2_%3_%4_%5")
            .arg(font.familyName())
            .arg(font.styleName())
            .arg(font.weight())
            .arg(font.style())
            .arg(renderTypeQuality);
    }
}

void QSGDefaultRenderContext::initializeRhiShader(QSGMaterialShader *shader, QShader::Variant shaderVariant)
{
    QSGMaterialShaderPrivate::get(shader)->prepare(shaderVariant);
}

void QSGDefaultRenderContext::preprocess()
{
    for (auto it = m_glyphCaches.begin(); it != m_glyphCaches.end(); ++it) {
        it.value()->processPendingGlyphs();
        it.value()->update();
    }
}

QSGDistanceFieldGlyphCache *QSGDefaultRenderContext::distanceFieldGlyphCache(const QRawFont &font, int renderTypeQuality)
{
    QString key = fontKey(font, renderTypeQuality);
    QSGDistanceFieldGlyphCache *cache = m_glyphCaches.value(key, 0);
    if (!cache) {
        cache = new QSGRhiDistanceFieldGlyphCache(this, font, renderTypeQuality);
        m_glyphCaches.insert(key, cache);
    }

    return cache;
}

QRhiResourceUpdateBatch *QSGDefaultRenderContext::maybeGlyphCacheResourceUpdates()
{
    return m_glyphCacheResourceUpdates;
}

QRhiResourceUpdateBatch *QSGDefaultRenderContext::glyphCacheResourceUpdates()
{
    if (!m_glyphCacheResourceUpdates)
        m_glyphCacheResourceUpdates = m_rhi->nextResourceUpdateBatch();

    return m_glyphCacheResourceUpdates;
}

void QSGDefaultRenderContext::releaseGlyphCacheResourceUpdates()
{
    if (m_glyphCacheResourceUpdates) {
        m_glyphCacheResourceUpdates->release();
        m_glyphCacheResourceUpdates = nullptr;
    }
}

QT_END_NAMESPACE

#include "moc_qsgdefaultrendercontext_p.cpp"
