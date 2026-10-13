load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "VisualQuote",
    module_name = "VisualQuote",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/AsyncDisplayKit",
        "//submodules/Display",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/AccountContext",
        "//submodules/TelegramPresentationData",
        "//submodules/ComponentFlow",
        "//submodules/Components/ComponentDisplayAdapters",
        "//submodules/TelegramUI/Components/GlassControls",
        "//submodules/TelegramUI/Components/MediaEditor/ImageObjectSeparation",
    ],
    visibility = [
        "//visibility:public",
    ],
)
