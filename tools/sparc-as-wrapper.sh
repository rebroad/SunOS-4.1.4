#!/bin/bash
set -euo pipefail

as_args=()
cpp_args=(-m32 -mno-v8plus -mcpu=v8 -E -P -traditional-cpp -undef
    -Wno-endif-labels
    -Dsparc -Dsun -DKERNEL -x assembler-with-cpp)
source_file=
for arg in "$@"; do
    case "$arg" in
        -P) ;;
        -D*|-I*) cpp_args+=("$arg") ;;
        *.s|*.S) source_file=$arg ;;
        *) as_args+=("$arg") ;;
    esac
done

if [[ -z $source_file ]]; then
    printf 'sparc-as-wrapper: no assembly source argument\n' >&2
    exit 2
fi

sparc64-linux-gnu-gcc "${cpp_args[@]}" "$source_file" |
    sparc-linux-gnu-as "${as_args[@]}" -
