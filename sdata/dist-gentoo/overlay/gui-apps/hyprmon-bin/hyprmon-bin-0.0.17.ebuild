# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Monitor configuration tool for Hyprland"
HOMEPAGE="https://github.com/erans/hyprmon"
SRC_URI="
	amd64? ( https://github.com/erans/hyprmon/releases/download/v${PV}/hyprmon-linux-amd64.tar.gz -> hyprmon-${PV}-amd64.tar.gz )
	arm64? ( https://github.com/erans/hyprmon/releases/download/v${PV}/hyprmon-linux-arm64.tar.gz -> hyprmon-${PV}-arm64.tar.gz )
"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
RESTRICT="strip"

DEPEND=""
RDEPEND=""

S="${WORKDIR}"

src_install() {
	if use amd64; then
		newbin "${WORKDIR}/hyprmon-linux-amd64" hyprmon
	elif use arm64; then
		newbin "${WORKDIR}/hyprmon-linux-arm64" hyprmon
	fi
	dodoc README.md
}
