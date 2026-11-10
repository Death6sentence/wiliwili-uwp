cmake_minimum_required(VERSION 3.20)

# Project Info
project(wiliwili-uwp)

set(VERSION_MAJOR "1")
set(VERSION_MINOR "6")
set(VERSION_REVISION "0")
set(VERSION_BUILD "99")
set(PROJECT_AUTHOR "xfangfang")
set(PACKAGE_NAME cn.xfangfang.wiliwili)
set(APP_VERSION "${VERSION_MAJOR}.${VERSION_MINOR}.${VERSION_REVISION}")
set(GIT_TAG_VERSION "${VERSION_MAJOR}.${VERSION_MINOR}.${VERSION_REVISION}-uwp-unofficial")
set(GIT_TAG_SHORT "uwp-unofficial")

set(DISABLE_OPENCC ON)

# version
list(APPEND APP_PLATFORM_OPTION
   -DBUILD_PACKAGE_NAME=${PACKAGE_NAME}
   -DBUILD_VERSION_MAJOR=${VERSION_MAJOR}
   -DBUILD_VERSION_MINOR=${VERSION_MINOR}
   -DBUILD_VERSION_REVISION=${VERSION_REVISION}
)

#git_info(GIT_TAG_VERSION GIT_TAG_SHORT)
list(APPEND APP_PLATFORM_OPTION -DBUILD_TAG_VERSION=${GIT_TAG_VERSION} -DBUILD_TAG_SHORT=${GIT_TAG_SHORT})

