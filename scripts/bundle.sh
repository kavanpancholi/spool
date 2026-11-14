#!/bin/sh
set -eu

configuration="${1:-release}"
root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/build/Spool.app"

swift build -c "$configuration" --package-path "$root"
binary="$(swift build -c "$configuration" --package-path "$root" --show-bin-path)/Spool"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/Spool"
cp "$root/Support/Info.plist" "$app/Contents/Info.plist"

identity="${SPOOL_SIGN_IDENTITY:-}"
if [ -z "$identity" ] && security find-identity -p codesigning 2>/dev/null | grep -q '"Spool Development"'; then
  identity="Spool Development"
fi
if [ -z "$identity" ]; then
  identity="-"
  echo "Signing ad hoc. macOS asks for Accessibility again after each rebuild."
  echo "Create a \"Spool Development\" code signing certificate to avoid that (see CONTRIBUTING.md)."
fi

codesign --force --sign "$identity" "$app"
echo "Built $app (signed with: $identity)"
