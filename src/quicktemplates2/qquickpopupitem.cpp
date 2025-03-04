/****************************************************************************
**
** Copyright (C) 2017 The Qt Company Ltd.
** Contact: https://www.qt.io/licensing/
**
** This file is part of the Qt Quick Templates 2 module of the Qt Toolkit.
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

#include "qquickpopupitem_p_p.h"
#include "qquickapplicationwindow_p.h"
#include "qquickshortcutcontext_p_p.h"
#include "qquickpage_p_p.h"
#include "qquickcontentitem_p.h"
#include "qquickpopup_p_p.h"
#include "qquickdeferredexecute_p_p.h"

#include <QtCore/qloggingcategory.h>
#if QT_CONFIG(shortcut)
#  include <QtGui/private/qshortcutmap_p.h>
#endif
#include <QtGui/private/qguiapplication_p.h>

#if QT_CONFIG(accessibility)
#include <QtQuick/private/qquickaccessibleattached_p.h>
#endif

QT_BEGIN_NAMESPACE

Q_LOGGING_CATEGORY(lcPopupItem, "qt.quick.controls.popupitem")

QQuickPopupItemPrivate::QQuickPopupItemPrivate(QQuickPopup *popup)
    : popup(popup)
{
    isTabFence = true;
}

void QQuickPopupItemPrivate::implicitWidthChanged()
{
    qCDebug(lcPopupItem).nospace() << "implicitWidthChanged called on " << q_func() << "; new implicitWidth is " << implicitWidth;
    QQuickPagePrivate::implicitWidthChanged();
    emit popup->implicitWidthChanged();
}

void QQuickPopupItemPrivate::implicitHeightChanged()
{
    qCDebug(lcPopupItem).nospace() << "implicitHeightChanged called on " << q_func() << "; new implicitHeight is " << implicitHeight;
    QQuickPagePrivate::implicitHeightChanged();
    emit popup->implicitHeightChanged();
}

void QQuickPopupItemPrivate::resolveFont()
{
    if (QQuickApplicationWindow *window = qobject_cast<QQuickApplicationWindow *>(popup->window()))
        inheritFont(window->font());
    else
        inheritFont(QQuickTheme::font(QQuickTheme::System));
}

QQuickItem *QQuickPopupItemPrivate::getContentItem()
{
    Q_Q(QQuickPopupItem);
    if (QQuickItem *item = QQuickPagePrivate::getContentItem())
        return item;

    return new QQuickContentItem(popup, q);
}

static inline QString contentItemName() { return QStringLiteral("contentItem"); }

void QQuickPopupItemPrivate::cancelContentItem()
{
    quickCancelDeferred(popup, contentItemName());
}

void QQuickPopupItemPrivate::executeContentItem(bool complete)
{
    if (contentItem.wasExecuted())
        return;

    if (!contentItem || complete)
        quickBeginDeferred(popup, contentItemName(), contentItem);
    if (complete)
        quickCompleteDeferred(popup, contentItemName(), contentItem);
}

static inline QString backgroundName() { return QStringLiteral("background"); }

void QQuickPopupItemPrivate::cancelBackground()
{
    quickCancelDeferred(popup, backgroundName());
}

void QQuickPopupItemPrivate::executeBackground(bool complete)
{
    if (background.wasExecuted())
        return;

    if (!background || complete)
        quickBeginDeferred(popup, backgroundName(), background);
    if (complete)
        quickCompleteDeferred(popup, backgroundName(), background);
}

QQuickPopupItem::QQuickPopupItem(QQuickPopup *popup)
    : QQuickPage(*(new QQuickPopupItemPrivate(popup)), nullptr)
{
    setParent(popup);
    setFlag(ItemIsFocusScope);
    setAcceptedMouseButtons(Qt::AllButtons);
#if QT_CONFIG(quicktemplates2_multitouch)
    setAcceptTouchEvents(true);
#endif
#if QT_CONFIG(cursor)
    setCursor(Qt::ArrowCursor);
#endif

    connect(popup, &QQuickPopup::paletteChanged, this, &QQuickItem::paletteChanged);
    connect(popup, &QQuickPopup::paletteCreated, this, &QQuickItem::paletteCreated);

#if QT_CONFIG(quicktemplates2_hover)
    // TODO: switch to QStyleHints::useHoverEffects in Qt 5.8
    setHoverEnabled(true);
    // setAcceptHoverEvents(QGuiApplication::styleHints()->useHoverEffects());
    // connect(QGuiApplication::styleHints(), &QStyleHints::useHoverEffectsChanged, this, &QQuickItem::setAcceptHoverEvents);
#endif
}

void QQuickPopupItem::grabShortcut()
{
#if QT_CONFIG(shortcut)
    Q_D(QQuickPopupItem);
    QGuiApplicationPrivate *pApp = QGuiApplicationPrivate::instance();
    if (!d->backId)
        d->backId = pApp->shortcutMap.addShortcut(this, Qt::Key_Back, Qt::WindowShortcut, QQuickShortcutContext::matcher);
    if (!d->escapeId)
        d->escapeId = pApp->shortcutMap.addShortcut(this, Qt::Key_Escape, Qt::WindowShortcut, QQuickShortcutContext::matcher);
#endif
}

void QQuickPopupItem::ungrabShortcut()
{
#if QT_CONFIG(shortcut)
    Q_D(QQuickPopupItem);
    QGuiApplicationPrivate *pApp = QGuiApplicationPrivate::instance();
    if (d->backId) {
        pApp->shortcutMap.removeShortcut(d->backId, this);
        d->backId = 0;
    }
    if (d->escapeId) {
        pApp->shortcutMap.removeShortcut(d->escapeId, this);
        d->escapeId = 0;
    }
#endif
}

QQuickPalette *QQuickPopupItemPrivate::palette() const
{
    return QQuickPopupPrivate::get(popup)->palette();
}

void QQuickPopupItemPrivate::setPalette(QQuickPalette *p)
{
    QQuickPopupPrivate::get(popup)->setPalette(p);
}

void QQuickPopupItemPrivate::resetPalette()
{
    QQuickPopupPrivate::get(popup)->resetPalette();
}

QPalette QQuickPopupItemPrivate::defaultPalette() const
{
    return QQuickPopupPrivate::get(popup)->defaultPalette();
}

bool QQuickPopupItemPrivate::providesPalette() const
{
    return QQuickPopupPrivate::get(popup)->providesPalette();
}

QPalette QQuickPopupItemPrivate::parentPalette() const
{
    return QQuickPopupPrivate::get(popup)->parentPalette();
}

void QQuickPopupItem::updatePolish()
{
    Q_D(QQuickPopupItem);
    return QQuickPopupPrivate::get(d->popup)->reposition();
}

bool QQuickPopupItem::event(QEvent *event)
{
#if QT_CONFIG(shortcut)
    Q_D(QQuickPopupItem);
    if (event->type() == QEvent::Shortcut) {
        QShortcutEvent *se = static_cast<QShortcutEvent *>(event);
        if (se->shortcutId() == d->escapeId || se->shortcutId() == d->backId) {
            QQuickPopupPrivate *p = QQuickPopupPrivate::get(d->popup);
            if (p->interactive) {
                p->closeOrReject();
                return true;
            }
        }
    }
#endif
    return QQuickItem::event(event);
}

bool QQuickPopupItem::childMouseEventFilter(QQuickItem *child, QEvent *event)
{
    Q_D(QQuickPopupItem);
    return d->popup->childMouseEventFilter(child, event);
}

void QQuickPopupItem::focusInEvent(QFocusEvent *event)
{
    Q_D(QQuickPopupItem);
    d->popup->focusInEvent(event);
}

void QQuickPopupItem::focusOutEvent(QFocusEvent *event)
{
    Q_D(QQuickPopupItem);
    d->popup->focusOutEvent(event);
}

void QQuickPopupItem::keyPressEvent(QKeyEvent *event)
{
    Q_D(QQuickPopupItem);
    d->popup->keyPressEvent(event);
}

void QQuickPopupItem::keyReleaseEvent(QKeyEvent *event)
{
    Q_D(QQuickPopupItem);
    d->popup->keyReleaseEvent(event);
}

void QQuickPopupItem::mousePressEvent(QMouseEvent *event)
{
    Q_D(QQuickPopupItem);
    d->popup->mousePressEvent(event);
}

void QQuickPopupItem::mouseMoveEvent(QMouseEvent *event)
{
    Q_D(QQuickPopupItem);
    d->popup->mouseMoveEvent(event);
}

void QQuickPopupItem::mouseReleaseEvent(QMouseEvent *event)
{
    Q_D(QQuickPopupItem);
    d->popup->mouseReleaseEvent(event);
}

void QQuickPopupItem::mouseDoubleClickEvent(QMouseEvent *event)
{
    Q_D(QQuickPopupItem);
    d->popup->mouseDoubleClickEvent(event);
}

void QQuickPopupItem::mouseUngrabEvent()
{
    Q_D(QQuickPopupItem);
    d->popup->mouseUngrabEvent();
}

#if QT_CONFIG(quicktemplates2_multitouch)
void QQuickPopupItem::touchEvent(QTouchEvent *event)
{
    Q_D(QQuickPopupItem);
    d->popup->touchEvent(event);
}

void QQuickPopupItem::touchUngrabEvent()
{
    Q_D(QQuickPopupItem);
    d->popup->touchUngrabEvent();
}
#endif

#if QT_CONFIG(wheelevent)
void QQuickPopupItem::wheelEvent(QWheelEvent *event)
{
    Q_D(QQuickPopupItem);
    d->popup->wheelEvent(event);
}
#endif

void QQuickPopupItem::contentItemChange(QQuickItem *newItem, QQuickItem *oldItem)
{
    Q_D(QQuickPopupItem);
    QQuickPage::contentItemChange(newItem, oldItem);
    d->popup->contentItemChange(newItem, oldItem);
}

void QQuickPopupItem::contentSizeChange(const QSizeF &newSize, const QSizeF &oldSize)
{
    Q_D(QQuickPopupItem);
    qCDebug(lcPopupItem) << "contentSizeChange called on" << this << "newSize" << newSize << "oldSize" << oldSize;
    QQuickPage::contentSizeChange(newSize, oldSize);
    d->popup->contentSizeChange(newSize, oldSize);
}

void QQuickPopupItem::fontChange(const QFont &newFont, const QFont &oldFont)
{
    Q_D(QQuickPopupItem);
    QQuickPage::fontChange(newFont, oldFont);
    d->popup->fontChange(newFont, oldFont);
}

void QQuickPopupItem::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    Q_D(QQuickPopupItem);
    qCDebug(lcPopupItem) << "geometryChange called on" << this << "newGeometry" << newGeometry << "oldGeometry" << oldGeometry;
    QQuickPage::geometryChange(newGeometry, oldGeometry);
    d->popup->geometryChange(newGeometry, oldGeometry);
}

void QQuickPopupItem::localeChange(const QLocale &newLocale, const QLocale &oldLocale)
{
    Q_D(QQuickPopupItem);
    QQuickPage::localeChange(newLocale, oldLocale);
    d->popup->localeChange(newLocale, oldLocale);
}

void QQuickPopupItem::mirrorChange()
{
    Q_D(QQuickPopupItem);
    emit d->popup->mirroredChanged();
}

void QQuickPopupItem::itemChange(ItemChange change, const ItemChangeData &data)
{
    Q_D(QQuickPopupItem);
    QQuickPage::itemChange(change, data);
    d->popup->itemChange(change, data);
}

void QQuickPopupItem::paddingChange(const QMarginsF &newPadding, const QMarginsF &oldPadding)
{
    Q_D(QQuickPopupItem);
    QQuickPage::paddingChange(newPadding, oldPadding);
    d->popup->paddingChange(newPadding, oldPadding);
}

void QQuickPopupItem::enabledChange()
{
    Q_D(QQuickPopupItem);
    // Just having QQuickPopup connect our QQuickItem::enabledChanged() signal
    // to its enabledChanged() signal is enough for the enabled property to work,
    // but we must also ensure that its paletteChanged() signal is emitted
    // so that bindings to palette are re-evaluated, because QQuickControl::palette()
    // returns a different palette depending on whether or not the control is enabled.
    // To save a connection, we also emit enabledChanged here.
    emit d->popup->enabledChanged();
}

QFont QQuickPopupItem::defaultFont() const
{
    Q_D(const QQuickPopupItem);
    return d->popup->defaultFont();
}

#if QT_CONFIG(accessibility)
QAccessible::Role QQuickPopupItem::accessibleRole() const
{
    Q_D(const QQuickPopupItem);
    return d->popup->accessibleRole();
}

void QQuickPopupItem::accessibilityActiveChanged(bool active)
{
    Q_D(const QQuickPopupItem);
    // Can't just use d->popup->accessibleName() here, because that refers to the accessible
    // name of us, the popup item, which is not what we want.
    const QQuickAccessibleAttached *popupAccessibleAttached = QQuickControlPrivate::accessibleAttached(d->popup);
    const QString oldPopupName = popupAccessibleAttached ? popupAccessibleAttached->name() : QString();
    const bool wasNameExplicitlySetOnPopup = popupAccessibleAttached && popupAccessibleAttached->wasNameExplicitlySet();

    QQuickPage::accessibilityActiveChanged(active);

    QQuickAccessibleAttached *accessibleAttached = QQuickControlPrivate::accessibleAttached(this);
    const QString ourName = accessibleAttached ? accessibleAttached->name() : QString();
    if (wasNameExplicitlySetOnPopup && accessibleAttached && ourName != oldPopupName) {
        // The user set Accessible.name on the Popup. Since the Popup and its popup item
        // have different accessible attached properties, the popup item doesn't know that
        // a name was set on the Popup by the user, and that it should use that, rather than
        // whatever QQuickPage sets. That's why we need to do it here.
        // To avoid it being overridden by the call to accessibilityActiveChanged() below,
        // we set it explicitly. It's safe to do this as the popup item is an internal implementation detail.
        accessibleAttached->setName(oldPopupName);
    }

    // This allows the different popup types to set a name on their popup item accordingly.
    // For example: Dialog uses its title and ToolTip uses its text.
    d->popup->accessibilityActiveChanged(active);
}
#endif

QT_END_NAMESPACE
