#####################################################################
## tst_softwarerenderer Test:
#####################################################################

qt_internal_add_test(tst_softwarerenderer
    SOURCES
        tst_softwarerenderer.cpp
    DEFINES
        QT_QMLTEST_DATADIR=\\\"${CMAKE_CURRENT_SOURCE_DIR}/data\\\"
    PUBLIC_LIBRARIES
        Qt::Gui
        Qt::Quick
        Qt::QuickPrivate
        Qt::QuickTestUtilsPrivate
)

## Scopes:
#####################################################################

qt_internal_extend_target(tst_softwarerenderer CONDITION ANDROID OR IOS
    DEFINES
        QT_QMLTEST_DATADIR=\\\":/data\\\"
)

qt_internal_extend_target(tst_softwarerenderer CONDITION NOT ANDROID AND NOT IOS
    DEFINES
        QT_QMLTEST_DATADIR=\\\"${CMAKE_CURRENT_SOURCE_DIR}/data\\\"
)
