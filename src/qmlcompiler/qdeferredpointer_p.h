/****************************************************************************
**
** Copyright (C) 2020 The Qt Company Ltd.
** Contact: https://www.qt.io/licensing/
**
** This file is part of the tools applications of the Qt Toolkit.
**
** $QT_BEGIN_LICENSE:GPL-EXCEPT$
** Commercial License Usage
** Licensees holding valid commercial Qt licenses may use this file in
** accordance with the commercial license agreement provided with the
** Software or, alternatively, in accordance with the terms contained in
** a written agreement between you and The Qt Company. For licensing terms
** and conditions see https://www.qt.io/terms-conditions. For further
** information use the contact form at https://www.qt.io/contact-us.
**
** GNU General Public License Usage
** Alternatively, this file may be used under the terms of the GNU
** General Public License version 3 as published by the Free Software
** Foundation with exceptions as appearing in the file LICENSE.GPL3-EXCEPT
** included in the packaging of this file. Please review the following
** information to ensure the GNU General Public License requirements will
** be met: https://www.gnu.org/licenses/gpl-3.0.html.
**
** $QT_END_LICENSE$
**
****************************************************************************/

#ifndef QDEFERREDPOINTER_P_H
#define QDEFERREDPOINTER_P_H

//
//  W A R N I N G
//  -------------
//
// This file is not part of the Qt API.  It exists purely as an
// implementation detail.  This header file may change from version to
// version without notice, or even be removed.
//
// We mean it.

#include <private/qtqmlcompilerexports_p.h>

#include <QtCore/private/qglobal_p.h>
#include <QtCore/qsharedpointer.h>

QT_BEGIN_NAMESPACE

template<typename T>
class QDeferredSharedPointer;

template<typename T>
class QDeferredWeakPointer;

template<typename T>
class QDeferredFactory
{
public:
    bool isValid() const;

private:
    friend class QDeferredSharedPointer<const T>;
    friend class QDeferredWeakPointer<const T>;
    friend class QDeferredSharedPointer<T>;
    friend class QDeferredWeakPointer<T>;
    void populate(const QSharedPointer<T> &) const;
};

template<typename T>
class QDeferredSharedPointer
{
public:
    using Factory = QDeferredFactory<std::remove_const_t<T>>;

    QDeferredSharedPointer() = default;

    QDeferredSharedPointer(QSharedPointer<T> data)
        : m_data(data)
    {}

    QDeferredSharedPointer(QWeakPointer<T> data)
        : m_data(data)
    {}

    QDeferredSharedPointer(QSharedPointer<T> data, QSharedPointer<Factory> factory)
        : m_data(data), m_factory(factory)
    {
        // You have to provide a valid pointer if you provide a factory. We cannot allocate the
        // pointer for you because then two copies of the same QDeferredSharedPointer will diverge
        // and lazy-load two separate data objects.
        Q_ASSERT(!m_data.isNull() || m_factory.isNull());
    }

    operator QSharedPointer<T>() const
    {
        lazyLoad();
        return m_data;
    }

    operator QDeferredSharedPointer<const T>() const { return { m_data, m_factory }; }

    T &operator*() const { return QSharedPointer<T>(*this).operator*(); }
    T *operator->() const { return QSharedPointer<T>(*this).operator->(); }

    bool isNull() const
    {
        return m_data.isNull();
    }

    explicit operator bool() const noexcept { return !isNull(); }
    bool operator !() const noexcept { return isNull(); }

    T *data() const { return QSharedPointer<T>(*this).data(); }
    T *get() const { return data(); }

    friend size_t qHash(const QDeferredSharedPointer &ptr, size_t seed = 0)
    {
        // This is a hash of the pointer, not the data.
        return qHash(ptr.m_data, seed);
    }

    friend bool operator==(const QDeferredSharedPointer &a, const QDeferredSharedPointer &b)
    {
        // This is a comparison of the pointers, not their data. As we require the pointers to
        // be given in the ctor, we can do this.
        return a.m_data == b.m_data;
    }

