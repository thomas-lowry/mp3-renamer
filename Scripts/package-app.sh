#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
app_name="MP3 Renamer"
executable_name="MP3Renamer"
output_dir="${project_dir}/dist"
app_path="${output_dir}/${app_name}.app"
stage_path="${output_dir}/dmg-stage"
dmg_path="${output_dir}/${app_name}.dmg"

cd "${project_dir}"

"${script_dir}/generate-icon.sh"

rm -rf "${output_dir}"
mkdir -p "${app_path}/Contents/MacOS" "${app_path}/Contents/Resources"

# Build a universal binary so the DMG runs on Apple Silicon and Intel Macs.
swift build -c release --arch arm64
swift build -c release --arch x86_64
lipo -create \
  "${project_dir}/.build/arm64-apple-macosx/release/${executable_name}" \
  "${project_dir}/.build/x86_64-apple-macosx/release/${executable_name}" \
  -output "${app_path}/Contents/MacOS/${executable_name}"

cp "${project_dir}/App/Info.plist" "${app_path}/Contents/Info.plist"
cp "${project_dir}/Assets/AppIcon.icns" "${app_path}/Contents/Resources/AppIcon.icns"

# Ad-hoc signing allows local installation. Replace '-' with a Developer ID
# identity and notarize the DMG before distributing outside your own Macs.
codesign --force --deep --sign - "${app_path}"
codesign --verify --deep --strict "${app_path}"
plutil -lint "${app_path}/Contents/Info.plist"

mkdir -p "${stage_path}"
cp -R "${app_path}" "${stage_path}/${app_name}.app"
ln -s /Applications "${stage_path}/Applications"

hdiutil create \
  -volname "${app_name}" \
  -srcfolder "${stage_path}" \
  -ov \
  -format UDZO \
  "${dmg_path}"
hdiutil verify "${dmg_path}"

print "Created ${dmg_path}"
