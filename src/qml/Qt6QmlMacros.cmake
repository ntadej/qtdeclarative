#
# Q6QmlMacros
#

set(__qt_qml_macros_module_base_dir "${CMAKE_CURRENT_LIST_DIR}" CACHE INTERNAL "")

# Install support uses the CMAKE_INSTALL_xxxDIR variables. Include this here
# so that it is more likely to get pulled in earlier at a higher level, and also
# to avoid re-including it many times later
include(GNUInstallDirs)
_qt_internal_add_deploy_support("${CMAKE_CURRENT_LIST_DIR}/Qt6QmlDeploySupport.cmake")

function(qt6_add_qml_module target)
    set(args_option
        STATIC
        SHARED
        DESIGNER_SUPPORTED
        FOLLOW_FOREIGN_VERSIONING
        NO_PLUGIN
        NO_PLUGIN_OPTIONAL
        NO_CREATE_PLUGIN_TARGET
        NO_GENERATE_PLUGIN_SOURCE
        NO_GENERATE_QMLTYPES
        NO_GENERATE_QMLDIR
        NO_LINT
        NO_CACHEGEN
        NO_RESOURCE_TARGET_PATH
        NO_IMPORT_SCAN
        # TODO: Remove once all usages have also been removed
        SKIP_TYPE_REGISTRATION

        # Used only by _qt_internal_qml_type_registration()
        # TODO: Remove this once qt6_extract_metatypes does not install by default.
        __QT_INTERNAL_INSTALL_METATYPES_JSON

        # Used to mark modules as having static side effects (i.e. if they install an image provider)
        __QT_INTERNAL_STATIC_MODULE
        # Used to mark modules as being a system module that provides all builtins
        __QT_INTERNAL_SYSTEM_MODULE
    )

    set(args_single
        PLUGIN_TARGET
        INSTALLED_PLUGIN_TARGET  # Internal option only, it may be removed
        OUTPUT_TARGETS
        RESOURCE_PREFIX
        URI
        TARGET_PATH   # Internal option only, it may be removed
        VERSION
        OUTPUT_DIRECTORY
        CLASS_NAME
        CLASSNAME  # TODO: For backward compatibility, remove once all repos no longer use it
        TYPEINFO
        NAMESPACE
        # TODO: We don't handle installation, warn if callers used these with the old
        #       API and eventually remove them once we have updated all other repos
        RESOURCE_EXPORT
        INSTALL_DIRECTORY
        INSTALL_LOCATION
    )

    set(args_multi
        SOURCES
        QML_FILES
        RESOURCES
        IMPORTS
        IMPORT_PATH
        OPTIONAL_IMPORTS
        DEFAULT_IMPORTS
        DEPENDENCIES
        PAST_MAJOR_VERSIONS
    )

    cmake_parse_arguments(PARSE_ARGV 1 arg
       "${args_option}"
       "${args_single}"
       "${args_multi}"
    )
    if(arg_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR "Unknown/unexpected arguments: ${arg_UNPARSED_ARGUMENTS}")
    endif()

    # Warn about options we no longer need/use (these were used by the internal
    # targets and examples, but the logic has been shifted to
    # qt_internal_add_qml_module() or left as a responsibility of the caller).
    if(DEFINED arg_RESOURCE_EXPORT)
        message(AUTHOR_WARNING
            "RESOURCE_EXPORT will be ignored. This function does not handle "
            "installation, which is what RESOURCE_EXPORT was previously used "
            "for. Please update your project to install the target directly."
        )
    endif()

    if(DEFINED arg_INSTALL_DIRECTORY)
        message(AUTHOR_WARNING
            "INSTALL_DIRECTORY will be ignored. This function does not handle "
            "installation, please update your project to install the target "
            "directly."
        )
    endif()

    if(DEFINED arg_INSTALL_LOCATION)
        message(AUTHOR_WARNING
            "INSTALL_LOCATION will be ignored. This function does not handle "
            "installation, please update your project to install the target "
            "directly."
        )
    endif()

    if(arg_SKIP_TYPE_REGISTRATION)
        message(AUTHOR_WARNING
            "SKIP_TYPE_REGISTRATION is no longer used and will be ignored."
        )
    endif()

    # Mandatory arguments
    if (NOT arg_URI)
        message(FATAL_ERROR
            "Called without a module URI. Please specify one using the URI argument."
        )
    endif()

    if (NOT arg_VERSION)
        message(FATAL_ERROR
            "Called without a module version. Please specify one using the VERSION argument."
        )
    endif()

    if ("${arg_VERSION}" MATCHES "^([0-9]+\\.[0-9]+)\\.[0-9]+$")
        set(arg_VERSION "${CMAKE_MATCH_1}")
    endif()

    if (NOT "${arg_VERSION}" MATCHES "^[0-9]+\\.[0-9]+$")
        message(FATAL_ERROR
            "Called with an invalid version argument: '${arg_VERSION}'. "
            "Expected version in the form: VersionMajor.VersionMinor."
        )
    endif()

    # Other arguments and checking for invalid combinations
    if (NOT arg_TARGET_PATH)
        # NOTE: This will always be used for copying things to the build
        #       directory, but it will not be used for resource paths if
        #       NO_RESOURCE_TARGET_PATH was given.
        string(REPLACE "." "/" arg_TARGET_PATH ${arg_URI})
    endif()

    if(arg_NO_PLUGIN AND DEFINED arg_PLUGIN_TARGET)
        message(FATAL_ERROR
            "NO_PLUGIN was specified, but PLUGIN_TARGET was also given. "
            "At most one of these can be present."
            )
    endif()

    set(is_executable FALSE)
    if(TARGET ${target})
        if(arg_STATIC OR arg_SHARED)
            message(FATAL_ERROR
                "Cannot use STATIC or SHARED keyword when passed an existing target (${target})"
                )
        endif()

        # With CMake 3.17 and earlier, a source file's generated property isn't
        # visible outside of the directory scope in which it is set. That can
        # lead to build errors for things like type registration due to CMake
        # thinking nothing will create a missing file on the first run. With
        # CMake 3.18 or later, we can force that visibility. Policy CMP0118
        # added in CMake 3.20 should have made this unnecessary, but we can't
        # rely on that because the user project controls what it is set to at
        # the point where it matters, which is the end of the target's
        # directory scope (hence we can't even test for it here).
        get_target_property(source_dir ${target} SOURCE_DIR)
        if(NOT source_dir STREQUAL CMAKE_CURRENT_SOURCE_DIR AND
           CMAKE_VERSION VERSION_LESS "3.18")
            message(WARNING
                "qt6_add_qml_module() is being called in a different "
                "directory scope to the one in which the target \"${target}\" "
                "was created. CMake 3.18 or later is required to generate a "
                "project robustly for this scenario, but you are using "
                "CMake ${CMAKE_VERSION}. Ideally, qt6_add_qml_module() should "
                "only be called from the same scope as the one the target was "
                "created in to avoid dependency and visibility problems."
            )
        endif()

        get_target_property(backing_target_type ${target} TYPE)
        get_target_property(is_android_executable "${target}" _qt_is_android_executable)
        if (backing_target_type STREQUAL "EXECUTABLE" OR is_android_executable)
            if(DEFINED arg_PLUGIN_TARGET)
                message(FATAL_ERROR
                    "A QML module with an executable as its backing target "
                    "cannot have a plugin."
                )
            endif()
            if(arg_NO_CREATE_PLUGIN_TARGET)
                message(WARNING
                    "A QML module with an executable as its backing target "
                    "cannot have a plugin. The NO_CREATE_PLUGIN_TARGET option "
                    "has no effect and should be removed."
                )
            endif()
            set(arg_NO_PLUGIN TRUE)
            set(lib_type "")
            set(is_executable TRUE)
        elseif(arg_NO_RESOURCE_TARGET_PATH)
            message(FATAL_ERROR
                "NO_RESOURCE_TARGET_PATH cannot be used for a backing target "
                "that is not an executable"
            )
        elseif(backing_target_type STREQUAL "STATIC_LIBRARY")
            set(lib_type STATIC)
        elseif(backing_target_type MATCHES "(SHARED|MODULE)_LIBRARY")
            set(lib_type SHARED)
        else()
            message(FATAL_ERROR "Unsupported backing target type: ${backing_target_type}")
        endif()
    else()
        if(arg_STATIC AND arg_SHARED)
            message(FATAL_ERROR
                "Both STATIC and SHARED specified, at most one can be given"
                )
        endif()

        if(arg_NO_RESOURCE_TARGET_PATH)
            message(FATAL_ERROR
                "NO_RESOURCE_TARGET_PATH can only be provided when an existing "
                "executable target is passed in as the backing target"
            )
        endif()

        # Explicit arguments take precedence, otherwise default to using the same
        # staticality as what Qt was built with. This follows the already
        # established default behavior for building ordinary Qt plugins.
        # We don't allow the standard CMake BUILD_SHARED_LIBS variable to control
        # the default because that can lead to different defaults depending on
        # whether you build with a separate backing target or not.
        if(arg_STATIC)
            set(lib_type STATIC)
        elseif(arg_SHARED)
            set(lib_type SHARED)
        elseif(QT6_IS_SHARED_LIBS_BUILD)
            set(lib_type SHARED)
        else()
            set(lib_type STATIC)
        endif()
    endif()

    if(arg_NO_PLUGIN)
        # Simplifies things a bit further below
        set(arg_PLUGIN_TARGET "")
    elseif(NOT DEFINED arg_PLUGIN_TARGET)
        if(arg_NO_CREATE_PLUGIN_TARGET)
            # We technically could allow this and rely on the project using the
            # default plugin target name, but not doing so gives us the
            # flexibility to potentially change that default later if needed.
            message(FATAL_ERROR
                "PLUGIN_TARGET must also be provided when NO_CREATE_PLUGIN_TARGET "
                "is used. If you want to disable creating a plugin altogether, "
                "use the NO_PLUGIN option instead."
            )
        endif()
        set(arg_PLUGIN_TARGET ${target}plugin)
    endif()
    if(arg_NO_CREATE_PLUGIN_TARGET AND arg_PLUGIN_TARGET STREQUAL target AND NOT TARGET ${target})
        message(FATAL_ERROR
            "PLUGIN_TARGET is the same as the backing target, which is allowed, "
            "but NO_CREATE_PLUGIN_TARGET was also given and the target does not "
            "exist. Either ensure the target is already created or do not "
            "specify NO_CREATE_PLUGIN_TARGET."
        )
    endif()
    if(NOT arg_INSTALLED_PLUGIN_TARGET)
        set(arg_INSTALLED_PLUGIN_TARGET ${arg_PLUGIN_TARGET})
    endif()

    set(no_gen_source)
    if(arg_NO_GENERATE_PLUGIN_SOURCE)
        set(no_gen_source NO_GENERATE_PLUGIN_SOURCE)
    endif()

    if(arg_OUTPUT_DIRECTORY)
        get_filename_component(arg_OUTPUT_DIRECTORY "${arg_OUTPUT_DIRECTORY}"
            ABSOLUTE BASE_DIR "${CMAKE_CURRENT_BINARY_DIR}"
        )
    else()
        if("${QT_QML_OUTPUT_DIRECTORY}" STREQUAL "")
            set(arg_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR})
            # For libraries, we assume/require that the source directory
            # structure is consistent with the target path. For executables,
            # the source directory will usually not reflect the target path
            # and the project will often expect to be able to use resource
            # paths that don't include the target path (they need the
            # NO_RESOURCE_TARGET_PATH option if they do that). Tooling always
            # needs the target path in the file system though, so the output
            # directory should always have it. Handle the special case for
            # executables to ensure this is what we get.
            if(is_executable)
                string(APPEND arg_OUTPUT_DIRECTORY "/${arg_TARGET_PATH}")
            endif()
        else()
            if(NOT IS_ABSOLUTE "${QT_QML_OUTPUT_DIRECTORY}")
                message(FATAL_ERROR
                    "QT_QML_OUTPUT_DIRECTORY must be an absolute path, but given: "
                    "${QT_QML_OUTPUT_DIRECTORY}"
                )
            endif()
            # This inherently does what we want for libraries and executables
            set(arg_OUTPUT_DIRECTORY ${QT_QML_OUTPUT_DIRECTORY}/${arg_TARGET_PATH})
        endif()
    endif()

    # Sanity check that we are not trying to have two different QML modules use
    # the same output directory.
    get_property(dirs GLOBAL PROPERTY _qt_all_qml_output_dirs)
    if(dirs)
        list(FIND dirs "${arg_OUTPUT_DIRECTORY}" index)
        if(NOT index EQUAL -1)
            get_property(qml_targets GLOBAL PROPERTY _qt_all_qml_targets)
            list(GET qml_targets ${index} other_target)
            message(FATAL_ERROR
                "Output directory for target \"${target}\" is already used by "
                "another QML module (target \"${other_target}\"). "
                "Output directory is:\n  ${arg_OUTPUT_DIRECTORY}\n"
            )
        endif()
    endif()
    set_property(GLOBAL APPEND PROPERTY _qt_all_qml_output_dirs ${arg_OUTPUT_DIRECTORY})
    set_property(GLOBAL APPEND PROPERTY _qt_all_qml_targets     ${target})

    # TODO: Support for old keyword, remove once all repos no longer use CLASSNAME
    if(arg_CLASSNAME)
        if(arg_CLASS_NAME AND NOT arg_CLASSNAME STREQUAL arg_CLASS_NAME)
            message(FATAL_ERROR
                "Both CLASSNAME and CLASS_NAME were given and were different. "
                "Update call site to only use CLASS_NAME."
            )
        endif()
        set(arg_CLASS_NAME "${arg_CLASSNAME}")
        unset(arg_CLASSNAME)
    endif()

    if(NOT arg_CLASS_NAME AND TARGET "${arg_PLUGIN_TARGET}")
        get_target_property(class_name ${arg_PLUGIN_TARGET} QT_PLUGIN_CLASS_NAME)
        if(class_name)
            set(arg_CLASS_NAME)
        endif()
    endif()
    if(NOT arg_CLASS_NAME)
        _qt_internal_compute_qml_plugin_class_name_from_uri("${arg_URI}" arg_CLASS_NAME)
    endif()

    if(TARGET ${target})
        if(arg_PLUGIN_TARGET STREQUAL target)
            # Insert the plugin's URI into its meta data to enable usage
            # of static plugins in QtDeclarative (like in mkspecs/features/qml_plugin.prf).
            set_property(TARGET ${target} APPEND PROPERTY
                AUTOMOC_MOC_OPTIONS "-Muri=${arg_URI}"
            )
        endif()
    else()
        if(arg_PLUGIN_TARGET STREQUAL target)
            set(conditional_args ${no_gen_source})
            if(arg_NAMESPACE)
                list(APPEND conditional_args NAMESPACE ${arg_NAMESPACE})
            endif()
            qt6_add_qml_plugin(${target}
                ${lib_type}
                OUTPUT_DIRECTORY ${arg_OUTPUT_DIRECTORY}
                URI ${arg_URI}
                CLASS_NAME ${arg_CLASS_NAME}
                ${conditional_args}
            )
        else()
            qt6_add_library(${target} ${lib_type})
        endif()
    endif()

    if(NOT target STREQUAL Qml)
        target_link_libraries(${target} PRIVATE ${QT_CMAKE_EXPORT_NAMESPACE}::Qml)
    endif()

    if(NOT arg_TYPEINFO)
        set(arg_TYPEINFO ${target}.qmltypes)
    endif()

    foreach(import_set IN ITEMS IMPORTS OPTIONAL_IMPORTS DEFAULT_IMPORTS)
        foreach(import IN LISTS arg_${import_set})
            string(FIND ${import} "/" slash_position REVERSE)
            if (slash_position EQUAL -1)
                set_property(TARGET ${target} APPEND PROPERTY
                    QT_QML_MODULE_${import_set} "${import}"
                )
            else()
                string(SUBSTRING ${import} 0 ${slash_position} import_module)
                math(EXPR slash_position "${slash_position} + 1")
                string(SUBSTRING ${import} ${slash_position} -1 import_version)
                if (import_version MATCHES "^([0-9]+(\\.[0-9]+)?|auto)$")
                    set_property(TARGET ${target} APPEND PROPERTY
                        QT_QML_MODULE_${import_set} "${import_module} ${import_version}"
                    )
                else()
                    message(FATAL_ERROR
                        "Invalid module ${import} version number. "
                        "Expected 'VersionMajor', 'VersionMajor.VersionMinor' or 'auto'."
                    )
                endif()
            endif()
        endforeach()
    endforeach()

    foreach(dependency IN LISTS arg_DEPENDENCIES)
        string(FIND ${dependency} "/" slash_position REVERSE)
        if (slash_position EQUAL -1)
            set_property(TARGET ${target} APPEND PROPERTY
                QT_QML_MODULE_DEPENDENCIES "${dependency}"
            )
        else()
            string(SUBSTRING ${dependency} 0 ${slash_position} dep_module)
            math(EXPR slash_position "${slash_position} + 1")
            string(SUBSTRING ${dependency} ${slash_position} -1 dep_version)
            if (dep_version MATCHES "^([0-9]+(\\.[0-9]+)?|auto)$")
                set_property(TARGET ${target} APPEND PROPERTY
                    QT_QML_MODULE_DEPENDENCIES "${dep_module} ${dep_version}"
                )
            else()
                message(FATAL_ERROR
                    "Invalid module dependency version number. "
                    "Expected 'VersionMajor', 'VersionMajor.VersionMinor' or 'auto'."
                )
            endif()
        endif()
    endforeach()

    _qt_internal_canonicalize_resource_path("${arg_RESOURCE_PREFIX}" arg_RESOURCE_PREFIX)
    if(arg_NO_RESOURCE_TARGET_PATH)
        set(qt_qml_module_resource_prefix "${arg_RESOURCE_PREFIX}")
    else()
        if(arg_RESOURCE_PREFIX STREQUAL "/")   # Checked so we prevent double-slash
            set(qt_qml_module_resource_prefix "/${arg_TARGET_PATH}")
        else()
            set(qt_qml_module_resource_prefix "${arg_RESOURCE_PREFIX}/${arg_TARGET_PATH}")
        endif()
    endif()

    set_target_properties(${target} PROPERTIES
        QT_QML_MODULE_NO_LINT "${arg_NO_LINT}"
        QT_QML_MODULE_NO_CACHEGEN "${arg_NO_CACHEGEN}"
        QT_QML_MODULE_NO_GENERATE_QMLDIR "${arg_NO_GENERATE_QMLDIR}"
        QT_QML_MODULE_NO_PLUGIN "${arg_NO_PLUGIN}"
        QT_QML_MODULE_NO_PLUGIN_OPTIONAL "${arg_NO_PLUGIN_OPTIONAL}"
        QT_QML_MODULE_NO_IMPORT_SCAN "${arg_NO_IMPORT_SCAN}"
        _qt_qml_module_follow_foreign_versioning "${arg_FOLLOW_FOREIGN_VERSIONING}"
        QT_QML_MODULE_URI "${arg_URI}"
        QT_QML_MODULE_TARGET_PATH "${arg_TARGET_PATH}"
        QT_QML_MODULE_VERSION "${arg_VERSION}"
        QT_QML_MODULE_CLASS_NAME "${arg_CLASS_NAME}"

        QT_QML_MODULE_PLUGIN_TARGET "${arg_PLUGIN_TARGET}"
        QT_QML_MODULE_INSTALLED_PLUGIN_TARGET "${arg_INSTALLED_PLUGIN_TARGET}"

        # Also Save the PLUGIN_TARGET values in a separate property to circumvent
        # https://gitlab.kitware.com/cmake/cmake/-/issues/21484 when exporting the properties
        _qt_qml_module_plugin_target "${arg_PLUGIN_TARGET}"
        _qt_qml_module_installed_plugin_target "${arg_INSTALLED_PLUGIN_TARGET}"

        QT_QML_MODULE_DESIGNER_SUPPORTED "${arg_DESIGNER_SUPPORTED}"
        QT_QML_MODULE_IS_STATIC "${arg___QT_INTERNAL_STATIC_MODULE}"
        QT_QML_MODULE_IS_SYSTEM "${arg___QT_INTERNAL_SYSTEM_MODULE}"
        QT_QML_MODULE_OUTPUT_DIRECTORY "${arg_OUTPUT_DIRECTORY}"
        QT_QML_MODULE_RESOURCE_PREFIX "${qt_qml_module_resource_prefix}"
        QT_QML_MODULE_PAST_MAJOR_VERSIONS "${arg_PAST_MAJOR_VERSIONS}"
        QT_QML_MODULE_TYPEINFO "${arg_TYPEINFO}"

        # TODO: Check how this is used by qt6_android_generate_deployment_settings()
        QT_QML_IMPORT_PATH "${arg_IMPORT_PATH}"
    )

    # Executables don't have a plugin target, so no need to export the properties.
    if(NOT backing_target_type STREQUAL "EXECUTABLE" AND NOT is_android_executable)
        set_property(TARGET ${target} APPEND PROPERTY
            EXPORT_PROPERTIES _qt_qml_module_plugin_target _qt_qml_module_installed_plugin_target
        )
    endif()

    set(ensure_set_properties
        QT_QML_MODULE_PLUGIN_TYPES_FILE
        QT_QML_MODULE_RESOURCES       # Original files as provided by the project (absolute)
        QT_QML_MODULE_RESOURCE_PATHS  # By qmlcachegen (resource paths)
        QT_QMLCACHEGEN_DIRECT_CALLS
        QT_QMLCACHEGEN_EXECUTABLE
        QT_QMLCACHEGEN_ARGUMENTS
    )
    foreach(prop IN LISTS ensure_set_properties)
        get_target_property(val ${target} ${prop})
        if("${val}" MATCHES "-NOTFOUND$")
            set_target_properties(${target} PROPERTIES ${prop} "")
        endif()
    endforeach()

    if(NOT arg_NO_GENERATE_QMLTYPES)
        set(type_registration_extra_args "")
        if(arg___QT_INTERNAL_INSTALL_METATYPES_JSON)
            list(APPEND type_registration_extra_args __QT_INTERNAL_INSTALL_METATYPES_JSON)
        endif()
        if(arg_NAMESPACE)
            list(APPEND type_registration_extra_args NAMESPACE ${arg_NAMESPACE})
        endif()
        _qt_internal_qml_type_registration(${target} ${type_registration_extra_args})
    endif()

    set(output_targets)

    if(NOT arg_NO_GENERATE_QMLDIR)
        _qt_internal_target_generate_qmldir(${target})

        # Embed qmldir in qrc. The following comments relate mostly to Qt5->6 transition.
        # The requirement to keep the same resource name might no longer apply, but it doesn't
        # currently appear to cause any hinderance to keep it.
        # The qmldir resource name needs to match the one generated by qmake's qml_module.prf, to
        # ensure that all Q_INIT_RESOURCE(resource_name) calls in Qt code don't lead to undefined
        # symbol errors when linking an application project.
        # The Q_INIT_RESOURCE() calls are not strictly necessary anymore because the CMake Qt
        # build passes around the compiled resources as object files.
        # These object files have global initiliazers that don't get discared when linked into
        # an application (as opposed to when the resource libraries were embedded into the static
        # libraries when Qt was built with qmake).
        # The reason to match the naming is to ensure that applications link successfully regardless
        # if Qt was built with CMake or qmake, while the build system transition phase is still
        # happening.
        string(REPLACE "/" "_" qmldir_resource_name "qmake_${arg_TARGET_PATH}")

        # The qmldir file ALWAYS has to be under the target path, even in the
        # resources. If it isn't, an explicit import can't find it. We need a
        # second copy NOT under the target path if NO_RESOURCE_TARGET_PATH is
        # given so that the implicit import will work.
        set(prefixes "${qt_qml_module_resource_prefix}")
        if(arg_NO_RESOURCE_TARGET_PATH)
            # The above prefixes item won't include the target path, so add a
            # second one that does.
            if(qt_qml_module_resource_prefix STREQUAL "/")
                list(APPEND prefixes "/${arg_TARGET_PATH}")
            else()
                list(APPEND prefixes "${qt_qml_module_resource_prefix}/${arg_TARGET_PATH}")
            endif()
        endif()
        set_source_files_properties(${arg_OUTPUT_DIRECTORY}/qmldir
            PROPERTIES QT_RESOURCE_ALIAS "qmldir"
        )

        foreach(prefix IN LISTS prefixes)
            set(resource_targets)
            qt6_add_resources(${target} ${qmldir_resource_name}
                FILES ${arg_OUTPUT_DIRECTORY}/qmldir
                PREFIX "${prefix}"
                OUTPUT_TARGETS resource_targets
            )
            list(APPEND output_targets ${resource_targets})
            # If we are adding the same file twice, we need a different resource
            # name for the second one. It has the same QT_RESOURCE_ALIAS but a
            # different prefix, so we can't put it in the same resource.
            string(APPEND qmldir_resource_name "_copy")
        endforeach()
    endif()

    if(NOT arg_NO_PLUGIN AND NOT arg_NO_CREATE_PLUGIN_TARGET)
        # This also handles the case where ${arg_PLUGIN_TARGET} already exists,
        # including where it is the same as ${target}. If ${arg_PLUGIN_TARGET}
        # already exists, it will update the necessary things that are specific
        # to qml plugins.
        if(TARGET ${arg_PLUGIN_TARGET})
            set(plugin_args "")
        else()
            set(plugin_args ${lib_type})
        endif()
        list(APPEND plugin_args ${no_gen_source})
        if(arg_NAMESPACE)
            list(APPEND plugin_args NAMESPACE ${arg_NAMESPACE})
        endif()
        qt6_add_qml_plugin(${arg_PLUGIN_TARGET}
            ${plugin_args}
            OUTPUT_DIRECTORY ${arg_OUTPUT_DIRECTORY}
            BACKING_TARGET ${target}
            CLASS_NAME ${arg_CLASS_NAME}
        )
    endif()

    if(TARGET "${arg_PLUGIN_TARGET}" AND NOT arg_PLUGIN_TARGET STREQUAL target)
        target_link_libraries(${arg_PLUGIN_TARGET} PRIVATE ${target})
    endif()

    target_sources(${target} PRIVATE ${arg_SOURCES})

    set(cache_target)
    qt6_target_qml_sources(${target}
        __QT_INTERNAL_FORCE_DEFER_QMLDIR
        QML_FILES ${arg_QML_FILES}
        RESOURCES ${arg_RESOURCES}
        OUTPUT_TARGETS cache_target
        PREFIX "${qt_qml_module_resource_prefix}"
    )
    list(APPEND output_targets ${cache_target})

    # Build an init object library for static plugins and propagate it along with the plugin
    # target.
    # TODO: Figure out if we can move this code block into qt_add_qml_plugin. Need to consider
    #       various corner cases.
    #       QTBUG-96937
    if(TARGET "${arg_PLUGIN_TARGET}")
        get_target_property(plugin_lib_type ${arg_PLUGIN_TARGET} TYPE)
        if(plugin_lib_type STREQUAL "STATIC_LIBRARY")
            __qt_internal_add_static_plugin_init_object_library(
                "${arg_PLUGIN_TARGET}" plugin_init_target)
            list(APPEND output_targets ${plugin_init_target})

            __qt_internal_propagate_object_library("${arg_PLUGIN_TARGET}" "${plugin_init_target}")
        endif()
    endif()

    if(NOT arg_NO_GENERATE_QMLDIR)
        if(${CMAKE_VERSION} VERSION_GREATER_EQUAL "3.19.0")
            # Defer the write to allow more qml files to be added later by calls to
            # qt6_target_qml_sources(). We wrap the deferred call with EVAL CODE
            # so that ${target} is evaluated now rather than the end of the scope.
            # We also delay target finalization until after our deferred write
            # because the qmldir file must be written before any finalizer
            # might call qt_import_qml_plugins().
            cmake_language(EVAL CODE
                "cmake_language(DEFER ID_VAR write_id CALL _qt_internal_write_deferred_qmldir_file ${target})"
            )
            _qt_internal_delay_finalization_until_after(${write_id})
        else()
            # Can't defer the write, have to do it now
            _qt_internal_write_deferred_qmldir_file(${target})
        endif()
    endif()

    if(arg_OUTPUT_TARGETS)
        set(${arg_OUTPUT_TARGETS} ${output_targets} PARENT_SCOPE)
    endif()

