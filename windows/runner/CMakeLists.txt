cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "../native/windows_backend_bridge.cpp"
  "../proxy/system_proxy_manager.cpp"
  "../xray/xray_process_manager.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "wininet.lib" "advapi32.lib" "shell32.lib" "secur32.lib")
# Flutter-generated headers are rooted at windows/, while native bridge
# headers use paths rooted at the Flutter project directory.
target_include_directories(${BINARY_NAME} PRIVATE
  "${CMAKE_SOURCE_DIR}"
  "${CMAKE_SOURCE_DIR}/.."
)
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_CURRENT_BINARY_DIR}")

# Private build inputs can come from windows/local.properties for local builds
# or environment variables for CI. The generated header stays in the build
# directory and the raw values are never tracked by Git.
set(NIRAN_LOCAL_PROPERTIES "${CMAKE_SOURCE_DIR}/local.properties")
function(NIRAN_PRIVATE_INPUT INPUT_NAME OUTPUT_NAME)
  set(INPUT_VALUE "$ENV{${INPUT_NAME}}")
  if(INPUT_VALUE STREQUAL "" AND EXISTS "${NIRAN_LOCAL_PROPERTIES}")
    file(STRINGS "${NIRAN_LOCAL_PROPERTIES}" INPUT_LINES REGEX "^[ \\t]*${INPUT_NAME}[ \\t]*=")
    if(INPUT_LINES)
      list(GET INPUT_LINES 0 INPUT_LINE)
      string(REGEX REPLACE
        "^[ \t]*${INPUT_NAME}[ \t]*=" "" INPUT_VALUE "${INPUT_LINE}")
      string(STRIP "${INPUT_VALUE}" INPUT_VALUE)
    endif()
  endif()
  set(${OUTPUT_NAME} "${INPUT_VALUE}" PARENT_SCOPE)
endfunction()

NIRAN_PRIVATE_INPUT("NIRANG_SUBSCRIPTION_URL" NIRAN_SUBSCRIPTION_URL)
NIRAN_PRIVATE_INPUT("NIRANG_TELEGRAM_URL" NIRAN_TELEGRAM_URL)
NIRAN_PRIVATE_INPUT("NIRANG_TELEGRAM_CONTACT" NIRAN_TELEGRAM_CONTACT)
configure_file("private_config.h.in" "${CMAKE_CURRENT_BINARY_DIR}/private_config.h" @ONLY)

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
