%{!?rishot_version: %global rishot_version 0}
%{!?rishot_release: %global rishot_release 1}

# Nothing is compiled, so there is no ELF to strip and no debuginfo to split out.
%global debug_package %{nil}

Name:           rishot
Version:        %{rishot_version}
Release:        %{rishot_release}%{?dist}
Summary:        Wayland screenshot and annotation overlay built on Quickshell

License:        MIT
URL:            https://github.com/Gakuseei/rishot
Source0:        %{name}-%{version}.tar.gz

BuildArch:      noarch
BuildRequires:  desktop-file-utils

# quickshell is in Fedora 44+. Older releases take it from the community COPR
# errornointernet/quickshell; build.sh prints the two commands for that.
Requires:       quickshell
Requires:       wl-clipboard
Requires:       qt6-qtdeclarative
Requires:       qt6-qtsvg
Requires:       qt6-qt5compat
Requires:       qt6-qtwayland

# Each optional dep switches on one feature, so they are weak: a missing one
# costs that feature and nothing else. cliphist is not in Fedora proper, hence
# Suggests rather than Recommends.
Recommends:     ImageMagick
Recommends:     curl
Recommends:     kdialog
Recommends:     libnotify
Recommends:     tesseract
Recommends:     zbar
# rishot gif: the recorder plus ffmpeg, and gifski for better gif encoding.
Recommends:     ffmpeg
Recommends:     wl-screenrec
Suggests:       wf-recorder
Suggests:       gifski
Suggests:       cliphist

%description
Drag a region, click a window, or grab a whole monitor, then mark the shot up
with twelve annotation tools and copy, save, or upload it.

rishot is a Quickshell config plus a POSIX sh launcher, so there is nothing to
compile. It captures through wlr-screencopy or ext-image-copy, and on KDE
through spectacle, which KWin needs because it speaks no screencopy protocol.

%prep
%autosetup -n %{name}-%{version}

%build
# Deliberately empty: QML and shell, nothing to build.

%install
# The Quickshell config tree goes to %%{_datadir}/rishot/src, which bin/rishot
# resolves at runtime. GNU find substitutes {} inside the longer argument, so
# each file lands at the same relative path under the buildroot.
find src -type f -exec install -Dm644 '{}' '%{buildroot}%{_datadir}/rishot/{}' ';'

install -Dm755 bin/rishot %{buildroot}%{_bindir}/rishot
install -Dm755 bin/rishot-record %{buildroot}%{_bindir}/rishot-record
install -Dm644 rishot.desktop %{buildroot}%{_datadir}/applications/rishot.desktop
install -Dm644 packaging/rishot.svg %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/rishot.svg

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/rishot.desktop

%files
%license LICENSE
%doc README.md
%{_bindir}/rishot
%{_bindir}/rishot-record
%{_datadir}/rishot/
%{_datadir}/applications/rishot.desktop
%{_datadir}/icons/hicolor/scalable/apps/rishot.svg

%changelog
* Fri Nov 06 2026 rishot packaging <noreply@localhost> - 0-1
- Versions come from the git checkout; see packaging/fedora/build.sh.
