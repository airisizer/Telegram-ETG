load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@rules_cc//cc:objc_library.bzl", "objc_library")
load("@build_bazel_rules_apple//apple:apple.bzl", "apple_dynamic_xcframework_import")

# C-бридж Python→Swift (нативный CPython-модуль _etg).
# Заголовки CPython подкладывает CI (Python.xcframework из BeeWare).
objc_library(
    name = "ETGBridge",
    srcs = ["Sources/ETGBridge/PythonBridge.c"],
    hdrs = ["Sources/ETGBridge/include/PythonBridge.h"],
    copts = [
        # Путь к заголовкам CPython внутри xcframework (arm64-слайс для девайса).
        "-Isubmodules/PluginsEngine/third_party_python/Python.xcframework/ios-arm64/Python.framework/Headers",
    ],
    includes = ["Sources/ETGBridge/include"],
    module_name = "ETGBridge",
    visibility = ["//visibility:public"],
)

# Заголовки CPython как clang-модуль для Swift (import CPython).
objc_library(
    name = "CPython",
    hdrs = glob(["Sources/CPython/**/*"]),
    copts = [
        "-Isubmodules/PluginsEngine/third_party_python/Python.xcframework/ios-arm64/Python.framework/Headers",
    ],
    includes = ["Sources/CPython"],
    module_name = "CPython",
    textual_hdrs = [],
    visibility = ["//visibility:public"],
)

swift_library(
    name = "PluginsEngine",
    module_name = "PluginsEngine",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    deps = [
        ":ETGBridge",
        ":CPython",
        ":PythonLib",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/Postbox:Postbox",
        "//submodules/AccountContext:AccountContext",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# Статическая CPython-библиотека (xcframework кладётся CI-шагом в
# third-party/python/). Линкуется в приложение.
apple_dynamic_xcframework_import(
    name = "PythonLib",
    xcframework_imports = glob(
        ["third_party_python/Python.xcframework/**"],
        allow_empty = True,
    ),
    visibility = ["//visibility:public"],
)

# Python-совместимый слой (extera SDK) + stdlib — ОДНИМ tar-файлом.
# plugins-sdk.tar собирается CI-шагом (sdk/ → tar); локальная сборка без
# Python просто не включит ресурс (allow_empty) — движок сам отключится.
filegroup(
    name = "PythonSdkBundle",
    srcs = glob(["plugins-sdk.tar"], allow_empty = True),
    visibility = ["//visibility:public"],
)
