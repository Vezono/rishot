#!/bin/sh
# Build an RPM of this checkout and install it. The Fedora counterpart to
# packaging/aur/PKGBUILD, for a system-wide install under /usr instead of the
# per-user tree that install.sh drops in ~/.local/share/rishot.
#
#   sh packaging/fedora/build.sh              build, then install with dnf
#   sh packaging/fedora/build.sh --no-install build only, print the rpm path
#
# It packs the working tree, not HEAD, so local edits end up in the rpm. The
# result is a plain noarch rpm, so it installs on any dnf/rpm system; only the
# dependency names are Fedora's.

set -eu

PROG=${0##*/}
SPEC_NAME=rishot.spec
OUTDIR="${RISHOT_RPM_OUTDIR:-${XDG_CACHE_HOME:-$HOME/.cache}/rishot}"

say() { printf '%s\n' "$*"; }
warn() { printf 'rishot: %s\n' "$*" >&2; }
die() { printf 'rishot: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# True on an rpm-ostree / atomic system (Silverblue, Kinoite, Bazzite). dnf
# cannot write to the running deployment there, so the rpm is layered instead,
# which takes a reboot. Same marker install.sh checks.
is_atomic() { [ -f /run/ostree-booted ]; }

usage() {
	say "usage: $PROG [--no-install]"
	say ""
	say "  --no-install   build the rpm and stop, leaving it in $OUTDIR"
	say "  -h, --help     this text"
	say ""
	say "environment:"
	say "  RISHOT_RPM_OUTDIR   where the finished rpm is written"
	say "  RISHOT_ENABLE_COPR  1 to add the quickshell COPR when Fedora lacks it"
}

do_install=1
while [ $# -gt 0 ]; do
	case "$1" in
	--no-install) do_install=0 ;;
	-h | --help) usage; exit 0 ;;
	*) warn "unknown argument: $1"; usage >&2; exit 1 ;;
	esac
	shift
done

# The checkout is two levels up from this script: packaging/fedora/build.sh.
script_dir=$(unset CDPATH && cd -- "$(dirname -- "$0")" && pwd)
spec="$script_dir/$SPEC_NAME"
root=$(unset CDPATH && cd -- "$script_dir/../.." && pwd)
[ -f "$spec" ] || die "$SPEC_NAME is missing next to this script"
[ -f "$root/src/shell.qml" ] && [ -f "$root/bin/rishot" ] \
	|| die "run this from a rishot checkout; $root does not look like one"

# rpmbuild lives in rpm-build, which a desktop Fedora install does not carry.
if ! have rpmbuild; then
	have dnf || die "rpmbuild is missing and there is no dnf to install it with"
	say "Installing rpm-build…"
	sudo dnf install -y rpm-build || die "could not install rpm-build"
fi

# Version the rpm the way the PKGBUILD versions the AUR package: a tag when the
# tree has one, else the commit count. RPM forbids '-' in Version and Release,
# and sorts Release as a string, so the commit count leads to keep successive
# builds upgradeable. A tree with no git at all still builds, as 0-1.
version=0
release=1
if have git && git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
	if tag=$(git -C "$root" describe --tags --abbrev=0 2>/dev/null); then
		version=$(printf '%s' "${tag#v}" | tr -d '-')
	fi
	count=$(git -C "$root" rev-list --count HEAD 2>/dev/null || echo 0)
	sha=$(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo unknown)
	release="$count.git$sha"
	# An uncommitted edit is in the tarball but not in the sha, so mark it.
	if ! git -C "$root" diff --quiet HEAD 2>/dev/null; then
		release="$release.dirty"
		warn "working tree has uncommitted changes; they are in this rpm"
	fi
fi

topdir=$(mktemp -d "${TMPDIR:-/tmp}/rishot-rpm.XXXXXX")
trap 'rm -rf "$topdir"' EXIT INT TERM
mkdir -p "$topdir/SOURCES" "$topdir/BUILD" "$topdir/RPMS" "$topdir/SPECS"

# %autosetup wants the tarball to hold one top directory named name-version, so
# --transform rewrites the paths on the way in rather than staging a copy first.
tar -C "$root" -czf "$topdir/SOURCES/rishot-$version.tar.gz" \
	--exclude=.git \
	--transform "s,^\.,rishot-$version," \
	. \
	|| die "could not pack the checkout"

say "Building rishot $version-$release…"
rpmbuild \
	--define "_topdir $topdir" \
	--define "rishot_version $version" \
	--define "rishot_release $release" \
	-bb "$spec" \
	|| die "rpmbuild failed"

rpm=$(find "$topdir/RPMS" -name 'rishot-*.rpm' -type f | head -n 1)
[ -n "$rpm" ] || die "rpmbuild reported success but produced no rpm"

mkdir -p "$OUTDIR"
cp "$rpm" "$OUTDIR/"
built="$OUTDIR/${rpm##*/}"
say "Built $built"

[ "$do_install" = 1 ] || exit 0

# quickshell is the one hard dep Fedora may not have. Adding a third-party COPR
# as root is a trust decision, so this prints the commands rather than running
# them, unless RISHOT_ENABLE_COPR=1 says otherwise. Same contract as install.sh.
ensure_quickshell() {
	have qs && return 0
	rpm -q quickshell >/dev/null 2>&1 && return 0
	have dnf || return 0
	dnf list --available quickshell >/dev/null 2>&1 && return 0

	if [ "${RISHOT_ENABLE_COPR:-0}" = 1 ]; then
		warn "enabling third-party COPR errornointernet/quickshell (RISHOT_ENABLE_COPR=1)"
		sudo dnf -y copr enable errornointernet/quickshell \
			|| warn "could not enable the COPR; the install below will fail on quickshell"
		return 0
	fi

	warn "quickshell is not in your Fedora repos. The community COPR has it:"
	say "  sudo dnf copr enable errornointernet/quickshell"
	say "or re-run with RISHOT_ENABLE_COPR=1 to add it here"
	say ""
}

ensure_quickshell

if is_atomic; then
	say "Atomic system detected; layering the rpm (this needs a reboot)."
	say "  sudo rpm-ostree install $built"
	say ""
	say "Not run for you: layering reboots into a new deployment, so it is yours to time."
	exit 0
fi

say "Installing $built…"
sudo dnf install -y "$built" || die "dnf could not install the rpm"

say ""
say "Done. rishot is at $(command -v rishot 2>/dev/null || echo /usr/bin/rishot)."
say "It has no global hotkey; bind it in your compositor config, e.g.:"
say "  Hyprland:  bind = , Print, exec, rishot"
say "  Sway:      bindsym Print exec rishot"
