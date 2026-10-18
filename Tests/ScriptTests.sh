#!/bin/bash
# Exercise build configuration and failures without touching the installed app.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p .test-scratch
scratch="$(mktemp -d "${PWD}/.test-scratch/scripts.XXXXXX")"
trap 'rm -rf "${scratch}"' EXIT
mkdir -p "${scratch}/script" "${scratch}/bin" "${scratch}/AgentIDE.xcodeproj"
printf '{"pins": [], "version": 3}\n' >"${scratch}/Package.resolved"
cp script/build script/install script/package script/analyze script/test script/project "${scratch}/script/"
cat >"${scratch}/script/version" <<'VERSION'
#!/bin/bash
printf '1.2.3\n42\n'
VERSION
for command in xcodegen codesign; do
  printf '#!/bin/bash\nexit 0\n' >"${scratch}/bin/${command}"
done
cat >"${scratch}/bin/xcodebuild" <<'BUILDER'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$@" >xcode-arguments
printf '%s\n' "$*" >>xcode-invocations
echo 'Build diagnostic on stdout'
echo 'Build diagnostic on stderr' >&2
[[ "${BUILD_TEST_FAIL:-}" != 1 ]] || exit 65
if [[ " $* " != *' ARCHS=arm64 '* ]]; then
  echo 'Package dependencies would also build unused Intel slices' >&2
  exit 1
