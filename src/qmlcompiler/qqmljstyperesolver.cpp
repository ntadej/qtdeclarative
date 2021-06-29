/****************************************************************************
**
** Copyright (C) 2021 The Qt Company Ltd.
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

#include "qqmljstyperesolver_p.h"

#include <private/qqmljsimporter_p.h>
#include <private/qqmljsimportvisitor_p.h>
#include <private/qv4value_p.h>

#include <QtCore/qqueue.h>
#include <QtCore/qloggingcategory.h>

QT_BEGIN_NAMESPACE

Q_LOGGING_CATEGORY(lcTypeResolver, "qml.compiler.typeresolver", QtInfoMsg);

template<typename Action>
static bool searchBaseAndExtensionTypes(const QQmlJSScope::ConstPtr type, const Action &check)
{
    for (QQmlJSScope::ConstPtr scope = type; scope; scope = scope->baseType()) {
        // Extensions override their base types
        for (QQmlJSScope::ConstPtr extension = scope->extensionType(); extension;
             extension = extension->baseType()) {
            if (check(extension, QQmlJSTypeResolver::Extension))
                return true;
        }

        if (check(scope, QQmlJSTypeResolver::Base))
            return true;
    }

    return false;
}

QQmlJSTypeResolver::QQmlJSTypeResolver(QQmlJSImporter *importer, const QmlIR::Document *document,
                                       const QString &implicitImportDirectory,
                                       const QStringList &qmltypesFiles, bool wrapAllTypes)
    : m_importer(importer), m_document(document), m_wrapAllTypes(wrapAllTypes)
{
    m_knownGlobalTypes = importer->builtinInternalNames();
    m_voidType = m_knownGlobalTypes[QStringLiteral("void")];
    m_realType = m_knownGlobalTypes[QStringLiteral("double")];
    m_intType = m_knownGlobalTypes[QStringLiteral("int")];
    m_boolType = m_knownGlobalTypes[QStringLiteral("bool")];
    m_stringType = m_knownGlobalTypes[QStringLiteral("QString")];
    m_urlType = m_knownGlobalTypes[QStringLiteral("QUrl")];
    m_dateTimeType = m_knownGlobalTypes[QStringLiteral("QDateTime")];
    m_variantListType = m_knownGlobalTypes[QStringLiteral("QVariantList")];
    m_numberType = m_intType->baseType();
    Q_ASSERT(m_realType->baseType() == m_numberType);
    m_varType = m_knownGlobalTypes[QStringLiteral("QVariant")];
    m_jsValueType = m_knownGlobalTypes[QStringLiteral("QJSValue")];

    QQmlJSScope::Ptr jsPrimitiveType = QQmlJSScope::create();
    jsPrimitiveType->setInternalName(u"QJSPrimitiveValue"_qs);
    jsPrimitiveType->setFileName(u"qjsprimitivevalue.h"_qs);
    jsPrimitiveType->setAccessSemantics(QQmlJSScope::AccessSemantics::Value);
    m_jsPrimitiveType = jsPrimitiveType;

    QQmlJSScope::Ptr listPropertyType = QQmlJSScope::create();
    listPropertyType->setInternalName(u"QQmlListProperty<QObject>"_qs);
    listPropertyType->setFileName(u"qqmllist.h"_qs);
    listPropertyType->setAccessSemantics(QQmlJSScope::AccessSemantics::Value);
    m_listPropertyType = listPropertyType;

    QQmlJSImportVisitor visitor(importer, implicitImportDirectory, qmltypesFiles);
    m_document->program->accept(&visitor);

    QQueue<QQmlJSScope::Ptr> objects;
    objects.enqueue(visitor.result());
    m_objectsById = visitor.addressableScopes();

    while (!objects.isEmpty()) {
        const QQmlJSScope::Ptr object = objects.dequeue();
        const QQmlJS::SourceLocation location = object->sourceLocation();
        qCDebug(lcTypeResolver()).nospace() << "inserting " << object.data() << " at "
                                            << location.startLine << ':' << location.startColumn;
        m_objectsByLocation.insert({ location.startLine, location.startColumn }, object);

        const auto childScopes = object->childScopes();
        for (const auto &childScope : childScopes)
            objects.enqueue(childScope);
    }

    m_imports = visitor.imports();

    // This is pre-sorted. Don't mess it up.
    m_jsGlobalProperties = { QStringLiteral("Array"),
                             QStringLiteral("ArrayBuffer"),
                             QStringLiteral("Atomics"),
                             QStringLiteral("Boolean"),
                             QStringLiteral("DOMException"),
                             QStringLiteral("DataView"),
                             QStringLiteral("Date"),
                             QStringLiteral("Error"),
                             QStringLiteral("EvalError"),
                             QStringLiteral("Float32Array"),
                             QStringLiteral("Float64Array"),
                             QStringLiteral("Function"),
                             QStringLiteral("Infinity"),
                             QStringLiteral("Int16Array"),
                             QStringLiteral("Int32Array"),
                             QStringLiteral("Int8Array"),
                             QStringLiteral("JSON"),
                             QStringLiteral("Map"),
                             QStringLiteral("Math"),
                             QStringLiteral("NaN"),
                             QStringLiteral("Number"),
                             QStringLiteral("Object"),
                             QStringLiteral("Promise"),
                             QStringLiteral("Proxy"),
                             QStringLiteral("QT_TRANSLATE_NOOP"),
                             QStringLiteral("QT_TRID_NOOP"),
                             QStringLiteral("QT_TR_NOOP"),
                             QStringLiteral("Qt"),
                             QStringLiteral("RangeError"),
                             QStringLiteral("ReferenceError"),
                             QStringLiteral("Reflect"),
                             QStringLiteral("RegExp"),
                             QStringLiteral("SQLException"),
                             QStringLiteral("Set"),
                             QStringLiteral("SharedArrayBuffer"),
                             QStringLiteral("String"),
                             QStringLiteral("Symbol"),
                             QStringLiteral("SyntaxError"),
                             QStringLiteral("TypeError"),
                             QStringLiteral("URIError"),
                             QStringLiteral("URL"),
                             QStringLiteral("URLSearchParams"),
                             QStringLiteral("Uint16Array"),
                             QStringLiteral("Uint32Array"),
                             QStringLiteral("Uint8Array"),
                             QStringLiteral("Uint8ClampedArray"),
                             QStringLiteral("WeakMap"),
                             QStringLiteral("WeakSet"),
                             QStringLiteral("XMLHttpRequest"),
                             QStringLiteral("console"),
                             QStringLiteral("decodeURI"),
                             QStringLiteral("decodeURIComponent"),
                             QStringLiteral("encodeURI"),
                             QStringLiteral("encodeURIComponent"),
                             QStringLiteral("escape"),
                             QStringLiteral("eval"),
                             QStringLiteral("gc"),
                             QStringLiteral("isFinite"),
                             QStringLiteral("isNaN"),
                             QStringLiteral("parseFloat"),
                             QStringLiteral("parseInt"),
                             QStringLiteral("print"),
                             QStringLiteral("qsTr"),
                             QStringLiteral("qsTrId"),
                             QStringLiteral("qsTranslate"),
                             QStringLiteral("undefined"),
                             QStringLiteral("unescape") };
}

QQmlJSScope::ConstPtr
QQmlJSTypeResolver::scopeForLocation(const QV4::CompiledData::Location &location) const
{
    qCDebug(lcTypeResolver()).nospace()
            << "looking for object at " << location.line << ':' << location.column;
    return m_objectsByLocation[location];
}

QQmlJSScope::ConstPtr QQmlJSTypeResolver::scopeForId(const QString &id) const
{
    return m_objectsById[id];
}

QQmlJSScope::ConstPtr QQmlJSTypeResolver::typeFromAST(QQmlJS::AST::Type *type) const
{
    return m_imports[QmlIR::IRBuilder::asString(type->typeId)];
}

QQmlJSScope::ConstPtr QQmlJSTypeResolver::typeForConst(QV4::ReturnedValue rv) const
{
    QV4::Value value = QV4::Value::fromReturnedValue(rv);
    if (value.isUndefined())
        return voidType();

    if (value.isInt32())
        return intType();

    if (value.isBoolean())
        return boolType();

    if (value.isDouble())
        return realType();

    if (value.isNull())
        return jsPrimitiveType();

    return {};
}

QQmlJSRegisterContent
QQmlJSTypeResolver::typeForBinaryOperation(QSOperator::Op oper, const QQmlJSRegisterContent &left,
                                           const QQmlJSRegisterContent &right) const
{
    Q_ASSERT(left.isValid());
    Q_ASSERT(right.isValid());

    switch (oper) {
    case QSOperator::Op::Equal:
    case QSOperator::Op::NotEqual:
    case QSOperator::Op::StrictEqual:
    case QSOperator::Op::StrictNotEqual:
    case QSOperator::Op::Lt:
    case QSOperator::Op::Gt:
    case QSOperator::Op::Ge:
    case QSOperator::Op::In:
    case QSOperator::Op::Le:
        return globalType(boolType());
    case QSOperator::Op::BitAnd:
    case QSOperator::Op::BitOr:
    case QSOperator::Op::BitXor:
    case QSOperator::Op::LShift:
    case QSOperator::Op::RShift:
    case QSOperator::Op::URShift:
        return globalType(intType());
    case QSOperator::Op::Add: {
        const auto leftContents = containedType(left);
        const auto rightContents = containedType(right);
        if (leftContents == stringType() || rightContents == stringType())
            return QQmlJSRegisterContent::create(stringType(), stringType(),
                                                 QQmlJSRegisterContent::Builtin);

        const QQmlJSScope::ConstPtr result = merge(leftContents, rightContents);
        if (result == boolType())
            return QQmlJSRegisterContent::create(intType(), intType(),
                                                 QQmlJSRegisterContent::Builtin);
        if (isNumeric(result))
            return QQmlJSRegisterContent::create(realType(), numberType(),
                                                 QQmlJSRegisterContent::Builtin);

        return QQmlJSRegisterContent::create(jsPrimitiveType(), jsPrimitiveType(),
                                             QQmlJSRegisterContent::Builtin);
    }
    case QSOperator::Op::Sub: {
        const QQmlJSScope::ConstPtr result = merge(containedType(left), containedType(right));
        if (result == boolType())
            return QQmlJSRegisterContent::create(intType(), intType(),
                                                 QQmlJSRegisterContent::Builtin);
        if (isNumeric(result))
            return QQmlJSRegisterContent::create(realType(), numberType(),
                                                 QQmlJSRegisterContent::Builtin);
        return QQmlJSRegisterContent::create(jsPrimitiveType(), numberType(),
                                             QQmlJSRegisterContent::Builtin);
    }
    case QSOperator::Op::Mul:
    case QSOperator::Op::Div:
    case QSOperator::Op::Exp:
    case QSOperator::Op::Mod:
        return QQmlJSRegisterContent::create(
                isNumeric(merge(containedType(left), containedType(right))) ? realType()
                                                                            : jsPrimitiveType(),
                numberType(), QQmlJSRegisterContent::Builtin);
    case QSOperator::Op::As:
        return right;
    default:
        break;
    }

    return merge(left, right);
}

QQmlJSRegisterContent
QQmlJSTypeResolver::typeForUnaryOperation(UnaryOperator oper,
                                          const QQmlJSRegisterContent &operand) const
{
    // For now, we are only concerned with the unary arithmetic operators.
    // The boolean and bitwise ones are special cased elsewhere.
    Q_UNUSED(oper);

    return QQmlJSRegisterContent::create(isNumeric(operand) ? realType() : jsPrimitiveType(),
                                         containedType(operand) == realType() ? realType()
                                                                              : numberType(),
                                         QQmlJSRegisterContent::Builtin);
}

bool QQmlJSTypeResolver::isPrimitive(const QQmlJSRegisterContent &type) const
{
    return isPrimitive(containedType(type));
}

bool QQmlJSTypeResolver::isNumeric(const QQmlJSRegisterContent &type) const
{
    return isNumeric(containedType(type));
}

bool QQmlJSTypeResolver::isPrimitive(const QQmlJSScope::ConstPtr &type) const
{
    return type == m_intType || type == m_realType || type == m_boolType || type == m_voidType
            || type == m_stringType || type == m_jsPrimitiveType || type == m_numberType;
}

bool QQmlJSTypeResolver::isNumeric(const QQmlJSScope::ConstPtr &type) const
{
    for (auto base = type; base; base = base->baseType()) {
        if (base == numberType())
            return true;
    }
    return false;
}

QQmlJSScope::ConstPtr
QQmlJSTypeResolver::containedType(const QQmlJSRegisterContent &container) const
{
    if (container.isType())
        return container.type();
    if (container.isProperty()) {
        const QQmlJSMetaProperty prop = container.property();
        return prop.isList() ? listPropertyType() : QQmlJSScope::ConstPtr(prop.type());
    }
    if (container.isEnumeration())
        return container.enumeration().type();
    if (container.isMethod())
        return jsValueType();

    Q_UNREACHABLE();
    return {};
}

bool QQmlJSTypeResolver::canConvertFromTo(const QQmlJSScope::ConstPtr &from,
                                          const QQmlJSScope::ConstPtr &to) const
{
    // ### need a generic solution for custom cpp types:
    // if (from->m_hasBoolOverload && to == boolType)
    //    return true;

    if (from == to)
        return true;
    if (from == m_varType || to == m_varType)
        return true;
    if (from == m_jsValueType || to == m_jsValueType)
        return true;
    if (from == m_numberType && to->baseType() == m_numberType)
        return true;
    if (from->baseType() == m_numberType && to == m_numberType)
        return true;
    if (from->baseType() == m_numberType && to->baseType() == m_numberType)
        return true;
    if (from == m_intType && to == m_boolType)
        return true;
    if (from->accessSemantics() == QQmlJSScope::AccessSemantics::Reference && to == m_boolType)
        return true;

    // Yes, our String has number constructors.
    if ((from == m_intType || from == m_realType) && to == m_stringType)
        return true;

    // We can always convert between strings and urls.
    if ((from == m_stringType && to == m_urlType) || (from == m_urlType && to == m_stringType))
        return true;

    if (from == m_voidType)
        return true;

    if (from == m_jsPrimitiveType) {
        // You can cast any primitive (in particular null) to a nullptr
        return isPrimitive(to) || to->accessSemantics() == QQmlJSScope::AccessSemantics::Reference;
    }

    if (to == m_jsPrimitiveType)
        return isPrimitive(from);

    for (auto baseType = from->baseType(); baseType; baseType = baseType->baseType()) {
        if (baseType == to)
            return true;
    }

    return false;
}

bool QQmlJSTypeResolver::canConvertFromTo(const QQmlJSRegisterContent &from,
                                          const QQmlJSRegisterContent &to) const
{
    return canConvertFromTo(containedType(from), containedType(to));
}

static QQmlJSRegisterContent::ContentVariant mergeVariants(QQmlJSRegisterContent::ContentVariant a,
                                                           QQmlJSRegisterContent::ContentVariant b)
{
    return (a == b) ? a : QQmlJSRegisterContent::Unknown;
}

QQmlJSRegisterContent QQmlJSTypeResolver::merge(const QQmlJSRegisterContent &a,
                                                const QQmlJSRegisterContent &b) const
{
    const auto mergedStoredType = merge(a.storedType(), b.storedType());

    return QQmlJSRegisterContent::create(
            mergedStoredType == numberType() ? realType() : mergedStoredType,
            merge(containedType(a), containedType(b)), mergeVariants(a.variant(), b.variant()),
            merge(a.scopeType(), b.scopeType()));
}

static QQmlJSScope::ConstPtr commonBaseType(const QQmlJSScope::ConstPtr &a,
                                            const QQmlJSScope::ConstPtr &b)
{
    if (!a || !b)
        return {};

    auto inheritanceChain = [](QQmlJSScope::ConstPtr type) {
        QVector<QQmlJSScope::ConstPtr> result;
        do {
            result.prepend(type);
            type = type->baseType();
        } while (type);
        return result;
    };

    auto aInheritanceChain = inheritanceChain(a);
    auto bInheritanceChain = inheritanceChain(b);

    int length = qMin(aInheritanceChain.length(), bInheritanceChain.length());
    QQmlJSScope::ConstPtr result;
    for (int i = 0; i < length; ++i) {
        if (aInheritanceChain.at(i)->internalName() == bInheritanceChain.at(i)->internalName())
            result = aInheritanceChain.at(i);
        else
            break;
    }
    return result;
}

QQmlJSScope::ConstPtr QQmlJSTypeResolver::merge(const QQmlJSScope::ConstPtr &a,
                                                const QQmlJSScope::ConstPtr &b) const
{

    if (a == jsValueType() || a == varType())
        return a;
    if (b == jsValueType() || b == varType())
        return b;

    auto canConvert = [&](const QQmlJSScope::ConstPtr &from, const QQmlJSScope::ConstPtr &to) {
        return (a == from && b == to) || (b == from && a == to);
    };

    if (isNumeric(a) && isNumeric(b))
        return commonBaseType(a, b);

    if (canConvert(boolType(), intType()))
        return intType();
    if (canConvert(intType(), stringType()))
        return stringType();
    if (isPrimitive(a) && isPrimitive(b))
        return jsPrimitiveType();

    if (auto commonBase = commonBaseType(a, b))
        return commonBase;

    return jsValueType();
}

QQmlJSScope::ConstPtr QQmlJSTypeResolver::genericType(const QQmlJSScope::ConstPtr &type,
                                                      ComponentIsGeneric allowComponent) const
{
    if (type->isScript())
        return m_jsValueType;

    if (type->accessSemantics() == QQmlJSScope::AccessSemantics::Reference) {
        for (auto base = type; base; base = base->baseType()) {
            // QObject and QQmlComponent are the two required base types.
            // Any QML type system has to define those, or use the ones from builtins.
            // As QQmlComponent is derived from QObject, we can restrict ourselves to the latter.
            // This results in less if'ery when retrieving a QObject* from somewhere and deciding
            // what it is.
            if (base->internalName() == u"QObject"_qs) {
                return base;
            } else if (allowComponent == ComponentIsGeneric::Yes
                       && base->internalName() == u"QQmlComponent"_qs) {
                return base;
            }
        }

        qWarning() << "Object type" << type->internalName()
                   << "is not derived from QObject or QQmlComponent";
        return {};
    }

    if (type == voidType() || type == numberType())
        return jsPrimitiveType();

    if (isPrimitive(type) || type == m_jsValueType || type == m_listPropertyType
        || type == m_urlType || type == m_dateTimeType || type == m_variantListType
        || type == m_varType) {
        return type;
    }

    if (type->scopeType() == QQmlJSScope::EnumScope)
        return m_intType;

    return m_varType;
}

QQmlJSRegisterContent QQmlJSTypeResolver::globalType(const QQmlJSScope::ConstPtr &type) const
{
    return QQmlJSRegisterContent::create(storedType(type), type, QQmlJSRegisterContent::Unknown);
}

static QQmlJSRegisterContent::ContentVariant
scopeContentVariant(QQmlJSTypeResolver::BaseOrExtension mode, bool isMethod)
{
    switch (mode) {
    case QQmlJSTypeResolver::Base:
        return isMethod ? QQmlJSRegisterContent::ScopeMethod : QQmlJSRegisterContent::ScopeProperty;
    case QQmlJSTypeResolver::Extension:
        return isMethod ? QQmlJSRegisterContent::ExtensionScopeMethod
                        : QQmlJSRegisterContent::ExtensionScopeProperty;
    }
    Q_UNREACHABLE();
    return QQmlJSRegisterContent::Unknown;
}

QQmlJSRegisterContent QQmlJSTypeResolver::scopedType(const QQmlJSScope::ConstPtr &scope,
                                                     const QString &name) const
{
    if (QQmlJSScope::ConstPtr identified = scopeForId(name)) {
        return QQmlJSRegisterContent::create(storedType(identified), identified,
                                             QQmlJSRegisterContent::ObjectById, scope);
    }

    if (QQmlJSScope::ConstPtr base = QQmlJSScope::findCurrentQMLScope(scope)) {
        QQmlJSRegisterContent result;
        if (searchBaseAndExtensionTypes(
                    base, [&](const QQmlJSScope::ConstPtr &scope, BaseOrExtension mode) {
                        if (scope->hasOwnProperty(name)) {
                            const auto prop = scope->ownProperty(name);
                            result = QQmlJSRegisterContent::create(
                                    prop.isList() ? listPropertyType() : storedType(prop.type()),
                                    prop, scopeContentVariant(mode, false), scope);
                            return true;
                        }

                        if (scope->hasOwnMethod(name)) {
                            const auto methods = scope->ownMethods(name);
                            result = QQmlJSRegisterContent::create(
                                    jsValueType(), methods, scopeContentVariant(mode, true), scope);
                            return true;
                        }

                        // Unqualified enums are not allowed

                        return false;
                    })) {
            return result;
        }
    }

    if (QQmlJSScope::ConstPtr type = typeForName(name)) {
        if (type->isSingleton())
            return QQmlJSRegisterContent::create(storedType(type), type,
                                                 QQmlJSRegisterContent::Singleton);

        if (type->isScript())
            return QQmlJSRegisterContent::create(storedType(type), type,
                                                 QQmlJSRegisterContent::Script);

        if (const auto attached = type->attachedType()) {
            if (!genericType(attached)) {
                qWarning() << "Cannot resolve generic base of attached" << attached->internalName();
                return {};
            } else if (type->accessSemantics() != QQmlJSScope::AccessSemantics::Reference) {
                qWarning() << "Cannot retrieve attached object for non-reference type"
                           << type->internalName();
                return {};
            } else {
                // We don't know yet whether we need the attached or the plain object. In direct
                // mode, we will figure this out using the scope type and access any enums of the
                // plain type directly. In indirect mode, we can use enum lookups.
                return QQmlJSRegisterContent::create(storedType(attached), attached,
                                                     QQmlJSRegisterContent::ScopeAttached, type);
            }
        }

        // A plain reference to a non-singleton, non-attached type.
        // If it's undefined, we can actually get an "instance" of it.
        // Therefore, use a primitive value to store it.
        // Otherwise this is a plain type reference without instance.
        // We may still need the plain type reference for enum lookups,
        // so store it in QJSValue for now.
        return QQmlJSRegisterContent::create((type == voidType()) ? jsPrimitiveType()
                                                                  : jsValueType(),
                                             type, QQmlJSRegisterContent::PlainType);
    }

    if (std::binary_search(m_jsGlobalProperties.begin(), m_jsGlobalProperties.end(), name)) {
        return QQmlJSRegisterContent::create(jsValueType(), jsValueType(),
                                             QQmlJSRegisterContent::JavaScriptGlobal);
    }

    return {};
}

bool QQmlJSTypeResolver::checkEnums(const QQmlJSScope::ConstPtr &scope, const QString &name,
                                    QQmlJSRegisterContent *result, BaseOrExtension mode) const
{
    const auto enums = scope->ownEnumerations();
    for (const auto &enumeration : enums) {
        if (enumeration.name() == name) {
            *result = QQmlJSRegisterContent::create(
                    storedType(intType()), enumeration, QString(),
                    mode == Extension ? QQmlJSRegisterContent::ExtensionObjectEnum
                                      : QQmlJSRegisterContent::ObjectEnum,
                    scope);
            return true;
        }

        if (enumeration.hasKey(name)) {
            *result = QQmlJSRegisterContent::create(
                    storedType(intType()), enumeration, name,
                    mode == Extension ? QQmlJSRegisterContent::ExtensionObjectEnum
                                      : QQmlJSRegisterContent::ObjectEnum,
                    scope);
            return true;
        }
    }

    return false;
}

QQmlJSRegisterContent QQmlJSTypeResolver::memberType(const QQmlJSScope::ConstPtr &type,
                                                     const QString &name) const
{
    QQmlJSRegisterContent result;

    if (type == jsValueType()) {
        QQmlJSMetaProperty prop;
        prop.setPropertyName(name);
        prop.setTypeName(u"QJSValue"_qs);
        prop.setType(jsValueType());
        prop.setIsWritable(true);
        return QQmlJSRegisterContent::create(jsValueType(), prop,
                                             QQmlJSRegisterContent::JavaScriptObjectProperty, type);
    }

    if (type == stringType() && name == QStringLiteral("length")) {
        QQmlJSMetaProperty prop;
        prop.setPropertyName(name);
        prop.setTypeName(u"int"_qs);
        prop.setType(intType());
        prop.setIsWritable(false);
        return QQmlJSRegisterContent::create(intType(), prop, QQmlJSRegisterContent::Builtin, type);
    }

    const auto check = [&](const QQmlJSScope::ConstPtr &scope, BaseOrExtension mode) {
        if (scope->hasOwnProperty(name)) {
            const auto prop = scope->ownProperty(name);
            result = QQmlJSRegisterContent::create(
                    prop.isList() ? listPropertyType() : storedType(prop.type()), prop,
                    mode == Base ? QQmlJSRegisterContent::ObjectProperty
                                 : QQmlJSRegisterContent::ExtensionObjectProperty,
                    scope);
            return true;
        }

        if (scope->hasOwnMethod(name)) {
            const auto methods = scope->ownMethods(name);
            result = QQmlJSRegisterContent::create(
                    jsValueType(), methods,
                    mode == Base ? QQmlJSRegisterContent::ObjectMethod
                                 : QQmlJSRegisterContent::ExtensionObjectMethod,
                    scope);
            return true;
        }

        return checkEnums(scope, name, &result, mode);
    };

    if (searchBaseAndExtensionTypes(type, check))
        return result;

    if (QQmlJSScope::ConstPtr attachedBase = typeForName(name)) {
        if (QQmlJSScope::ConstPtr attached = attachedBase->attachedType()) {
            if (!genericType(attached)) {
                qWarning() << "Cannot resolve generic base of attached" << attached->internalName();
                return {};
            } else if (type->accessSemantics() != QQmlJSScope::AccessSemantics::Reference) {
                qWarning() << "Cannot retrieve attached object for non-reference type"
                           << type->internalName();
                return {};
            } else {
                return QQmlJSRegisterContent::create(storedType(attached), attached,
                                                     QQmlJSRegisterContent::ObjectAttached,
                                                     attachedBase);
            }
        }
    }

    return {};
}

QQmlJSRegisterContent QQmlJSTypeResolver::memberEnumType(const QQmlJSScope::ConstPtr &type,
                                                         const QString &name) const
{
    QQmlJSRegisterContent result;

    if (searchBaseAndExtensionTypes(type,
                                    [&](const QQmlJSScope::ConstPtr &scope, BaseOrExtension mode) {
                                        return checkEnums(scope, name, &result, mode);
                                    })) {
        return result;
    }

    return {};
}

QQmlJSRegisterContent QQmlJSTypeResolver::memberType(const QQmlJSRegisterContent &type,
                                                     const QString &name) const
{
    if (type.isType()) {
        const auto content = type.type();
        const auto result = memberType(content, name);
        if (result.isValid())
            return result;

        // If we didn't find anything and it's an attached type,
        // we might have an enum of the attaching type.
        return memberEnumType(type.scopeType(), name);
    }
    if (type.isProperty()) {
        const auto prop = type.property();
        if (prop.isList())
            return {};
        return memberType(prop.type(), name);
    }
    if (type.isEnumeration()) {
        const auto enumeration = type.enumeration();
        if (!type.enumMember().isEmpty() || !enumeration.hasKey(name))
            return {};
        return QQmlJSRegisterContent::create(storedType(intType()), enumeration, name,
                                             QQmlJSRegisterContent::ObjectEnum, type.scopeType());
    }
    if (type.isMethod()) {
        QQmlJSMetaProperty prop;
        prop.setTypeName(u"QJSValue"_qs);
        prop.setPropertyName(name);
        prop.setType(jsValueType());
        prop.setIsWritable(true);
        return QQmlJSRegisterContent::create(jsValueType(), prop,
                                             QQmlJSRegisterContent::JavaScriptObjectProperty,
                                             jsValueType());
    }

    Q_UNREACHABLE();
    return {};
}

QQmlJSRegisterContent QQmlJSTypeResolver::valueType(const QQmlJSRegisterContent &listType) const
{
    QQmlJSScope::ConstPtr scope;
    QQmlJSScope::ConstPtr value;

    auto valueType = [this](const QQmlJSScope::ConstPtr &scope) {
        if (scope->accessSemantics() == QQmlJSScope::AccessSemantics::Sequence)
            return scope->valueType();
        else if (scope == m_jsValueType || scope == m_varType)
            return m_jsValueType;
        return QQmlJSScope::ConstPtr();
    };

    if (listType.isType()) {
        scope = listType.type();
        value = valueType(scope);
    } else if (listType.isProperty()) {
        const auto prop = listType.property();
        if (prop.isList()) {
            scope = m_listPropertyType;
            value = prop.type();
        } else {
            scope = prop.type();
            value = valueType(scope);
        }
    }

    if (value.isNull())
        return {};

    QQmlJSMetaProperty property;
    property.setPropertyName(u"[]"_qs);
    property.setTypeName(value->internalName());
    property.setType(value);

    QQmlJSScope::ConstPtr stored;

    // Special handling of stored type here: List lookup can always produce undefined
    if (isPrimitive(value))
        stored = jsPrimitiveType();
    else
        stored = jsValueType();

    return QQmlJSRegisterContent::create(stored, property, QQmlJSRegisterContent::ListValue, scope);
}

bool QQmlJSTypeResolver::registerContains(const QQmlJSRegisterContent &reg,
                                          const QQmlJSScope::ConstPtr &type) const
{
    if (reg.isType())
        return reg.type() == type;
    if (reg.isProperty()) {
        const auto prop = reg.property();
        return prop.isList() ? type == listPropertyType() : prop.type() == type;
    }
    if (reg.isEnumeration())
        return type == intType();
    if (reg.isMethod())
        return type == jsValueType();
    return false;
}

QQmlJSScope::ConstPtr QQmlJSTypeResolver::storedType(const QQmlJSScope::ConstPtr &type,
                                                     ComponentIsGeneric allowComponent) const
{
    if (type.isNull())
        return {};
    if (m_wrapAllTypes)
        return genericType(type, allowComponent);
    if (type == voidType())
        return jsPrimitiveType();
    if (type->isScript())
        return jsValueType();
    if (type->isComposite())
        return QQmlJSScope::nonCompositeBaseType(type);
    if (type->fileName().isEmpty())
        return genericType(type);
    return type;
}

QT_END_NAMESPACE
