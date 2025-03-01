#####################################################################
## qtquickcontrols2iosstyleplugin Plugin:
#####################################################################

set(qml_files
    "Slider.qml"
    "RangeSlider.qml"
    "Switch.qml"
    "Button.qml"
    "CheckBox.qml"
    "RadioButton.qml"
    "SpinBox.qml"
    "ProgressBar.qml"
)
set_source_files_properties(Slider.qml PROPERTIES
    QT_QML_SOURCE_VERSIONS "2.2;6.0"
)

qt_internal_add_qml_module(qtquickcontrols2iosstyleplugin
    URI "QtQuick.Controls.iOS"
    VERSION "${PROJECT_VERSION}"
    CLASS_NAME QtQuickControls2IOSStylePlugin
    IMPORTS
        QtQuick.Controls.Basic/auto
    PAST_MAJOR_VERSIONS 2
    PLUGIN_TARGET qtquickcontrols2iosstyleplugin
    NO_PLUGIN_OPTIONAL
    NO_GENERATE_PLUGIN_SOURCE
    SOURCES
        qtquickcontrols2iosstyleplugin.cpp
        qquickiosstyle.cpp qquickiosstyle_p.h
        qquickiostheme_p.h qquickiostheme.mm
    QML_FILES
        ${qml_files}
    DEFINES
        QT_NO_CAST_FROM_ASCII
        QT_NO_CAST_TO_ASCII
    LIBRARIES
        Qt::CorePrivate
        Qt::GuiPrivate
        Qt::QmlPrivate
        Qt::QuickControls2Private
        Qt::QuickPrivate
        Qt::QuickTemplates2Private
        Qt::QuickControls2ImplPrivate
)

qt_internal_extend_target(Core CONDITION APPLE AND IOS
    LIBRARIES
        ${FWUIKit}
)

file(GLOB resource_glob RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" "images/*.png")
foreach(file IN LISTS resource_glob_0)
    set_source_files_properties("${CMAKE_CURRENT_SOURCE_DIR}/${file}" PROPERTIES QT_RESOURCE_ALIAS "${file}")
endforeach()

# Resources:
set(qmake_qtquickcontrols2iosstyleplugin_resource_files
    ${resource_glob}
)

qt_internal_add_resource(qtquickcontrols2iosstyleplugin "qmake_qtquickcontrols2iosstyleplugin"
    PREFIX
        "/qt-project.org/imports/QtQuick/Controls/iOS"
    FILES
        ${qmake_qtquickcontrols2iosstyleplugin_resource_files}
)

# _qt_internal_add_qml_static_plugin_dependency(qtquickcontrols2iosstyleplugin
#                                              qtquickcontrols2nativestyleplugin)

# Basic style is the required fallback style.
# _qt_internal_add_qml_static_plugin_dependency(qtquickcontrols2iosstyleplugin
#                                              qtquickcontrols2basicstyleplugin)
