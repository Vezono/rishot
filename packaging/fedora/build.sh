#!/bin/sh
# Build an RPM of this checkout and install it. The Fedora counterpart to
# packaging/aur/PKGBUILD, for a system-wide install under /usr instead of the
# per-user tree that install.sh drops in ~/.local/share/rishot.
#
#   sh packaging/fedora/build.sh              deps, then build and install
#   sh packaging/fedora/build.sh --no-install deps and build, print the rpm path
#   sh packaging/fedora/build.sh --no-deps    skip the dependency step
#   sh packaging/fedora/build.sh --deps-only  install the dependencies and stop
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
	say "usage: $PROG [--no-install] [--no-deps | --deps-only]"
	say ""
	say "  --no-install   build the rpm and stop, leaving it in $OUTDIR"
	say "  --no-deps      do not install dependencies"
	say "  --deps-only    install dependencies and stop"
	say "  -h, --help     this text"
	say ""
	say "environment:"
	say "  RISHOT_RPM_OUTDIR        where the finished rpm is written"
	say "  RISHOT_ENABLE_COPR       1 to add the quickshell COPR when Fedora lacks it"
	say "  RISHOT_ENABLE_RPMFUSION  1 to add RPM Fusion for an ffmpeg with libx264"
}

do_install=1
do_deps=1
deps_only=0
while [ $# -gt 0 ]; do
	case "$1" in
	--no-install) do_install=0 ;;
	--no-deps) do_deps=0 ;;
	--deps-only) deps_only=1 ;;
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

# --- dependencies ----------------------------------------------------------
#
# dnf resolves the rpm's own Requires and Recommends when it installs the built
# package, so this step exists for the pieces it cannot reach on its own:
# quickshell on a Fedora that predates it, an ffmpeg that can actually encode
# H.264, and the handful of optional tools Fedora does not package.

# One optional dep, best effort. A package missing from the repos warns and is
# skipped rather than aborting, so the run always completes; each one only
# switches off its own feature.
opt_install() {
	pkg=$1
	what=$2
	rpm -q "$pkg" >/dev/null 2>&1 && return 0
	if sudo dnf install -y "$pkg" >/dev/null 2>&1; then
		say "  $pkg: installed"
	else
		warn "$pkg is not in your repos, skipping ($what stays off)"
	fi
}

# quickshell is in Fedora 44+. Older releases take it from the community COPR,
# and adding a third-party repo as root is a trust decision, so it is printed
# rather than done unless RISHOT_ENABLE_COPR says otherwise.
ensure_quickshell() {
	have qs && return 0
	sudo dnf install -y quickshell >/dev/null 2>&1 && { say "  quickshell: installed"; return 0; }

	if [ "${RISHOT_ENABLE_COPR:-0}" = 1 ]; then
		warn "enabling third-party COPR errornointernet/quickshell (RISHOT_ENABLE_COPR=1)"
		sudo dnf -y copr enable errornointernet/quickshell \
			&& sudo dnf install -y quickshell && return 0
		warn "COPR install failed; check the COPR build against your Qt6 version"
		return 1
	fi

	warn "quickshell is not in your Fedora repos, and rishot cannot run without it:"
	say "  sudo dnf copr enable errornointernet/quickshell"
	say "  sudo dnf install quickshell"
	say "or re-run with RISHOT_ENABLE_COPR=1 to add it here"
	return 1
}