endfunction()

if(NOT QT_NO_CREATE_VERSIONLESS_FUNCTIONS)
    function(qt_add_qml_module)
        qt6_add_qml_module(${ARGV})
        cmake_parse_arguments(PARSE_ARGV 1 arg "" "OUTPUT_TARGETS" "")
        if(arg_OUTPUT_TARGETS)
            set(${arg_OUTPUT_TARGETS} ${${arg_OUTPUT_TARGETS}} PARENT_SCOPE)
        endif()
    endfunction()
endif()

# Make the prefix conform to the following:
#   - Starts with a "/"
#   - Does not end with a "/" unless the prefix is exactly "/"
function(_qt_internal_canonicalize_resource_path path out_var)
    if(NOT path)
        set(path "/")
    endif()
    if(NOT path MATCHES "^/")
        string(PREPEND path "/")
    endif()
    if(path MATCHES [[(.+)/$]])
        set(path "${CMAKE_MATCH_1}")
    endif()
    set(${out_var} "${path}" PARENT_SCOPE)
endfunction()

function(_qt_internal_get_escaped_uri uri out_var)
    string(REGEX REPLACE "[^A-Za-z0-9]" "_" escaped_uri "${uri}")
    set(${out_var} "${escaped_uri}" PARENT_SCOPE)
endfunction()

function(_qt_internal_compute_qml_plugin_class_name_from_uri uri out_var)
    _qt_internal_get_escaped_uri("${uri}" escaped_uri)
    set(${out_var} "${escaped_uri}Plugin" PARENT_SCOPE)
endfunction()

macro(_qt_internal_genex_getproperty var target property)
    set(${var} "$<TARGET_PROPERTY:${target},${property}>")
    set(have_${var} "$<BOOL:${${var}}>")
endmacro()

macro(_qt_internal_genex_getjoinedproperty var target property item_prefix glue)
    _qt_internal_genex_getproperty(${var} ${target} ${property})
    set(${var} "$<${have_${var}}:${item_prefix}$<JOIN:${${var}},${glue}${item_prefix}>>")
endmacro()

macro(_qt_internal_genex_getoption var target property)
    set(${var} "$<BOOL:$<TARGET_PROPERTY:${target},${property}>>")
endmacro()

function(_qt_internal_extend_qml_import_paths import_paths_var)
    set(local_var ${${import_paths_var}})

    # prepend extra import path which is a current module's build dir: we need
    # this to ensure correct importing of QML modules when having a prefix-build
    # with QLibraryInfo::path(QLibraryInfo::QmlImportsPath) pointing to the
    # install location
    if(QT_BUILDING_QT AND QT_WILL_INSTALL)
        list(PREPEND local_var -I "${QT_BUILD_DIR}/${INSTALL_QMLDIR}")
    endif()

    set(${import_paths_var} ${local_var} PARENT_SCOPE)
endfunction()

function(_qt_internal_target_enable_qmllint target)
    set(lint_target ${target}_qmllint)
    set(lint_target_json ${target}_qmllint_json)
    if(TARGET ${lint_target} OR TARGET ${target}_qmllint_json)
        return()
    endif()

    _qt_internal_genex_getproperty(qmllint_files ${target} QT_QML_LINT_FILES)
    _qt_internal_genex_getjoinedproperty(import_args ${target}
        QT_QML_IMPORT_PATH "-I$<SEMICOLON>" "$<SEMICOLON>"
    )
    _qt_internal_genex_getjoinedproperty(qrc_args ${target}
        _qt_generated_qrc_files "--resource$<SEMICOLON>" "$<SEMICOLON>"
    )

    # Facilitate self-import so it can find the qmldir file. We also try to walk
    # back up the directory structure to find a base path under which this QML
    # module is located. Such a base path is likely to be used for other QML
    # modules that we might need to find, so add it to the import path if we
    # find a compatible directory structure. It doesn't make sense to do this
    # for an executable though, since it can never be found as a QML module for
    # a different QML module/target.
    get_target_property(target_type ${target} TYPE)
    get_target_property(is_android_executable ${target} _qt_is_android_executable)
    if(target_type STREQUAL "EXECUTABLE" OR is_android_executable)
        # The executable's own QML module's qmldir file will usually be under a
        # subdirectory (matching the module's target path) below the target's
        # build directory.
        list(APPEND import_args -I "$<TARGET_PROPERTY:${target},BINARY_DIR>")
    elseif(target_type MATCHES "LIBRARY")
        get_target_property(output_dir  ${target} QT_QML_MODULE_OUTPUT_DIRECTORY)
        get_target_property(target_path ${target} QT_QML_MODULE_TARGET_PATH)
        if(output_dir MATCHES "${target_path}$")
            string(REGEX REPLACE "(.*)/${target_path}" "\\1" base_dir "${output_dir}")
            list(APPEND import_args -I "${base_dir}")
        else()
            message(WARNING
                "The ${target} target is a QML module with target path ${target_path}. "
                "It uses an OUTPUT_DIRECTORY of ${output_dir}, which should end in the "
                "same target path, but doesn't. Tooling such as qmllint may not work "
                "correctly."
            )
        endif()
    endif()

    if(NOT "${QT_QML_OUTPUT_DIRECTORY}" STREQUAL "")
        list(APPEND import_args -I "${QT_QML_OUTPUT_DIRECTORY}")
    endif()

    _qt_internal_extend_qml_import_paths(import_args)

    set(cmd
        ${QT_TOOL_COMMAND_WRAPPER_PATH}
        ${QT_CMAKE_EXPORT_NAMESPACE}::qmllint
        ${import_args}
        ${qrc_args}
        ${qmllint_files}
    )

    # We need this target to depend on all qml type registrations. This is the
    # only way we can be sure that all *.qmltypes files for any QML modules we
    # depend on will have been generated.
    add_custom_target(${lint_target}
        COMMAND "$<${have_qmllint_files}:${cmd}>"
        COMMAND_EXPAND_LISTS
        DEPENDS
            ${QT_CMAKE_EXPORT_NAMESPACE}::qmllint
            ${qmllint_files}
            $<TARGET_NAME_IF_EXISTS:all_qmltyperegistrations>
        WORKING_DIRECTORY "$<TARGET_PROPERTY:${target},SOURCE_DIR>"
    )

    add_custom_target(${lint_target_json}
        COMMAND "$<${have_qmllint_files}:${cmd}>" --json ${CMAKE_BINARY_DIR}/${lint_target}.json
        COMMAND_EXPAND_LISTS
        DEPENDS
            ${QT_CMAKE_EXPORT_NAMESPACE}::qmllint
            ${qmllint_files}
            $<TARGET_NAME_IF_EXISTS:all_qmltyperegistrations>
        WORKING_DIRECTORY "$<TARGET_PROPERTY:${target},SOURCE_DIR>"
    )

   set_target_properties(${lint_target_json} PROPERTIES EXCLUDE_FROM_ALL TRUE)

    # Make the global linting target depend on the one we add here.
    # Note that the caller is free to change the value of QT_QMLLINT_ALL_TARGET
    # for different QML modules if they wish, which means they can implement
    # their own grouping of the ${target}_qmllint targets.
    if("${QT_QMLLINT_ALL_TARGET}" STREQUAL "")
        set(QT_QMLLINT_ALL_TARGET all_qmllint)
    endif()
    if(NOT TARGET ${QT_QMLLINT_ALL_TARGET})
        add_custom_target(${QT_QMLLINT_ALL_TARGET})
    endif()
    add_dependencies(${QT_QMLLINT_ALL_TARGET} ${lint_target})

    if("${QT_QMLLINT_JSON_ALL_TARGET}" STREQUAL "")
        set(QT_QMLLINT_JSON_ALL_TARGET all_qmllint_json)
    endif()
    if(NOT TARGET ${QT_QMLLINT_JSON_ALL_TARGET})
        add_custom_target(${QT_QMLLINT_JSON_ALL_TARGET})
    endif()
    add_dependencies(${QT_QMLLINT_JSON_ALL_TARGET} ${lint_target_json})

