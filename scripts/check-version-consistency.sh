#!/bin/bash
set -euo pipefail

value_for() {
  awk -F ' *= *' -v key="$1" '$1 == key { print $2; exit }' Version.xcconfig
}

version=$(value_for MARKETING_VERSION)
build=$(value_for CURRENT_PROJECT_VERSION)
minimum_macos=$(value_for MACOSX_DEPLOYMENT_TARGET)
display_macos=${minimum_macos%.0}

if [[ -z "$version" || -z "$build" || -z "$minimum_macos" ]]; then
  echo "Version.xcconfig must define MARKETING_VERSION, CURRENT_PROJECT_VERSION, and MACOSX_DEPLOYMENT_TARGET" >&2
  exit 1
fi

if [[ "${1:-}" == "tag" && "${2:-}" != "v${version}" ]]; then
  echo "Tag ${2:-<missing>} does not match Version.xcconfig (v${version})" >&2
  exit 1
fi

grep -Fq "macOS ${display_macos} and later" README.md || {
  echo "README macOS requirement does not match Version.xcconfig (${minimum_macos})" >&2
  exit 1
}

grep -Fq "macOS ${display_macos} or later" RELEASE_NOTES.md || {
  echo "Release notes macOS requirement does not match Version.xcconfig (${minimum_macos})" >&2
  exit 1
}

if grep -Eq 'MARKETING_VERSION =|CURRENT_PROJECT_VERSION =|MACOSX_DEPLOYMENT_TARGET =' NetSpeedMonitor.xcodeproj/project.pbxproj; then
  echo "Version settings must only be declared in Version.xcconfig" >&2
  exit 1
fi

echo "Version ${version} (${build}), minimum macOS ${minimum_macos}"
