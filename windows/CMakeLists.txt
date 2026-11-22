# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(reader LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "easy_copy")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  if(MSVC)
    target_compile_options(${TARGET} PRIVATE /utf-8)
  endif()
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
if(POLICY CMP0175)
  set(CMAKE_POLICY_DEFAULT_CMP0175 OLD)
endif()

if(NUGET AND NOT EXISTS "${NUGET}")
  unset(NUGET CACHE)
endif()
find_program(NUGET nuget HINTS "${CMAKE_BINARY_DIR}")
if(NOT NUGET)
  set(NUGET "${CMAKE_BINARY_DIR}/nuget.exe")
  message(STATUS "Downloading NuGet for Windows plugin dependencies.")
  set(nuget_previous_no_proxy "$ENV{NO_PROXY}")
  set(ENV{NO_PROXY} "*")
  file(DOWNLOAD "https://dist.nuget.org/win-x86-commandline/v5.10.0/nuget.exe"
    "${NUGET}.tmp" TLS_VERIFY ON STATUS nuget_status)
  set(ENV{NO_PROXY} "${nuget_previous_no_proxy}")
  list(GET nuget_status 0 nuget_exit_code)
  if(NOT nuget_exit_code EQUAL 0)
    file(REMOVE "${NUGET}.tmp")
    list(GET nuget_status 1 nuget_error)
    message(FATAL_ERROR "NuGet download failed: ${nuget_error}")
  endif()
  file(RENAME "${NUGET}.tmp" "${NUGET}")
  set(NUGET "${NUGET}" CACHE FILEPATH "NuGet executable for Windows plugin dependencies" FORCE)
endif()

# Only the Android implementation of path_provider uses JNI. Its transitive
# Flutter FFI plugin also probes for a desktop JVM when a JDK is installed.
set(CMAKE_DISABLE_FIND_PACKAGE_JNI TRUE)
include(flutter/generated_plugins.cmake)

# Use our corrected dispose handler with webview_windows 0.4.0 (EasyCopy #21).
get_target_property(webview_dir webview_windows_plugin SOURCE_DIR)
get_target_property(webview_sources webview_windows_plugin SOURCES)
list(TRANSFORM webview_sources REPLACE "^webview_windows_plugin[.]cc$"
  "${CMAKE_CURRENT_SOURCE_DIR}/third_party/webview_windows/webview_windows_plugin.cc")
set_property(TARGET webview_windows_plugin PROPERTY SOURCES "${webview_sources}")
target_include_directories(webview_windows_plugin PRIVATE "${webview_dir}")

# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(CODE "
  if(CMAKE_INSTALL_CONFIG_NAME MATCHES \"^([Pp][Rr][Oo][Ff][Ii][Ll][Ee]|[Rr][Ee][Ll][Ee][Aa][Ss][Ee])$\")
    if(EXISTS \"${AOT_LIBRARY}\")
      file(INSTALL DESTINATION \"${INSTALL_BUNDLE_DATA_DIR}\" TYPE FILE FILES \"${AOT_LIBRARY}\")
    elseif(NOT EXISTS \"${INSTALL_BUNDLE_DATA_DIR}/app.so\")
      message(FATAL_ERROR \"AOT library not found: ${AOT_LIBRARY}\")
    endif()
  endif()
  " COMPONENT Runtime)
