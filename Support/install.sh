#!/bin/sh
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

[ "$(id -u)" = 0 ] || { echo 'Run this installer with sudo.' >&2; exit 1; }
source_app=${1:?Usage: install.sh /path/to/signed/ETHZ VPN.app}
app='/Applications/ETHZ VPN.app'
runtime_parent='/Library/Application Support/ETHZ VPN'
runtime="$runtime_parent/Runtime.app"

# Updating running privileged code is unsafe. Unregister through the app first.
if /bin/launchctl print system/com.dcamenisch.ethz-vpn-menubar.helper >/dev/null 2>&1; then
    echo 'Disconnect, Disable VPN Access in Manage Profiles, and quit the app before installing an update.' >&2
    exit 1
fi
/usr/bin/codesign --verify --deep --strict "$source_app"
/usr/bin/codesign --verify -R '=anchor apple generic' "$source_app"
# Exact dedicated installation paths only; refuse symbolic links.
for target in "$app" "$runtime_parent" "$runtime"; do
    [ ! -L "$target" ] || { echo "Refusing symbolic link: $target" >&2; exit 1; }
done
/usr/bin/install -d -o root -g wheel -m 755 "$runtime_parent"
staging=$(/usr/bin/mktemp -d "$runtime_parent/.install.XXXXXX")
trap '/bin/rm -rf "$staging"' EXIT
/usr/bin/ditto "$source_app" "$staging/Runtime.app"
/usr/sbin/chown -R root:wheel "$staging/Runtime.app"
/bin/chmod -R go-w "$staging/Runtime.app"
/usr/bin/codesign --verify --deep --strict "$staging/Runtime.app"
/usr/bin/codesign --verify -R '=anchor apple generic' "$staging/Runtime.app"
/bin/rm -rf "$runtime"
/bin/mv "$staging/Runtime.app" "$runtime"
/usr/bin/ditto "$runtime" "$app"
/usr/sbin/chown -R root:wheel "$app"
/bin/chmod -R go-w "$app"
/usr/bin/codesign --verify --deep --strict "$app"
echo 'Installed. Enable VPN Access in Manage Profiles to approve the macOS helper.'
