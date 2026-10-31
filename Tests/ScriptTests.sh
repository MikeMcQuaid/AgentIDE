#!/bin/bash
# Exercise development scripts without touching the installed app.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p .test-scratch
scratch="$(mktemp -d "${PWD}/.test-scratch/scripts.XXXXXX")"
trap 'rm -rf "${scratch}"' EXIT
[[ "$(readlink bin/agentide)" == sanductor ]]
mkdir -p "${scratch}/workspace/repositories/example/.git"
for command in sanductor agentide; do
  SHARED_WORKSPACE="${scratch}/workspace" "bin/${command}" repositories \
    >"${scratch}/${command}.out" 2>"${scratch}/${command}.err"
  [[ "$(cat "${scratch}/${command}.out")" == example ]]
done
[[ ! -s "${scratch}/sanductor.err" ]]
grep -qx "Warning: 'agentide' is deprecated; use 'sanductor' instead." "${scratch}/agentide.err"
echo 'Deprecated command compatibility tests passed'

mkdir -p "${scratch}/public-bin"
ln -s "${PWD}/bin/sanductor" "${scratch}/public-bin/sanductor"
SHARED_WORKSPACE="${scratch}/workspace" "${scratch}/public-bin/sanductor" repositories \
  >"${scratch}/linked.out" 2>"${scratch}/linked.err"
[[ "$(cat "${scratch}/linked.out")" == example && ! -s "${scratch}/linked.err" ]]

env -u SANDUCTOR_EDITS AGENTIDE_EDITS="${scratch}/legacy-edits" \
  bin/sanductor "${scratch}/file" >"${scratch}/legacy.out" 2>"${scratch}/legacy.err"
[[ ! -s "${scratch}/legacy.out" ]]
grep -qx 'Warning: AGENTIDE_EDITS is deprecated; use SANDUCTOR_EDITS instead.' "${scratch}/legacy.err"
[[ -n "$(find "${scratch}/legacy-edits" -name '*.request' -print)" ]]
# shellcheck disable=SC2016 # Deliberate literal shell syntax tests injection resistance.
legacy_value='$(touch should-not-exist)`touch should-not-exist` with spaces'
# shellcheck disable=SC2016 # Only the child shell expands the variable.
env -u SANDUCTOR_EDITS AGENTIDE_EDITS="${legacy_value}" /bin/sh -c \
  '. bin/environment.sh; printf "%s" "${SANDUCTOR_EDITS}"' \
  >"${scratch}/literal.out" 2>"${scratch}/literal.err"
[[ "$(cat "${scratch}/literal.out")" == "${legacy_value}" ]]
[[ ! -e should-not-exist ]]
# shellcheck disable=SC2016 # Only the child shell expands the variable.
SANDUCTOR_EDITS='' AGENTIDE_EDITS=old /bin/sh -c \
  '. bin/environment.sh; printf "%s" "${SANDUCTOR_EDITS}"' \
  >"${scratch}/canonical.out" 2>"${scratch}/canonical.err"
[[ ! -s "${scratch}/canonical.out" && ! -s "${scratch}/canonical.err" ]]
echo 'Legacy environment compatibility tests passed'

mkdir -p "${scratch}/script" "${scratch}/bin" "${scratch}/Sanductor.xcodeproj"
cp bin/environment.sh "${scratch}/bin/"

sed 's/families=(shell github_actions docs swift)/families=(docs)/' script/style >"${scratch}/script/style"
touch "${scratch}/AGENTS.md"
ln -s AGENTS.md "${scratch}/CLAUDE.md"
markers=('-' '*' '+')
for heading in 'Features' '✨ Features'; do
  for count in 0 9 10 11; do
    {
      printf '%s\n' '## Requirements' '- Prerequisite' "## ${heading}"
      for ((feature = 0; feature < count; feature++)); do
        printf '%s Feature\n' "${markers[feature % 3]}"
      done
      printf '%s\n' '## Configuration' '- Setting'
    } >"${scratch}/README.md"
    result=0
    bash "${scratch}/script/style" >"${scratch}/style.log" 2>&1 || result=$?
    if [[ "${result}" -ne $((count > 10)) ]]; then
      cat "${scratch}/style.log"
      echo "README style check returned ${result} for ${count} bullets under ${heading}" >&2
      exit 1
    fi
    if [[ "${count}" -gt 10 ]]; then
      grep -q 'README.md:.*Features must contain at most 10 bullets' "${scratch}/style.log"
    fi
  done
