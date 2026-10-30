#!/bin/bash
# Exercise notarisation recovery without credentials or network access.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p .test-scratch
scratch="$(mktemp -d "${PWD}/.test-scratch/package.XXXXXX")"
trap 'rm -rf "${scratch}"' EXIT
mkdir -p "${scratch}/script" "${scratch}/bin" "${scratch}/tmp"
cp script/package "${scratch}/script/"
cat >"${scratch}/script/zip" <<'ZIP'
#!/bin/bash
echo zip >>events
echo .build/Sanductor.zip
ZIP
cat >"${scratch}/bin/security" <<'SECURITY'
#!/bin/bash
case "$1" in
  find-identity) echo '  1) 0123456789012345678901234567890123456789 "Developer ID Application: Fixture"' ;;
  list-keychains) [[ $# -gt 3 ]] || echo '"fixture.keychain-db"' ;;
  delete-keychain) echo cleanup >>events ;;
esac
exit 0
SECURITY
cat >"${scratch}/bin/xcrun" <<'XCRUN'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >>calls
submission=39ecde57-af81-4b28-a369-1ec62f3a145f
case "$1 $2" in
  'notarytool submit')
    [[ "${PACKAGE_TEST_MODE}" != submit-failure ]] || exit 65
    if [[ " $* " == *' --wait '* ]]; then
      echo 'The request timed out.' >&2
      exit 65
    fi
    printf '<plist version="1.0"><dict><key>id</key><string>%s</string></dict></plist>\n' "${submission}"
    ;;
  'notarytool wait')
    [[ "$3" == "${submission}" ]] || exit 99
    attempt=$(($(cat attempts 2>/dev/null || echo 0) + 1))
    echo "${attempt}" >attempts
    if [[ "${PACKAGE_TEST_MODE}" == persistent || ("${PACKAGE_TEST_MODE}" == transient && "${attempt}" == 1) ]]; then
      echo 'The request timed out.' >&2
      exit 65
    fi
    status=Accepted
    [[ "${PACKAGE_TEST_MODE}" != invalid ]] || status=Invalid
    printf '<plist version="1.0"><dict><key>status</key><string>%s</string></dict></plist>\n' "${status}"
    [[ "${status}" == Accepted ]] || exit 65
    ;;
  'notarytool log')
    [[ "$3" == "${submission}" ]] || exit 99
    echo 'Invalid signature diagnostic'
    ;;
  'stapler staple') echo staple >>events ;;
  *) exit 99 ;;
esac
XCRUN
for command in codesign spctl sleep; do
  printf '#!/bin/bash\necho %s >>events\n' "${command}" >"${scratch}/bin/${command}"
done
chmod +x "${scratch}/script/"* "${scratch}/bin/"*

for mode in transient success persistent invalid submit-failure; do
  : >"${scratch}/calls"
  : >"${scratch}/events"
  echo 0 >"${scratch}/attempts"
  result=0
  env -i PATH="${scratch}/bin:/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="${scratch}/tmp/" \
    DEVELOPER_ID_APPLICATION_CERTIFICATE=Zml4dHVyZQ== DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD=fixture \
    NOTARIZATION_KEY=fixture NOTARIZATION_KEY_ID=fixture NOTARIZATION_ISSUER_ID=fixture PACKAGE_TEST_MODE="${mode}" \
    "${scratch}/script/package" >"${scratch}/package.log" 2>&1 || result=$?
  case "${mode}" in
    transient | success)
      if [[ "${result}" != 0 ]]; then
        cat "${scratch}/package.log"
        echo "Packaging failed after ${mode} notarisation" >&2
        exit 1
      fi
      attempts=1
      [[ "${mode}" != transient ]] || attempts=2
      [[ "$(cat "${scratch}/attempts")" == "${attempts}" ]]
      grep -qx staple "${scratch}/events"
      grep -qx spctl "${scratch}/events"
      [[ "$(grep -cx zip "${scratch}/events")" == 2 ]]
      ;;
    *)
      [[ "${result}" != 0 ]]
      ! grep -qx staple "${scratch}/events"
      ! grep -qx spctl "${scratch}/events"
      [[ "$(grep -cx zip "${scratch}/events")" == 1 ]]
      case "${mode}" in
        persistent) [[ "$(cat "${scratch}/attempts")" == 3 ]] ;;
        invalid)
          [[ "$(cat "${scratch}/attempts")" == 1 ]]
          grep -q 'Invalid signature diagnostic' "${scratch}/package.log"
          ;;
        submit-failure) [[ "$(cat "${scratch}/attempts")" == 0 ]] ;;
        *) exit 1 ;;
      esac
      ;;
  esac
  [[ "$(grep -c '^notarytool submit ' "${scratch}/calls")" == 1 ]]
  grep -qx cleanup "${scratch}/events"
done
echo 'Notarisation script tests passed'