# Fedora ships ffmpeg-free, which is built without the patent-encumbered
# encoders: no libx264. rishot-record falls back to openh264 and then mpeg4, so
# gif mode still records either way, but libx264 is the one that gives a small
# file at good quality. RPM Fusion is where the full build lives, and adding it
# is the user's call, like the COPR above.
ensure_ffmpeg() {
	if ! have ffmpeg; then
		sudo dnf install -y ffmpeg-free >/dev/null 2>&1 \
			|| sudo dnf install -y ffmpeg >/dev/null 2>&1 \
			|| { warn "could not install ffmpeg; gif mode cannot encode without it"; return 1; }
		say "  ffmpeg: installed"
	fi
	have ffmpeg || return 1

	case "$(ffmpeg -hide_banner -encoders 2>/dev/null)" in
	*" libx264 "*) say "  ffmpeg: libx264 present"; return 0 ;;
	esac

	if [ "${RISHOT_ENABLE_RPMFUSION:-0}" = 1 ]; then
		warn "enabling third-party RPM Fusion for a full ffmpeg (RISHOT_ENABLE_RPMFUSION=1)"
		rel=$(rpm -E %fedora)
		sudo dnf install -y \
			"https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$rel.noarch.rpm" \
			&& sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing || :
		# Confirm rather than trust the exit code: a swap can report success
		# and still leave a build without the encoder.
		case "$(ffmpeg -hide_banner -encoders 2>/dev/null)" in
		*" libx264 "*) say "  ffmpeg: swapped for the RPM Fusion build"; return 0 ;;
		esac
		warn "libx264 is still missing after the swap; gif mode falls back to openh264"
		return 0
	fi

	warn "your ffmpeg has no libx264 (Fedora strips it from ffmpeg-free)."
	say "  mp4 export still works through openh264, at a larger file for the same quality."
	say "  For libx264, enable RPM Fusion and swap the build:"
	say "    sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-\$(rpm -E %fedora).noarch.rpm"
	say "    sudo dnf swap ffmpeg-free ffmpeg --allowerasing"
	say "  or re-run with RISHOT_ENABLE_RPMFUSION=1 to do both here"
}

install_deps() {
	if is_atomic; then
		warn "atomic system: dnf cannot install onto the running deployment."
		say "  Layer the dependencies instead, then re-run with --no-deps:"
		say "    sudo rpm-ostree install quickshell wl-clipboard ffmpeg wf-recorder"
		say ""
		return 0
	fi
	have dnf || die "no dnf; install the dependencies yourself, or pass --no-deps"

	say "Installing required dependencies…"
	sudo dnf install -y wl-clipboard \
		qt6-qtdeclarative qt6-qtsvg qt6-qt5compat qt6-qtwayland \
		|| warn "some required deps failed; rishot may not start"
	ensure_quickshell || :

	say "Installing optional dependencies…"
	opt_install ImageMagick "multi-monitor stitch"
	opt_install curl "upload"
	opt_install kdialog "save dialog and folder picker"
	opt_install libnotify "desktop notifications"
	opt_install tesseract "OCR"
	opt_install zbar "QR codes and barcodes"
	opt_install cliphist "clipboard history"

	say "Installing gif mode dependencies…"
	ensure_ffmpeg || :
	# wf-recorder is the recorder Fedora actually packages; wl-screenrec, which
	# rishot prefers when both are present, lives only in COPRs.
	opt_install wf-recorder "screen recording"
	# gifski is a Rust program and is not in Fedora; cargo is the usual route.
	if ! have gifski; then
		if sudo dnf install -y gifski >/dev/null 2>&1; then
			say "  gifski: installed"
		else
			warn "gifski is not in your repos; gifs will use the ffmpeg palette instead"
			say "    cargo install gifski   # roughly half the file size at the same quality"
		fi
	fi
}

if [ "$do_deps" = 1 ]; then
	install_deps
	say ""
fi

if [ "$deps_only" = 1 ]; then
	say "Dependencies done (--deps-only)."
	exit 0
fi

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

# The dependency step handles this; when it was skipped, say so rather than
# letting dnf fail on an unresolvable quickshell halfway through the install.
if [ "$do_deps" = 0 ] && ! have qs && ! rpm -q quickshell >/dev/null 2>&1 \
	&& ! dnf list --available quickshell >/dev/null 2>&1; then
	warn "quickshell is not installed or available, and --no-deps was passed;"
	say "  the install below will fail until quickshell is there."
	say ""
fi

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
