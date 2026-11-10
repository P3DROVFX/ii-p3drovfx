#!/usr/bin/env bash
# Packs ii-material-you into a .vsix and installs it in every VS Code flavour found.
# The theme itself is rendered by matugen into
# $XDG_STATE_HOME/quickshell/user/generated/vscode/theme.json and picked up live.
# Extra arguments go to each CLI (e.g. --extensions-dir for a sandbox).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXT_DIR="$SCRIPT_DIR/ii-material-you"
VERSION=$(jq -r .version "$EXT_DIR/package.json")
BUILD=$(mktemp -d)
trap 'rm -rf "$BUILD"' EXIT

mkdir -p "$BUILD/extension"
cp -r "$EXT_DIR"/. "$BUILD/extension/"
cat > "$BUILD/[Content_Types].xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension=".json" ContentType="application/json"/>
  <Default Extension=".js" ContentType="application/javascript"/>
  <Default Extension=".vsixmanifest" ContentType="text/xml"/>
</Types>
XML
cat > "$BUILD/extension.vsixmanifest" <<XML
<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
  <Metadata>
    <Identity Language="en-US" Id="ii-material-you" Version="$VERSION" Publisher="illogical-impulse"/>
    <DisplayName>ii Material You</DisplayName>
    <Description xml:space="preserve">Material 3 Expressive theme that follows the illogical-impulse wallpaper palette.</Description>
    <Categories>Themes</Categories>
    <Properties>
      <Property Id="Microsoft.VisualStudio.Code.Engine" Value="^1.75.0"/>
    </Properties>
  </Metadata>
  <Installation><InstallationTarget Id="Microsoft.VisualStudio.Code"/></Installation>
  <Dependencies/>
  <Assets>
    <Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/>
  </Assets>
</PackageManifest>
XML
VSIX="$BUILD/ii-material-you-$VERSION.vsix"
(cd "$BUILD" && zip -qr "$VSIX" "[Content_Types].xml" extension.vsixmanifest extension)

installed=0
for cli in ${II_VSCODE_CLIS:-code codium code-insiders code-oss cursor windsurf antigravity}; do
    command -v "$cli" > /dev/null || continue
    "$cli" --install-extension "$VSIX" --force "$@" && installed=1
done
[ "$installed" = 1 ] || { echo "[ii-material-you] No VS Code CLI found." >&2; exit 1; }
echo "[ii-material-you] Installed. Pick \"ii Material You Dark/Light\" in Preferences: Color Theme."