fi
while [[ $# -gt 0 ]]; do
  if [[ "$1" == -configuration ]]; then
    mkdir -p ".DerivedData/Build/Products/$2/AgentIDE.app"
    break
  fi
  shift
done
BUILDER
cat >"${scratch}/bin/swift" <<'SWIFT'
#!/bin/bash
printf '%s\n' "$@" >swift-arguments
echo 'Build complete'
SWIFT
cat >"${scratch}/bin/ditto" <<'DITTO'
#!/bin/bash
[[ -d "$1" && "$2" == /Applications/AgentIDE.app ]] || exit 1
printf '%s\n' "$1" >installed-app
echo copy >>installation-events
DITTO
cat >"${scratch}/bin/osascript" <<'QUIT'
#!/bin/bash
[[ "$1" == -e && "$2" == 'quit app "AgentIDE"' ]] || exit 1
echo quit >>installation-events
# Quitting the app closes its shell panes and hangs up their commands.
kill -HUP "${PPID}"
QUIT
cat >"${scratch}/bin/open" <<'OPEN'
#!/bin/bash
[[ "$1" == /Applications/AgentIDE.app ]] || exit 1
echo open >>installation-events
OPEN
printf '#!/bin/bash\ntouch installation-started\necho replace >>installation-events\n' >"${scratch}/bin/rm"
printf '#!/bin/bash\ntouch keychain-accessed\nexit 99\n' >"${scratch}/bin/security"
chmod +x "${scratch}/script/"* "${scratch}/bin/"*

for configuration in Release Debug; do
  override="${configuration/Release/}"
  env PATH="${scratch}/bin:${PATH}" SV_SESSION_ID= XCODE_CONFIGURATION="${override}" \
    "${scratch}/script/build" >"${scratch}/build.log" 2>&1
  app=".DerivedData/Build/Products/${configuration}/AgentIDE.app"
  [[ "$(tail -1 "${scratch}/build.log")" == "${app}" ]] || exit 1
  [[ "$(readlink "${scratch}/AgentIDE.app")" == "${app}" ]] || exit 1
  cmp "${scratch}/Package.resolved" "${scratch}/AgentIDE.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
  touch -t 200001010000 "${scratch}/AgentIDE.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
  grep -qx -- -onlyUsePackageVersionsFromResolvedFile "${scratch}/xcode-arguments"
  grep -A 1 '^-clonedSourcePackagesDirPath$' "${scratch}/xcode-arguments" | grep -qx .build
  for stream in stdout stderr; do
    grep -q "Build diagnostic on ${stream}" "${scratch}/build.log"
  done
  : >"${scratch}/installation-events"
  env PATH="${scratch}/bin:${PATH}" SV_SESSION_ID= XCODE_CONFIGURATION="${override}" \
    "${scratch}/script/install" >"${scratch}/install.log" 2>&1
  [[ "$(cat "${scratch}/installed-app")" == "${app}" ]] || exit 1
  [[ "$(cat "${scratch}/installation-events")" == $'quit\nreplace\ncopy\nopen' ]] || exit 1
  [[ "$(stat -f %Sm -t %Y "${scratch}/AgentIDE.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")" == 2000 ]] || exit 1

  env PATH="${scratch}/bin:${PATH}" SV_SESSION_ID=fixture XCODE_CONFIGURATION="${override}" \
    "${scratch}/script/build" >"${scratch}/sandbox.log" 2>&1
  grep -A 1 '^--configuration$' "${scratch}/swift-arguments" |
    grep -qx "$(tr '[:upper:]' '[:lower:]' <<<"${configuration}")"
  grep -qx -- --force-resolved-versions "${scratch}/swift-arguments"
done

rm "${scratch}/installation-started"
: >"${scratch}/installation-events"
if env PATH="${scratch}/bin:${PATH}" SV_SESSION_ID= BUILD_TEST_FAIL=1 \
  "${scratch}/script/install" >"${scratch}/failure.log" 2>&1; then
  echo 'A failed build installed a stale app' >&2
  exit 1
fi
[[ ! -e "${scratch}/installation-started" ]] || exit 1
[[ ! -s "${scratch}/installation-events" ]] || exit 1
if env PATH="${scratch}/bin:${PATH}" SV_SESSION_ID=fixture \
  "${scratch}/script/install" >"${scratch}/failure.log" 2>&1; then
  echo 'A sandbox build installed a stale app' >&2
  exit 1
fi
[[ ! -e "${scratch}/installation-started" ]] || exit 1
[[ ! -s "${scratch}/installation-events" ]] || exit 1

for missing in DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD NOTARIZATION_KEY NOTARIZATION_KEY_ID NOTARIZATION_ISSUER_ID; do
  if env -i PATH="${scratch}/bin:/usr/bin:/bin" \
    DEVELOPER_ID_APPLICATION_CERTIFICATE=fixture DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD=fixture \
    NOTARIZATION_KEY=fixture NOTARIZATION_KEY_ID=fixture NOTARIZATION_ISSUER_ID=fixture "${missing}=" \
    "${scratch}/script/package" >"${scratch}/package.log" 2>&1; then
    echo "Packaging accepted missing ${missing}" >&2
    exit 1
  fi
  grep -q "${missing}" "${scratch}/package.log"
  [[ ! -e "${scratch}/keychain-accessed" ]] || exit 1
done
echo 'Build and packaging script tests passed'

mkdir -p "${scratch}/Tests" "${scratch}/.build"
printf 'only_rules: [trailing_newline]\n' >"${scratch}/.swiftlint.yml"
mkdir -p "${scratch}/App" "${scratch}/iOSApp" "${scratch}/Sources/Interface/"{macOS,iOS}
touch "${scratch}/Sources/Interface/"{macOS,iOS}/Font.swift
printf 'exit 0\n' >"${scratch}/Tests/ScriptTests.sh"
printf '#!/bin/bash\nexit 0\n' >"${scratch}/bin/ps"
cat >"${scratch}/bin/swift" <<'SWIFT'
#!/bin/bash
printf '%s\n' "$@" >swift-arguments
case "$*" in
  *--show-bin-path*) echo "${PWD}/.build/analyze/debug" ;;
  package*) echo '{}' ;;
  *) exit "${SCRIPT_TEST_STATUS:-0}" ;;
esac
SWIFT
cat >"${scratch}/bin/periphery" <<'PERIPHERY'
#!/bin/bash
printf '%s\n' "$@" >periphery-arguments
if [[ " $* " != *' --skip-build '* ]]; then
  echo 'Periphery rebuilt the project instead of reusing the index' >&2
  exit 99
fi
exit "${ANALYZE_TEST_STATUS:-0}"
PERIPHERY
cat >"${scratch}/bin/swiftlint" <<'SWIFTLINT'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >>swiftlint-invocations
"${SCRIPT_TEST_SWIFTLINT}" lint --config .swiftlint.yml --use-script-input-file-lists --no-cache --strict
exit "${ANALYZE_TEST_STATUS:-0}"
SWIFTLINT
chmod +x "${scratch}/bin/"*

