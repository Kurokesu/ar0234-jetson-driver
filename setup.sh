#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026, UAB Kurokesu. All rights reserved.
#
# Former installer name, runs install.sh

exec sh "$(dirname "$0")/install.sh" "$@"
