#!/bin/bash
set -euo pipefail

target=${1:?usage: $0 TARGET_SOURCE_OR_BUILD_TREE}
patch_file=${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/patches/qemu-idle-kernel.patch}

[[ -d "$target" ]] || {
	printf 'target tree does not exist: %s\n' "$target" >&2
	exit 2
}
[[ -r "$patch_file" ]] || {
	printf 'patch file does not exist: %s\n' "$patch_file" >&2
	exit 2
}

if git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	if git -C "$target" apply --check "$patch_file" >/dev/null 2>&1; then
		git -C "$target" apply --whitespace=nowarn "$patch_file"
	elif git -C "$target" apply --reverse --check "$patch_file" >/dev/null 2>&1; then
		printf 'QEMU idle kernel patch already applied: %s\n' "$target"
	else
		printf 'QEMU idle kernel patch does not apply cleanly: %s\n' "$target" >&2
		exit 1
	fi
elif patch --dry-run -d "$target" -p1 <"$patch_file" >/dev/null 2>&1; then
	patch -d "$target" -p1 <"$patch_file"
elif patch --dry-run -R -d "$target" -p1 <"$patch_file" >/dev/null 2>&1; then
	printf 'QEMU idle kernel patch already applied: %s\n' "$target"
else
	printf 'QEMU idle kernel patch does not apply cleanly: %s\n' "$target" >&2
	exit 1
fi