endfunction()

# This is a  modified version of __qt_propagate_generated_resource from qtbase.
#
# It uses a common __qt_internal_propagate_object_library function to link and propagate the object
# library to the end-point executable.
#
# The reason for propagating the qmlcache target as a 'fake resource' from the build system
# perspective is to ensure proper handling of the object files in generated qmake .prl files.
function(_qt_internal_propagate_qmlcache_object_lib
         target
         generated_source_code
         link_condition
         output_generated_target)
    set(resource_target "${target}_qmlcache")
    qt6_add_library("${resource_target}" OBJECT "${generated_source_code}")

    # Needed to trigger the handling of the object library for .prl generation.
    set_property(TARGET ${resource_target} APPEND PROPERTY _qt_resource_name ${resource_target})

    # Export info that this is a qmlcache target, in case if we ever need to detect such targets,
    # similar how we need it for plugin initializers.
    set_property(TARGET ${resource_target} PROPERTY _is_qt_qmlcache_target TRUE)
    set_property(TARGET ${resource_target} APPEND PROPERTY
        EXPORT_PROPERTIES _is_qt_qmlcache_target
    )

    # Save the path to the generated source file, relative to the the current build dir.
    # The path will be used in static library prl file generation to ensure qmake links
    # against the installed resource object files.
    # Example saved path:
    #    .rcc/qrc_qprintdialog.cpp
    file(RELATIVE_PATH generated_cpp_file_relative_path
        "${CMAKE_CURRENT_BINARY_DIR}"
        "${generated_source_code}")
    set_property(TARGET ${resource_target} APPEND PROPERTY
        _qt_resource_generated_cpp_relative_path "${generated_cpp_file_relative_path}")

    # Qml specific additions.
    target_link_libraries(${resource_target} PRIVATE
        ${QT_CMAKE_EXPORT_NAMESPACE}::QmlPrivate
        ${QT_CMAKE_EXPORT_NAMESPACE}::Core
    )

    __qt_internal_propagate_object_library(${target} ${resource_target}
        EXTRA_CONDITIONS "${link_condition}"
    )

    set(${output_generated_target} "${resource_target}" PARENT_SCOPE)
endfunction()

function(_qt_internal_target_enable_qmlcachegen target output_targets_var qmlcachegen)

    set(output_targets)
    set_target_properties(${target} PROPERTIES _qt_cachegen_set_up TRUE)

    get_target_property(target_binary_dir ${target} BINARY_DIR)
    set(qmlcache_dir ${target_binary_dir}/.rcc/qmlcache)
    set(qmlcache_resource_name qmlcache_${target})

    # INTEGRITY_SYMBOL_UNIQUENESS
    # The cache loader file name has to be unique, because the Integrity compiler uses the file name
    # for the generation of the translation unit static constructor symbol name.
    #    e.g. __sti___19_qmlcache_loader_cpp_11acedbd
    # For some reason the symbol is created with global visibility.
    #
    # When an application links against the Basic and Fusion static qml plugins, the linker
    # fails with duplicate symbol errors because both of those plugins will contain the same symbol.
    #
    # With gcc on regular Linux, the symbol names are also the same, but it's not a problem because
    # they have local (hidden) visbility.
    #
    # Make the file name unique by prepending the target name.
    set(qmlcache_loader_cpp ${qmlcache_dir}/${target}_qmlcache_loader.cpp)

    set(qmlcache_loader_list ${qmlcache_dir}/${target}_qml_loader_file_list.rsp)
    set(qmlcache_resource_paths "$<TARGET_PROPERTY:${target},QT_QML_MODULE_RESOURCE_PATHS>")

    _qt_internal_genex_getjoinedproperty(qrc_resource_args ${target}
        _qt_generated_qrc_files "--resource$<SEMICOLON>" "$<SEMICOLON>"
    )

    if(CMAKE_GENERATOR STREQUAL "Ninja Multi-Config" AND CMAKE_VERSION VERSION_GREATER_EQUAL "3.20")
        set(qmlcachegen "$<COMMAND_CONFIG:${qmlcachegen}>")
    endif()
    set(cmd
        ${QT_TOOL_COMMAND_WRAPPER_PATH}
        ${qmlcachegen}
        --resource-name "${qmlcache_resource_name}"
        ${qrc_resource_args}
        -o "${qmlcache_loader_cpp}"
        "@${qmlcache_loader_list}"
    )

    file(GENERATE
        OUTPUT ${qmlcache_loader_list}
        CONTENT "$<JOIN:${qmlcache_resource_paths},\n>\n"
    )

    add_custom_command(
        OUTPUT ${qmlcache_loader_cpp}
        COMMAND "${cmd}"
        COMMAND_EXPAND_LISTS
        DEPENDS
            ${qmlcachegen}
            ${qmlcache_loader_list}
            $<TARGET_PROPERTY:${target},_qt_generated_qrc_files>
        VERBATIM
    )

    # The current scope sees the file as generated automatically, but the
    # target scope may not if it is different. Force it where we can.
    if(CMAKE_VERSION VERSION_GREATER_EQUAL "3.18")
        set_source_files_properties(
            ${qmlcache_loader_cpp}
            TARGET_DIRECTORY ${target}
            PROPERTIES GENERATED TRUE
        )
    endif()
    get_target_property(target_source_dir ${target} SOURCE_DIR)
    if(NOT target_source_dir STREQUAL CMAKE_CURRENT_SOURCE_DIR)
        add_custom_target(${target}_qmlcachegen DEPENDS ${qmlcache_loader_cpp})
        add_dependencies(${target} ${target}_qmlcachegen)
    endif()

    # TODO: Probably need to reject ${target} being an object library as unsupported
    get_target_property(target_type ${target} TYPE)
    if(target_type STREQUAL "STATIC_LIBRARY")
        set(extra_conditions "")
        _qt_internal_propagate_qmlcache_object_lib(
            ${target}
            "${qmlcache_loader_cpp}"
            "${extra_conditions}"
            output_target)

        list(APPEND output_targets ${output_target})
    else()
        target_sources(${target} PRIVATE "${qmlcache_loader_cpp}")
        target_link_libraries(${target} PRIVATE
            ${QT_CMAKE_EXPORT_NAMESPACE}::QmlPrivate
            ${QT_CMAKE_EXPORT_NAMESPACE}::Core
        )
    endif()

    set(${output_targets_var} ${output_targets} PARENT_SCOPE)
endfunction()

# We cannot defer writing out the qmldir file to generation time because the
# qmlimportscanner runs at configure time as part of target finalizers.
# Therefore, the best we can do is defer writing the qmldir file if we are
# using a recent enough CMake version, otherwise we write it out progressively
# on each call that adds qml sources. The immediate progressive writes will
# trigger some unnecessary rebuilds after reconfiguring due to the qmldir
# file's timestamp being updated even though its contents might not change,
# but that's the cost of not having deferred write capability.
function(_qt_internal_target_generate_qmldir target)

    macro(_qt_internal_qmldir_item prefix property)
        get_target_property(_value ${target} ${property})
        if(_value)
            string(APPEND content "${prefix} ${_value}\n")
        endif()
    endmacro()

    macro(_qt_internal_qmldir_item_list prefix property)
        get_target_property(_values ${target} ${property})
        if(_values)
            foreach(_value IN LISTS _values)
                string(APPEND content "${prefix} ${_value}\n")
            endforeach()
        endif()
    endmacro()

    get_target_property(uri ${target} QT_QML_MODULE_URI)
    if(NOT uri)
        message(FATAL_ERROR "Target ${target} has no URI set, cannot create qmldir")
    endif()
    set(content "module ${uri}\n")

    _qt_internal_qmldir_item(linktarget QT_QML_MODULE_INSTALLED_PLUGIN_TARGET)

    get_target_property(plugin_target ${target} QT_QML_MODULE_PLUGIN_TARGET)
    if(plugin_target)
        get_target_property(no_plugin_optional ${target} QT_QML_MODULE_NO_PLUGIN_OPTIONAL)
        if(NOT no_plugin_optional MATCHES "NOTFOUND" AND NOT no_plugin_optional)
            string(APPEND content "optional ")
        endif()

        get_target_property(target_path ${target} QT_QML_MODULE_TARGET_PATH)
        _qt_internal_get_qml_plugin_output_name(plugin_output_name ${plugin_target}
            TARGET_PATH "${target_path}"
            URI "${uri}"
        )
        string(APPEND content "plugin ${plugin_output_name}\n")

        _qt_internal_qmldir_item(classname QT_QML_MODULE_CLASS_NAME)
    endif()

    get_target_property(designer_supported ${target} QT_QML_MODULE_DESIGNER_SUPPORTED)
    if(designer_supported)
        string(APPEND content "designersupported\n")
    endif()

    get_target_property(static_module ${target} QT_QML_MODULE_IS_STATIC)
    if (static_module)
       string(APPEND content "static\n")
    endif()

    get_target_property(system_module ${target} QT_QML_MODULE_IS_SYSTEM)
    if (system_module)
       string(APPEND content "system\n")
    endif()

    _qt_internal_qmldir_item(typeinfo QT_QML_MODULE_TYPEINFO)

    _qt_internal_qmldir_item_list(import QT_QML_MODULE_IMPORTS)
    _qt_internal_qmldir_item_list("optional import" QT_QML_MODULE_OPTIONAL_IMPORTS)
    _qt_internal_qmldir_item_list("default import" QT_QML_MODULE_DEFAULT_IMPORTS)

    _qt_internal_qmldir_item_list(depends QT_QML_MODULE_DEPENDENCIES)

    get_target_property(prefix ${target} QT_QML_MODULE_RESOURCE_PREFIX)
    if(prefix)
        # Ensure we use a path that ends with a "/", but handle the special case
        # of "/" without anything after it
        if(NOT prefix STREQUAL "/" AND NOT prefix MATCHES "/$")
            string(APPEND prefix "/")
        endif()
        string(APPEND content "prefer :${prefix}\n")
    endif()

    # TODO: What about multi-config generators? Would we need per-config qmldir
    #       files (because we will have per-config plugin targets)?

    # Record the contents but defer the actual write. We will write the file
    # later, either at the end of qt6_add_qml_module() or the end of the
    # directory scope (depending on the CMake version being used).
    set_property(TARGET ${target} PROPERTY _qt_internal_qmldir_content "${content}")

    # NOTE: qt6_target_qml_sources() may append further content later.
endfunction()

function(_qt_internal_write_deferred_qmldir_file target)
    get_target_property(__qt_qmldir_content ${target} _qt_internal_qmldir_content)
    get_target_property(out_dir ${target} QT_QML_MODULE_OUTPUT_DIRECTORY)
    set(qmldir_file "${out_dir}/qmldir")
    configure_file(${__qt_qml_macros_module_base_dir}/Qt6qmldirTemplate.cmake.in ${qmldir_file} @ONLY)
endfunction()

# With a macOS framework Qt build, moc needs to be passed -F<qt-framework-path>
# arguments to resolve framework style includes like #include <QtCore/qobject.h>
# Extract the location of the Qt frameworks by querying the imported location of
# the target (where target is a Qt library). Do not care about non-Qt targets.
function(_qt_internal_qml_get_qt_framework_path target out_var)
    set(value "")
    # NOTE: only exercise IMPORTED_LOCATION of various flavors. this seems to be
    # good enough in other places (e.g. when locating qmlimportscanner)
    get_target_property(target_path ${target} IMPORTED_LOCATION)
    if(NOT target_path)
        set(configs "RELWITHDEBINFO;RELEASE;MINSIZEREL;DEBUG")
        foreach(config ${configs})
            get_target_property(target_path ${target} IMPORTED_LOCATION_${config})
            # NOTE: to be fair, any location is good enough. the macro
            # definitions we need must not vary between configurations
            if(target_path)
                break()
            endif()
        endforeach()
    endif()
    string(REGEX REPLACE "(.*)/Qt[^/]+\\.framework.*" "\\1" target_fw_path "${target_path}")
    if(target_fw_path)
        set(value "${target_fw_path}")
    endif()
    set(${out_var} "${value}" PARENT_SCOPE)
endfunction()

function(_qt_internal_qml_get_qt_framework_path_moc_option target out_var)
    _qt_internal_qml_get_qt_framework_path(${target} target_fw_path)
    if(target_fw_path)
        set(${out_var} "-F${target_fw_path}" PARENT_SCOPE)
    else()
        set(${out_var} "" PARENT_SCOPE)
    endif()
endfunction()

# Compile Qml files (.qml) to C++ source files with Qml Type Compiler (qmltc).
function(qt6_target_compile_qml_to_cpp target)
    set(args_option "")
    set(args_single NAMESPACE)
    set(args_multi QML_FILES IMPORT_PATHS)

    cmake_parse_arguments(PARSE_ARGV 1 arg
        "${args_option}" "${args_single}" "${args_multi}"
    )
    if(arg_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR "Unknown/unexpected arguments: ${arg_UNPARSED_ARGUMENTS}")
    endif()

    if (NOT arg_QML_FILES)
        message(FATAL_ERROR "FILES option not given or contains empty list for target ${target}")
    endif()

    if(NOT TARGET "${target}")
        message(FATAL_ERROR "\"${target}\" is not a known target")
    endif()

    get_target_property(prefix ${target} QT_QML_MODULE_RESOURCE_PREFIX)
    if (NOT prefix)
        message(FATAL_ERROR
                "Target is not a QML module? QT_QML_MODULE_RESOURCE_PREFIX is unspecified")
    endif()
    if(NOT prefix MATCHES [[/$]])
        string(APPEND prefix "/")
    endif()

    get_target_property(target_source_dir ${target} SOURCE_DIR)
    get_target_property(target_binary_dir ${target} BINARY_DIR)

    set(generated_sources_other_scope)

    set(compiled_files) # compiled files list to be used to generate MOC C++
    set(non_qml_files) # non .qml files to warn about
    set(qmltc_executable "$<TARGET_FILE:${QT_CMAKE_EXPORT_NAMESPACE}::qmltc>")
    if(CMAKE_GENERATOR STREQUAL "Ninja Multi-Config" AND CMAKE_VERSION VERSION_GREATER_EQUAL "3.20")
        set(qmltc_executable "$<COMMAND_CONFIG:${qmltc_executable}>")
    endif()

    set(common_args "")
    if(arg_NAMESPACE)
        list(APPEND common_args --namespace "${arg_NAMESPACE}")
    endif()

    get_target_property(output_dir ${target} QT_QML_MODULE_OUTPUT_DIRECTORY)
    set(qmldir_file ${output_dir}/qmldir)
    # TODO: we still need to specify the qmldir here for _explicit_ imports of
    # own module. in theory this could be pushed to the user side
    list(APPEND common_args "-i" ${qmldir_file})

    foreach(import_path IN LISTS arg_IMPORT_PATHS)
        list(APPEND common_args -I "${import_path}")
    endforeach()

    _qt_internal_extend_qml_import_paths(common_args)

    # we explicitly depend on qmldir (due to `-i ${qmldir_file}`) but also
    # implicitly on the generated qmltypes file, which is a part of qmldir
    set(qml_module_files)
    list(APPEND qml_module_files ${qmldir_file})
    get_target_property(qmltypes_file ${target} QT_QML_MODULE_TYPEINFO)
    if(qmltypes_file)
        list(APPEND qml_module_files ${output_dir}/${qmltypes_file})
    endif()

    get_target_property(potential_qml_modules ${target} LINK_LIBRARIES)
    foreach(lib ${potential_qml_modules})
        if(NOT TARGET ${lib})
            continue()
        endif()

        # if we have a versionless Qt lib, find the public one with a version
        if(lib MATCHES "^Qt::(.*)")
            set(lib "${CMAKE_MATCH_1}")
            if(lib MATCHES "^(.*)Private") # remove "Private"
                set(lib "${CMAKE_MATCH_1}")
            endif()
            set(lib ${QT_CMAKE_EXPORT_NAMESPACE}::${lib})
            if(NOT TARGET ${lib})
                continue()
            endif()
        endif()

        # when we have a suitable lib, ignore INTERFACE_LIBRARY and IMPORTED
        get_target_property(lib_type ${lib} TYPE)
        get_target_property(lib_is_imported ${lib} IMPORTED)
        if(lib_type STREQUAL "INTERFACE_LIBRARY" OR lib_is_imported)
            continue()
        endif()

        # get any QT_QML_MODULE_ property, this way we can tell whether we deal
        # with QML module target or not. use output dir as it's used later
        get_target_property(external_output_dir ${lib} QT_QML_MODULE_OUTPUT_DIRECTORY)
        if(NOT external_output_dir) # not a QML module, so not interesting
            continue()
        endif()

        get_target_property(external_qmltypes_file ${lib} QT_QML_MODULE_TYPEINFO)
        if(external_qmltypes)
            # add linked module's qmltypes file to a list of target
            # dependencies. unlike qmllint or other tooling, qmltc only cares
            # about explicitly linked libraries. things like plugins are not
            # supported by design and would result in C++ compilation errors
            list(APPEND qml_module_files ${external_output_dir}/${external_qmltypes_file})
        endif()
    endforeach()

    # qmltc needs qrc files to supply to the QQmlJSResourceFileMapper
    _qt_internal_genex_getjoinedproperty(qrc_args ${target}
        _qt_generated_qrc_files "--resource$<SEMICOLON>" "$<SEMICOLON>"
    )
    list(APPEND common_args ${qrc_args})

    foreach(qml_file_src IN LISTS arg_QML_FILES)
        if(NOT qml_file_src MATCHES "\\.(qml)$")
            list(APPEND non_qml_files ${qml_file_src})
            continue()
        endif()

        get_filename_component(file_absolute ${qml_file_src} ABSOLUTE)

        get_filename_component(file_basename ${file_absolute} NAME_WLE) # extension is always .qml
        string(REGEX REPLACE "[$#?]+" "_" compiled_file ${file_basename})
        string(TOLOWER ${compiled_file} file_name)

        # NB: use <lowercase(file_name)>.<extension> pattern. if
        # lowercase(file_name) is already taken (e.g. project has main.qml and
        # main.h/main.cpp), the compilation might fail. in this case, expect
        # user to specify QT_QMLTC_FILE_BASENAME
        get_source_file_property(specified_file_name ${qml_file_src} QT_QMLTC_FILE_BASENAME)
        if (specified_file_name)
            get_filename_component(file_name ${specified_file_name} NAME_WLE)
        endif()

        # Note: add '${target}' to path to avoid potential conflicts where 2+
        # distinct targets use the same ${target_binary_dir}/.qmltc/ output dir
        set(compiled_header "${target_binary_dir}/.qmltc/${target}/${file_name}.h")
        set(compiled_cpp "${target_binary_dir}/.qmltc/${target}/${file_name}.cpp")
        get_filename_component(out_dir ${compiled_header} DIRECTORY)

        add_custom_command(
            OUTPUT ${compiled_header} ${compiled_cpp}
            COMMAND ${CMAKE_COMMAND} -E make_directory ${out_dir}
            COMMAND
                ${QT_TOOL_COMMAND_WRAPPER_PATH}
                ${qmltc_executable}
                --header "${compiled_header}"
                --impl "${compiled_cpp}"
                ${common_args}
                ${file_absolute}
            COMMAND_EXPAND_LISTS
            DEPENDS
                ${qmltc_executable}
                "${file_absolute}"
                ${qml_module_files}
                $<TARGET_PROPERTY:${target},_qt_generated_qrc_files>
            VERBATIM
        )

        set_source_files_properties(${compiled_header} ${compiled_cpp}
            PROPERTIES SKIP_AUTOGEN ON
                       SKIP_UNITY_BUILD_INCLUSION ON)
        target_sources(${target} PRIVATE ${compiled_header} ${compiled_cpp})
        target_include_directories(${target} PUBLIC ${out_dir})
        # The current scope automatically sees the file as generated, but the
        # target scope may not if it is different. Force it where we can.
        # We will also have to add the generated file to a target in this
        # scope at the end to ensure correct dependencies.
        if(NOT target_source_dir STREQUAL CMAKE_CURRENT_SOURCE_DIR)
            if(CMAKE_VERSION VERSION_GREATER_EQUAL "3.18")
                list(APPEND generated_sources_other_scope ${compiled_header} ${compiled_cpp})
            endif()
        endif()

        list(APPEND compiled_files ${compiled_header})
    endforeach()

    set(extra_moc_options "")
    if(APPLE AND QT_FEATURE_framework)
        # this is a special case, where we need -F options passed to manual moc.
        # since we're in qmltc code, we only ever need to check QtCore and QtQml
        # for framework path
        list(APPEND link_libs ${QT_CMAKE_EXPORT_NAMESPACE}::Core ${QT_CMAKE_EXPORT_NAMESPACE}::Qml)
        foreach(lib ${link_libs})
            _qt_internal_qml_get_qt_framework_path_moc_option(${lib} moc_option)
            if(moc_option)
                list(APPEND extra_moc_options ${moc_option})
            endif()
        endforeach()
    endif()

    # run MOC manually for the generated files
    qt6_wrap_cpp(compiled_moc_files ${compiled_files} TARGET ${target} OPTIONS ${extra_moc_options})
    set_source_files_properties(${compiled_moc_files} PROPERTIES SKIP_AUTOGEN ON
                                                                 SKIP_UNITY_BUILD_INCLUSION ON)
    target_sources(${target} PRIVATE ${compiled_moc_files})
    if(NOT target_source_dir STREQUAL CMAKE_CURRENT_SOURCE_DIR)
        if(CMAKE_VERSION VERSION_GREATER_EQUAL "3.18")
            set_source_files_properties(${generated_sources_other_scope} ${compiled_moc_files}
                TARGET_DIRECTORY ${target}
                PROPERTIES
                    SKIP_AUTOGEN TRUE
                    GENERATED TRUE
            )
        endif()

        if(NOT TARGET ${target}_tooling)
            message(FATAL_ERROR
                    "${target}_tooling is not found, although it should be in this function.")
        endif()
        # adding sources to ${target}_tooling would ensure that these sources
        # become a dependency of ${target} in this weird case that we have.
        # add_dependencies() for ${target} and ${target}_tooling must have been
        # added as part of qt_add_qml_module() command run.
        target_sources(${target}_tooling PRIVATE
            ${generated_sources_other_scope} ${compiled_moc_files}
        )
    endif()

    if(non_qml_files)
        list(JOIN non_qml_files "\n  " file_list)
        message(WARNING
            "Only .qml files should be added with this function. "
            "The following files were not processed:"
            "\n  ${file_list}"
        )
    endif()

