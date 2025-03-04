/****************************************************************************
**
** Copyright (C) 2019 The Qt Company Ltd.
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

#include "qsgrhisupport_p.h"
#include "qsgcontext_p.h"
#include "qsgdefaultrendercontext_p.h"

#include <QtQuick/private/qquickitem_p.h>
#include <QtQuick/private/qquickwindow_p.h>

#include <QtGui/qwindow.h>

#if QT_CONFIG(vulkan)
#include <QtGui/private/qvulkandefaultinstance_p.h>
#endif

#include <QOperatingSystemVersion>
#include <QOffscreenSurface>

#include <memory>

QT_BEGIN_NAMESPACE

QSGRhiSupport::QSGRhiSupport()
    : m_settingsApplied(false),
      m_debugLayer(false),
      m_profile(false),
      m_shaderEffectDebug(false),
      m_preferSoftwareRenderer(false)
{
}

void QSGRhiSupport::applySettings()
{
    // Multiple calls to this function are perfectly possible!
    // Just store that it was called at least once.
    m_settingsApplied = true;

    // This is also done when creating the renderloop but we may be before that
    // in case we get here due to a setGraphicsApi() -> configure() early
    // on in main(). Avoid losing info logs since troubleshooting gets
    // confusing otherwise.
    QSGRhiSupport::checkEnvQSgInfo();

    if (m_requested.valid) {
        // explicit rhi backend request from C++ (e.g. via QQuickWindow)
        switch (m_requested.api) {
        case QSGRendererInterface::OpenGLRhi:
            m_rhiBackend = QRhi::OpenGLES2;
            break;
        case QSGRendererInterface::Direct3D11Rhi:
            m_rhiBackend = QRhi::D3D11;
            break;
        case QSGRendererInterface::VulkanRhi:
            m_rhiBackend = QRhi::Vulkan;
            break;
        case QSGRendererInterface::MetalRhi:
            m_rhiBackend = QRhi::Metal;
            break;
        case QSGRendererInterface::NullRhi:
            m_rhiBackend = QRhi::Null;
            break;
        default:
            Q_ASSERT_X(false, "QSGRhiSupport", "Internal error: unhandled GraphicsApi type");
            break;
        }
    } else {
        // check env.vars., fall back to platform-specific defaults when backend is not set
        const QByteArray rhiBackend = qgetenv("QSG_RHI_BACKEND");
        if (rhiBackend == QByteArrayLiteral("gl")
                || rhiBackend == QByteArrayLiteral("gles2")
                || rhiBackend == QByteArrayLiteral("opengl"))
        {
            m_rhiBackend = QRhi::OpenGLES2;
        } else if (rhiBackend == QByteArrayLiteral("d3d11") || rhiBackend == QByteArrayLiteral("d3d")) {
            m_rhiBackend = QRhi::D3D11;
        } else if (rhiBackend == QByteArrayLiteral("vulkan")) {
            m_rhiBackend = QRhi::Vulkan;
        } else if (rhiBackend == QByteArrayLiteral("metal")) {
            m_rhiBackend = QRhi::Metal;
        } else if (rhiBackend == QByteArrayLiteral("null")) {
            m_rhiBackend = QRhi::Null;
        } else {
            if (!rhiBackend.isEmpty()) {
                qWarning("Unknown key \"%s\" for QSG_RHI_BACKEND, falling back to default backend.",
                         rhiBackend.constData());
            }
#if defined(Q_OS_WIN)
            m_rhiBackend = QRhi::D3D11;
#elif defined(Q_OS_MACOS) || defined(Q_OS_IOS)
            m_rhiBackend = QRhi::Metal;
#elif QT_CONFIG(opengl)
            m_rhiBackend = QRhi::OpenGLES2;
#else
            m_rhiBackend = QRhi::Vulkan;
#endif

            // Now that we established our initial choice, we may want to opt
            // for another backend under certain special circumstances.
            adjustToPlatformQuirks();
        }
    }

    // At this point the RHI backend is fixed, it cannot be changed once we
    // return from this function. This is because things like the QWindow
    // (QQuickWindow) may depend on the graphics API as well (surfaceType
    // f.ex.), and all that is based on what we report from here. So further
    // adjustments are not possible (or, at minimum, not safe and portable).

    // validation layers (Vulkan) or debug layer (D3D)
    m_debugLayer = uint(qEnvironmentVariableIntValue("QSG_RHI_DEBUG_LAYER"));

    // EnableProfiling + DebugMarkers
    m_profile = uint(qEnvironmentVariableIntValue("QSG_RHI_PROFILE"));

    // EnablePipelineCacheDataSave
    m_pipelineCacheSave = qEnvironmentVariable("QSG_RHI_PIPELINE_CACHE_SAVE");

    m_pipelineCacheLoad = qEnvironmentVariable("QSG_RHI_PIPELINE_CACHE_LOAD");

    m_shaderEffectDebug = uint(qEnvironmentVariableIntValue("QSG_RHI_SHADEREFFECT_DEBUG"));

    m_preferSoftwareRenderer = uint(qEnvironmentVariableIntValue("QSG_RHI_PREFER_SOFTWARE_RENDERER"));

    m_killDeviceFrameCount = qEnvironmentVariableIntValue("QSG_RHI_SIMULATE_DEVICE_LOSS");
    if (m_killDeviceFrameCount > 0 && m_rhiBackend == QRhi::D3D11)
        qDebug("Graphics device will be reset every %d frames", m_killDeviceFrameCount);

    QByteArray hdrRequest = qgetenv("QSG_RHI_HDR");
    if (!hdrRequest.isEmpty()) {
        hdrRequest = hdrRequest.toLower();
        if (hdrRequest == QByteArrayLiteral("scrgb") || hdrRequest == QByteArrayLiteral("extendedsrgblinear"))
            m_swapChainFormat = QRhiSwapChain::HDRExtendedSrgbLinear;
        else if (hdrRequest == QByteArrayLiteral("hdr10"))
            m_swapChainFormat = QRhiSwapChain::HDR10;
        else
            qWarning("Unknown HDR mode '%s'", hdrRequest.constData());
    }

    const QString backendName = rhiBackendName();
    qCDebug(QSG_LOG_INFO,
            "Using QRhi with backend %s\n"
            "  Graphics API debug/validation layers: %d\n"
            "  QRhi profiling and debug markers: %d\n"
            "  Shader/pipeline cache collection: %d",
            qPrintable(backendName), m_debugLayer, m_profile, !m_pipelineCacheSave.isEmpty());
    if (m_preferSoftwareRenderer)
        qCDebug(QSG_LOG_INFO, "Prioritizing software renderers");
}

void QSGRhiSupport::adjustToPlatformQuirks()
{
#if defined(Q_OS_MACOS) || defined(Q_OS_IOS)
    // A macOS VM may not have Metal support at all. We have to decide at this
    // point, it will be too late afterwards, and the only way is to see if
    // MTLCreateSystemDefaultDevice succeeds.
    if (m_rhiBackend == QRhi::Metal) {
        QRhiMetalInitParams rhiParams;
        if (!QRhi::probe(m_rhiBackend, &rhiParams)) {
            m_rhiBackend = QRhi::OpenGLES2;
            qCDebug(QSG_LOG_INFO, "Metal does not seem to be supported. Falling back to OpenGL.");
        }
    }
#endif
}

void QSGRhiSupport::checkEnvQSgInfo()
{
    // For compatibility with 5.3 and earlier's QSG_INFO environment variables
    if (qEnvironmentVariableIsSet("QSG_INFO"))
        const_cast<QLoggingCategory &>(QSG_LOG_INFO()).setEnabled(QtDebugMsg, true);
}

void QSGRhiSupport::configure(QSGRendererInterface::GraphicsApi api)
{
    if (api == QSGRendererInterface::Unknown) {
        // behave as if nothing was explicitly requested
        m_requested.valid = false;
        applySettings();
    } else {
        Q_ASSERT(QSGRendererInterface::isApiRhiBased(api));
        m_requested.valid = true;
        m_requested.api = api;
        applySettings();
    }
}

QSGRhiSupport *QSGRhiSupport::instance_internal()
{
    static QSGRhiSupport inst;
    return &inst;
}

QSGRhiSupport *QSGRhiSupport::instance()
{
    QSGRhiSupport *inst = instance_internal();
    if (!inst->m_settingsApplied)
        inst->applySettings();
    return inst;
}

QString QSGRhiSupport::rhiBackendName() const
{
    switch (m_rhiBackend) {
    case QRhi::Null:
        return QLatin1String("Null");
    case QRhi::Vulkan:
        return QLatin1String("Vulkan");
    case QRhi::OpenGLES2:
        return QLatin1String("OpenGL");
    case QRhi::D3D11:
        return QLatin1String("D3D11");
    case QRhi::Metal:
        return QLatin1String("Metal");
    default:
        return QLatin1String("Unknown");
    }
}

QSGRendererInterface::GraphicsApi QSGRhiSupport::graphicsApi() const
{
    switch (m_rhiBackend) {
    case QRhi::Null:
        return QSGRendererInterface::NullRhi;
    case QRhi::Vulkan:
        return QSGRendererInterface::VulkanRhi;
    case QRhi::OpenGLES2:
        return QSGRendererInterface::OpenGLRhi;
    case QRhi::D3D11:
        return QSGRendererInterface::Direct3D11Rhi;
    case QRhi::Metal:
        return QSGRendererInterface::MetalRhi;
    default:
        return QSGRendererInterface::Unknown;
    }
}

QSurface::SurfaceType QSGRhiSupport::windowSurfaceType() const
{
    switch (m_rhiBackend) {
    case QRhi::Vulkan:
        return QSurface::VulkanSurface;
    case QRhi::OpenGLES2:
        return QSurface::OpenGLSurface;
    case QRhi::D3D11:
        return QSurface::Direct3DSurface;
    case QRhi::Metal:
        return QSurface::MetalSurface;
    default:
        return QSurface::OpenGLSurface;
    }
}

#if QT_CONFIG(vulkan)
static const void *qsgrhi_vk_rifResource(QSGRendererInterface::Resource res,
                                         const QRhiNativeHandles *nat,
                                         const QRhiNativeHandles *cbNat,
                                         const QRhiNativeHandles *rpNat)
{
    const QRhiVulkanNativeHandles *vknat = static_cast<const QRhiVulkanNativeHandles *>(nat);
    const QRhiVulkanCommandBufferNativeHandles *maybeVkCbNat =
            static_cast<const QRhiVulkanCommandBufferNativeHandles *>(cbNat);
    const QRhiVulkanRenderPassNativeHandles *maybeVkRpNat =
            static_cast<const QRhiVulkanRenderPassNativeHandles *>(rpNat);

    switch (res) {
    case QSGRendererInterface::DeviceResource:
        return &vknat->dev;
    case QSGRendererInterface::CommandQueueResource:
        return &vknat->gfxQueue;
    case QSGRendererInterface::CommandListResource:
        if (maybeVkCbNat)
            return &maybeVkCbNat->commandBuffer;
        else
            return nullptr;
    case QSGRendererInterface::PhysicalDeviceResource:
        return &vknat->physDev;
    case QSGRendererInterface::RenderPassResource:
        if (maybeVkRpNat)
            return &maybeVkRpNat->renderPass;
        else
            return nullptr;
    default:
        return nullptr;
    }
}
#endif

#if QT_CONFIG(opengl)
static const void *qsgrhi_gl_rifResource(QSGRendererInterface::Resource res, const QRhiNativeHandles *nat)
{
    const QRhiGles2NativeHandles *glnat = static_cast<const QRhiGles2NativeHandles *>(nat);
    switch (res) {
    case QSGRendererInterface::OpenGLContextResource:
        return glnat->context;
    default:
        return nullptr;
    }
}
#endif

#ifdef Q_OS_WIN
static const void *qsgrhi_d3d11_rifResource(QSGRendererInterface::Resource res, const QRhiNativeHandles *nat)
{
    const QRhiD3D11NativeHandles *d3dnat = static_cast<const QRhiD3D11NativeHandles *>(nat);
    switch (res) {
    case QSGRendererInterface::DeviceResource:
        return d3dnat->dev;
    case QSGRendererInterface::DeviceContextResource:
        return d3dnat->context;
    default:
        return nullptr;
    }
}
#endif

#if defined(Q_OS_MACOS) || defined(Q_OS_IOS)
static const void *qsgrhi_mtl_rifResource(QSGRendererInterface::Resource res, const QRhiNativeHandles *nat,
                                    const QRhiNativeHandles *cbNat)
{
    const QRhiMetalNativeHandles *mtlnat = static_cast<const QRhiMetalNativeHandles *>(nat);
    const QRhiMetalCommandBufferNativeHandles *maybeMtlCbNat =
            static_cast<const QRhiMetalCommandBufferNativeHandles *>(cbNat);

    switch (res) {
    case QSGRendererInterface::DeviceResource:
        return mtlnat->dev;
    case QSGRendererInterface::CommandQueueResource:
        return mtlnat->cmdQueue;
    case QSGRendererInterface::CommandListResource:
        if (maybeMtlCbNat)
            return maybeMtlCbNat->commandBuffer;
        else
            return nullptr;
    case QSGRendererInterface::CommandEncoderResource:
        if (maybeMtlCbNat)
            return maybeMtlCbNat->encoder;
        else
            return nullptr;
    default:
        return nullptr;
    }
}
#endif

const void *QSGRhiSupport::rifResource(QSGRendererInterface::Resource res,
                                       const QSGDefaultRenderContext *rc,
                                       const QQuickWindow *w)
{
    QRhi *rhi = rc->rhi();
    if (!rhi)
        return nullptr;

    // Accessing the underlying QRhi* objects are essential both for Qt Quick
    // 3D and advanced solutions, such as VR engine integrations.
    switch (res) {
    case QSGRendererInterface::RhiResource:
        return rhi;
    case QSGRendererInterface::RhiSwapchainResource:
        return QQuickWindowPrivate::get(w)->swapchain;
    case QSGRendererInterface::RhiRedirectCommandBuffer:
        return QQuickWindowPrivate::get(w)->redirect.commandBuffer;
    case QSGRendererInterface::RhiRedirectRenderTarget:
        return QQuickWindowPrivate::get(w)->redirect.rt.renderTarget;
    default:
        break;
    }

    const QRhiNativeHandles *nat = rhi->nativeHandles();
    if (!nat)
        return nullptr;

    switch (m_rhiBackend) {
#if QT_CONFIG(vulkan)
    case QRhi::Vulkan:
    {
        QRhiCommandBuffer *cb = rc->currentFrameCommandBuffer();
        QRhiRenderPassDescriptor *rp = rc->currentFrameRenderPass();
        return qsgrhi_vk_rifResource(res, nat,
                                     cb ? cb->nativeHandles() : nullptr,
                                     rp ? rp->nativeHandles() : nullptr);
    }
#endif
#if QT_CONFIG(opengl)
    case QRhi::OpenGLES2:
        return qsgrhi_gl_rifResource(res, nat);
#endif
#ifdef Q_OS_WIN
    case QRhi::D3D11:
        return qsgrhi_d3d11_rifResource(res, nat);
#endif
#if defined(Q_OS_MACOS) || defined(Q_OS_IOS)
    case QRhi::Metal:
    {
        QRhiCommandBuffer *cb = rc->currentFrameCommandBuffer();
        return qsgrhi_mtl_rifResource(res, nat, cb ? cb->nativeHandles() : nullptr);
    }
#endif
    default:
        return nullptr;
    }
}

int QSGRhiSupport::chooseSampleCount(int samples, QRhi *rhi)
{
    int msaaSampleCount = samples;
    if (qEnvironmentVariableIsSet("QSG_SAMPLES"))
        msaaSampleCount = qEnvironmentVariableIntValue("QSG_SAMPLES");
    msaaSampleCount = qMax(1, msaaSampleCount);
    if (msaaSampleCount > 1) {
        const QVector<int> supportedSampleCounts = rhi->supportedSampleCounts();
        if (!supportedSampleCounts.contains(msaaSampleCount)) {
            int reducedSampleCount = 1;
            for (int i = supportedSampleCounts.count() - 1; i >= 0; --i) {
                if (supportedSampleCounts[i] <= msaaSampleCount) {
                    reducedSampleCount = supportedSampleCounts[i];
                    break;
                }
            }
            qWarning() << "Requested MSAA sample count" << msaaSampleCount
                       << "but supported sample counts are" << supportedSampleCounts
                       << ", using sample count" << reducedSampleCount << "instead";
            msaaSampleCount = reducedSampleCount;
        }
    }
    return msaaSampleCount;
}

int QSGRhiSupport::chooseSampleCountForWindowWithRhi(QWindow *window, QRhi *rhi)
{
    return chooseSampleCount(qMax(QSurfaceFormat::defaultFormat().samples(), window->requestedFormat().samples()), rhi);
}

// must be called on the main thread
QOffscreenSurface *QSGRhiSupport::maybeCreateOffscreenSurface(QWindow *window)
{
    QOffscreenSurface *offscreenSurface = nullptr;
#if QT_CONFIG(opengl)
    if (rhiBackend() == QRhi::OpenGLES2) {
        const QSurfaceFormat format = window->requestedFormat();
        offscreenSurface = QRhiGles2InitParams::newFallbackSurface(format);
    }
#else
    Q_UNUSED(window);
#endif
    return offscreenSurface;
}

void QSGRhiSupport::prepareWindowForRhi(QQuickWindow *window)
{
#if QT_CONFIG(vulkan)
    if (rhiBackend() == QRhi::Vulkan) {
        QQuickWindowPrivate *wd = QQuickWindowPrivate::get(window);
        // QQuickWindows must get a QVulkanInstance automatically (it is
        // created when the first window is constructed and is destroyed only
        // on exit), unless the application decided to set its own. With
        // QQuickRenderControl, no QVulkanInstance is created, because it must
        // always be under the application's control then (since the default
        // instance we could create here would not be configurable by the
        // application in any way, and that is often not acceptable).
        if (!window->vulkanInstance() && !wd->renderControl) {
            QVulkanInstance *vkinst = QVulkanDefaultInstance::instance();
            if (vkinst)
                qCDebug(QSG_LOG_INFO) << "Got Vulkan instance from QVulkanDefaultInstance, requested api version was" << vkinst->apiVersion();
            else
                qCDebug(QSG_LOG_INFO) << "No Vulkan instance from QVulkanDefaultInstance, expect problems";
            window->setVulkanInstance(vkinst);
        }
    }
#else
    Q_UNUSED(window);
#endif
}

void QSGRhiSupport::preparePipelineCache(QRhi *rhi)
{
    if (m_pipelineCacheLoad.isEmpty())
        return;

    QFile f(m_pipelineCacheLoad);
    if (f.open(QIODevice::ReadOnly)) {
        qCDebug(QSG_LOG_INFO, "Attempting to seed pipeline cache from '%s'",
                qPrintable(m_pipelineCacheLoad));
        rhi->setPipelineCacheData(f.readAll());
    } else {
        qWarning("Could not open pipeline cache source file '%s'",
                 qPrintable(m_pipelineCacheLoad));
    }
}

// must be called on the render thread
QSGRhiSupport::RhiCreateResult QSGRhiSupport::createRhi(QQuickWindow *window, QSurface *offscreenSurface)
{
    QRhi *rhi = nullptr;
    QQuickWindowPrivate *wd = QQuickWindowPrivate::get(window);
    const QQuickGraphicsDevicePrivate *customDevD = QQuickGraphicsDevicePrivate::get(&wd->customDeviceObjects);
    if (customDevD->type == QQuickGraphicsDevicePrivate::Type::Rhi) {
        rhi = customDevD->u.rhi;
        if (rhi) {
            preparePipelineCache(rhi);
            return { rhi, false };
        }
    }

    QRhi::Flags flags;
    if (isProfilingRequested())
        flags |= QRhi::EnableProfiling | QRhi::EnableDebugMarkers;
    if (isSoftwareRendererRequested())
        flags |= QRhi::PreferSoftwareRenderer;
    if (!m_pipelineCacheSave.isEmpty())
        flags |= QRhi::EnablePipelineCacheDataSave;

    const QRhi::Implementation backend = rhiBackend();
    if (backend == QRhi::Null) {
        QRhiNullInitParams rhiParams;
        rhi = QRhi::create(backend, &rhiParams, flags);
    }
#if QT_CONFIG(opengl)
    if (backend == QRhi::OpenGLES2) {
        const QSurfaceFormat format = window->requestedFormat();
        QRhiGles2InitParams rhiParams;
        rhiParams.format = format;
        rhiParams.fallbackSurface = offscreenSurface;
        rhiParams.window = window;
        if (customDevD->type == QQuickGraphicsDevicePrivate::Type::OpenGLContext) {
            QRhiGles2NativeHandles importDev;
            importDev.context = customDevD->u.context;
            qCDebug(QSG_LOG_INFO, "Using existing QOpenGLContext %p", importDev.context);
            rhi = QRhi::create(backend, &rhiParams, flags, &importDev);
        } else {
            rhi = QRhi::create(backend, &rhiParams, flags);
        }
    }
#else
    Q_UNUSED(offscreenSurface);
    if (backend == QRhi::OpenGLES2)
        qWarning("OpenGL was requested for Qt Quick, but this build of Qt has no OpenGL support.");
#endif
#if QT_CONFIG(vulkan)
    if (backend == QRhi::Vulkan) {
        if (isDebugLayerRequested())
            QVulkanDefaultInstance::setFlag(QVulkanDefaultInstance::EnableValidation, true);
        QRhiVulkanInitParams rhiParams;
        prepareWindowForRhi(window); // sets a vulkanInstance if not yet present
        rhiParams.inst = window->vulkanInstance();
        if (!rhiParams.inst)
            qWarning("No QVulkanInstance set for QQuickWindow, this is wrong.");
        if (window->handle()) // only used for vkGetPhysicalDeviceSurfaceSupportKHR and that implies having a valid native window
            rhiParams.window = window;
        rhiParams.deviceExtensions = wd->graphicsConfig.deviceExtensions();
        if (customDevD->type == QQuickGraphicsDevicePrivate::Type::DeviceObjects) {
            QRhiVulkanNativeHandles importDev;
            importDev.physDev = reinterpret_cast<VkPhysicalDevice>(customDevD->u.deviceObjects.physicalDevice);
            importDev.dev = reinterpret_cast<VkDevice>(customDevD->u.deviceObjects.device);
            importDev.gfxQueueFamilyIdx = customDevD->u.deviceObjects.queueFamilyIndex;
            importDev.gfxQueueIdx = customDevD->u.deviceObjects.queueIndex;
            qCDebug(QSG_LOG_INFO, "Using existing native Vulkan physical device %p device %p graphics queue family index %d",
                    importDev.physDev, importDev.dev, importDev.gfxQueueFamilyIdx);
            rhi = QRhi::create(backend, &rhiParams, flags, &importDev);
        } else if (customDevD->type == QQuickGraphicsDevicePrivate::Type::PhysicalDevice) {
            QRhiVulkanNativeHandles importDev;
            importDev.physDev = reinterpret_cast<VkPhysicalDevice>(customDevD->u.physicalDevice.physicalDevice);
            qCDebug(QSG_LOG_INFO, "Using existing native Vulkan physical device %p", importDev.physDev);
            rhi = QRhi::create(backend, &rhiParams, flags, &importDev);
        } else {
            rhi = QRhi::create(backend, &rhiParams, flags);
        }
    }
#else
    if (backend == QRhi::Vulkan)
        qWarning("Vulkan was requested for Qt Quick, but this build of Qt has no Vulkan support.");
#endif
#ifdef Q_OS_WIN
    if (backend == QRhi::D3D11) {
        QRhiD3D11InitParams rhiParams;
        rhiParams.enableDebugLayer = isDebugLayerRequested();
        if (m_killDeviceFrameCount > 0) {
            rhiParams.framesUntilKillingDeviceViaTdr = m_killDeviceFrameCount;
            rhiParams.repeatDeviceKill = true;
        }
        if (customDevD->type == QQuickGraphicsDevicePrivate::Type::DeviceAndContext) {
            QRhiD3D11NativeHandles importDev;
            importDev.dev = customDevD->u.deviceAndContext.device;
            importDev.context = customDevD->u.deviceAndContext.context;
            qCDebug(QSG_LOG_INFO, "Using existing native D3D11 device %p and context %p",
                    importDev.dev, importDev.context);
            rhi = QRhi::create(backend, &rhiParams, flags, &importDev);
        } else if (customDevD->type == QQuickGraphicsDevicePrivate::Type::Adapter) {
            QRhiD3D11NativeHandles importDev;
            importDev.adapterLuidLow = customDevD->u.adapter.luidLow;
            importDev.adapterLuidHigh = customDevD->u.adapter.luidHigh;
            importDev.featureLevel = customDevD->u.adapter.featureLevel;
            qCDebug(QSG_LOG_INFO, "Using D3D11 adapter LUID %u, %d and feature level %d",
                    importDev.adapterLuidLow, importDev.adapterLuidHigh, importDev.featureLevel);
            rhi = QRhi::create(backend, &rhiParams, flags, &importDev);
        } else {
            rhi = QRhi::create(backend, &rhiParams, flags);
        }
    }
#endif
#if defined(Q_OS_MACOS) || defined(Q_OS_IOS)
    if (backend == QRhi::Metal) {
        QRhiMetalInitParams rhiParams;
        if (customDevD->type == QQuickGraphicsDevicePrivate::Type::DeviceAndCommandQueue) {
            QRhiMetalNativeHandles importDev;
            importDev.dev = (MTLDevice *) customDevD->u.deviceAndCommandQueue.device;
            importDev.cmdQueue = (MTLCommandQueue *) customDevD->u.deviceAndCommandQueue.cmdQueue;
            qCDebug(QSG_LOG_INFO, "Using existing native Metal device %p and command queue %p",
                    importDev.dev, importDev.cmdQueue);
            rhi = QRhi::create(backend, &rhiParams, flags, &importDev);
        } else {
            rhi = QRhi::create(backend, &rhiParams, flags);
        }
    }
#endif

    if (rhi)
        preparePipelineCache(rhi);
    else
        qWarning("Failed to create RHI (backend %d)", backend);

    return { rhi, true };
}

void QSGRhiSupport::destroyRhi(QRhi *rhi)
{
    if (!rhi)
        return;

    if (!rhi->isDeviceLost()) {
        if (!m_pipelineCacheSave.isEmpty()) {
            QFile f(m_pipelineCacheSave);
            if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
                qCDebug(QSG_LOG_INFO, "Writing pipeline cache contents to '%s'",
                        qPrintable(m_pipelineCacheSave));
                f.write(rhi->pipelineCacheData());
            } else {
                qWarning("Could not open pipeline cache output file '%s'",
                         qPrintable(m_pipelineCacheSave));
            }
        }
    }

    delete rhi;
}

QImage QSGRhiSupport::grabAndBlockInCurrentFrame(QRhi *rhi, QRhiCommandBuffer *cb, QRhiTexture *src)
{
    Q_ASSERT(rhi->isRecordingFrame());

    QRhiReadbackResult result;
    QRhiReadbackDescription readbackDesc(src); // null src == read from swapchain backbuffer
    QRhiResourceUpdateBatch *resourceUpdates = rhi->nextResourceUpdateBatch();
    resourceUpdates->readBackTexture(readbackDesc, &result);

    cb->resourceUpdate(resourceUpdates);
    rhi->finish(); // make sure the readback has finished, stall the pipeline if needed

    // May be RGBA or BGRA. Plus premultiplied alpha.
    QImage::Format imageFormat;
    if (result.format == QRhiTexture::BGRA8) {
#if Q_BYTE_ORDER == Q_LITTLE_ENDIAN
        imageFormat = QImage::Format_ARGB32_Premultiplied;
#else
        imageFormat = QImage::Format_RGBA8888_Premultiplied;
        // ### and should swap too
#endif
    } else {
        imageFormat = QImage::Format_RGBA8888_Premultiplied;
    }

    const uchar *p = reinterpret_cast<const uchar *>(result.data.constData());
    const QImage img(p, result.pixelSize.width(), result.pixelSize.height(), imageFormat);

    if (rhi->isYUpInFramebuffer())
        return img.mirrored();

    return img.copy();
}

QImage QSGRhiSupport::grabOffscreen(QQuickWindow *window)
{
    // Set up and then tear down the entire rendering infrastructure. This
    // function is called on the gui/main thread - but that's alright because
    // there is no onscreen rendering initialized at this point (so no render
    // thread for instance).

    QQuickWindowPrivate *wd = QQuickWindowPrivate::get(window);
    // It is expected that window is not using QQuickRenderControl, i.e. it is
    // a normal QQuickWindow that just happens to be not exposed.
    Q_ASSERT(!wd->renderControl);

    QScopedPointer<QOffscreenSurface> offscreenSurface(maybeCreateOffscreenSurface(window));
    RhiCreateResult rhiResult = createRhi(window, offscreenSurface.data());
    if (!rhiResult.rhi) {
        qWarning("Failed to initialize QRhi for offscreen readback");
        return QImage();
    }
    std::unique_ptr<QRhi> rhiOwner(rhiResult.rhi);
    QRhi *rhi = rhiResult.own ? rhiOwner.get() : rhiOwner.release();

    const QSize pixelSize = window->size() * window->devicePixelRatio();
    QScopedPointer<QRhiTexture> texture(rhi->newTexture(QRhiTexture::RGBA8, pixelSize, 1,
                                                        QRhiTexture::RenderTarget | QRhiTexture::UsedAsTransferSource));
    if (!texture->create()) {
        qWarning("Failed to build texture for offscreen readback");
        return QImage();
    }
    QScopedPointer<QRhiRenderBuffer> depthStencil(rhi->newRenderBuffer(QRhiRenderBuffer::DepthStencil, pixelSize, 1));
    if (!depthStencil->create()) {
        qWarning("Failed to create depth/stencil buffer for offscreen readback");
        return QImage();
    }
    QRhiTextureRenderTargetDescription rtDesc(texture.data());
    rtDesc.setDepthStencilBuffer(depthStencil.data());
    QScopedPointer<QRhiTextureRenderTarget> rt(rhi->newTextureRenderTarget(rtDesc));
    QScopedPointer<QRhiRenderPassDescriptor> rpDesc(rt->newCompatibleRenderPassDescriptor());
    rt->setRenderPassDescriptor(rpDesc.data());
    if (!rt->create()) {
        qWarning("Failed to build render target for offscreen readback");
        return QImage();
    }

    wd->rhi = rhi;

    QSGDefaultRenderContext::InitParams params;
    params.rhi = rhi;
    params.sampleCount = 1;
    params.initialSurfacePixelSize = pixelSize;
    params.maybeSurface = window;
    wd->context->initialize(&params);

    // There was no rendercontrol which means a custom render target
    // should not be set either. Set our own, temporarily.
    window->setRenderTarget(QQuickRenderTarget::fromRhiRenderTarget(rt.data()));

    QRhiCommandBuffer *cb = nullptr;
    if (rhi->beginOffscreenFrame(&cb) != QRhi::FrameOpSuccess) {
        qWarning("Failed to start recording the frame for offscreen readback");
        return QImage();
    }

    wd->setCustomCommandBuffer(cb);
    wd->polishItems();
    wd->syncSceneGraph();
    wd->renderSceneGraph(window->size());
    wd->setCustomCommandBuffer(nullptr);

    QImage image = grabAndBlockInCurrentFrame(rhi, cb, texture.data());
    rhi->endOffscreenFrame();

    image.setDevicePixelRatio(window->devicePixelRatio());
    wd->cleanupNodesOnShutdown();
    wd->context->invalidate();

    window->setRenderTarget(QQuickRenderTarget());
    wd->rhi = nullptr;

    return image;
}

#ifdef Q_OS_WEBOS
QImage QSGRhiSupport::grabOffscreenForProtectedContent(QQuickWindow *window)
{
    // If a context is created for protected content, grabbing GPU
    // resources are restricted. For the case, normal context
    // and surface are needed to allow CPU access.
    // So dummy offscreen window is used here
    // This function is called in rendering thread.

    QScopedPointer<QQuickWindow> offscreenWindow;
    QQuickWindowPrivate *wd = QQuickWindowPrivate::get(window);
    // It is expected that window is not using QQuickRenderControl, i.e. it is
    // a normal QQuickWindow that just happens to be not exposed.
    Q_ASSERT(!wd->renderControl);

    // If context and surface are created for protected content,
    // CPU can't read the frame resources. So normal context and surface are needed.
    if (window->requestedFormat().testOption(QSurfaceFormat::ProtectedContent)) {
        QSurfaceFormat surfaceFormat = window->requestedFormat();
        surfaceFormat.setOption(QSurfaceFormat::ProtectedContent, false);
        offscreenWindow.reset(new QQuickWindow());
        offscreenWindow->setFormat(surfaceFormat);
    }

    QScopedPointer<QOffscreenSurface> offscreenSurface(maybeCreateOffscreenSurface(window));
    RhiCreateResult rhiResult = createRhi(offscreenWindow.data() ? offscreenWindow.data() : window, offscreenSurface.data());
    if (!rhiResult.rhi) {
        qWarning("Failed to initialize QRhi for offscreen readback");
        return QImage();
    }
    QScopedPointer<QRhi> rhiOwner(rhiResult.rhi);
    QRhi *rhi = rhiResult.own ? rhiOwner.data() : rhiOwner.take();

    const QSize pixelSize = window->size() * window->devicePixelRatio();
    QScopedPointer<QRhiTexture> texture(rhi->newTexture(QRhiTexture::RGBA8, pixelSize, 1,
                                                        QRhiTexture::RenderTarget | QRhiTexture::UsedAsTransferSource));
    if (!texture->create()) {
        qWarning("Failed to build texture for offscreen readback");
        return QImage();
    }
    QScopedPointer<QRhiRenderBuffer> depthStencil(rhi->newRenderBuffer(QRhiRenderBuffer::DepthStencil, pixelSize, 1));
    if (!depthStencil->create()) {
        qWarning("Failed to create depth/stencil buffer for offscreen readback");
        return QImage();
    }
    QRhiTextureRenderTargetDescription rtDesc(texture.data());
    rtDesc.setDepthStencilBuffer(depthStencil.data());
    QScopedPointer<QRhiTextureRenderTarget> rt(rhi->newTextureRenderTarget(rtDesc));
    QScopedPointer<QRhiRenderPassDescriptor> rpDesc(rt->newCompatibleRenderPassDescriptor());
    rt->setRenderPassDescriptor(rpDesc.data());
    if (!rt->create()) {
        qWarning("Failed to build render target for offscreen readback");
        return QImage();
    }

    // Backup the original Rhi
    QRhi *currentRhi = wd->rhi;
    wd->rhi = rhi;

    QSGDefaultRenderContext::InitParams params;
    params.rhi = rhi;
    params.sampleCount = 1;
    params.initialSurfacePixelSize = pixelSize;
    params.maybeSurface = window;
    wd->context->initialize(&params);

    // Backup the original RenderTarget
    QQuickRenderTarget currentRenderTarget = window->renderTarget();
    // There was no rendercontrol which means a custom render target
    // should not be set either. Set our own, temporarily.
    window->setRenderTarget(QQuickRenderTarget::fromRhiRenderTarget(rt.data()));

    QRhiCommandBuffer *cb = nullptr;
    if (rhi->beginOffscreenFrame(&cb) != QRhi::FrameOpSuccess) {
        qWarning("Failed to start recording the frame for offscreen readback");
        return QImage();
    }

    wd->setCustomCommandBuffer(cb);
    wd->polishItems();
    wd->syncSceneGraph();
    wd->renderSceneGraph(window->size());
    wd->setCustomCommandBuffer(nullptr);

    QImage image = grabAndBlockInCurrentFrame(rhi, cb, texture.data());
    rhi->endOffscreenFrame();

    image.setDevicePixelRatio(window->devicePixelRatio());

    // Called from gui/main thread on no onscreen rendering initialized
    if (!currentRhi) {
        wd->cleanupNodesOnShutdown();
        wd->context->invalidate();

        window->setRenderTarget(QQuickRenderTarget());
        wd->rhi = nullptr;
    } else {
        // Called from rendering thread for protected content
        // Restore to original Rhi, RenderTarget and Context
        window->setRenderTarget(currentRenderTarget);
        wd->rhi = currentRhi;
        params.rhi = currentRhi;
        wd->context->initialize(&params);
    }

    return image;
}
#endif

void QSGRhiSupport::applySwapChainFormat(QRhiSwapChain *scWithWindowSet)
{
    const char *fmtStr = "unknown";
    switch (m_swapChainFormat) {
    case QRhiSwapChain::SDR:
        fmtStr = "SDR";
        break;
    case QRhiSwapChain::HDRExtendedSrgbLinear:
        fmtStr = "scRGB";
        break;
    case QRhiSwapChain::HDR10:
        fmtStr = "HDR10";
        break;
    default:
        break;
    }

    if (!scWithWindowSet->isFormatSupported(m_swapChainFormat)) {
        if (m_swapChainFormat != QRhiSwapChain::SDR) {
            qCDebug(QSG_LOG_INFO, "Requested a %s swapchain but it is reported to be unsupported with the current display(s). "
                                  "In multi-screen configurations make sure the window is located on a HDR-enabled screen. "
                                  "Request ignored, using SDR swapchain.", fmtStr);
        }
        return;
    }

    scWithWindowSet->setFormat(m_swapChainFormat);

    if (m_swapChainFormat != QRhiSwapChain::SDR) {
        qCDebug(QSG_LOG_INFO, "Creating %s swapchain", fmtStr);
        qCDebug(QSG_LOG_INFO) << "HDR output info:" << scWithWindowSet->hdrInfo();
    }
}

QT_END_NAMESPACE
