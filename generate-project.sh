#!/bin/bash
# Generate Xcode project and patch .icon file types for alternate app icons.
# xcodegen doesn't recognize .icon as folder.iconcomposer.icon, so we fix it.
set -euo pipefail

xcodegen generate

sed -i '' \
  's/lastKnownFileType = folder; name = AppIconBlue.icon/lastKnownFileType = folder.iconcomposer.icon; name = AppIconBlue.icon/g; s/lastKnownFileType = folder; name = AppIconRed.icon/lastKnownFileType = folder.iconcomposer.icon; name = AppIconRed.icon/g' \
  AthanFramework.xcodeproj/project.pbxproj

echo "Project generated and .icon file types patched."
