#!/bin/bash
# Check native source discovery without changing the working tree.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p .test-scratch
scratch="$(mktemp -d "${PWD}/.test-scratch/project.XXXXXX")"
trap 'rm -rf "${scratch}"' EXIT
cp -R Sanductor.xcodeproj App iOSApp "${scratch}/"
mkdir -p "${scratch}/Tests" "${scratch}/.build"
printf '%s\n' 'MARKETING_VERSION = 1.2.3' 'CURRENT_PROJECT_VERSION = 42' >"${scratch}/.build/version.xcconfig"
cp -R Tests/SanductorIntentTests "${scratch}/Tests/"
project="${scratch}/Sanductor.xcodeproj"

phase() {
  xcrun xcodeproj target phase info --project "${project}" --target "$1" "$2"
}

for entry in App:SanductorApp iOSApp:Sanductor-iOS Tests/SanductorIntentTests:SanductorIntentTests; do
  directory="${entry%:*}"
  target="${entry##*:}"
  mkdir -p "${scratch}/${directory}/Nested/Deeper"
  source="${scratch}/${directory}/Nested/Deeper/DiscoveryProbe.swift"
  touch "${source}"
  phase "${target}" 1 | grep -q DiscoveryProbe.swift
  for other in SanductorApp Sanductor-iOS SanductorIntentTests; do
    [[ "${other}" != "${target}" ]] || continue
    if phase "${other}" 1 | grep -q DiscoveryProbe.swift; then
      echo "Source from ${directory} leaked into ${other}" >&2
      exit 1
    fi
  done
  mv "${source}" "${source%/*}/RenamedProbe.swift"
  phase "${target}" 1 >"${scratch}/sources"
  grep -q RenamedProbe.swift "${scratch}/sources"
  grep -q DiscoveryProbe.swift "${scratch}/sources" && exit 1
  rm "${source%/*}/RenamedProbe.swift"
  phase "${target}" 1 >"${scratch}/sources"
  grep -q Probe.swift "${scratch}/sources" && exit 1
  if [[ "${target}" != SanductorIntentTests ]]; then
    touch "${scratch}/${directory}/Nested/Discovered.txt"
    phase "${target}" 2 | grep -q Discovered.txt
    touch "${scratch}/${directory}/Info.plist" "${scratch}/${directory}/Signing.entitlements"
    phase "${target}" 2 >"${scratch}/resources"
    grep -Eq 'Info.plist|version.xcconfig|Signing.entitlements' "${scratch}/resources" && exit 1
  fi
done
mkdir -p "${scratch}/App/Assets.xcassets/Nested/Deeper"
touch "${scratch}/App/Assets.xcassets/Nested/Deeper/ExcludedProbe.swift" \
  "${scratch}/App/Assets.xcassets/Nested/Deeper/ExcludedProbe.txt"
phase SanductorApp 1 >"${scratch}/sources"
grep -q ExcludedProbe.swift "${scratch}/sources" && exit 1
for target in SanductorApp Sanductor-iOS; do
  phase "${target}" 2 >"${scratch}/resources"
  [[ "$(grep -c Assets.xcassets "${scratch}/resources")" == 1 ]]
  grep -q ExcludedProbe "${scratch}/resources" && exit 1
done
phase SanductorApp 2 | grep -q Credits.html
phase SanductorApp 2 | grep -q bin
phase Sanductor-iOS 2 | grep -q PrivacyInfo.xcprivacy
phase Sanductor-iOS 2 >"${scratch}/resources"
grep -Eq 'Credits.html|bin|entitlements' "${scratch}/resources" && exit 1
cmp Sanductor.xcodeproj/project.xcproj "${project}/project.xcproj"
plutil -convert json -o - "${project}/project.xcproj" | python3 -c '
import json, pathlib, sys, xml.etree.ElementTree as ET
project = json.load(sys.stdin)
targets = {target["id"]: target for target in project["targets"]}
for scheme in pathlib.Path("Sanductor.xcodeproj/xcshareddata/xcschemes").glob("*.xcscheme"):
    for reference in ET.parse(scheme).iter("BuildableReference"):
        target = targets[reference.attrib["BlueprintIdentifier"]]
        extension = ".app" if target["product-type"] == "application" else ".xctest"
        product = target["build-settings"].get("PRODUCT_NAME", target["name"]) + extension
        assert reference.attrib["BuildableName"] == product, (scheme, product)
'
echo 'Native project discovery and isolation tests passed'

for platform in macosx iphoneos; do
  device=mac
  [[ "${platform}" != iphoneos ]] || device=iphone
  mkdir -p "${scratch}/${platform}"
  xcrun actool App/Assets.xcassets --compile "${scratch}/${platform}" \
    --platform "${platform}" --target-device "${device}" --minimum-deployment-target 26.0 \
    --app-icon AppIcon --output-partial-info-plist "${scratch}/${platform}/info.plist" \
    --warnings --output-format human-readable-text >"${scratch}/${platform}/assets.log" 2>&1
  if grep -q 'warning:' "${scratch}/${platform}/assets.log"; then
    cat "${scratch}/${platform}/assets.log" >&2
    exit 1
  fi
done
echo 'Mac and iPhone asset catalogue tests passed'