endfunction()

if(NOT QT_NO_CREATE_VERSIONLESS_FUNCTIONS)
    function(qt_target_compile_qml_to_cpp)
        qt6_target_compile_qml_to_cpp(${ARGV})
    endfunction()
endif()

function(qt6_add_qml_plugin target)
    set(args_option
        STATIC
        SHARED
        NO_GENERATE_PLUGIN_SOURCE
    )

    set(args_single
        OUTPUT_DIRECTORY
        URI
        BACKING_TARGET
        CLASS_NAME
        NAMESPACE
        # The following is only needed on Android, and even then, only if the
        # default conversion from the URI is not applicable. It is an internal
        # option, it may be removed.
        TARGET_PATH
    )

    set(args_multi "")

    cmake_parse_arguments(PARSE_ARGV 1 arg
       "${args_option}"
       "${args_single}"
       "${args_multi}"
    )

    if(arg_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR "Unexpected arguments: ${arg_UNPARSED_ARGUMENTS}")
    endif()

    if(NOT arg_URI)
        if(NOT arg_BACKING_TARGET)
            message(FATAL_ERROR "No URI or BACKING_TARGET provided")
        endif()
        if(NOT TARGET ${arg_BACKING_TARGET})
            if(arg_BACKING_TARGET STREQUAL target)
                message(FATAL_ERROR
                    "Plugin ${target} is its own backing target, URI must be provided"
                )
            else()
                message(FATAL_ERROR
                    "No URI provided and unable to obtain it from the BACKING_TARGET "
                    "(${arg_BACKING_TARGET}) because no such target exists"
                )
            endif()
        endif()
        get_target_property(arg_URI ${arg_BACKING_TARGET} QT_QML_MODULE_URI)
        if(NOT arg_URI)
            message(FATAL_ERROR
                "No URI provided and the BACKING_TARGET (${arg_BACKING_TARGET}) "
                "does not have one set either"
            )
        endif()
    endif()

    # TODO: Probably should remove TARGET_PATH as a supported keyword now
    if(NOT arg_TARGET_PATH AND TARGET "${arg_BACKING_TARGET}")
        get_target_property(arg_TARGET_PATH ${arg_BACKING_TARGET} QT_QML_MODULE_TARGET_PATH)
    endif()
    if(NOT arg_TARGET_PATH)
        string(REPLACE "." "/" arg_TARGET_PATH "${arg_URI}")
    endif()

    _qt_internal_get_escaped_uri("${arg_URI}" escaped_uri)

    if(NOT arg_CLASS_NAME)
        if(NOT "${arg_BACKING_TARGET}" STREQUAL "")
            get_target_property(arg_CLASS_NAME ${target} QT_QML_MODULE_CLASS_NAME)
        endif()
        if(NOT arg_CLASS_NAME)
            _qt_internal_compute_qml_plugin_class_name_from_uri("${arg_URI}" arg_CLASS_NAME)
        endif()
    endif()

    if(TARGET ${target})
        # Plugin target already exists. Perform a few sanity checks, but we
        # otherwise trust that the target is appropriate for use as a plugin.
        get_target_property(target_type ${target} TYPE)
        if(target_type STREQUAL "EXECUTABLE")
            message(FATAL_ERROR "Plugins cannot be executables (target: ${target})")
        endif()
        foreach(arg IN ITEMS STATIC SHARED)
            if(arg_${arg})
                message(FATAL_ERROR
                    "Cannot specify ${arg} keyword, target ${target} already exists"
                )
            endif()
        endforeach()

        get_target_property(existing_class_name ${target} QT_PLUGIN_CLASS_NAME)
        if(existing_class_name)
            if(NOT existing_class_name STREQUAL arg_CLASS_NAME)
                message(FATAL_ERROR
                    "An existing plugin target was given, but it has a different class name "
                    "(${existing_class_name}) to that being used here (${arg_CLASS_NAME})"
                )
            endif()
        elseif(arg_CLASS_NAME)
            set_property(TARGET ${target} PROPERTY QT_PLUGIN_CLASS_NAME "${arg_CLASS_NAME}")
        else()
            message(FATAL_ERROR
                "An existing '${target}' plugin target was given, but it has no class name set "
                "and no new class name was provided."
            )
        endif()
    else()
        if(arg_STATIC AND arg_SHARED)
            message(FATAL_ERROR
                "Cannot specify both STATIC and SHARED for target ${target}"
            )
        endif()
        set(lib_type "")
        if(arg_STATIC)
            set(lib_type STATIC)
        elseif(arg_SHARED)
            set(lib_type SHARED)
        endif()

        if(TARGET "${arg_BACKING_TARGET}")
            # Ensure that the plugin type we create will be compatible with the
            # type of backing target we were given
            get_target_property(backing_type ${arg_BACKING_TARGET} TYPE)
            if(backing_type STREQUAL "STATIC_LIBRARY")
                if(lib_type STREQUAL "")
                    set(lib_type STATIC)
                elseif(lib_type STREQUAL "SHARED")
                    message(FATAL_ERROR
                        "Mixing a static backing library with a non-static plugin "
                        "is not supported"
                    )
                endif()
            elseif(backing_type STREQUAL "SHARED_LIBRARY")
                if(lib_type STREQUAL "")
                    set(lib_type SHARED)
                elseif(lib_type STREQUAL "STATIC")
                    message(FATAL_ERROR
                        "Mixing a non-static backing library with a static plugin "
                        "is not supported"
                    )
                endif()
            elseif(backing_type STREQUAL "EXECUTABLE")
                message(FATAL_ERROR
                    "A separate plugin should not be needed when the backing target "
                    "is an executable. Pre-create the plugin target before calling "
                    "this command if you really must have a separate plugin."
                )
            else()
                # Object libraries, utility/custom targets
                message(FATAL_ERROR "Unsupported backing target type: ${backing_type}")
            endif()
        endif()

        qt6_add_plugin(${target} ${lib_type}
            PLUGIN_TYPE qml_plugin
            CLASS_NAME ${arg_CLASS_NAME}
        )
    endif()

    # Ignore any CMAKE_INSTALL_RPATH and set a better default RPATH on platforms
    # that support it, if allowed. Projects will often set CMAKE_INSTALL_RPATH
    # for executables or backing libraries, but forget about plugins. Because
    # the path for QML plugins depends on their URI, it is unlikely that
    # CMAKE_INSTALL_RPATH would ever be intended for use with QML plugins.
    if(NOT WIN32 AND NOT QT_NO_QML_PLUGIN_RPATH)
        # Construct a relative path from a default install location (assumed to
        # be qml/target-path) to ${CMAKE_INSTALL_LIBDIR}. This would be
        # applicable for Apple too (although unusual) if this is a bare install
         # (i.e. not part of an app bundle).
        string(REPLACE "/" ";" path "qml/${arg_TARGET_PATH}")
        list(LENGTH path path_count)
        string(REPEAT "../" ${path_count} rel_path)
        string(APPEND rel_path "${CMAKE_INSTALL_LIBDIR}")
        if(APPLE)
            set(install_rpath
                # If embedded in an app bundle, search in a bundle-local path
                # first. This path should always be the same for every app
                # bundle because plugin binaries should live in the PlugIns
                # directory, not a subdirectory of it or anywhere else.
                # Similarly, frameworks and bare shared libraries should always
                # be in the bundle's Frameworks directory.
                "@loader_path/../Frameworks"

                # This will be needed if the plugin is not installed as part of
                # an app bundle, such as when used by a command-line tool.
                "@loader_path/${rel_path}"
            )
        else()
            set(install_rpath "$ORIGIN/${rel_path}")
        endif()
        set_target_properties(${target} PROPERTIES INSTALL_RPATH "${install_rpath}")
    endif()

    get_target_property(moc_opts ${target} AUTOMOC_MOC_OPTIONS)
    set(already_set FALSE)
    if(moc_opts)
        foreach(opt IN LISTS moc_opts)
            if("${opt}" MATCHES "^-Muri=")
                set(already_set TRUE)
                break()
            endif()
        endforeach()
    endif()
    if(NOT already_set)
        # Insert the plugin's URI into its meta data to enable usage
        # of static plugins in QtDeclarative (like in mkspecs/features/qml_plugin.prf).
        set_property(TARGET ${target} APPEND PROPERTY
            AUTOMOC_MOC_OPTIONS "-Muri=${arg_URI}"
        )
    endif()

    if(ANDROID)
        _qt_internal_get_qml_plugin_output_name(plugin_output_name ${target}
            BACKING_TARGET "${arg_BACKING_TARGET}"
            TARGET_PATH "${arg_TARGET_PATH}"
            URI "${arg_URI}"
        )
        set_target_properties(${target}
            PROPERTIES
            LIBRARY_OUTPUT_NAME "${plugin_output_name}"
        )
        qt6_android_apply_arch_suffix(${target})
    endif()

    if(NOT arg_OUTPUT_DIRECTORY AND arg_BACKING_TARGET AND TARGET ${arg_BACKING_TARGET})
        get_target_property(arg_OUTPUT_DIRECTORY ${arg_BACKING_TARGET} QT_QML_MODULE_OUTPUT_DIRECTORY)
    endif()
    if(arg_OUTPUT_DIRECTORY)
        # Plugin target must be in the output directory. The backing target,
        # if it is different to the plugin target, can be anywhere.
        set_target_properties(${target} PROPERTIES
            RUNTIME_OUTPUT_DIRECTORY ${arg_OUTPUT_DIRECTORY}
            LIBRARY_OUTPUT_DIRECTORY ${arg_OUTPUT_DIRECTORY}
            ARCHIVE_OUTPUT_DIRECTORY ${arg_OUTPUT_DIRECTORY}
        )
    endif()

    if(NOT arg_NO_GENERATE_PLUGIN_SOURCE)
        set(generated_cpp_file_name_base "${target}_${arg_CLASS_NAME}")
        set(register_types_function_name "qml_register_types_${escaped_uri}")

        # These are all substituted in the template file used further below
        set(qt_qml_plugin_class_name "${arg_CLASS_NAME}")
        set(qt_qml_plugin_moc_include_name "${generated_cpp_file_name_base}.moc")
        set(qt_qml_plugin_intro "")
        set(qt_qml_plugin_outro "")
        if (arg_NAMESPACE)
            string(APPEND qt_qml_plugin_intro "namespace ${arg_NAMESPACE} {\n\n")
            string(APPEND qt_qml_plugin_outro "} // namespace ${arg_NAMESPACE}")
        endif()

        string(APPEND qt_qml_plugin_intro "extern void ${register_types_function_name}();\nQ_GHS_KEEP_REFERENCE(${register_types_function_name});")

        # Indenting here is deliberately different so as to make the generated
        # file have sensible indenting
        set(qt_qml_plugin_constructor_content
        "volatile auto registration = &${register_types_function_name};
        Q_UNUSED(registration);"
        )

        set(generated_cpp_file
            "${CMAKE_CURRENT_BINARY_DIR}/${generated_cpp_file_name_base}.cpp"
        )
        configure_file(
            "${__qt_qml_macros_module_base_dir}/Qt6QmlPluginTemplate.cpp.in"
            "${generated_cpp_file}"
            @ONLY
        )
        target_sources(${target} PRIVATE "${generated_cpp_file}")

        # The generated cpp file expects to include its moc-ed output file.
        set_target_properties(${target} PROPERTIES AUTOMOC TRUE)
    endif()

    target_link_libraries(${target} PRIVATE ${QT_CMAKE_EXPORT_NAMESPACE}::Qml)

    # Link plugin against its backing lib if it has one.
    if(NOT arg_BACKING_TARGET STREQUAL "" AND NOT arg_BACKING_TARGET STREQUAL target)
        target_link_libraries(${target} PRIVATE ${arg_BACKING_TARGET})
    endif()

    if(${CMAKE_VERSION} VERSION_GREATER_EQUAL "3.19.0")
        # Defer the collection of plugin dependencies until after any extra target_link_libraries
        # calls that a user project might do.
        # We wrap the deferred call with EVAL CODE
        # so that ${target} is evaluated now rather than the end of the scope.
        cmake_language(EVAL CODE
            "cmake_language(DEFER CALL _qt_internal_add_static_qml_plugin_dependencies \"${target}\" \"${arg_BACKING_TARGET}\")"
        )
    else()
        # Can't defer, have to do it now.
        _qt_internal_add_static_qml_plugin_dependencies("${target}" "${arg_BACKING_TARGET}")
    endif()
endfunction()

if(NOT QT_NO_CREATE_VERSIONLESS_FUNCTIONS)
    function(qt_add_qml_plugin)
        qt6_add_qml_plugin(${ARGV})
    endfunction()
endif()

