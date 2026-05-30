#!/bin/zsh
set -euo pipefail

app_file="PlantVision/PlantVisionApp.swift"
plist_file="PlantVision/Info.plist"
project_file="PlantVision.xcodeproj/project.pbxproj"

if rg -q "windowStyle\\(\\.volumetric\\)" "$app_file"; then
  echo "Main WindowGroup is still volumetric"
  exit 1
fi

if rg -q "defaultSize\\(width: .*depth:" "$app_file"; then
  echo "Main WindowGroup still declares depth"
  exit 1
fi

role=$(/usr/libexec/PlistBuddy -c "Print :UIApplicationSceneManifest:UIApplicationPreferredDefaultSceneSessionRole" "$plist_file")
if [[ "$role" != "UIWindowSceneSessionRoleApplication" ]]; then
  echo "Info.plist scene role is $role"
  exit 1
fi

if rg -q "INFOPLIST_KEY_UIApplicationPreferredDefaultSceneSessionRole = UIWindowSceneSessionRoleVolumetricApplication" "$project_file"; then
  echo "Project build setting still prefers volumetric scene role"
  exit 1
fi

echo "Main window is plain application role"
