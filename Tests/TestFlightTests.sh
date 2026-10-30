#!/bin/bash
# Check release gating, signing cleanup and uploads without credentials.
set -euo pipefail

cd "$(dirname "$0")/.."
ruby -ryaml <<'WORKFLOW'
jobs = YAML.load_file('.github/workflows/release.yml').fetch('jobs')
release = jobs.fetch('release')
unless Array(release['needs']).include?('testflight')
  abort 'GitHub publication can run before TestFlight succeeds'
end
if release.fetch('if', '').match?(/\b(always|failure|cancelled)\s*\(/)
  abort 'GitHub publication bypasses successful dependencies'
end
testflight = jobs.fetch('testflight')
if Array(testflight['needs']).include?('release') || testflight.fetch('if', '').include?('needs.release')
  abort 'TestFlight depends on GitHub publication'
end
if testflight['continue-on-error'] || testflight.fetch('steps').any? { |step| step['continue-on-error'] }
  abort 'TestFlight failures can be ignored'
end
puts 'TestFlight release gating tests passed'
WORKFLOW
mkdir -p "${PWD}/.test-scratch"
scratch="$(mktemp -d "${PWD}/.test-scratch/testflight.XXXXXX")"
trap 'rm -rf "${scratch}"' EXIT
mkdir -p "${scratch}/bin"
export TESTFLIGHT_TEST_DIRECTORY="${scratch}"
export PATH="${scratch}/bin:${PATH}"

cat >"${scratch}/bin/security" <<'SECURITY'
#!/bin/bash
set -euo pipefail
echo "$1" >>"${TESTFLIGHT_TEST_DIRECTORY}/security.log"
case "$1" in
  list-keychains)
    if [[ $# == 3 ]]; then
      echo '"/existing.keychain-db"'
      [[ "${TESTFLIGHT_TEST_FAILURE}" != list ]] || exit 1
    else
      printf '%s\n' "$@" >"${TESTFLIGHT_TEST_DIRECTORY}/keychains"
    fi
    ;;
  create-keychain) dirname "$4" >"${TESTFLIGHT_TEST_DIRECTORY}/credentials" ;;
  cms) cat "$4" ;;
  import) [[ "${TESTFLIGHT_TEST_FAILURE}" != import ]] ;;
esac
SECURITY
cat >"${scratch}/bin/xcodebuild" <<'XCODEBUILD'
#!/bin/bash
set -euo pipefail
if [[ "$1" == -exportArchive ]]; then
  while [[ "$1" != -exportOptionsPlist ]]; do shift; done
  cp "$2" "${TESTFLIGHT_TEST_DIRECTORY}/export.plist"
  destination="$(/usr/libexec/PlistBuddy -c 'Print :destination' "$2")"
  echo "${destination}" >>"${TESTFLIGHT_TEST_DIRECTORY}/calls"
  [[ "${TESTFLIGHT_TEST_FAILURE}" != export ]]
else
  echo archive >>"${TESTFLIGHT_TEST_DIRECTORY}/calls"
  printf '%s\n' "$@" >"${TESTFLIGHT_TEST_DIRECTORY}/archive.args"
  [[ "${TESTFLIGHT_TEST_FAILURE}" != archive ]]
fi
XCODEBUILD
cat >"${scratch}/bin/xcrun" <<'VALIDATOR'
#!/bin/bash
set -euo pipefail
[[ "$1" == altool && "$2" == --validate-app ]]
[[ "$3" == */export/Sanductor.ipa ]]
[[ "$4" == --api-key && "$5" == KEY1234567 ]]
[[ "$6" == --api-issuer && "$7" == issuer ]]
[[ "$8" == --p8-file-path && "$(cat "$9")" == 'test API key' ]]
echo validate >>"${TESTFLIGHT_TEST_DIRECTORY}/calls"
[[ "${TESTFLIGHT_TEST_FAILURE}" != validate ]]
VALIDATOR
chmod +x "${scratch}/bin/"*

export RELEASE_VERSION=1.2.3 BUILD_NUMBER=42.2
unset APP_STORE_TEAM_ID APP_STORE_WATCHOS_PROFILE
export APP_STORE_KEY='test API key' APP_STORE_KEY_ID=KEY1234567 APP_STORE_ISSUER_ID=issuer
export APP_STORE_CERTIFICATES=dGVzdA== APP_STORE_CERTIFICATES_PASSWORD=password
plutil -create xml1 "${scratch}/IOS.plist"
/usr/libexec/PlistBuddy -c "Add :UUID string $(uuidgen)" \
  -c 'Add :TeamIdentifier array' -c 'Add :TeamIdentifier:0 string ABCDEFGHIJ' \
  -c 'Add :Entitlements dict' \
  -c 'Add :Entitlements:application-identifier string OLDPREFIX1.com.mikemcquaid.Sanductor' \
  "${scratch}/IOS.plist"
export "APP_STORE_IOS_PROFILE=$(base64 -i "${scratch}/IOS.plist")"