function(qt6_target_qml_sources target)

    get_target_property(uri        ${target} QT_QML_MODULE_URI)
    get_target_property(output_dir ${target} QT_QML_MODULE_OUTPUT_DIRECTORY)
    if(NOT uri OR NOT output_dir)
        message(FATAL_ERROR "Target ${target} is not a QML module")
    endif()

    set(args_option
        NO_LINT
        NO_CACHEGEN
        NO_QMLDIR_TYPES
        __QT_INTERNAL_FORCE_DEFER_QMLDIR  # Used only by qt6_add_qml_module()
    )

    set(args_single
        PREFIX
        OUTPUT_TARGETS
    )

    set(args_multi
        QML_FILES
        RESOURCES
    )

    cmake_parse_arguments(PARSE_ARGV 1 arg
        "${args_option}" "${args_single}" "${args_multi}"
    )
    if(arg_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR "Unknown/unexpected arguments: ${arg_UNPARSED_ARGUMENTS}")
    endif()

    if (NOT arg_QML_FILES AND NOT arg_RESOURCES)
        if(arg_OUTPUT_TARGETS)
            set(${arg_OUTPUT_TARGETS} "" PARENT_SCOPE)
        endif()
        return()
    endif()

    if(NOT arg___QT_INTERNAL_FORCE_DEFER_QMLDIR AND ${CMAKE_VERSION} VERSION_LESS "3.19.0")
        message(FATAL_ERROR
            "You are using CMake ${CMAKE_VERSION}, but CMake 3.19 or later "
            "is required to add qml files with this function. Either pass "
            "the qml files to qt6_add_qml_module() instead or update to "
            "CMake 3.19 or later."
        )
    endif()

    get_target_property(no_lint                ${target} QT_QML_MODULE_NO_LINT)
    get_target_property(no_cachegen            ${target} QT_QML_MODULE_NO_CACHEGEN)
    get_target_property(no_qmldir              ${target} QT_QML_MODULE_NO_GENERATE_QMLDIR)
    get_target_property(resource_prefix        ${target} QT_QML_MODULE_RESOURCE_PREFIX)
    get_target_property(qml_module_version     ${target} QT_QML_MODULE_VERSION)
    get_target_property(past_major_versions    ${target} QT_QML_MODULE_PAST_MAJOR_VERSIONS)

    if(NOT output_dir)
        # Probably not a qml module. We still want to support tooling for this
        # scenario, it's just that we will be relying solely on the implicit
        # imports to find things.
        set(output_dir ${CMAKE_CURRENT_BINARY_DIR})
        set(no_qmldir TRUE)
    endif()

    if(NOT arg_PREFIX)
        if(resource_prefix)
            set(arg_PREFIX ${resource_prefix})
        else()
            message(FATAL_ERROR
                "PREFIX option not given and target ${target} does not have a "
                "QT_QML_MODULE_RESOURCE_PREFIX property set."
            )
        endif()
    endif()
    _qt_internal_canonicalize_resource_path("${arg_PREFIX}" arg_PREFIX)
    if(arg_PREFIX STREQUAL resource_prefix)
        set(prefix_override "")
    else()
        set(prefix_override "${arg_PREFIX}")
    endif()
    if(NOT arg_PREFIX STREQUAL "/")
        string(APPEND arg_PREFIX "/")
    endif()

    if (qml_module_version MATCHES "^([0-9]+)\\.")
        set(qml_module_files_versions "${CMAKE_MATCH_1}.0")
    else()
        message(FATAL_ERROR
            "No major version found in '${qml_module_version}'."
        )
    endif()
    if (past_major_versions OR past_major_versions STREQUAL "0")
        foreach (past_major_version ${past_major_versions})
            list(APPEND qml_module_files_versions "${past_major_version}.0")
        endforeach()
    endif()

    # Linting and cachegen can still occur for a target that isn't a qml module,
    # but for such targets, there is no qmldir file to update.
    if(arg_NO_LINT)
        set(no_lint TRUE)
    endif()
    if(arg_NO_CACHEGEN)
        set(no_cachegen TRUE)
    endif()
    if(no_qmldir MATCHES "NOTFOUND" OR arg_NO_QMLDIR_TYPES)
        set(no_qmldir TRUE)
    endif()

    if(NOT no_cachegen AND arg_QML_FILES)

        # Even if we don't generate a qmldir file, it still should be here, manually written.
        # We can pass it unconditionally. If it's not there, qmlcachegen or qmlsc might warn,
        # but that's not fatal.
        set(qmldir_file ${output_dir}/qmldir)

        _qt_internal_genex_getproperty(qmltypes_file ${target} QT_QML_MODULE_PLUGIN_TYPES_FILE)
        _qt_internal_genex_getproperty(qmlcachegen   ${target} QT_QMLCACHEGEN_EXECUTABLE)
        _qt_internal_genex_getproperty(direct_calls  ${target} QT_QMLCACHEGEN_DIRECT_CALLS)
        _qt_internal_genex_getjoinedproperty(arguments ${target}
            QT_QMLCACHEGEN_ARGUMENTS "$<SEMICOLON>" "$<SEMICOLON>"
        )
        _qt_internal_genex_getjoinedproperty(import_paths ${target}
            QT_QML_IMPORT_PATH "-I$<SEMICOLON>" "$<SEMICOLON>"
        )
        _qt_internal_genex_getjoinedproperty(qrc_resource_args ${target}
            _qt_generated_qrc_files "--resource$<SEMICOLON>" "$<SEMICOLON>"
        )
        get_target_property(target_type ${target} TYPE)
        get_target_property(is_android_executable ${target} _qt_is_android_executable)
        if(target_type STREQUAL "EXECUTABLE" OR is_android_executable)
            # The application binary directory is part of the default import path.
            list(APPEND import_paths -I "$<TARGET_PROPERTY:${target},BINARY_DIR>")
        endif()
        _qt_internal_extend_qml_import_paths(import_paths)
        set(cachegen_args
            ${import_paths}
            -i "${qmldir_file}"
            "$<${have_direct_calls}:--direct-calls>"
            "$<${have_arguments}:${arguments}>"
            ${qrc_resource_args}
        )

        # For direct evaluation in if() below
        get_target_property(cachegen_prop ${target} QT_QMLCACHEGEN_EXECUTABLE)
        if(cachegen_prop)
            if(cachegen_prop STREQUAL "qmlcachegen" OR cachegen_prop STREQUAL "qmlsc")
                # If it's qmlcachegen or qmlsc, don't go looking for other programs of that name
                set(qmlcachegen "$<TARGET_FILE:${QT_CMAKE_EXPORT_NAMESPACE}::${cachegen_prop}>")
            else()
                find_program(${target}_QMLCACHEGEN ${cachegen_prop})
                if(${target}_QMLCACHEGEN)
                    set(qmlcachegen "${${target}_QMLCACHEGEN}")
                else()
                    message(FATAL_ERROR "Invalid qmlcachegen binary ${cachegen_prop} for ${target}")
                endif()
            endif()
        else()
            set(have_qmlsc "$<TARGET_EXISTS:${QT_CMAKE_EXPORT_NAMESPACE}::qmlsc>")
            set(cachegen_name "$<IF:${have_qmlsc},qmlsc,qmlcachegen>")
            set(qmlcachegen "$<TARGET_FILE:${QT_CMAKE_EXPORT_NAMESPACE}::${cachegen_name}>")
        endif()
    endif()

    set(non_qml_files)
    set(output_targets)
    set(copied_files)

    # We want to set source file properties in the target's own scope if we can.
    # That's the canonical place the properties will be read from.
    if(CMAKE_VERSION VERSION_GREATER_EQUAL 3.18)
        set(scope_option TARGET_DIRECTORY ${target})
    else()
        set(scope_option "")
    endif()

    foreach(file_set IN ITEMS QML_FILES RESOURCES)
        foreach(file_src IN LISTS arg_${file_set})
            get_filename_component(file_absolute ${file_src} ABSOLUTE)

            # Store the original files so the project can query them later.
            set_property(TARGET ${target} APPEND PROPERTY
                QT_QML_MODULE_${file_set} ${file_absolute}
            )
            if(prefix_override)
                set_source_files_properties(${file_absolute} ${scope_option}
                    PROPERTIES
                        QT_QML_MODULE_PREFIX_OVERRIDE "${prefix_override}"
                )
            endif()

            # We need to copy the file to the build directory now so that when
            # qmlimportscanner is run in qt6_import_qml_plugins() as part of
            # target finalizers, the files will be there. We need to do this
            # in a way that CMake doesn't create a dependency on the source or it
            # will re-run CMake every time the file is modified. We also don't
            # want to update the file's timestamp if its contents won't change.
            # We still enforce the dependency on the source file by adding a
            # build-time rule. This avoids having to re-run CMake just to re-copy
            # the file.
            __qt_get_relative_resource_path_for_file(file_resource_path ${file_src})
            set(file_out ${output_dir}/${file_resource_path})

            # Don't generate or copy the file in an in-source build if the source
            # and destination paths are the same, it will cause a ninja dependency
            # cycle at build time.
            if(NOT file_out STREQUAL file_absolute)
                get_filename_component(file_out_dir ${file_out} DIRECTORY)
                file(MAKE_DIRECTORY ${file_out_dir})

                execute_process(COMMAND
                    ${CMAKE_COMMAND} -E copy_if_different ${file_absolute} ${file_out}
                )

                add_custom_command(OUTPUT ${file_out}
                    COMMAND ${CMAKE_COMMAND} -E copy ${file_src} ${file_out}
                    DEPENDS ${file_absolute}
                    WORKING_DIRECTORY $<TARGET_PROPERTY:${target},SOURCE_DIR>
                    VERBATIM
                )
                list(APPEND copied_files ${file_out})
            endif()
        endforeach()
    endforeach()

    set(generated_sources_other_scope)
    foreach(qml_file_src IN LISTS arg_QML_FILES)
        # This is to facilitate updating code that used the earlier tech preview
        # API function qt6_target_qml_files()
        if(NOT qml_file_src MATCHES "\\.(js|mjs|qml)$")
            list(APPEND non_qml_files ${qml_file_src})
            continue()
        endif()

        # Mark QML files as source files, so that they do not appear in <Other Locations> in Creator
        # or other IDEs
        set_source_files_properties(${qml_file_src} HEADER_FILE_ONLY ON)
        target_sources(${target} PRIVATE ${qml_file_src})

        get_filename_component(file_absolute ${qml_file_src} ABSOLUTE)
        __qt_get_relative_resource_path_for_file(file_resource_path ${qml_file_src})

        # For the tooling steps below, run the tools on the copied qml file in
        # the build directory, not the source directory. This is required
        # because the tools may need to reference imported modules from
        # subdirectories, which would require those subdirectories to have
        # their generated qmldir files present. They also need to use the right
        # resource paths and the source locations might be structured quite
        # differently.

        # Add file to those processed by qmllint
        get_source_file_property(skip_qmllint ${qml_file_src} QT_QML_SKIP_QMLLINT)
        if(NOT no_lint AND NOT skip_qmllint)
            # The set of qml files to run qmllint on may be a subset of the
            # full set of files, so record these in a separate property.
            _qt_internal_target_enable_qmllint(${target})
            set_property(TARGET ${target} APPEND PROPERTY QT_QML_LINT_FILES ${file_absolute})
        endif()

        # Add qml file's type to qmldir
        get_source_file_property(skip_qmldir ${qml_file_src} QT_QML_SKIP_QMLDIR_ENTRY)
        if(NOT no_qmldir AND NOT skip_qmldir)
            get_source_file_property(qml_file_typename ${qml_file_src} QT_QML_SOURCE_TYPENAME)
            if (NOT qml_file_typename)
                get_filename_component(qml_file_ext ${qml_file_src} EXT)
                get_filename_component(qml_file_typename ${qml_file_src} NAME_WE)
            endif()

            # Do not add qmldir entries for lowercase names. Those are not components.
            if (qml_file_typename AND qml_file_typename MATCHES "^[A-Z]")
                if (qml_file_ext AND NOT qml_file_ext STREQUAL ".qml" AND NOT qml_file_ext STREQUAL ".ui.qml"
                        AND NOT qml_file_ext STREQUAL ".js" AND NOT qml_file_ext STREQUAL ".mjs")
                    message(AUTHOR_WARNING
                        "${qml_file_src} has a file extension different from .qml, .ui.qml, .js, "
                        "and .mjs. This leads to unexpected component names."
                    )
                endif()

                # We previously accepted the singular form of this property name
                # during tech preview. Issue a warning for that, but still
                # honor it. The plural form will override it if both are set.
                get_property(have_singular_property SOURCE ${qml_file_src}
                    PROPERTY QT_QML_SOURCE_VERSION SET
                )
                if(have_singular_property)
                    message(AUTHOR_WARNING
                        "The QT_QML_SOURCE_VERSION source file property has been replaced "
                        "by QT_QML_SOURCE_VERSIONS (i.e. plural rather than singular). "
                        "The singular form will eventually be removed, please update "
                        "the project to use the plural form instead for the file at:\n"
                        "  ${qml_file_src}"
                    )
                endif()
                get_source_file_property(qml_file_versions ${qml_file_src} QT_QML_SOURCE_VERSIONS)
                if(NOT qml_file_versions AND have_singular_property)
                    get_source_file_property(qml_file_versions ${qml_file_src} QT_QML_SOURCE_VERSION)
                endif()

                get_source_file_property(qml_file_singleton ${qml_file_src} QT_QML_SINGLETON_TYPE)
                get_source_file_property(qml_file_internal  ${qml_file_src} QT_QML_INTERNAL_TYPE)

                if (NOT qml_file_versions)
                    set(qml_file_versions ${qml_module_files_versions})
                endif()

                set(qmldir_file_contents "")
                foreach(qml_file_version IN LISTS qml_file_versions)
                    if (qml_file_singleton)
                        string(APPEND qmldir_file_contents "singleton ")
                    endif()
                    string(APPEND qmldir_file_contents "${qml_file_typename} ${qml_file_version} ${file_resource_path}\n")
                endforeach()

                if (qml_file_internal)
                    string(APPEND qmldir_file_contents "internal ${qml_file_typename} ${file_resource_path}\n")
                endif()

                set_property(TARGET ${target} APPEND_STRING PROPERTY
                    _qt_internal_qmldir_content "${qmldir_file_contents}"
                )
            endif()
        endif()

        # Run cachegen on the qml file, or if disabled, store the raw qml file in the resources
        get_source_file_property(skip_cachegen ${qml_file_src} QT_QML_SKIP_CACHEGEN)
        if(NOT no_cachegen AND NOT skip_cachegen)
            # We delay this to here to ensure that we only ever enable cachegen
            # after we know there will be at least one file to compile.
            get_target_property(is_cachegen_set_up ${target} _qt_cachegen_set_up)
            if(NOT is_cachegen_set_up)
                _qt_internal_target_enable_qmlcachegen(${target} resource_target ${qmlcachegen})
                list(APPEND output_targets ${resource_target})
            endif()

            # We ensured earlier that arg_PREFIX always ends with "/"
            file(TO_CMAKE_PATH "${arg_PREFIX}${file_resource_path}" file_resource_path)

            set_property(TARGET ${target} APPEND PROPERTY
                QT_QML_MODULE_RESOURCE_PATHS ${file_resource_path}
            )

            file(RELATIVE_PATH file_relative ${CMAKE_CURRENT_SOURCE_DIR} ${file_absolute})
            string(REGEX REPLACE "\\.(js|mjs|qml)$" "_\\1" compiled_file ${file_relative})
            string(REGEX REPLACE "[$#?]+" "_" compiled_file ${compiled_file})

            # The file name needs to be unique to work around an Integrity compiler issue.
            # Search for INTEGRITY_SYMBOL_UNIQUENESS in this file for details.
            set(compiled_file
                "${CMAKE_CURRENT_BINARY_DIR}/.rcc/qmlcache/${target}_${compiled_file}.cpp")
            get_filename_component(out_dir ${compiled_file} DIRECTORY)

            if(CMAKE_GENERATOR STREQUAL "Ninja Multi-Config" AND CMAKE_VERSION VERSION_GREATER_EQUAL "3.20")
                set(qmlcachegen_cmd "$<COMMAND_CONFIG:${qmlcachegen}>")
            else()
                set(qmlcachegen_cmd "${qmlcachegen}")
            endif()
            add_custom_command(
                OUTPUT ${compiled_file}
                COMMAND ${CMAKE_COMMAND} -E make_directory ${out_dir}
                COMMAND
                    ${QT_TOOL_COMMAND_WRAPPER_PATH}
                    ${qmlcachegen_cmd}
                    --resource-path "${file_resource_path}"
                    ${cachegen_args}
                    -o "${compiled_file}"
                    "${file_absolute}"
                COMMAND_EXPAND_LISTS
                DEPENDS
                    ${qmlcachegen_cmd}
                    "${file_absolute}"
                    $<TARGET_PROPERTY:${target},_qt_generated_qrc_files>
                    "$<$<BOOL:${qmltypes_file}>:${qmltypes_file}>"
                    "${qmldir_file}"
                VERBATIM
            )

            target_sources(${target} PRIVATE ${compiled_file})
            set_source_files_properties(${compiled_file} PROPERTIES
                SKIP_AUTOGEN ON
            )
            # The current scope automatically sees the file as generated, but the
            # target scope may not if it is different. Force it where we can.
            # We will also have to add the generated file to a target in this
            # scope at the end to ensure correct dependencies.
            get_target_property(target_source_dir ${target} SOURCE_DIR)
            if(NOT target_source_dir STREQUAL CMAKE_CURRENT_SOURCE_DIR)
                list(APPEND generated_sources_other_scope ${compiled_file})
                if(CMAKE_VERSION VERSION_GREATER_EQUAL "3.18")
                    set_source_files_properties(
                        ${compiled_file}
                        TARGET_DIRECTORY ${target}
                        PROPERTIES
                            SKIP_AUTOGEN TRUE
                            GENERATED TRUE
                    )
                endif()
            endif()
        endif()
    endforeach()

    if(ANDROID)
        _qt_internal_collect_qml_root_paths("${target}" ${arg_QML_FILES})
    endif()

    if(non_qml_files)
        list(JOIN non_qml_files "\n  " file_list)
        message(WARNING
            "Only .qml, .js or .mjs files should be added with QML_FILES. "
            "The following files should be added with RESOURCES instead:"
            "\n  ${file_list}"
        )
    endif()

    if(copied_files OR generated_sources_other_scope)
        if(CMAKE_VERSION VERSION_LESS 3.19)
            # Called from qt6_add_qml_module() and we know there can only be
            # this one call. With those constraints, we can use a custom target
            # to implement the necessary dependencies to get files copied to the
            # build directory when their source files change.
            add_custom_target(${target}_tooling ALL
                DEPENDS
                    ${copied_files}
                    ${generated_sources_other_scope}
            )
            add_dependencies(${target} ${target}_tooling)
        else()
            # We could be called multiple times and a custom target can only
            # have file-level dependencies added at the time the target is
            # created. Use an interface library instead, since we can add
            # private sources to those and have the library act as a build
            # system target from CMake 3.19 onward, and we can add the sources
            # progressively over multiple calls.
            if(NOT TARGET ${target}_tooling)
                add_library(${target}_tooling INTERFACE)
                add_dependencies(${target} ${target}_tooling)
            endif()
            target_sources(${target}_tooling PRIVATE
                ${copied_files}
                ${generated_sources_other_scope}
            )
        endif()
    endif()

    # Batch all the non-compiled qml sources into a single resource for this
    # call. Subsequent calls for the same target will be in their own separate
    # resource file.
    get_target_property(counter ${target} QT_QML_MODULE_RAW_QML_SETS)
    if(NOT counter)
        set(counter 0)
    endif()
    set(resource_name ${target}_raw_qml_${counter})
    set(resource_targets)
    qt6_add_resources(${target} ${resource_name}
        PREFIX ${arg_PREFIX}
        FILES ${arg_QML_FILES} ${arg_RESOURCES}
        OUTPUT_TARGETS resource_targets
    )
    math(EXPR counter "${counter} + 1")
    set_target_properties(${target} PROPERTIES QT_QML_MODULE_RAW_QML_SETS ${counter})
    list(APPEND output_targets ${resource_targets})

    if(arg_OUTPUT_TARGETS)
        set(${arg_OUTPUT_TARGETS} ${output_targets} PARENT_SCOPE)
    endif()