done
for count in 179 180 181; do
  for wrapped in 0 1; do
    awk -v count="${count}" -v wrapped="${wrapped}" 'BEGIN {
      for (line = 0; line < count; line++) {
        printf "%-72s%s", "README text.", wrapped ? "\n" : ""
      }
      if (!wrapped) print ""
    }' >"${scratch}/README.md"
    result=0
    bash "${scratch}/script/style" >"${scratch}/style.log" 2>&1 || result=$?
    if [[ "${result}" -ne $((count > 180)) ]]; then
      cat "${scratch}/style.log"
      echo "README style check returned ${result} for ${count} wrapped lines (wrapped=${wrapped})" >&2
      exit 1
    fi
    if [[ "${count}" -gt 180 ]]; then
      grep -q 'README.md: 181 lines when wrapped at 72 columns (maximum 180)' "${scratch}/style.log"
    fi
  done
done
echo 'README style tests passed'

printf '{"pins": [], "version": 3}\n' >"${scratch}/Package.resolved"
cp script/bootstrap script/build script/install script/package script/analyze script/test script/package-pins "${scratch}/script/"
cat >"${scratch}/script/version" <<'VERSION'
#!/bin/bash
printf '1.2.3\n42\n'
VERSION
printf '#!/bin/bash\nexit 0\n' >"${scratch}/bin/codesign"
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
case "$*" in
  *'-scheme SanductorApp'*)
    echo "/usr/bin/swiftc -module-name Sanductor ${PWD}/Sources/Interface/macOS/Font.swift"
    ;;
  *'-scheme Sanductor-iOS'*)
    echo "/usr/bin/swiftc -module-name SanductoriOS ${PWD}/Sources/Interface/iOS/Font.swift"
    ;;
