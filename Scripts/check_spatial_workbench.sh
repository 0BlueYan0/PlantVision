#!/bin/zsh
set -euo pipefail

root_view="PlantVision/Views/RootView.swift"

if rg -q "TabView" "$root_view"; then
  echo "RootView still uses TabView"
  exit 1
fi

rg -q "WorkbenchSection" "$root_view"
rg -q "workbenchRail" "$root_view"
rg -q "sectionContent" "$root_view"

echo "Spatial workbench structure present"