endfunction()

if(NOT QT_NO_CREATE_VERSIONLESS_FUNCTIONS)
    function(qt_target_qml_sources)
        qt6_target_qml_sources(${ARGV})
        cmake_parse_arguments(PARSE_ARGV 1 arg  "" "OUTPUT_TARGETS" "")
        if(arg_OUTPUT_TARGETS)
            set(${arg_OUTPUT_TARGETS} ${${arg_OUTPUT_TARGETS}} PARENT_SCOPE)
        endif()
    endfunction()
endif()

# This function is currently in Technical Preview.
# It's signature and behavior might change.
function(qt6_generate_foreign_qml_types source_target destination_qml_target)
    qt6_extract_metatypes(${source_target})
    get_target_property(target_metatypes_json_file ${source_target}
                        INTERFACE_QT_META_TYPES_BUILD_FILE)
    if (NOT target_metatypes_json_file)
        message(FATAL_ERROR "Need target metatypes.json file")
    endif()

    set(registration_files_base ${source_target}_${destination_qml_target})
    set(additional_sources ${registration_files_base}.cpp ${registration_files_base}.h)

    add_custom_command(
        OUTPUT
            ${additional_sources}
        DEPENDS
            ${source_target}
            ${target_metatypes_json_file}
            ${QT_CMAKE_EXPORT_NAMESPACE}::qmltyperegistrar
        COMMAND
            ${QT_TOOL_COMMAND_WRAPPER_PATH}
            $<TARGET_FILE:${QT_CMAKE_EXPORT_NAMESPACE}::qmltyperegistrar>
            "--extract"
            -o ${registration_files_base}
            ${target_metatypes_json_file}
        COMMENT "Generate QML registration code for target ${source_target}"
        VERBATIM
    )

    target_sources(${destination_qml_target} PRIVATE ${additional_sources})
    qt6_wrap_cpp(${additional_sources} TARGET ${destination_qml_target})
endfunction()

if(NOT QT_NO_CREATE_VERSIONLESS_FUNCTIONS)
    if(QT_DEFAULT_MAJOR_VERSION EQUAL 6)
        function(qt_generate_foreign_qml_types)
            qt6_generate_foreign_qml_types(${ARGV})
        endfunction()
    else()
        message(FATAL_ERROR "qt_generate_foreign_qml_types() is only available in Qt 6.")
    endif()
endif()

# target: Expected to be the backing target for a qml module. Certain target
#   properties normally set by qt6_add_qml_module() will be retrieved from this
#   target. (REQUIRED)
#
# MANUAL_MOC_JSON_FILES: Specifies a list of json files, generated by a manual
#   moc call, to extract metatypes. (OPTIONAL)
#
# NAMESPACE: Specifies a namespace the type registration function shall be
#   generated into. (OPTIONAL)
#
function(_qt_internal_qml_type_registration target)
    set(args_option __QT_INTERNAL_INSTALL_METATYPES_JSON)
    set(args_single NAMESPACE)
    set(args_multi  MANUAL_MOC_JSON_FILES)

    cmake_parse_arguments(PARSE_ARGV 1 arg
        "${args_option}" "${args_single}" "${args_multi}"
    )
    if(arg_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR "Unknown/unexpected arguments: ${arg_UNPARSED_ARGUMENTS}")
    endif()

    get_target_property(import_name ${target} QT_QML_MODULE_URI)
    if (NOT import_name)
        message(FATAL_ERROR "Target ${target} is not a QML module")
    endif()
    get_target_property(qmltypes_output_name ${target} QT_QML_MODULE_TYPEINFO)
    if (NOT qmltypes_output_name)
        get_target_property(compile_definitions_list ${target} COMPILE_DEFINITIONS)
        list(FIND compile_definitions_list QT_PLUGIN is_a_plugin)
        if (is_a_plugin GREATER_EQUAL 0)
            set(qmltypes_output_name "plugins.qmltypes")
        else()
            set(qmltypes_output_name ${target}.qmltypes)
        endif()
    endif()

    set(meta_types_json_args "")
    if(arg_MANUAL_MOC_JSON_FILES)
        list(APPEND meta_types_json_args "MANUAL_MOC_JSON_FILES" ${arg_MANUAL_MOC_JSON_FILES})
    endif()

    # Don't install the metatypes json files by default for user project created qml modules.
    # Only install them for Qt provided qml modules.
    if(NOT arg___QT_INTERNAL_INSTALL_METATYPES_JSON)
        list(APPEND meta_types_json_args __QT_INTERNAL_NO_INSTALL)
    endif()
    qt6_extract_metatypes(${target} ${meta_types_json_args})

    get_target_property(import_version ${target} QT_QML_MODULE_VERSION)
    get_target_property(output_dir ${target} QT_QML_MODULE_OUTPUT_DIRECTORY)
    get_target_property(target_source_dir ${target} SOURCE_DIR)
    get_target_property(target_binary_dir ${target} BINARY_DIR)
    get_target_property(target_metatypes_file ${target} INTERFACE_QT_META_TYPES_BUILD_FILE)
    if (NOT target_metatypes_file)
        message(FATAL_ERROR "Target ${target} does not have a meta types file")
    endif()

    # Extract major and minor version (could also have patch part, but we don't
    # need that here)
    if (import_version MATCHES "^([0-9]+)\\.([0-9]+)")
        set(major_version ${CMAKE_MATCH_1})
        set(minor_version ${CMAKE_MATCH_2})
    else()
        message(FATAL_ERROR
            "Invalid module version number '${import_version}'. "
            "Expected VersionMajor.VersionMinor."
        )
    endif()

    # check if plugins.qmltypes is already defined
    get_target_property(target_plugin_qmltypes ${target} QT_QML_MODULE_PLUGIN_TYPES_FILE)
    if (target_plugin_qmltypes)
        message(FATAL_ERROR "Target ${target} already has a qmltypes file set.")
    endif()

    set(cmd_args)
    set(plugin_types_file "${output_dir}/${qmltypes_output_name}")
    set(generated_marker_file "${target_binary_dir}/.generated/${qmltypes_output_name}")
    get_filename_component(generated_marker_dir "${generated_marker_file}" DIRECTORY)
    set_target_properties(${target} PROPERTIES
        QT_QML_MODULE_PLUGIN_TYPES_FILE ${plugin_types_file}
    )

    if (arg_NAMESPACE)
        list(APPEND cmd_args
            --namespace=${arg_NAMESPACE}
        )
    endif()

    list(APPEND cmd_args
        --generate-qmltypes=${plugin_types_file}
        --import-name=${import_name}
        --major-version=${major_version}
        --minor-version=${minor_version}
    )


    # Add --follow-foreign-versioning if requested
    get_target_property(follow_foreign_versioning ${target}
                        _qt_qml_module_follow_foreign_versioning)

    if (follow_foreign_versioning)
        list(APPEND cmd_args
            --follow-foreign-versioning
        )
    endif()

    # Add past minor versions
    get_target_property(past_major_versions ${target} QT_QML_MODULE_PAST_MAJOR_VERSIONS)

    if (past_major_versions OR past_major_versions STREQUAL "0")
        foreach (past_major_version ${past_major_versions})
            list(APPEND cmd_args
                --past-major-version ${past_major_version}
            )
        endforeach()
    endif()

    # Run a script to recursively evaluate all the metatypes.json files in order
    # to collect all foreign types.
    string(TOLOWER "${target}_qmltyperegistrations.cpp" type_registration_cpp_file_name)
    set(foreign_types_file "${target_binary_dir}/qmltypes/${target}_foreign_types.txt")
    set(type_registration_cpp_file "${target_binary_dir}/${type_registration_cpp_file_name}")

    # Enable evaluation of metatypes.json source interfaces
    set_target_properties(${target} PROPERTIES QT_CONSUMES_METATYPES TRUE)
    set(genex_list "$<REMOVE_DUPLICATES:$<FILTER:$<TARGET_PROPERTY:${target},SOURCES>,INCLUDE,metatypes.json$>>")
    set(genex_main "$<JOIN:${genex_list},$<COMMA>>")
    file(GENERATE OUTPUT "${foreign_types_file}"
        CONTENT "$<IF:$<BOOL:${genex_list}>,--foreign-types=${genex_main},\n>"
    )

    list(APPEND cmd_args
        "@${foreign_types_file}"
    )

    if (TARGET ${target}Private)
        list(APPEND cmd_args --private-includes)
    endif()

    get_target_property(target_metatypes_json_file ${target} INTERFACE_QT_META_TYPES_BUILD_FILE)
    if (NOT target_metatypes_json_file)
        message(FATAL_ERROR "Need target metatypes.json file")
    endif()

    cmake_policy(PUSH)

    set(registration_cpp_file_dep_args)
    if (CMAKE_GENERATOR MATCHES "Ninja" OR
        (CMAKE_VERSION VERSION_GREATER_EQUAL 3.20 AND CMAKE_GENERATOR MATCHES "Makefiles"))
        if(POLICY CMP0116)
            # Without explicitly setting this policy to NEW, we get a warning
            # even though we ensure there's actually no problem here.
            # See https://gitlab.kitware.com/cmake/cmake/-/issues/21959
            cmake_policy(SET CMP0116 NEW)
            set(relative_to_dir ${CMAKE_CURRENT_BINARY_DIR})
        else()
            set(relative_to_dir ${CMAKE_BINARY_DIR})
        endif()
        set(dependency_file_cpp "${target_binary_dir}/qmltypes/${type_registration_cpp_file_name}.d")
        set(registration_cpp_file_dep_args DEPFILE ${dependency_file_cpp})
        file(RELATIVE_PATH cpp_file_name "${relative_to_dir}" "${type_registration_cpp_file}")
        file(GENERATE OUTPUT "${dependency_file_cpp}"
            CONTENT "${cpp_file_name}: $<IF:$<BOOL:${genex_list}>,\\\n$<JOIN:${genex_list}, \\\n>, \\\n>"
        )
    endif()

    add_custom_command(
        OUTPUT
            ${type_registration_cpp_file}
            ${plugin_types_file}
        DEPENDS
            ${foreign_types_file}
            ${target_metatypes_json_file}
            ${QT_CMAKE_EXPORT_NAMESPACE}::qmltyperegistrar
            "$<$<BOOL:${genex_list}>:${genex_list}>"
        COMMAND
            ${QT_TOOL_COMMAND_WRAPPER_PATH}
            $<TARGET_FILE:${QT_CMAKE_EXPORT_NAMESPACE}::qmltyperegistrar>
            ${cmd_args}
            -o ${type_registration_cpp_file}
            ${target_metatypes_json_file}
        COMMAND
            ${CMAKE_COMMAND} -E make_directory "${generated_marker_dir}"
        COMMAND
            ${CMAKE_COMMAND} -E touch "${generated_marker_file}"
        ${registration_cpp_file_dep_args}
        COMMENT "Automatic QML type registration for target ${target}"
        VERBATIM
    )

    cmake_policy(POP)

    # The ${target}_qmllint targets need to depend on the generation of all
    # *.qmltypes files in the build. We have no way of reliably working out
    # which QML modules a given target depends on at configure time, so we
    # have to be conservative and make ${target}_qmllint targets depend on all
    # *.qmltypes files. We need to provide a target for those dependencies
    # here. Note that we can't use ${target} itself for those dependencies
    # because the user might want to run qmllint without having to build the
    # QML module.
    add_custom_target(${target}_qmltyperegistration
        DEPENDS
            ${type_registration_cpp_file}
            ${plugin_types_file}
    )
    if(NOT TARGET all_qmltyperegistrations)
        add_custom_target(all_qmltyperegistrations)
    endif()
    add_dependencies(all_qmltyperegistrations ${target}_qmltyperegistration)

    # Both ${target} (via target_sources) and ${target}_qmltyperegistration (via add_custom_target
    # DEPENDS option) depend on ${type_registration_cpp_file}.
    # The new Xcode build system requires a common target to drive the generation of files,
    # otherwise project configuration fails.
    # Make ${target} the common target, by adding it as a dependency for
    # ${target}_qmltyperegistration.
    # The consequence is that the ${target}_qmllint target will now first build ${target} when using
    # the Xcode generator (mostly only relevant for projects using Qt for iOS).
    # See QTBUG-95763.
    if(CMAKE_GENERATOR STREQUAL "Xcode")
        add_dependencies(${target}_qmltyperegistration ${target})
    endif()

    target_sources(${target} PRIVATE ${type_registration_cpp_file})

    # FIXME: The generated .cpp file has usually lost the path information for
    #        the headers it #include's. Since these generated .cpp files are in
    #        the build directory away from those headers, the header search path
    #        has to be augmented to ensure they can be found. We don't know what
    #        paths are needed, but add the source directory to at least handle
    #        the common case of headers in the same directory as the target.
    #        See QTBUG-93443.
    target_include_directories(${target} PRIVATE ${target_source_dir})

    # Circumvent "too many sections" error when doing a 32 bit debug build on Windows with
    # MinGW.
    set(additional_source_files_properties "")
    if(MINGW)
        set(additional_source_files_properties "COMPILE_OPTIONS" "-Wa,-mbig-obj")
    elseif(MSVC)
        set(additional_source_files_properties "COMPILE_OPTIONS" "/bigobj")
    endif()
    set_source_files_properties(${type_registration_cpp_file} PROPERTIES
        SKIP_AUTOGEN ON
        ${additional_source_files_properties}
    )
    if(CMAKE_VERSION VERSION_GREATER_EQUAL "3.18")
        set_source_files_properties(
            ${type_registration_cpp_file}
            TARGET_DIRECTORY ${target}
            PROPERTIES
                SKIP_AUTOGEN TRUE
                GENERATED TRUE
                ${additional_source_files_properties}
        )
    endif()

    target_include_directories(${target} PRIVATE
        $<TARGET_PROPERTY:${QT_CMAKE_EXPORT_NAMESPACE}::QmlPrivate,INTERFACE_INCLUDE_DIRECTORIES>
    )
endfunction()

function(qt6_qml_type_registration)
    message(FATAL_ERROR
        "This function, previously available under Technical Preview, has been removed. "
        "Please use qt6_add_qml_module() instead."
    )
endfunction()

if(NOT QT_NO_CREATE_VERSIONLESS_FUNCTIONS)
    function(qt_qml_type_registration)
        message(FATAL_ERROR
            "This function, previously available under Technical Preview, has been removed. "
            "Please use qt_add_qml_module() instead."
        )
    endfunction()
endif()