esac
for source in "${PWD}"/Sources/*.swift "${PWD}"/Sources/SanductorDomain/*.swift; do
  [[ -f "${source}" ]] || continue
  printf '/usr/bin/swiftc -module-name Shared %q\n' "${source}"
done
while [[ $# -gt 0 ]]; do
  if [[ "$1" == -configuration ]]; then
    mkdir -p ".DerivedData/Build/Products/$2/Sanductor.app"
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
[[ -d "$1" && "$2" == /Applications/Sanductor.app && ! -e app-running ]] || exit 1
printf '%s\n' "$1" >installed-app
echo copy >>installation-events
DITTO
cat >"${scratch}/bin/osascript" <<'QUIT'
#!/bin/bash
[[ "$*" == *'quit app "Sanductor"'* ]] || exit 1
echo quit >>installation-events
# Quitting the app closes its shell panes and hangs up their commands.
kill -HUP "${PPID}"
[[ "${INSTALL_TEST_STUCK:-}" == 1 ]] || /bin/rm -f app-running
QUIT
cat >"${scratch}/bin/pgrep" <<'PGREP'
#!/bin/bash
[[ "$*" == "-u $(id -u) -x Sanductor" ]] || exit 99
[[ -e app-running ]]
PGREP
cat >"${scratch}/bin/pkill" <<'PKILL'
#!/bin/bash
[[ "$*" == "-KILL -u $(id -u) -x Sanductor" ]] || exit 99
echo kill >>installation-events
[[ "${INSTALL_TEST_UNKILLABLE:-}" == 1 ]] || /bin/rm -f app-running
PKILL
printf '#!/bin/bash\nexit 0\n' >"${scratch}/bin/sleep"
cat >"${scratch}/bin/open" <<'OPEN'
#!/bin/bash
[[ "$1" == /Applications/Sanductor.app && ! -e app-running ]] || exit 1
echo open >>installation-events
OPEN
printf '#!/bin/bash\ntouch installation-started\necho replace >>installation-events\n' >"${scratch}/bin/rm"
printf '#!/bin/bash\ntouch keychain-accessed\nexit 99\n' >"${scratch}/bin/security"
chmod +x "${scratch}/script/"* "${scratch}/bin/"*

cat >"${scratch}/bin/brew" <<'BREW'
#!/bin/bash
printf '%s\n' "$*" >>brew-invocations
if [[ "$*" == 'bundle check' ]]; then
  exit "${BOOTSTRAP_TEST_MISSING:-0}"
fi
exit "${BOOTSTRAP_TEST_STATUS:-0}"
BREW
chmod +x "${scratch}/bin/brew"
for missing in 0 1; do
  : >"${scratch}/brew-invocations"
  env PATH="${scratch}/bin:${PATH}" BOOTSTRAP_TEST_MISSING="${missing}" "${scratch}/script/bootstrap"
  [[ "$(head -1 "${scratch}/brew-invocations")" == 'bundle check' ]] || exit 1
  [[ "$(wc -l <"${scratch}/brew-invocations")" -eq $((missing + 1)) ]] || exit 1
done
: >"${scratch}/brew-invocations"
env PATH="${scratch}/bin:${PATH}" "${scratch}/script/bootstrap" swiftlint ripgrep
[[ "$(cat "${scratch}/brew-invocations")" == 'install swiftlint ripgrep' ]] || exit 1
if env PATH="${scratch}/bin:${PATH}" BOOTSTRAP_TEST_STATUS=1 "${scratch}/script/bootstrap" ripgrep; then
  echo 'Bootstrap accepted a failed dependency installation' >&2
  exit 1
fi

for configuration in Release Debug; do
  override="${configuration/Release/}"
  env PATH="${scratch}/bin:${PATH}" SV_SESSION_ID= XCODE_CONFIGURATION="${override}" \
    "${scratch}/script/build" >"${scratch}/build.log" 2>&1
  app=".DerivedData/Build/Products/${configuration}/Sanductor.app"
  [[ "$(tail -1 "${scratch}/build.log")" == "${app}" ]] || exit 1
  [[ "$(readlink "${scratch}/Sanductor.app")" == "${app}" ]] || exit 1
  cmp "${scratch}/Package.resolved" "${scratch}/Sanductor.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
  touch -t 200001010000 "${scratch}/Sanductor.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
  grep -qx -- -onlyUsePackageVersionsFromResolvedFile "${scratch}/xcode-arguments"
  grep -A 1 '^-clonedSourcePackagesDirPath$' "${scratch}/xcode-arguments" | grep -qx .build
  for stream in stdout stderr; do
    grep -q "Build diagnostic on ${stream}" "${scratch}/build.log"
  done
  : >"${scratch}/installation-events"
  touch "${scratch}/app-running"
  env PATH="${scratch}/bin:${PATH}" SV_SESSION_ID= XCODE_CONFIGURATION="${override}" \
    "${scratch}/script/install" >"${scratch}/install.log" 2>&1
  for stream in stdout stderr; do
    grep -q "Build diagnostic on ${stream}" "${scratch}/install.log"
  done
  [[ "$(cat "${scratch}/installed-app")" == "${app}" ]] || exit 1
  [[ "$(cat "${scratch}/installation-events")" == $'quit\nreplace\ncopy\nopen' ]] || exit 1
  [[ "$(stat -f %Sm -t %Y "${scratch}/Sanductor.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")" == 2000 ]] || exit 1

  env PATH="${scratch}/bin:${PATH}" SV_SESSION_ID=fixture XCODE_CONFIGURATION="${override}" \
    "${scratch}/script/build" >"${scratch}/sandbox.log" 2>&1
  grep -A 1 '^--configuration$' "${scratch}/swift-arguments" |
    grep -qx "$(tr '[:upper:]' '[:lower:]' <<<"${configuration}")"
  grep -qx -- --force-resolved-versions "${scratch}/swift-arguments"
done

for stuck in 1 0; do
  : >"${scratch}/installation-events"
  [[ "${stuck}" == 0 ]] || touch "${scratch}/app-running"
  env PATH="${scratch}/bin:${PATH}" SV_SESSION_ID= INSTALL_TEST_STUCK="${stuck}" \
    "${scratch}/script/install" >"${scratch}/install.log" 2>&1
  if [[ "${stuck}" == 1 ]]; then
    [[ "$(cat "${scratch}/installation-events")" == $'quit\nkill\nreplace\ncopy\nopen' ]] || exit 1
  else
    [[ "$(cat "${scratch}/installation-events")" == $'replace\ncopy\nopen' ]] || exit 1
  fi
done
: >"${scratch}/installation-events"
touch "${scratch}/app-running"
if env PATH="${scratch}/bin:${PATH}" SV_SESSION_ID= INSTALL_TEST_STUCK=1 INSTALL_TEST_UNKILLABLE=1 \
  "${scratch}/script/install" >"${scratch}/install.log" 2>&1; then
  echo 'Installation replaced an app that was still running' >&2
  exit 1
fi
[[ "$(cat "${scratch}/installation-events")" == $'quit\nkill' ]] || exit 1
rm "${scratch}/app-running" "${scratch}/installation-started"
: >"${scratch}/installation-events"
build_status=0
env PATH="${scratch}/bin:${PATH}" SV_SESSION_ID= BUILD_TEST_FAIL=1 \
  "${scratch}/script/install" >"${scratch}/failure.log" 2>&1 || build_status=$?
[[ "${build_status}" == 65 ]] || exit 1
for stream in stdout stderr; do
  if ! grep -q "Build diagnostic on ${stream}" "${scratch}/failure.log"; then
    echo "Installation hid the build failure diagnostic on ${stream}" >&2
    exit 1
  fi
done
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
bash Tests/PackageTests.sh

mkdir -p "${scratch}/Tests" "${scratch}/.build"
python3 - "${scratch}" <<'PLISTS'
import pathlib, plistlib, sys
for configuration in ["Debug", "Release"]:
    for platform, path, encoding in [
        ("mac", f".DerivedData/Build/Products/{configuration}/Sanductor.app/Contents/Info.plist", plistlib.FMT_XML),
        ("ios", f".DerivedData/iOS/Build/Products/{configuration}-iphonesimulator/Sanductor.app/Info.plist", plistlib.FMT_BINARY),
    ]:
        target = pathlib.Path(sys.argv[1]) / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(plistlib.dumps({"NSPrincipalClass": f"{platform}.AppDelegate", "Configuration": configuration}, fmt=encoding))
PLISTS
printf 'only_rules: [trailing_newline]\nanalyzer_rules: [unused_import]\n' >"${scratch}/.swiftlint.yml"
mkdir -p "${scratch}/App" "${scratch}/iOSApp" "${scratch}/Sources/Interface/"{macOS,iOS}
touch "${scratch}/Sources/Interface/"{macOS,iOS}/Font.swift
printf 'exit 0\n' >"${scratch}/Tests/ScriptTests.sh"
printf '#!/bin/bash\nexit 0\n' >"${scratch}/bin/ps"
cat >"${scratch}/bin/swift" <<'SWIFT'
#!/bin/bash
printf '%s\n' "$@" >swift-arguments
printf '%s\n' "${TSAN_OPTIONS:-}" >thread-sanitizer-options
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
if [[ "${ANALYZE_TEST_EMPTY:-}" == 1 ]]; then
  echo 'Done analyzing! Found 0 violations, 0 serious in 0 files.'
  exit 0
fi
"${SCRIPT_TEST_SWIFTLINT}" "$@" --config .swiftlint.yml >swiftlint.log 2>&1
cat swiftlint.log
if [[ -z "${SANDUCTOR_ANALYZE_BASE:-}" ]]; then
  grep -q "Analyzing 'Font.swift' (1/1)" swiftlint.log
fi
exit "${ANALYZE_TEST_SWIFTLINT_STATUS:-${ANALYZE_TEST_STATUS:-0}}"
SWIFTLINT
chmod +x "${scratch}/bin/"*

real_swiftlint="$(command -v swiftlint)"
for sandbox in fixture ''; do
  for status in 0 1; do
    : >"${scratch}/xcode-invocations"
    : >"${scratch}/swiftlint-invocations"
    result=0
    env PATH="${scratch}/bin:${PATH}" SV_SESSION_ID="${sandbox}" ANALYZE_TEST_STATUS="${status}" XCODE_CONFIGURATION= \
      SCRIPT_TEST_SWIFTLINT="${real_swiftlint}" \
      "${scratch}/script/analyze" >"${scratch}/analyze.log" 2>&1 || result=$?
    [[ "${result}" == "${status}" ]] || {
      cat "${scratch}/analyze.log"
      exit 1
    }
    grep -qx -- --strict "${scratch}/periphery-arguments"
    if [[ -n "${sandbox}" ]]; then
      grep -qx -- --index-store-path "${scratch}/periphery-arguments"
    fi
    awk '/^--index-exclude$/ { exclude = 1; next } /^--/ { exclude = 0 } exclude' \
      "${scratch}/periphery-arguments" | grep -Fxq '**/BuildToolPluginIntermediates/**'
    if [[ -z "${sandbox}" ]]; then
      grep -q -- '-configuration Debug' "${scratch}/xcode-invocations"
      grep -q -- '-scheme SanductorApp' "${scratch}/xcode-invocations"
      grep -q -- '-scheme Sanductor-iOS' "${scratch}/xcode-invocations"
      grep -q -- 'generic/platform=iOS Simulator' "${scratch}/xcode-invocations"
      grep -qx -- --generic-project-config "${scratch}/periphery-arguments"
      python3 - "${scratch}/.build/analyze-project.json" <<'CONFIG'
import json, pathlib, plistlib, sys, xml.etree.ElementTree as ET
config = json.load(open(sys.argv[1]))
assert config["indexstores"] == [".DerivedData/Index.noindex/DataStore", ".DerivedData/iOS/Index.noindex/DataStore"]
assert config["test_targets"] == ["SanductorIntentTests"]
assert config["xibs"] == config["xcdatamodels"] == config["xcmappingmodels"] == []
assert len(config["plists"]) == 2
root = pathlib.Path(sys.argv[1]).parent.parent
for platform, path in zip(["mac", "ios"], config["plists"]):
    contents = (root / path).read_bytes()
    ET.fromstring(contents)
    assert plistlib.loads(contents) == {"NSPrincipalClass": f"{platform}.AppDelegate", "Configuration": "Debug"}
assert (root / ".DerivedData/iOS/Build/Products/Debug-iphonesimulator/Sanductor.app/Info.plist").read_bytes().startswith(b"bplist00")
CONFIG
      grep -q -- '--compiler-log-path .build/analyze-build.log' "${scratch}/swiftlint-invocations"
      grep -q -- '--compiler-log-path .build/analyze-ios-build.log' "${scratch}/swiftlint-invocations"
      grep -Fxq "${scratch}/Sources/Interface/macOS/Font.swift" "${scratch}/.build/analyze-mac-sources.xcfilelist"
      grep -Fxq "${scratch}/Sources/Interface/iOS/Font.swift" "${scratch}/.build/analyze-ios-sources.xcfilelist"
      if grep -q '/iOS/' "${scratch}/.build/analyze-mac-sources.xcfilelist" ||
        grep -q '/macOS/' "${scratch}/.build/analyze-ios-sources.xcfilelist"; then
        echo 'Analysis mixed platform-specific sources' >&2
        exit 1
      fi
    fi
  done
done
: >"${scratch}/xcode-invocations"
env PATH="${scratch}/bin:${PATH}" SV_SESSION_ID= XCODE_CONFIGURATION=Release \
  SCRIPT_TEST_SWIFTLINT="${real_swiftlint}" \
  "${scratch}/script/analyze" >"${scratch}/analyze.log" 2>&1
[[ "$(grep -c -- '-configuration Release' "${scratch}/xcode-invocations")" -eq 2 ]] || exit 1
python3 - "${scratch}" <<'PLISTS'
import json, pathlib, plistlib, sys
root = pathlib.Path(sys.argv[1])
for path in json.loads((root / ".build/analyze-project.json").read_text())["plists"]:
    assert plistlib.loads((root / path).read_bytes())["Configuration"] == "Release"
PLISTS
plist="${scratch}/.DerivedData/iOS/Build/Products/Release-iphonesimulator/Sanductor.app/Info.plist"
cp "${plist}" "${scratch}/original-info.plist"
for invalid in missing malformed; do
  rm -f "${plist}" "${scratch}/periphery-arguments"
  [[ "${invalid}" != malformed ]] || printf 'invalid plist' >"${plist}"
  if env PATH="${scratch}/bin:${PATH}" SV_SESSION_ID= XCODE_CONFIGURATION=Release \
    SCRIPT_TEST_SWIFTLINT="${real_swiftlint}" \
    "${scratch}/script/analyze" >"${scratch}/analyze.log" 2>&1; then
    echo "Analysis accepted a ${invalid} product plist" >&2
    exit 1
  fi
  [[ ! -f "${scratch}/periphery-arguments" ]] || exit 1
done
cp "${scratch}/original-info.plist" "${plist}"
if env PATH="${scratch}/bin:${PATH}" SV_SESSION_ID= ANALYZE_TEST_EMPTY=1 \
  "${scratch}/script/analyze" >"${scratch}/analyze.log" 2>&1; then
  echo 'Analysis accepted a SwiftLint pass that checked no files' >&2
  exit 1
fi

git -C "${scratch}" init --quiet --initial-branch=fixture
git -C "${scratch}" config user.name 'Script Tests'
git -C "${scratch}" config user.email 'tests@example.invalid'
mkdir -p "${scratch}/Sources/SanductorDomain"
touch "${scratch}/Sources/SanductorDomain/Core.swift"
touch "${scratch}/README.md" "${scratch}/Sources/Shared File.swift"
git -C "${scratch}" add -- README.md Sources Tests .swiftlint.yml Package.resolved
git -C "${scratch}" -c commit.gpgsign=false commit --quiet --no-verify -m 'Add analysis fixtures'
for change in docs shared domain conditional-domain mac ios rename delete configuration uncompiled; do
  base="$(git -C "${scratch}" rev-parse HEAD)"
  case "${change}" in
    docs) file=README.md ;;
    shared) file='Sources/Shared File.swift' ;;
    domain | conditional-domain) file=Sources/SanductorDomain/Core.swift ;;
    mac) file=Sources/Interface/macOS/Font.swift ;;
    ios) file=Sources/Interface/iOS/Font.swift ;;
    rename)
      file='Sources/Renamed File.swift'
      mv "${scratch}/Sources/Shared File.swift" "${scratch}/${file}"
      ;;
    delete)
      file='Sources/Renamed File.swift'
      rm "${scratch}/${file}"
      ;;
    configuration) file=.swiftlint.yml ;;
    uncompiled) file=Tests/Uncompiled.swift ;;
    *) exit 1 ;;
  esac
  if [[ "${change}" == conditional-domain ]]; then
    printf '#if os(iOS)\n#endif\n' >>"${scratch}/${file}"
  elif [[ "${change}" != delete ]]; then
    printf '\n' >>"${scratch}/${file}"
  fi
  git -C "${scratch}" add --all -- README.md Sources Tests .swiftlint.yml
  git -C "${scratch}" -c commit.gpgsign=false commit --quiet --no-verify -m 'Change analysis fixture'
  : >"${scratch}/swiftlint-invocations"
  rm "${scratch}/periphery-arguments"
  env PATH="${scratch}/bin:${PATH}" SV_SESSION_ID= SANDUCTOR_ANALYZE_BASE="${base}" \
    SCRIPT_TEST_SWIFTLINT="${real_swiftlint}" \
    "${scratch}/script/analyze" >"${scratch}/analyze.log" 2>&1
  [[ -s "${scratch}/periphery-arguments" ]] || exit 1
  for platform in mac ios; do
    case "${change}:${platform}" in
      shared:* | rename:* | domain:mac | conditional-domain:* | mac:mac | ios:ios | uncompiled:mac)
        expected="${scratch}/${file}"
        ;;
      *) expected="" ;;
    esac
    [[ "$(cat "${scratch}/.build/analyze-${platform}-sources.xcfilelist")" == "${expected}" ]] || {
      echo "Import analysis selected the wrong ${platform} files for ${change}" >&2
      exit 1
    }
    if [[ -n "${expected}" && "${change}" != uncompiled ]]; then
      grep -q 'in 1 file\.$' "${scratch}/.build/analyze-swiftlint-${platform}.log" || {
        cat "${scratch}/analyze.log"
        exit 1
      }
    fi
  done
  if [[ "${change}" == docs || "${change}" == delete || "${change}" == configuration ]]; then
    [[ ! -s "${scratch}/swiftlint-invocations" ]] || exit 1
  fi
  if [[ "${change}" == shared ]]; then
    rm "${scratch}/periphery-arguments"
    if env PATH="${scratch}/bin:${PATH}" SV_SESSION_ID= SANDUCTOR_ANALYZE_BASE="${base}" \
      ANALYZE_TEST_SWIFTLINT_STATUS=1 SCRIPT_TEST_SWIFTLINT="${real_swiftlint}" \
      "${scratch}/script/analyze" >"${scratch}/analyze.log" 2>&1; then
      echo 'Changed-file analysis ignored a SwiftLint failure' >&2
      exit 1
    fi
    [[ -s "${scratch}/periphery-arguments" ]] || exit 1
  fi
done
: >"${scratch}/xcode-invocations"
if env PATH="${scratch}/bin:${PATH}" SV_SESSION_ID= SANDUCTOR_ANALYZE_BASE=missing-commit \
  SCRIPT_TEST_SWIFTLINT="${real_swiftlint}" \
  "${scratch}/script/analyze" >"${scratch}/analyze.log" 2>&1; then
  echo 'Analysis accepted an invalid base commit' >&2
  exit 1
fi
[[ ! -s "${scratch}/xcode-invocations" ]] || exit 1

plutil -convert json -o - Sanductor.xcodeproj/project.xcproj | python3 -c '
import json
import sys

targets = {target["name"]: target for target in json.load(sys.stdin)["targets"]}
modules = [
    targets[name]["build-settings"].get("PRODUCT_MODULE_NAME", targets[name]["build-settings"]["PRODUCT_NAME"])
    for name in ["SanductorApp", "Sanductor-iOS"]
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
    env PATH="${scratch}/bin:${PATH}" SV_SESSION_ID=fixture SCRIPT_TEST_STATUS="${status}" TSAN_OPTIONS=halt_on_error=1 \
      "${scratch}/script/test" --sanitize "${sanitizer}" --scratch-path ".build/${sanitizer}-sanitizer" \
      &>"${scratch}/test.log" || result=$?
    [[ "${result}" == "${status}" ]] || exit 1
    grep -qx -- --force-resolved-versions "${scratch}/swift-arguments"
    grep -A 1 '^--sanitize$' "${scratch}/swift-arguments" | grep -qx "${sanitizer}"
    grep -A 1 '^--scratch-path$' "${scratch}/swift-arguments" | grep -qx ".build/${sanitizer}-sanitizer"
    if [[ "${sanitizer}" == thread ]]; then
      grep -qx 'halt_on_error=1:strip_env=0' "${scratch}/thread-sanitizer-options"
    else
      grep -qx 'halt_on_error=1' "${scratch}/thread-sanitizer-options"
    fi
  done
done
echo 'Analysis and sanitizer script tests passed'

bash Tests/TestFlightTests.sh
bash Tests/ProjectTests.sh
