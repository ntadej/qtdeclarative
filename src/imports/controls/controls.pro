TARGET  = qtquickcontrols2plugin
TARGETPATH = QtQuick/Controls.2
IMPORT_VERSION = 2.0

QT += qml quick
QT += core-private gui-private qml-private quick-private quicktemplates-private

QMAKE_DOCS = $$PWD/doc/qtquickcontrols2.qdocconf

OTHER_FILES += \
    qmldir

QML_FILES = \
    ApplicationWindow.qml \
    BusyIndicator.qml \
    Button.qml \
    CheckBox.qml \
    Dial.qml \
    Drawer.qml \
    Frame.qml \
    GroupBox.qml \
    Label.qml \
    PageIndicator.qml \
    ProgressBar.qml \
    RadioButton.qml \
    ScrollBar.qml \
    ScrollIndicator.qml \
    Slider.qml \
    StackView.qml \
    Switch.qml \
    SwipeView.qml \
    TabBar.qml \
    TabButton.qml \
    TextArea.qml \
    TextField.qml \
    ToggleButton.qml \
    ToolBar.qml \
    ToolButton.qml \
    Tumbler.qml

HEADERS += \
    $$PWD/qquickdial_p.h \
    $$PWD/qquickdrawer_p.h \
    $$PWD/qquickswipeview_p.h \
    $$PWD/qquicktheme_p.h \
    $$PWD/qquickthemedata_p.h \
    $$PWD/qquicktumbler_p.h

SOURCES += \
    $$PWD/qquickdial.cpp \
    $$PWD/qquickdrawer.cpp \
    $$PWD/qquickswipeview.cpp \
    $$PWD/qquicktheme.cpp \
    $$PWD/qquickthemedata.cpp \
    $$PWD/qquicktumbler.cpp \
    $$PWD/qtquickcontrols2plugin.cpp

RESOURCES += \
    $$PWD/qtquickcontrols2plugin.qrc

OTHER_FILES += \
    $$PWD/theme.json

include(designer/designer.pri)

CONFIG += no_cxx_module
load(qml_plugin)