if script/testflight macOS >"${scratch}/platform.log" 2>&1; then
  echo 'Unexpected platform argument did not prevent an upload' >&2
  exit 1
fi
if env -u APP_STORE_IOS_PROFILE script/testflight >"${scratch}/missing.log" 2>&1; then
  echo 'Missing iPhone profile did not prevent an upload' >&2
  exit 1
fi
grep -q APP_STORE_IOS_PROFILE "${scratch}/missing.log"
[[ ! -e "${scratch}/security.log" ]]

cp "${scratch}/IOS.plist" "${scratch}/old-profile.plist"
/usr/libexec/PlistBuddy \
  -c 'Set :Entitlements:application-identifier OLDPREFIX1.com.mikemcquaid.AgentIDE' \
  "${scratch}/old-profile.plist"
if APP_STORE_IOS_PROFILE="$(base64 -i "${scratch}/old-profile.plist")" TESTFLIGHT_TEST_FAILURE=none \
  script/testflight --dry-run >"${scratch}/old-profile.log" 2>&1; then
  echo 'An old bundle identifier did not prevent archiving' >&2
  exit 1
fi
grep -q SANDUCTOR_APP_STORE_IOS_PROFILE "${scratch}/old-profile.log"
[[ ! -e "${scratch}/calls" ]]
if grep -Eq '^(create-keychain|import)$' "${scratch}/security.log"; then
  echo 'An invalid profile changed the signing keychain' >&2
  exit 1
fi
rm "${scratch}/security.log"

for mode in upload export; do
  dry_run=
  [[ "${mode}" == export ]] && dry_run=1
  for failure in list none import archive export validate; do
    [[ "${mode}" == upload && "${failure}" == validate ]] && continue
    export TESTFLIGHT_TEST_FAILURE="${failure}"
    rm -f "${scratch}/calls" "${scratch}/security.log"
    if script/testflight ${dry_run:+--dry-run} >"${scratch}/run.log" 2>&1; then
      [[ "${failure}" == none ]]
    else
      [[ "${failure}" != none ]] || {
        cat "${scratch}/run.log"
        exit 1
      }
    fi
    if [[ "${failure}" == list ]]; then
      [[ "$(cat "${scratch}/security.log")" == list-keychains ]] || {
        echo 'Failed keychain read did not stop signing' >&2
        exit 1
      }
      [[ ! -e "${scratch}/calls" ]] || exit 1
      continue
    fi
    [[ ! -d "$(cat "${scratch}/credentials")" ]]
    grep -qx delete-keychain "${scratch}/security.log"
    [[ "$(tail -n 1 "${scratch}/keychains")" == /existing.keychain-db ]]
    if [[ "${failure}" == import ]]; then
      [[ ! -e "${scratch}/calls" ]]
      continue
    fi
    grep -qx Sanductor-iOS "${scratch}/archive.args"
    grep -qx generic/platform=iOS "${scratch}/archive.args"
    grep -qx DEVELOPMENT_TEAM=ABCDEFGHIJ "${scratch}/archive.args"
    grep -qx MARKETING_VERSION=1.2.3 "${scratch}/archive.args"
    grep -qx CURRENT_PROJECT_VERSION=42.2 "${scratch}/archive.args"
    if [[ "${failure}" == archive ]]; then
      [[ "$(cat "${scratch}/calls")" == archive ]]
    else
      grep -qx "${mode}" "${scratch}/calls"
      if [[ "${mode}" == export && "${failure}" != export ]]; then
        [[ "$(cat "${scratch}/calls")" == $'archive\nexport\nvalidate' ]]
      else
        [[ "$(cat "${scratch}/calls")" == "$(printf 'archive\n%s' "${mode}")" ]]
      fi
      [[ "$(/usr/libexec/PlistBuddy -c 'Print :method' "${scratch}/export.plist")" == app-store-connect ]]
      [[ "$(/usr/libexec/PlistBuddy -c 'Print :destination' "${scratch}/export.plist")" == "${mode}" ]]
      [[ "$(/usr/libexec/PlistBuddy -c 'Print :teamID' "${scratch}/export.plist")" == ABCDEFGHIJ ]]
      [[ "$(/usr/libexec/PlistBuddy -c 'Print :manageAppVersionAndBuildNumber' "${scratch}/export.plist")" == false ]]
    fi
    uuid="$(/usr/libexec/PlistBuddy -c 'Print UUID' "${scratch}/IOS.plist")"
    grep -qx "IOS_PROFILE_UUID=${uuid}" "${scratch}/archive.args"
    [[ ! -e "${HOME}/Library/Developer/Xcode/UserData/Provisioning Profiles/${uuid}.mobileprovision" ]]
    if [[ "${failure}" != archive ]]; then
      [[ "$(/usr/libexec/PlistBuddy -c "Print :provisioningProfiles:com.mikemcquaid.Sanductor" "${scratch}/export.plist")" == "${uuid}" ]]
    fi
  done
done
echo 'TestFlight script tests passed'
