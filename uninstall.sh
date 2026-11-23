#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026, UAB Kurokesu. All rights reserved.
#
# Uninstall Kurokesu camera driver (device tree overlay + kernel module via DKMS)

# Exit on errors
set -e

# Status line formatter (matches Makefile's PRINT)
print() { printf '  %-7s %s\n' "$1" "$2"; }

# Package identity and install paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DKMS_CONF="$SCRIPT_DIR/dkms.conf"
PACKAGE_NAME=$(grep '^PACKAGE_NAME=' "$DKMS_CONF" | cut -d'"' -f2)
MODULE=$(grep '^BUILT_MODULE_NAME=' "$DKMS_CONF" | cut -d'"' -f2)
SENSOR="${MODULE#nv_}"
DEPMOD_CONF="/etc/depmod.d/${PACKAGE_NAME}.conf"
TUNING_DIR="$SCRIPT_DIR/tuning"
NVCAM_SETTINGS="/var/nvidia/nvcam/settings"
EXTLINUX="/boot/extlinux/extlinux.conf"
REMOVED=0

# Check required variables
if [ -z "$PACKAGE_NAME" ] || [ -z "$SENSOR" ]; then
	echo "Error: failed to parse $DKMS_CONF" >&2
	exit 1
fi

echo "Kurokesu Camera Driver Uninstaller"
echo "${PACKAGE_NAME}"
echo ""

# Missing overlay aborts extlinux boot, refuse before touching anything
DEFAULT_OVERLAYS=$(awk '$1 == "DEFAULT" { d = $2 } $1 == "LABEL" { l = $2 }
	$1 == "OVERLAYS" { o[l] = o[l] " " $0 } END { print o[d] }' "$EXTLINUX" 2>/dev/null)
for DTS in "$SCRIPT_DIR"/*.dts; do
	DTBO="/boot/$(basename "$DTS" .dts).dtbo"
	case "$DEFAULT_OVERLAYS" in
	*"$DTBO"*)
		echo "Error: default boot entry in $EXTLINUX loads" >&2
		echo "$DTBO" >&2
		echo "Pick another module in Jetson-IO or boot without overlays:" >&2
		echo "sudo sed -i 's/^DEFAULT .*/DEFAULT primary/' $EXTLINUX" >&2
		exit 1
		;;
	esac
done

# Remove DKMS registrations matching sensor name, same sweep as install.sh
if command -v dkms >/dev/null 2>&1; then
	ENTRIES=$(dkms status 2>/dev/null | sed 's/[,:].*//' | sort -u)
	for ENTRY in $ENTRIES; do
		case "${ENTRY%%/*}" in
		*"$SENSOR"*)
			REMOVED=1
			print DKMS "remove $ENTRY"
			if ! OUT=$(dkms remove "$ENTRY" --all 2>&1); then
				print WARN "could not fully remove $ENTRY" >&2
				printf '%s\n' "$OUT" >&2
			fi
			;;
		esac
	done
fi

# Source trees a failed install may have left behind
for SRC in /usr/src/*"$SENSOR"*; do
	[ -f "$SRC/dkms.conf" ] || continue
	REMOVED=1
	print CLEAN "$SRC"
	rm -rf "$SRC" || print WARN "could not remove $SRC" >&2
done

if [ -f "$DEPMOD_CONF" ]; then
	REMOVED=1
	print REMOVE "$DEPMOD_CONF"
	rm -f "$DEPMOD_CONF"
	depmod
fi

for DTS in "$SCRIPT_DIR"/*.dts; do
	DTBO="/boot/$(basename "$DTS" .dts).dtbo"
	[ -f "$DTBO" ] || continue
	REMOVED=1
	print REMOVE "$DTBO"
	rm -f "$DTBO"
done

# Remove copied tuning and links to it, foreign links stay
if [ -d "$TUNING_DIR" ]; then
	for FILE in "$TUNING_DIR"/*; do
		NAME="${FILE##*/}"
		for LINK in "$NVCAM_SETTINGS"/*; do
			[ -L "$LINK" ] && [ "$(readlink "$LINK")" = "$NAME" ] || continue
			REMOVED=1
			print REMOVE "$LINK"
			rm -f "$LINK"
		done
		TARGET="$NVCAM_SETTINGS/$NAME"
		if [ -L "$TARGET" ]; then
			print KEEP "$NAME -> $(readlink "$TARGET")"
		elif [ -f "$TARGET" ]; then
			REMOVED=1
			print REMOVE "$TARGET"
			rm -f "$TARGET"
		fi
	done
fi

if [ "$REMOVED" -eq 0 ]; then
	echo "Nothing to remove, ${PACKAGE_NAME} not installed."
	exit 0
fi

echo ""
echo "Done. Reboot to unload driver."