# Keep the Store project separate from the upstream test-certificate build.
option(WILIWILI_STORE_BUILD "Generate the unsigned Xbox Store project" OFF)
set(WILIWILI_MPV_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/libs/mpv" CACHE PATH "UWP libmpv directory")

if(WILIWILI_STORE_BUILD)
    set(WILIWILI_STORE_MANIFEST "${CMAKE_CURRENT_SOURCE_DIR}/wiliwili-uwp/package.appxManifest"
        CACHE FILEPATH "Store manifest for this build")
    set(TEMPLATE_FILES "${CMAKE_CURRENT_BINARY_DIR}/Package.appxmanifest")
    configure_file("${WILIWILI_STORE_MANIFEST}" "${TEMPLATE_FILES}" COPYONLY)
    set(PACKAGE_ASSETS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/wiliwili-uwp/StoreAssets")
else()
    set(PACKAGE_ASSETS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/wiliwili-uwp/Assets")
    set(TEMPLATE_FILES
        ${CMAKE_CURRENT_SOURCE_DIR}/wiliwili-uwp/Sideload.appxmanifest
        ${CMAKE_CURRENT_SOURCE_DIR}/wiliwili-uwp/Windows_TemporaryKey.pfx
    )
endif()

file(GLOB_RECURSE PACKAGE_ASSETS_FILES "${PACKAGE_ASSETS_DIR}/*")
set_property(SOURCE ${PACKAGE_ASSETS_FILES} PROPERTY VS_DEPLOYMENT_CONTENT 1)
set_property(SOURCE ${PACKAGE_ASSETS_FILES} PROPERTY VS_DEPLOYMENT_LOCATION "Assets")

# resource
set(PROJECT_RESOURCES "${CMAKE_CURRENT_SOURCE_DIR}/wiliwili/resources")

function(add_deployment_content BASE_PATH FILE)
    set_property(SOURCE ${FILE} PROPERTY VS_TOOL_OVERRIDE None)
    set_property(SOURCE ${FILE} PROPERTY VS_DEPLOYMENT_CONTENT 1)
    get_filename_component(FILE_DIR ${FILE} DIRECTORY ABSOLUTE)
    file(RELATIVE_PATH TARGET_PATH ${BASE_PATH} ${FILE_DIR})
    set_property(SOURCE ${FILE} PROPERTY VS_DEPLOYMENT_LOCATION ${TARGET_PATH})
endfunction(add_deployment_content)

file(GLOB_RECURSE PROJECT_RESOURCES_FILES "${PROJECT_RESOURCES}/*")

foreach(FILE IN LISTS PROJECT_RESOURCES_FILES)
    add_deployment_content("${PROJECT_RESOURCES}/.." "${FILE}")
endforeach()
source_group(TREE "${PROJECT_RESOURCES}" PREFIX "resource" FILES ${PROJECT_RESOURCES_FILES})

# source 
set(HEADER_INCLUDES)

file(GLOB_RECURSE MAIN_SRC "${CMAKE_CURRENT_SOURCE_DIR}/wiliwili/wiliwili/source/*.cpp")
list(APPEND HEADER_INCLUDES ${CMAKE_CURRENT_SOURCE_DIR}/wiliwili/wiliwili/include)
list(APPEND HEADER_INCLUDES ${CMAKE_CURRENT_SOURCE_DIR}/wiliwili/wiliwili/include/api)

file(GLOB_RECURSE PDR_SRC ${CMAKE_CURRENT_SOURCE_DIR}/wiliwili/library/libpdr/src/*.cpp)
list(APPEND HEADER_INCLUDES ${CMAKE_CURRENT_SOURCE_DIR}/wiliwili/library/libpdr/include)

file(GLOB_RECURSE PYSTRING_SRC ${CMAKE_CURRENT_SOURCE_DIR}/wiliwili/library/pystring/*.cpp)
list(APPEND HEADER_INCLUDES ${CMAKE_CURRENT_SOURCE_DIR}/wiliwili/library/pystring)

source_group(TREE "${CMAKE_CURRENT_SOURCE_DIR}/wiliwili" PREFIX "sources" FILES ${MAIN_SRC} ${PDR_SRC} ${PYSTRING_SRC})

if(WILIWILI_STORE_BUILD)
    # Keep the pinned checkout pristine and use certificate validation by default.
    set(config_source "${CMAKE_CURRENT_SOURCE_DIR}/wiliwili/wiliwili/source/utils/config_helper.cpp")
    set(store_config_source "${CMAKE_CURRENT_BINARY_DIR}/store-config-helper.cpp")
    set(upstream_tls_condition "#if defined(__PSV__) || defined(__SWITCH__) || defined(PS4) || defined(__WINRT__)")
    file(READ "${config_source}" upstream_config)
    string(REPLACE "${upstream_tls_condition}"
        "#if defined(__PSV__) || defined(__SWITCH__) || defined(PS4)"
        store_config "${upstream_config}")
    if(store_config STREQUAL upstream_config)
        message(FATAL_ERROR "The pinned UWP TLS default changed. Review the Store TLS configuration.")
    endif()
    file(WRITE "${store_config_source}" "${store_config}")
    list(REMOVE_ITEM MAIN_SRC "${config_source}")
    list(APPEND MAIN_SRC "${store_config_source}")
endif()


file(GLOB_RECURSE PROJECT_RESOURCES2 "${WILIWILI_MPV_ROOT}/bin/*.dll")
set_property(SOURCE ${PROJECT_RESOURCES2} PROPERTY VS_DEPLOYMENT_CONTENT 1)
set_property(SOURCE ${PROJECT_RESOURCES2} PROPERTY VS_DEPLOYMENT_LOCATION ".")

# Target
add_executable(${PROJECT_NAME} WIN32 ${MAIN_SRC} ${PDR_SRC} ${PROJECT_RESOURCES2} ${PYSTRING_SRC} ${TEMPLATE_FILES} ${PROJECT_RESOURCES_FILES} ${PACKAGE_ASSETS_FILES})


if(WILIWILI_STORE_BUILD)
    set_target_properties(${PROJECT_NAME} PROPERTIES
        VS_WINDOWS_TARGET_PLATFORM_MIN_VERSION "10.0.17763.0"
        VS_GLOBAL_AppxPackageSigningEnabled "false"
    )
endif()

list(APPEND HEADER_INCLUDES "${WILIWILI_MPV_ROOT}/include")
target_link_libraries(${PROJECT_NAME} "${WILIWILI_MPV_ROOT}/lib/mpv.lib")

find_package(lunasvg CONFIG REQUIRED)
target_link_libraries(${PROJECT_NAME} lunasvg::lunasvg)

add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/wiliwili/library/mongoose EXCLUDE_FROM_ALL)
target_link_libraries(${PROJECT_NAME} mongoose)

find_package(unofficial-nayuki-qr-code-generator CONFIG REQUIRED)
target_link_libraries(${PROJECT_NAME} unofficial::nayuki-qr-code-generator::nayuki-qr-code-generator)

find_package(OpenSSL REQUIRED)
target_link_libraries(${PROJECT_NAME} OpenSSL::SSL OpenSSL::Crypto)

find_package(CURL REQUIRED)
target_link_libraries(${PROJECT_NAME} CURL::libcurl)

find_package(ZLIB REQUIRED)
target_link_libraries(${PROJECT_NAME}  ZLIB::ZLIB)

find_package(cpr CONFIG REQUIRED)
target_link_libraries(${PROJECT_NAME} cpr::cpr)

target_link_libraries(${PROJECT_NAME} borealis)

target_include_directories(${PROJECT_NAME} PUBLIC  ${HEADER_INCLUDES} )
target_compile_options(${PROJECT_NAME} PRIVATE -DBRLS_RESOURCES_DIR="." ${APP_PLATFORM_OPTION})
target_compile_definitions(${PROJECT_NAME} PRIVATE NO_GA BOREALIS_USE_STD_THREAD __WINRT__ __WINRT_NEW__ BOREALIS_USE_D3D11  NOMINMAX _SILENCE_ALL_CXX17_DEPRECATION_WARNINGS _WINSOCK_DEPRECATED_NO_WARNINGS _CRT_SECURE_NO_WARNINGS _CRT_NONSTDC_NO_WARNINGS)