real_swiftlint="$(command -v swiftlint)"
for sandbox in fixture ''; do
  for status in 0 1; do
    : >"${scratch}/xcode-invocations"
    : >"${scratch}/swiftlint-invocations"
    result=0
    env PATH="${scratch}/bin:${PATH}" SV_SESSION_ID="${sandbox}" ANALYZE_TEST_STATUS="${status}" \
      SCRIPT_TEST_SWIFTLINT="${real_swiftlint}" \
      "${scratch}/script/analyze" >"${scratch}/analyze.log" 2>&1 || result=$?
    [[ "${result}" == "${status}" ]] || {
      cat "${scratch}/analyze.log"
      exit 1
    }
    grep -qx -- --strict "${scratch}/periphery-arguments"
    grep -qx -- --index-store-path "${scratch}/periphery-arguments"
    awk '/^--index-exclude$/ { exclude = 1; next } /^--/ { exclude = 0 } exclude' \
      "${scratch}/periphery-arguments" | grep -Fxq '**/BuildToolPluginIntermediates/**'
    if [[ -z "${sandbox}" ]]; then
      grep -q -- '-scheme AgentIDEApp' "${scratch}/xcode-invocations"
      grep -q -- '-scheme AgentIDE-iOS' "${scratch}/xcode-invocations"
      grep -q -- 'generic/platform=iOS Simulator' "${scratch}/xcode-invocations"
      grep -qx 'AgentIDE-iOS' "${scratch}/periphery-arguments"
      grep -q -- '--compiler-log-path .build/analyze-build.log' "${scratch}/swiftlint-invocations"
      grep -q -- '--compiler-log-path .build/analyze-ios-build.log' "${scratch}/swiftlint-invocations"
      grep -qx 'Sources/Interface/macOS/Font.swift' "${scratch}/.build/analyze-mac-sources.xcfilelist"
      grep -qx 'Sources/Interface/iOS/Font.swift' "${scratch}/.build/analyze-ios-sources.xcfilelist"
      if grep -q '/iOS/' "${scratch}/.build/analyze-mac-sources.xcfilelist" ||
        grep -q '/macOS/' "${scratch}/.build/analyze-ios-sources.xcfilelist"; then
        echo 'Analysis mixed platform-specific sources' >&2
        exit 1
      fi
    fi
  done
done
xcodegen dump --type json | python3 -c '
import json
import sys

targets = json.load(sys.stdin)["targets"]
modules = [
    targets[name]["settings"]["base"].get("PRODUCT_MODULE_NAME", targets[name]["settings"]["base"]["PRODUCT_NAME"])
    for name in ["AgentIDEApp", "AgentIDE-iOS"]
]
assert len(set(modules)) == len(modules), "App targets share a Swift module name"
'
rm "${scratch}/periphery-arguments"
if env PATH="${scratch}/bin:${PATH}" SV_SESSION_ID=fixture SCRIPT_TEST_STATUS=65 \
  "${scratch}/script/analyze" >"${scratch}/analyze.log" 2>&1; then
  echo 'Analysis accepted a failed build' >&2
  exit 1
fi
[[ ! -f "${scratch}/periphery-arguments" ]] || exit 1

for sanitizer in address thread; do
  for status in 0 66; do
    result=0
    env PATH="${scratch}/bin:${PATH}" SV_SESSION_ID=fixture SCRIPT_TEST_STATUS="${status}" \
      "${scratch}/script/test" --sanitize "${sanitizer}" --scratch-path ".build/${sanitizer}-sanitizer" \
      >"${scratch}/test.log" 2>&1 || result=$?
    [[ "${result}" == "${status}" ]] || exit 1
    grep -qx -- --force-resolved-versions "${scratch}/swift-arguments"
    grep -A 1 '^--sanitize$' "${scratch}/swift-arguments" | grep -qx "${sanitizer}"
    grep -A 1 '^--scratch-path$' "${scratch}/swift-arguments" | grep -qx ".build/${sanitizer}-sanitizer"
  done
done
echo 'Analysis and sanitizer script tests passed'
