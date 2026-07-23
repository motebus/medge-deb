#!/bin/sh
set -eu

BASE_URL="https://motebus.github.io/medge-deb"
EXPECTED_FINGERPRINT="AECAA1DCDAF19C7B7FEAF0C082A0E180EDAEA7A0"
KEYRING_PATH="/etc/apt/keyrings/medge-archive-keyring.gpg"
SOURCES_PATH="/etc/apt/sources.list.d/medge.sources"

fail() {
    printf 'MEdge install failed: %s\n' "$*" >&2
    exit 1
}

[ "$(id -u)" -eq 0 ] ||
    fail "run this installer as root (for example: sudo sh /tmp/medge-install.sh)"

[ -r /etc/os-release ] || fail "cannot identify the operating system"
# shellcheck disable=SC1091
. /etc/os-release
[ "${ID:-}" = "ubuntu" ] && [ "${VERSION_ID:-}" = "24.04" ] ||
    fail "Ubuntu 24.04 is required"

command -v dpkg >/dev/null 2>&1 || fail "dpkg is unavailable"
[ "$(dpkg --print-architecture)" = "amd64" ] ||
    fail "amd64 architecture is required"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg

TEMP_DIR="$(mktemp -d /tmp/medge-install.XXXXXX)"
cleanup() {
    rm -f \
        "$TEMP_DIR/medge-archive-keyring.gpg" \
        "$TEMP_DIR/medge.sources" \
        "$TEMP_DIR/expected.sources"
    rmdir "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM

curl --proto '=https' --tlsv1.2 -fsSLo \
    "$TEMP_DIR/medge-archive-keyring.gpg" \
    "$BASE_URL/medge-archive-keyring.gpg"
curl --proto '=https' --tlsv1.2 -fsSLo \
    "$TEMP_DIR/medge.sources" \
    "$BASE_URL/medge.sources"

ACTUAL_FINGERPRINT="$(
    gpg --batch --show-keys --with-colons \
        "$TEMP_DIR/medge-archive-keyring.gpg" |
        awk -F: '
            $1 == "pub" { public_keys += 1 }
            $1 == "fpr" && fingerprint == "" { fingerprint = $10 }
            END {
                if (public_keys != 1 || fingerprint == "") {
                    exit 1
                }
                print fingerprint
            }
        '
)" || fail "the downloaded archive key is invalid"
[ "$ACTUAL_FINGERPRINT" = "$EXPECTED_FINGERPRINT" ] ||
    fail "archive-key fingerprint mismatch (received $ACTUAL_FINGERPRINT)"

cat >"$TEMP_DIR/expected.sources" <<EOF
Types: deb
URIs: $BASE_URL
Suites: stable
Components: main
Architectures: amd64
Signed-By: $KEYRING_PATH
EOF
cmp -s "$TEMP_DIR/medge.sources" "$TEMP_DIR/expected.sources" ||
    fail "the downloaded APT source definition is invalid"

install -d -m 0755 /etc/apt/keyrings
install -m 0644 "$TEMP_DIR/medge-archive-keyring.gpg" "$KEYRING_PATH"
install -m 0644 "$TEMP_DIR/medge.sources" "$SOURCES_PATH"

apt-get update
apt-get install -y medge

INSTALLED_VERSION="$(dpkg-query -W -f='${Version}' medge)"
printf 'MEdge %s installed successfully from %s\n' \
    "$INSTALLED_VERSION" "$BASE_URL"
