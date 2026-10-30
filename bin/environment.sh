#!/bin/sh
# Expand only these fixed variable names, never their values as shell code.
for sanductor_environment_name in SANDUCTOR SANDUCTOR_SESSION SANDUCTOR_EDITS \
  SANDUCTOR_COLOR SANDUCTOR_DRY_RUN SANDUCTOR_PERFORMANCE_LOG \
  SANDUCTOR_PERFORMANCE_LOG_DIRECTORY SANDUCTOR_DEVELOPMENT_TEAM \
  SANDUCTOR_SKIP_INTENT_TESTS SANDUCTOR_ANALYZE_BASE SANDUCTOR_APP_STORE_IOS_PROFILE; do
  sanductor_environment_legacy="AGENTIDE${sanductor_environment_name#SANDUCTOR}"
  eval 'sanductor_environment_current=${'"${sanductor_environment_name}"'+set}'
  eval 'sanductor_environment_old=${'"${sanductor_environment_legacy}"'+set}'
  if [ -z "${sanductor_environment_current}" ] && [ -n "${sanductor_environment_old}" ]; then
    printf 'Warning: %s is deprecated; use %s instead.\n' \
      "${sanductor_environment_legacy}" "${sanductor_environment_name}" >&2
    eval 'export '"${sanductor_environment_name}"'="${'"${sanductor_environment_legacy}"'}"'
  fi
done
unset sanductor_environment_name sanductor_environment_legacy sanductor_environment_current sanductor_environment_old
