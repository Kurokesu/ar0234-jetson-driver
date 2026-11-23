#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026, UAB Kurokesu. All rights reserved.
#
# Fetch NVIDIA public device tree headers from GitLab.
#
# Usage:
#	./scripts/fetch-nvidia-headers.sh <output_dir> [l4t_tag]
#
# If l4t_tag is not provided, it is auto-detected from /etc/nv_tegra_release.

set -e

# Status line formatter (matches Makefile's PRINT)
print() { printf '  %-7s %s\n' "$1" "$2"; }

OUT_DIR="${1:?Usage: $0 <output_dir> [l4t_tag]}"
TAGS="${2:-}"

GITLAB_BASE="https://gitlab.com/nvidia/nv-tegra/device/hardware/nvidia/t23x-public-dts/-/raw"
NV_TEGRA_RELEASE="/etc/nv_tegra_release"
DT_HEADER="$OUT_DIR/dt-bindings/tegra234-p3767-0000-common.h"

# Auto-detect tag from nv_tegra_release if not provided
if [ -z "$TAGS" ]; then
	read -r NV_RELEASE_STR < "$NV_TEGRA_RELEASE"

	if [[ "$NV_RELEASE_STR" =~ R([0-9]+).*REVISION:\ *([0-9]+)\.([0-9]+) ]]; then
		L4T_MAJOR="${BASH_REMATCH[1]}"
		L4T_MINOR="${BASH_REMATCH[2]}"
		L4T_PATCH="${BASH_REMATCH[3]}"
	else
		echo "ERROR: cannot parse $NV_TEGRA_RELEASE" >&2; exit 1
	fi

	TAGS="jetson_${L4T_MAJOR}.${L4T_MINOR}.${L4T_PATCH}"

	# NVIDIA mostly omits .0 patch in GitLab tags (jetson_36.5), but not always (jetson_39.2.0)
	if [ "$L4T_PATCH" = "0" ]; then TAGS="jetson_${L4T_MAJOR}.${L4T_MINOR} $TAGS"; fi
fi

mkdir -p "${DT_HEADER%/*}"

for TAG in $TAGS; do
	GITLAB_URL="${GITLAB_BASE}/${TAG}/include/platforms/dt-bindings/${DT_HEADER##*/}"
	if wget -q -O "$DT_HEADER" "$GITLAB_URL" 2>/dev/null; then
		print FETCH "${DT_HEADER##*/} (tag: $TAG)"
		print WROTE "$OUT_DIR"
		exit 0
	fi
done

rm -f "$DT_HEADER"
echo "ERROR: failed to download ${DT_HEADER##*/}" >&2
echo "       Verify that tag ($TAGS) exists and the file is available." >&2
exit 1