function(_qt_internal_scan_qml_imports target imports_file_var when_to_scan)
    if(NOT "${ARGN}" STREQUAL "")
        message(FATAL_ERROR "Unknown/unexpected arguments: ${ARGN}")
    endif()

    if(when_to_scan STREQUAL "BUILD_PHASE")
        set(scan_at_build_time TRUE)
    elseif(when_to_scan STREQUAL "IMMEDIATELY")
        set(scan_at_build_time FALSE)
    else()
        message(FATAL_ERROR "Unexpected value for when_to_scan: ${when_to_scan}")
    endif()

    # Find location of qmlimportscanner.
    get_target_property(tool_path ${QT_CMAKE_EXPORT_NAMESPACE}::qmlimportscanner IMPORTED_LOCATION)
    if(NOT tool_path)
        set(configs "RELWITHDEBINFO;RELEASE;MINSIZEREL;DEBUG")
        foreach(config ${configs})
            get_target_property(tool_path
                ${QT_CMAKE_EXPORT_NAMESPACE}::qmlimportscanner IMPORTED_LOCATION_${config})
            if(tool_path)
                break()
            endif()
        endforeach()
    endif()

    if(NOT EXISTS "${tool_path}")
        message(FATAL_ERROR "The package \"QmlImportScanner\" references the file
   \"${tool_path}\"
but this file does not exist.  Possible reasons include:
* The file was deleted, renamed, or moved to another location.
* An install or uninstall procedure did not complete successfully.
* The installation package was faulty.
")
    endif()

    # Find QML import paths.
    if("${_qt_additional_packages_prefix_paths}" STREQUAL "")
        # We have one installation prefix for all Qt modules. Add the "<prefix>/qml" directory.
        set(qml_import_paths "${QT6_INSTALL_PREFIX}/${QT6_INSTALL_QML}")
    else()
        # We have multiple installation prefixes: one per Qt repository (conan). Add those that have
        # a "qml" subdirectory.
        set(qml_import_paths)
        foreach(root IN ITEMS "${QT6_INSTALL_PREFIX};${_qt_additional_packages_prefix_paths}")
            set(candidate "${root}/${QT6_INSTALL_QML}")
            if(IS_DIRECTORY "${candidate}")
                list(APPEND qml_import_paths "${candidate}")
            endif()
        endforeach()
    endif()

    # Construct the -importPath arguments.
    set(import_path_arguments)
    foreach(path IN LISTS qml_import_paths)
        list(APPEND import_path_arguments -importPath ${path})
    endforeach()

    # Run qmlimportscanner to generate the cmake file that records the import entries
    get_target_property(target_source_dir ${target} SOURCE_DIR)
    get_target_property(target_binary_dir ${target} BINARY_DIR)
    set(out_dir "${target_binary_dir}/.qt_plugins")
    set(imports_file "${out_dir}/Qt6_QmlPlugins_Imports_${target}.cmake")
    set(${imports_file_var} "${imports_file}" PARENT_SCOPE)
    file(MAKE_DIRECTORY ${out_dir})

    set(cmd_args
        -rootPath "${target_source_dir}"
        -cmake-output
        -output-file "${imports_file}"
        ${import_path_arguments}
    )
    get_target_property(qml_import_path ${target} QT_QML_IMPORT_PATH)

    if (qml_import_path)
        list(APPEND cmd_args ${qml_import_path})
    endif()

    # Facilitate self-import so we can find the qmldir file
    get_target_property(module_out_dir ${target} QT_QML_MODULE_OUTPUT_DIRECTORY)
    if(module_out_dir)
        list(APPEND cmd_args "${module_out_dir}")
    endif()

    # Find qmldir files we copied to the build directory
    if(NOT "${QT_QML_OUTPUT_DIRECTORY}" STREQUAL "")
        if(EXISTS "${QT_QML_OUTPUT_DIRECTORY}")
            list(APPEND cmd_args "${QT_QML_OUTPUT_DIRECTORY}")
        endif()
    else()
        list(APPEND cmd_args "${CMAKE_CURRENT_BINARY_DIR}")
    endif()

    # All of the module's .qml files will be listed in one of the generated
    # .qrc files, so there's no need to list the files individually. We provide
    # the .qrc files instead because they have the additional information for
    # each file's resource alias.
    get_property(qrc_files TARGET ${target} PROPERTY _qt_generated_qrc_files)
    if (qrc_files)
        list(APPEND cmd_args "-qrcFiles" ${qrc_files})
    endif()

    # Use a response file to avoid command line length issues if we have a lot
    # of arguments on the command line
    string(LENGTH "${cmd_args}" length)
    if(length GREATER 240)
        set(rsp_file "${out_dir}/Qt6_QmlPlugins_Imports_${target}.rsp")
        list(JOIN cmd_args "\n" rsp_file_content)
        file(WRITE ${rsp_file} "${rsp_file_content}")
        set(cmd_args "@${rsp_file}")
    endif()

    set(import_scanner_args ${QT_TOOL_COMMAND_WRAPPER_PATH} ${tool_path} ${cmd_args})

    if(scan_at_build_time)
        add_custom_command(
            OUTPUT "${imports_file}"
            COMMENT "Running qmlimportscanner for ${target}"
            COMMAND ${import_scanner_args}
            WORKING_DIRECTORY ${target_source_dir}
            DEPENDS
                ${tool_path}
                ${qrc_files}
                $<TARGET_PROPERTY:${target},QT_QML_MODULE_QML_FILES>
            VERBATIM
        )
        add_custom_target(${target}_qmlimportscan DEPENDS "${imports_file}")
        add_dependencies(${target} ${target}_qmlimportscan)
    else()
        message(VERBOSE "Running qmlimportscanner for ${target}.")
        list(JOIN import_scanner_args " " import_scanner_args_string)
        message(DEBUG "qmlimportscanner command: ${import_scanner_args_string}")
        execute_process(
            COMMAND ${import_scanner_args}
            WORKING_DIRECTORY ${target_source_dir}
            RESULT_VARIABLE result
        )
        if(result)
            message(FATAL_ERROR
                "Failed to scan target ${target} for QML imports: ${result}"
            )
        endif()
    endif()
endfunction()

# Parse the entry at the specified index, assuming the caller already included
# the file generated by a call to _qt_internal_scan_qml_imports()
macro(_qt_internal_parse_qml_imports_entry prefix index)
    cmake_parse_arguments("${prefix}"
        ""
        "CLASSNAME;NAME;PATH;PLUGIN;RELATIVEPATH;TYPE;VERSION;LINKTARGET;PREFER"
        "COMPONENTS;SCRIPTS"
        ${qml_import_scanner_import_${index}}
    )
endmacro()


# This function is called as a finalizer in qt6_finalize_executable() for any
# target that links against the Qml library for a statically built Qt.
function(qt6_import_qml_plugins target)
    if(QT6_IS_SHARED_LIBS_BUILD)
        return()
    endif()

    # Protect against being called multiple times in case we are being called
    # explicitly before the finalizer is invoked.
    get_target_property(already_imported ${target} _QT_QML_PLUGINS_IMPORTED)
    get_target_property(no_import_scan   ${target} QT_QML_MODULE_NO_IMPORT_SCAN)
    if(already_imported OR no_import_scan)
        return()
    endif()
    set_target_properties(${target} PROPERTIES _QT_QML_PLUGINS_IMPORTED TRUE)

    _qt_internal_scan_qml_imports(${target} imports_file IMMEDIATELY)
    include("${imports_file}")

    # Parse the generated cmake file.
    # It is possible for the scanner to find no usage of QML, in which case the import count is 0.
    if(qml_import_scanner_imports_count GREATER 0)
        set(added_plugins "")
        set(plugins_to_link "")
        set(plugin_inits_to_link "")

        math(EXPR last_index "${qml_import_scanner_imports_count} - 1")
        foreach(index RANGE 0 ${last_index})
            _qt_internal_parse_qml_imports_entry(entry ${index})
            if(entry_PATH AND entry_PLUGIN)
                # Sometimes a plugin appears multiple times with different versions.
                # Make sure to process it only once.
                list(FIND added_plugins "${entry_PLUGIN}" _index)
                if(NOT _index EQUAL -1)
                    continue()
                endif()
                list(APPEND added_plugins "${entry_PLUGIN}")

                # Link against the Qml plugin.
                # For plugins provided by Qt, we assume those plugin targets are already defined
                # (typically brought in via find_package(Qt6...) ).
                # For other plugins, the targets can come from the project itself.
                #
                if(entry_LINKTARGET)
                    if(TARGET ${entry_LINKTARGET})
                        list(APPEND plugins_to_link "${entry_LINKTARGET}")
                    else()
                        message(WARNING
                            "The qml plugin '${entry_PLUGIN}' is a dependency of '${target}', "
                            "but the link target it defines (${entry_LINKTARGET}) does not exist "
                            "in the current scope. The plugin will not be linked."
                        )
                    endif()
                elseif(TARGET ${entry_PLUGIN})
                    list(APPEND plugins_to_link "${entry_PLUGIN}")
                else()
                    # TODO: QTBUG-94605 Figure out if this is a reasonable scenario to support
                    message(WARNING
                        "The qml plugin '${entry_PLUGIN}' is a dependency of '${target}', "
                        "but there is no target by that name in the current scope. The plugin will "
                        "not be linked."
                    )
                endif()
            endif()
        endforeach()

        if(plugins_to_link)
            # If ${target} is an executable or a shared library, link the plugins directly to
            # the target.
            # If ${target} is a static or INTERFACE library, the plugins should be propagated
            # across those libraries to the end target (executable or shared library).
            # The plugin initializers will be linked via usage requirements from the plugin target.
            get_target_property(target_type ${target} TYPE)
            if(target_type STREQUAL "EXECUTABLE" OR target_type STREQUAL "SHARED_LIBRARY")
                set(link_type "PRIVATE")
            else()
                set(link_type "INTERFACE")
            endif()
            target_link_libraries("${target}" ${link_type} ${plugins_to_link})
        endif()
    endif()
endfunction()

if(NOT QT_NO_CREATE_VERSIONLESS_FUNCTIONS)
    function(qt_import_qml_plugins)
        if(QT_DEFAULT_MAJOR_VERSION EQUAL 5)
            qt5_import_qml_plugins(${ARGV})
        elseif(QT_DEFAULT_MAJOR_VERSION EQUAL 6)
            qt6_import_qml_plugins(${ARGV})
        endif()
    endfunction()
endif()

# This function may be called as a finalizer in qt6_finalize_executable() for any
# target that links against the Qml library for a shared Qt.
function(_qt_internal_generate_deploy_qml_imports_script target)
    if(NOT QT6_IS_SHARED_LIBS_BUILD)
        return()
    endif()
    get_target_property(target_type ${target} TYPE)
    # TODO: Handle Android where executables are module libraries instead
    if(NOT target_type STREQUAL "EXECUTABLE")
        return()
    endif()

    # Protect against being called multiple times in case we are being called
    # explicitly before the finalizer is invoked.
    get_target_property(already_generated ${target} _QT_QML_PLUGIN_SCAN_GENERATED)
    get_target_property(no_import_scan    ${target} QT_QML_MODULE_NO_IMPORT_SCAN)
    if(already_generated OR no_import_scan)
        return()
    endif()
    set_target_properties(${target} PROPERTIES _QT_QML_PLUGIN_SCAN_GENERATED TRUE)

    # Defer actually running qmlimportscanner until build time. This keeps the
    # configure step fast and takes advantage of the build step supporting
    # parallel execution if there are multiple targets that need scanning.
    _qt_internal_scan_qml_imports(${target} imports_file BUILD_PHASE)

    set(is_bundle FALSE)
    if(APPLE)
        if(IOS)
            message(FATAL_ERROR "Install support not available for iOS builds")
        endif()
        get_target_property(is_bundle ${target} MACOSX_BUNDLE)
    endif()
    set(is_bundle "$<BOOL:${is_bundle}>")

    # For macOS app bundles, the directory layout must conform to Apple's
    # requirements, so we hard-code the required structure. This assumes the
    # app bundle is installed to the base dir with an install command like:
    #   install(TARGETS ${target} BUNDLE DESTINATION .)
    set(bundle_qml_dir     "$<TARGET_FILE_NAME:${target}>.app/Contents/Resources/qml")
    set(bundle_plugins_dir "$<TARGET_FILE_NAME:${target}>.app/Contents/PlugIns")

    _qt_internal_get_deploy_impl_dir(deploy_impl_dir)
    string(MAKE_C_IDENTIFIER "${target}" target_id)
    set(filename "${deploy_impl_dir}/deploy_qml_imports/${target_id}")
    get_cmake_property(is_multi_config GENERATOR_IS_MULTI_CONFIG)
    if(is_multi_config)
        string(APPEND filename "-$<CONFIG>")
    endif()
    string(APPEND filename ".cmake")

    # TODO: Fix macOS multi-config bundles to work.
    file(GENERATE OUTPUT "${filename}" CONTENT
"# Auto-generated deploy QML imports script for target \"${target}\".
# Do not edit, all changes will be lost.
# This file should only be included by qt_deploy_qml_imports().

set(__qt_opts $<${is_bundle}:BUNDLE>)
if(arg_NO_QT_IMPORTS)
    list(APPEND __qt_opts NO_QT_IMPORTS)
endif()

_qt_internal_deploy_qml_imports_for_target(
    \${__qt_opts}
    IMPORTS_FILE \"${imports_file}\"
    PLUGINS_FOUND __qt_internal_plugins_found
    QML_DIR     \"$<IF:${is_bundle},${bundle_qml_dir},\${arg_QML_DIR}>\"
    PLUGINS_DIR \"$<IF:${is_bundle},${bundle_plugins_dir},\${arg_PLUGINS_DIR}>\"
)

if(arg_PLUGINS_FOUND)
    set(\${arg_PLUGINS_FOUND} \"\${__qt_internal_plugins_found}\" PARENT_SCOPE)
endif()
")

endfunction()

# This function is currently in Technical Preview.
# Its signature and behavior might change.
function(qt6_generate_deploy_qml_app_script)
    # We take the target using a TARGET keyword instead of as the first
    # positional argument so that we have a consistent signature with the
    # qt6_generate_deploy_app_script() from qtbase. That function might accept
    # an executable instead of a target in the future, but we can't because we
    # need information associated with the target (scanning all its .qml files
    # for imported QML modules).
    set(no_value_options
        NO_UNSUPPORTED_PLATFORM_ERROR
        MACOS_BUNDLE_POST_BUILD
        DEPLOY_USER_QML_MODULES_ON_UNSUPPORTED_PLATFORM
    )
    set(single_value_options
        TARGET
        FILENAME_VARIABLE
    )
    set(multi_value_options "")
    cmake_parse_arguments(PARSE_ARGV 0 arg
        "${no_value_options}" "${single_value_options}" "${multi_value_options}"
    )
    if(arg_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR "Unexpected arguments: ${arg_UNPARSED_ARGUMENTS}")
    endif()
    if(NOT arg_TARGET)
        message(FATAL_ERROR "TARGET must be specified")
    endif()
    if(NOT arg_FILENAME_VARIABLE)
        message(FATAL_ERROR "FILENAME_VARIABLE must be specified")
    endif()

    # Check that the target was defer-finalized, and not immediately finalized when using
    # CMake < 3.19. This is important because if it's immediately finalized, Qt::Qml is likely
    # not in the dependency list, and thus _qt_internal_generate_deploy_qml_imports_script will
    # not be executed, leading to an error at install time
    # 'No QML imports information recorded for target X'.
    # _qt_is_immediately_finalized is set by qt6_add_executable.
    # TODO: Remove once minimum required CMAKE_VERSION is 3.19+.
    get_target_property(is_immediately_finalized "${arg_TARGET}" _qt_is_immediately_finalized)
    if(is_immediately_finalized)
        message(FATAL_ERROR
            "QML app deployment requires CMake version 3.19, or later, or manual executable "
            "finalization. For manual finalization, pass the MANUAL_FINALIZATION option to "
            "qt_add_executable() and then call qt_finalize_target(${arg_TARGET}) just before
            calling qt_generate_deploy_qml_app_script().")
    endif()

    # Create a file name that will be unique for this target and the combination
    # of arguments passed to this command. This allows the project to call us
    # multiple times with different arguments for the same target (e.g. to
    # create deployment scripts for different scenarios).
    string(MAKE_C_IDENTIFIER "${arg_TARGET}" target_id)
    string(SHA1 args_hash "${ARGV}")
    string(SUBSTRING "${args_hash}" 0 10 short_hash)
    _qt_internal_get_deploy_impl_dir(deploy_impl_dir)
    set(file_name "${deploy_impl_dir}/deploy_qml_app_${target_id}_${short_hash}")
    get_cmake_property(is_multi_config GENERATOR_IS_MULTI_CONFIG)
    if(is_multi_config)
        string(APPEND file_name "-$<CONFIG>")
    endif()
    set(${arg_FILENAME_VARIABLE} "${file_name}" PARENT_SCOPE)

    # This will be changed to TRUE in some future Qt version, when
    # qt_deploy_runtime_dependencies can handle Linux.
    set(desktop_linux_runtime_libs_deployment_supported FALSE)

    if(QT6_IS_SHARED_LIBS_BUILD)
        set(qt_build_type_string "shared Qt libs")
    else()
        set(qt_build_type_string "static Qt libs")
    endif()

    if(APPLE AND NOT IOS AND QT6_IS_SHARED_LIBS_BUILD)
        # TODO: Handle non-bundle applications if possible.
        get_target_property(is_bundle ${arg_TARGET} MACOSX_BUNDLE)
        if(NOT is_bundle)
            message(FATAL_ERROR
                "Executable targets have to be app bundles to use this command "
                "on Apple platforms."
            )
        endif()

        file(GENERATE OUTPUT "${file_name}" CONTENT "
include(${QT_DEPLOY_SUPPORT})
qt_deploy_qml_imports(TARGET ${arg_TARGET} PLUGINS_FOUND plugins_found)
if(NOT DEFINED __QT_DEPLOY_POST_BUILD)
    qt_deploy_runtime_dependencies(
        EXECUTABLE $<TARGET_FILE_NAME:${arg_TARGET}>.app
        ADDITIONAL_MODULES \${plugins_found}
    )
endif()")
        if(arg_MACOS_BUNDLE_POST_BUILD)
            # We must not deploy the runtime dependencies, otherwise we interfere
            # with CMake's RPATH rewriting at install time. We only need the QML
            # imports deployed to the bundle anyway, the build RPATHs will allow
            # the regular libraries, frameworks and non-QML plugins to still be
            # found, even if they are outside the app bundle.
            add_custom_command(TARGET ${arg_TARGET} POST_BUILD
                COMMAND ${CMAKE_COMMAND}
                -D "QT_DEPLOY_PREFIX=$<TARGET_PROPERTY:${arg_TARGET},BINARY_DIR>"
                -D "__QT_DEPLOY_IMPL_DIR=${deploy_impl_dir}"
                -D "__QT_DEPLOY_POST_BUILD=TRUE"
                -P "${file_name}"
                VERBATIM
            )
        endif()

    elseif(WIN32 AND QT6_IS_SHARED_LIBS_BUILD)
        file(GENERATE OUTPUT "${file_name}" CONTENT "
include(${QT_DEPLOY_SUPPORT})
qt_deploy_qml_imports(TARGET ${arg_TARGET} PLUGINS_FOUND plugins_found)
qt_deploy_runtime_dependencies(
    EXECUTABLE ${CMAKE_INSTALL_BINDIR}/$<TARGET_FILE_NAME:${arg_TARGET}>
    ADDITIONAL_MODULES \${plugins_found}
    GENERATE_QT_CONF
)")
    elseif(LINUX AND NOT CMAKE_CROSSCOMPILING AND desktop_linux_runtime_libs_deployment_supported)
        # TODO: This branch will only be enabled once qt_deploy_runtime_dependencies can handle
        # desktop Linux.
        file(GENERATE OUTPUT "${file_name}" CONTENT "
include(${QT_DEPLOY_SUPPORT})
qt_deploy_qml_imports(TARGET ${arg_TARGET} PLUGINS_FOUND plugins_found)
qt_deploy_runtime_dependencies(
EXECUTABLE ${CMAKE_INSTALL_BINDIR}/$<TARGET_FILE_NAME:${arg_TARGET}>
ADDITIONAL_MODULES \${plugins_found}
GENERATE_QT_CONF
)")
    elseif((arg_NO_UNSUPPORTED_PLATFORM_ERROR OR
            QT_INTERNAL_NO_UNSUPPORTED_PLATFORM_ERROR)
        AND (arg_DEPLOY_USER_QML_MODULES_ON_UNSUPPORTED_PLATFORM
            OR QT_INTERNAL_DEPLOY_USER_QML_MODULES_ON_UNSUPPORTED_PLATFORM)
        AND QT6_IS_SHARED_LIBS_BUILD)
        # User project explicitly requested to deploy only user QML modules on a shared Qt libs
        # platform where qt_deploy_runtime_dependencies does not work.
        # This is useful for projects that will deploy the Qt QML and runtime libraries manually.
        # This also offers a migration path to enable qt_deploy_runtime_dependencies for
        # unsupported platforms without breaking projects that already handle runtime libs manually.
        # But for it to work cleanly, projects will have to enable both
        # NO_UNSUPPORTED_PLATFORM_ERROR and DEPLOY_USER_QML_MODULES_ON_UNSUPPORTED_PLATFORM
        # conditionally per platform.
        file(GENERATE OUTPUT "${file_name}" CONTENT "
include(${QT_DEPLOY_SUPPORT})
_qt_internal_show_skip_runtime_deploy_message(\"${qt_build_type_string}\")
qt_deploy_qml_imports(TARGET ${arg_TARGET} NO_QT_IMPORTS)
")
    elseif(NOT arg_NO_UNSUPPORTED_PLATFORM_ERROR AND NOT QT_INTERNAL_NO_UNSUPPORTED_PLATFORM_ERROR)
        # Currently we don't deploy runtime dependencies if cross-compiling or using a static Qt.
        # We also don't do it if targeting Linux, but we could provide an option to do
        # so if we had a deploy tool or purely CMake-based deploy implementation.
        # Error out by default unless the project opted out of the error.
        # This provides us a migration path in the future without breaking compatibility promises.
        message(FATAL_ERROR
            "Support for installing runtime dependencies is not implemented for "
            "this target platform (${CMAKE_SYSTEM_NAME}, ${qt_build_type_string})."
        )
    else()
        file(GENERATE OUTPUT "${file_name}" CONTENT "
include(${QT_DEPLOY_SUPPORT})
_qt_internal_show_skip_runtime_deploy_message(\"${qt_build_type_string}\")
_qt_internal_show_skip_qml_runtime_deploy_message()
")
    endif()

endfunction()

if(NOT QT_NO_CREATE_VERSIONLESS_FUNCTIONS)
    macro(qt_generate_deploy_qml_app_script)
        qt6_generate_deploy_qml_app_script(${ARGV})
    endmacro()
endif()

# This function is currently in Technical Preview.
# Its signature and behavior might change.
function(qt6_query_qml_module target)

    if(NOT TARGET ${target})
        message(FATAL_ERROR "\"${target}\" is not a target")
    endif()

    get_target_property(is_imported ${target} IMPORTED)
    if(is_imported)
        message(FATAL_ERROR
            "Only targets built by the project can be used with this command, "
            "but target \"${target}\" is imported."
        )
    endif()

    get_target_property(uri ${target} QT_QML_MODULE_URI)
    if(NOT uri)
        message(FATAL_ERROR
            "Target \"${target}\" does not appear to be a QML module"
            )
    endif()

    set(no_value_options "")
    set(single_value_options
        URI
        VERSION
        PLUGIN_TARGET
        MODULE_RESOURCE_PATH
        TARGET_PATH
        QMLDIR
        TYPEINFO
        QML_FILES
        QML_FILES_DEPLOY_PATHS   # relative to target path
        QML_FILES_PREFIX_OVERRIDES
        RESOURCES
        RESOURCES_DEPLOY_PATHS   # relative to target path
        RESOURCES_PREFIX_OVERRIDES
    )
    set(multi_value_options "")
    cmake_parse_arguments(PARSE_ARGV 1 arg
        "${no_value_options}" "${single_value_options}" "${multi_value_options}"
    )
    if(arg_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR "Unexpected arguments: ${arg_UNPARSED_ARGUMENTS}")
    endif()

    if(arg_URI)
        set(${arg_URI} "${uri}" PARENT_SCOPE)
    endif()

    if(arg_VERSION)
        get_property(version TARGET ${target} PROPERTY QT_QML_MODULE_VERSION)
        set(${arg_VERSION} "${version}" PARENT_SCOPE)
    endif()

    if(arg_PLUGIN_TARGET)
        # There might not be a plugin target, so return an empty string for that
        get_property(plugin_target TARGET ${target} PROPERTY QT_QML_MODULE_PLUGIN_TARGET)
        set(${arg_PLUGIN_TARGET} "${plugin_target}" PARENT_SCOPE)
    endif()

    if(arg_MODULE_RESOURCE_PATH)
        # Note that QT_QML_MODULE_RESOURCE_PREFIX is not the RESOURCE_PREFIX
        # passed to qt6_add_qml_module(). It is that plus the target path, which
        # corresponds to what we mean by the MODULE_RESOURCE_PATH.
        get_property(prefix TARGET ${target} PROPERTY QT_QML_MODULE_RESOURCE_PREFIX)
        set(${arg_MODULE_RESOURCE_PATH} "${prefix}" PARENT_SCOPE)
    endif()

    string(REPLACE "." "/" target_path "${uri}")
    if(arg_TARGET_PATH)
        set(${arg_TARGET_PATH} "${target_path}" PARENT_SCOPE)
    endif()

    get_target_property(output_dir ${target} QT_QML_MODULE_OUTPUT_DIRECTORY)

    if(arg_QMLDIR)
        set(${arg_QMLDIR} "${output_dir}/qmldir" PARENT_SCOPE)
    endif()

    # This should always be set to something non-empty
    get_target_property(typeinfo ${target} QT_QML_MODULE_TYPEINFO)
    if(arg_TYPEINFO)
        set(${arg_TYPEINFO} "${output_dir}/${typeinfo}" PARENT_SCOPE)
    endif()

    get_target_property(target_source_dir ${target} SOURCE_DIR)
    if(CMAKE_VERSION VERSION_GREATER_EQUAL 3.18)
        set(scope_option TARGET_DIRECTORY ${target})
    else()
        set(scope_option "")
        if(NOT target_source_dir STREQUAL CMAKE_CURRENT_SOURCE_DIR AND
           (arg_QML_FILES_DEPLOY_PATHS OR arg_RESOURCES_DEPLOY_PATHS))
            # This isn't a fatal error because it will only be a problem if any
            # qml or resource files actually have source file properties set.
            message(WARNING
                "Calling qt6_query_qml_module() from a different directory scope "
                "to the one in which target \"${target}\" was created. "
                "This requires CMake 3.18 or later to be robust, but you are using "
                "CMake ${CMAKE_VERSION}. Deployment paths may not be correct."
            )
        endif()
    endif()

    # Because of how CMake lists work, in particular appending empty strings,
    # we have to use a placeholder to represent empty values and then replace
    # them at the end. If we don't do this, any list that starts with an empty
    # value ends up discarding that empty value because it is indistinguishable
    # from an empty list.
    set(empty_placeholder "__qt_empty_placeholder__")

    foreach(file_set IN ITEMS QML_FILES RESOURCES)
        # NOTE: We converted these files to absolute paths already when storing them
        get_target_property(files ${target} QT_QML_MODULE_${file_set})

        if(arg_${file_set})
            set(${arg_${file_set}} "${files}" PARENT_SCOPE)
        endif()

        if(arg_${file_set}_DEPLOY_PATHS OR arg_${file_set}_PREFIX_OVERRIDES)
            set(deploy_paths "")
            set(prefix_overrides "")
            foreach(abs_file IN LISTS files)
                # The QT_QML_MODULE_PREFIX_OVERRIDE is the PREFIX value that was passed to
                # qt_target_qml_sources. It has no relation to the QT_QML_MODULE_RESOURCE_PREFIX
                # property or the computed MODULE_RESOURCE_PATH variable above.
                get_property(prefix_override SOURCE ${abs_file} ${scope_option}
                    PROPERTY QT_QML_MODULE_PREFIX_OVERRIDE
                )
                if("${prefix_override}" STREQUAL "")
                    list(APPEND prefix_overrides "${empty_placeholder}")
                else()
                    list(APPEND prefix_overrides "${prefix_override}")
                endif()

                # We can't provide a deploy path when the resource prefix is
                # overridden. We still need to store an empty deploy path for it
                # though so that the file lists all line up correctly.
                if(NOT "${prefix_override}" STREQUAL "")
                    list(APPEND deploy_paths "${empty_placeholder}")
                else()
                    # Careful how we check whether this property is set. Projects might
                    # use a resource alias that matches one of CMake's false constants,
                    # so we must use get_property(), not get_source_file_property(),
                    # then compare the result with an empty string.
                    get_property(alias
                                 SOURCE ${abs_file} ${scope_option} PROPERTY QT_RESOURCE_ALIAS)
                    if(NOT "${alias}" STREQUAL "")
                        list(APPEND deploy_paths "${alias}")
                    else()
                        file(RELATIVE_PATH rel_file ${target_source_dir} ${abs_file})
                        list(APPEND deploy_paths "${rel_file}")
                    endif()
                endif()
            endforeach()
            string(REPLACE "${empty_placeholder}" "" deploy_paths "${deploy_paths}")
            string(REPLACE "${empty_placeholder}" "" prefix_overrides "${prefix_overrides}")
            if(arg_${file_set}_DEPLOY_PATHS)
                set(${arg_${file_set}_DEPLOY_PATHS} "${deploy_paths}" PARENT_SCOPE)
            endif()
            if(arg_${file_set}_PREFIX_OVERRIDES)
                set(${arg_${file_set}_PREFIX_OVERRIDES} "${prefix_overrides}" PARENT_SCOPE)
            endif()
        endif()
    endforeach()
endfunction()

if(NOT QT_NO_CREATE_VERSIONLESS_FUNCTIONS)
    macro(qt_query_qml_module)
        qt6_query_qml_module(${ARGV})
    endmacro()
endif()


function(_qt_internal_add_static_qml_plugin_dependencies plugin_target backing_target)
    # Protect against multiple calls of qt_add_qml_plugin.
    get_target_property(plugin_deps_added "${plugin_target}" _qt_extra_static_qml_plugin_deps_added)
    if(plugin_deps_added)
        return()
    endif()
    set_target_properties("${plugin_target}" PROPERTIES _qt_extra_static_qml_plugin_deps_added TRUE)

    # Get the install plugin target name, which we will need for filtering later on.
    if(TARGET "${backing_target}")
        get_target_property(installed_plugin_target
                            "${backing_target}" _qt_qml_module_installed_plugin_target)
    endif()

    if(NOT backing_target STREQUAL plugin_target AND TARGET "${backing_target}")
        set(has_backing_lib TRUE)
    else()
        set(has_backing_lib FALSE)
    endif()

    get_target_property(plugin_type ${plugin_target} TYPE)
    set(skip_prl_marker "$<BOOL:QT_IS_PLUGIN_GENEX>")

    # If ${plugin_target} is a static qml plugin, recursively get its private dependencies (and its
    # backing lib private deps), identify which of those are qml modules, extract any associated qml
    # plugin target from those qml modules and make them dependencies of ${plugin_target}.
    #
    # E.g. this ensures that if a user project links directly to the static qtquick2plugin plugin
    # target (note the plugin target, not the backing lib) it will automatically also link to
    # Quick's transitive plugin dependencies: qmlplugin, modelsplugin and workerscriptplugin, in
    # addition to the the Qml, QmlModels and QmlWorkerScript backing libraries.
    #
    # Note this logic is not specific to qtquick2plugin, it applies to all static qml plugins.
    #
    # This eliminates the needed boilerplate to link to the full transitive closure of qml plugins
    # in user projects that don't want to use qmlimportscanner / qt_import_qml_plugins.
    set(additional_plugin_deps "")

    if(plugin_type STREQUAL "STATIC_LIBRARY")
        set(all_private_deps "")

        # We walk both plugin_target and backing_lib private deps because they can have differing
        # dependencies and we want to consider all of them.
        __qt_internal_collect_all_target_dependencies(
            "${plugin_target}" plugin_private_deps)
        if(plugin_private_deps)
            list(APPEND all_private_deps ${plugin_private_deps})
        endif()

        if(has_backing_lib)
            __qt_internal_collect_all_target_dependencies(
                "${backing_target}" backing_lib_private_deps)
            if(backing_lib_private_deps)
                list(APPEND all_private_deps ${backing_lib_private_deps})
            endif()
        endif()

        foreach(dep IN LISTS all_private_deps)
            if(NOT TARGET "${dep}")
                continue()
            endif()
            get_target_property(dep_type ${dep} TYPE)
            if(dep_type STREQUAL "STATIC_LIBRARY")
                set(associated_qml_plugin "")

                # Check if the target has an associated imported qml plugin (like a Qt-provided
                # one).
                get_target_property(associated_qml_plugin_candidate ${dep}
                    _qt_qml_module_installed_plugin_target)

                if(associated_qml_plugin_candidate AND TARGET "${associated_qml_plugin_candidate}")
                    set(associated_qml_plugin "${associated_qml_plugin_candidate}")
                endif()

                # Check if the target has an associated qml plugin that's built as part of the
                # current project (non-installed one, so without a target namespace prefix).
                get_target_property(associated_qml_plugin_candidate ${dep}
                    _qt_qml_module_plugin_target)

                if(NOT associated_qml_plugin AND
                        associated_qml_plugin_candidate
                        AND TARGET "${associated_qml_plugin_candidate}")
                    set(associated_qml_plugin "${associated_qml_plugin_candidate}")
                endif()

                # We need to filter out adding the plugin_target as a dependency to itself,
                # when walking the backing lib of the plugin_target.
                if(associated_qml_plugin
                        AND NOT associated_qml_plugin STREQUAL plugin_target
                        AND NOT associated_qml_plugin STREQUAL installed_plugin_target)
                    # Abuse a genex marker, to skip the dependency to be added into prl files.
                    # TODO: Introduce a more generic marker name in qtbase specifically
                    # for skipping deps in prl file deps generation.
                    set(wrapped_associated_qml_plugin
                        "$<${skip_prl_marker}:$<TARGET_NAME:${associated_qml_plugin}>>")

                    if(NOT wrapped_associated_qml_plugin IN_LIST additional_plugin_deps)
                        list(APPEND additional_plugin_deps "${wrapped_associated_qml_plugin}")
                    endif()
                endif()
            endif()
        endforeach()
    endif()

    if(additional_plugin_deps)
        target_link_libraries(${plugin_target} PRIVATE ${additional_plugin_deps})
    endif()
endfunction()

# The function returns the output name of a qml plugin that will be used as library output
# name and in a qmldir file as the 'plugin <plugin_output_name>' record.
function(_qt_internal_get_qml_plugin_output_name out_var plugin_target)
    cmake_parse_arguments(arg
        ""
        "BACKING_TARGET;TARGET_PATH;URI"
        ""
        ${ARGN}
    )
    set(plugin_name)
    if(TARGET ${plugin_target})
        get_target_property(plugin_name ${plugin_target} OUTPUT_NAME)
    endif()
    if(NOT plugin_name)
        set(plugin_name "${plugin_target}")
    endif()

    if(ANDROID)
        # In Android all plugins are stored in directly the /libs directory. This means that plugin
        # names must be unique in scope of apk. To make this work we prepend uri-based prefix to
        # each qml plugin in case if users don't use the manually written qmldir files.
        get_target_property(no_generate_qmldir ${target} QT_QML_MODULE_NO_GENERATE_QMLDIR)
        if(TARGET "${arg_BACKING_TARGET}")
            get_target_property(no_generate_qmldir ${arg_BACKING_TARGET}
                QT_QML_MODULE_NO_GENERATE_QMLDIR)

            # Adjust Qml plugin names on Android similar to qml_plugin.prf which calls
            # $$qt5LibraryTarget($$TARGET, "qml/$$TARGETPATH/").
            # Example plugin names:
            # qtdeclarative
            #   TARGET_PATH: QtQml/Models
            #   file name:   libqml_QtQml_Models_modelsplugin_x86_64.so
            # qtquickcontrols2
            #   TARGET_PATH: QtQuick/Controls.2/Material
            #   file name:
            #     libqml_QtQuick_Controls.2_Material_qtquickcontrols2materialstyleplugin_x86_64.so
            if(NOT arg_TARGET_PATH)
                get_target_property(arg_TARGET_PATH ${arg_BACKING_TARGET}
                QT_QML_MODULE_TARGET_PATH)
            endif()
        endif()
        if(arg_TARGET_PATH)
            string(REPLACE "/" "_" android_plugin_name_infix_name "${arg_TARGET_PATH}")
        else()
            string(REPLACE "." "_" android_plugin_name_infix_name "${arg_URI}")
        endif()

        # If plugin supposed to use manually written qmldir file we don't prepend the uri-based
        # prefix to the plugin output name. User should keep the file name of a QML plugin in
        # qmldir the same as the name of plugin on a file system. Exception is the
        # ABI-/platform-specific suffix that has the separate processing and should not be
        # a part of plugin name in qmldir.
        if(NOT no_generate_qmldir)
            set(plugin_name
                "qml_${android_plugin_name_infix_name}_${plugin_name}")
        endif()
    endif()

    set(${out_var} "${plugin_name}" PARENT_SCOPE)
endfunction()

# Used to add extra dependencies between ${target} and ${dep_target} qml plugins in a static
# Qt build, without creating a dependency in the genereated qmake .prl files.
# These dependencies make manual linking to static plugins a nicer experience for users that don't
# want to use qt_import_qml_plugins.
function(_qt_internal_add_qml_static_plugin_dependency target dep_target)
    if(NOT BUILD_SHARED_LIBS)
        # Abuse a genex marker, to skip the dependency to be added into prl files.
        # TODO: Introduce a more generic marker name in qtbase specifically
        # for skipping deps in prl file deps generation.
        set(skip_prl_marker "$<BOOL:QT_IS_PLUGIN_GENEX>")
        target_link_libraries("${target}" PRIVATE
            "$<${skip_prl_marker}:$<TARGET_NAME:${dep_target}>>")
    endif()
endfunction()
