# Visual Quote prototype

Prototype of "Visual Quote": replying to a specific detail of a received photo inside the official Telegram-iOS client, the same way a text quote replies to a fragment of text.

Work in progress. This file will grow with each milestone; for now it records how to build and run the simulator build.

## Requirements (verified 2026-10-12)

- macOS 26, Xcode 26.6 (the version pinned in `versions.json`), iOS 26.5 simulator runtime.
- Xcode's **Metal Toolchain** component. It is not installed with Xcode 26 by default and the build fails in `MetalCompile` without it:
  ```sh
  xcodebuild -downloadComponent MetalToolchain
  ```
- Python 3, ~20 GB of free disk space (clone, Bazel cache and outputs).
- A build configuration JSON (see `build-system/template_minimal_development_configuration.json`) with your own `api_id` / `api_hash` from https://my.telegram.org/apps. Keep it outside the repository.

## Simulator build without a developer account

Code signing is not needed in the simulator. The build uses the fake profiles shipped in `build-system/fake-codesigning`. Those profiles are issued for `team_id = C67CF9S4VU` and `bundle_id = ph.telegra.Telegraph`, and `Make.py` only picks profiles whose `application-identifier` equals `<team_id>.<bundle_id>`, so the configuration JSON must use exactly these two values.

From the repository root:

```sh
python3 build-system/Make/Make.py --cacheDir="$HOME/telegram-bazel-cache" build \
  --configurationPath="$HOME/Developer/telegram-config/build-config.json" \
  --codesigningInformationPath=build-system/fake-codesigning \
  --buildNumber=1 --configuration=debug_sim_arm64
```

A clean build takes about 10 minutes on an M1 Pro. The result is `bazel-bin/Telegram/Telegram.ipa`.

## Install and run in the simulator

```sh
STAGE=$(mktemp -d)
unzip -q -o bazel-bin/Telegram/Telegram.ipa -d "$STAGE"
xcrun simctl install booted "$STAGE/Payload/Telegram.app"
xcrun simctl launch booted ph.telegra.Telegraph
```

When reinstalling a rebuilt app with the same build number, copy the whole `.app` over the installed bundle instead of `simctl install` (see the repository `CLAUDE.md`, "Updating the running simulator after a rebuild").

## Telegram test servers

Launching with the `--ui-test` argument makes the client use Telegram's test datacenters and an isolated data directory that is wiped on every launch. Test phone numbers are `+999 66X YYYY` and the login code is the DC digit `X` repeated five times (see `docs/ui-testing.md`).
