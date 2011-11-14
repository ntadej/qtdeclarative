TARGET = qmldbg_ost
QT       += declarative network

load(qt_plugin)

QTDIR_build:DESTDIR  = $$QT_BUILD_TREE/plugins/qmltooling
QTDIR_build:REQUIRES += "contains(QT_CONFIG, declarative)"

SOURCES += \
    qmlostplugin.cpp \
    qostdevice.cpp

HEADERS += \
    qmlostplugin.h \
    qostdevice.h \
    usbostcomm.h

target.path += $$[QT_INSTALL_PLUGINS]/qmltooling
INSTALLS += target
