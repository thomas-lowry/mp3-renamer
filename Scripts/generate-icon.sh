#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
source_icon="${project_dir}/Assets/AppIcon-light.png"
iconset_dir="${project_dir}/build/MP3Renamer.xcassets/AppIcon.appiconset"

if [[ ! -f "${source_icon}" ]]; then
  print -u2 "Missing ${source_icon}"
  exit 1
fi

rm -rf "${iconset_dir:h}"
mkdir -p "${iconset_dir}"

function render_icon() {
  local pixels="$1"
  local filename="$2"
  sips --resampleHeightWidth "${pixels}" "${pixels}" "${source_icon}" --out "${iconset_dir}/${filename}" >/dev/null
}

render_icon 16 AppIcon_16.png
render_icon 32 AppIcon_16@2x.png
render_icon 32 AppIcon_32.png
render_icon 64 AppIcon_32@2x.png
render_icon 128 AppIcon_128.png
render_icon 256 AppIcon_128@2x.png
render_icon 256 AppIcon_256.png
render_icon 512 AppIcon_256@2x.png
render_icon 512 AppIcon_512.png
render_icon 1024 AppIcon_512@2x.png

cat > "${iconset_dir}/Contents.json" <<'EOF'
{
  "images" : [
    { "filename" : "AppIcon_16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "AppIcon_16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "AppIcon_32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "AppIcon_32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "AppIcon_128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "AppIcon_128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "AppIcon_256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "AppIcon_256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "AppIcon_512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "AppIcon_512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF

swift -module-cache-path "${project_dir}/build/swift-module-cache" \
  "${script_dir}/make-icns.swift" \
  "${iconset_dir}" \
  "${project_dir}/Assets/AppIcon.icns"
print "Created ${project_dir}/Assets/AppIcon.icns"