    friend bool operator!=(const QDeferredSharedPointer &a, const QDeferredSharedPointer &b)
    {
        return !(a == b);
    }

    friend bool operator<(const QDeferredSharedPointer &a, const QDeferredSharedPointer &b)
    {
        return a.m_data < b.m_data;
    }

    friend bool operator<=(const QDeferredSharedPointer &a, const QDeferredSharedPointer &b)
    {
        return a.m_data <= b.m_data;
    }

    friend bool operator>(const QDeferredSharedPointer &a, const QDeferredSharedPointer &b)
    {
        return a.m_data > b.m_data;
    }

    friend bool operator>=(const QDeferredSharedPointer &a, const QDeferredSharedPointer &b)
    {
        return a.m_data >= b.m_data;
    }

    template <typename U>
    friend bool operator==(const QDeferredSharedPointer &a, const QSharedPointer<U> &b)
    {
        return a.m_data == b;
    }

    template <typename U>
    friend bool operator!=(const QDeferredSharedPointer &a, const QSharedPointer<U> &b)
    {
        return !(a == b);
    }

    template <typename U>
    friend bool operator==(const QSharedPointer<U> &a, const QDeferredSharedPointer &b)
    {
        return b == a;
    }

    template <typename U>
    friend bool operator!=(const QSharedPointer<U> &a, const QDeferredSharedPointer &b)
    {
        return b != a;
    }

    Factory *factory() const
    {
        return (m_factory && m_factory->isValid()) ? m_factory.data() : nullptr;
    }

private:
    friend class QDeferredWeakPointer<T>;

    void lazyLoad() const
    {
        if (Factory *f = factory()) {
            Factory localFactory;
            std::swap(localFactory, *f); // Swap before executing, to avoid recursion
            localFactory.populate(m_data.template constCast<std::remove_const_t<T>>());
        }
    }

    QSharedPointer<T> m_data;
    QSharedPointer<Factory> m_factory;
};

template<typename T>
class QDeferredWeakPointer
{
public:
    using Factory = QDeferredFactory<std::remove_const_t<T>>;

    QDeferredWeakPointer() = default;

    QDeferredWeakPointer(const QDeferredSharedPointer<T> &strong)
        : m_data(strong.m_data), m_factory(strong.m_factory)
    {
    }

    QDeferredWeakPointer(QWeakPointer<T> data, QWeakPointer<Factory> factory)
        : m_data(data), m_factory(factory)
    {}

    operator QWeakPointer<T>() const
    {
        lazyLoad();
        return m_data;
    }

    operator QDeferredSharedPointer<T>() const
    {
        return QDeferredSharedPointer<T>(m_data.toStrongRef(), m_factory.toStrongRef());
    }

    operator QDeferredWeakPointer<const T>() const { return {m_data, m_factory}; }

    QSharedPointer<T> toStrongRef() const
    {
        return QWeakPointer<T>(*this).toStrongRef();
    }

    bool isNull() const { return m_data.isNull(); }

    explicit operator bool() const noexcept { return !isNull(); }
    bool operator !() const noexcept { return isNull(); }

    friend bool operator==(const QDeferredWeakPointer &a, const QDeferredWeakPointer &b)
    {
        return a.m_data == b.m_data;
    }

    friend bool operator!=(const QDeferredWeakPointer &a, const QDeferredWeakPointer &b)
    {
        return !(a == b);
    }

private:
    void lazyLoad() const
    {
        if (m_factory) {
            auto factory = m_factory.toStrongRef();
            if (factory->isValid()) {
                Factory localFactory;
                std::swap(localFactory, *factory); // Swap before executing, to avoid recursion
                localFactory.populate(
                        m_data.toStrongRef().template constCast<std::remove_const_t<T>>());
            }
        }
    }

    QWeakPointer<T> m_data;
    QWeakPointer<Factory> m_factory;
};


QT_END_NAMESPACE

#endif // QDEFERREDPOINTER_P_H
