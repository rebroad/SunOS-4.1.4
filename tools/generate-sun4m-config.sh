#!/bin/bash
set -euo pipefail

# Generate a sun4m config from the historical master file with a host cpp.
# Sun's cpp accepted a few constructs which GNU cpp rejects: a leading '+ '
# continuation, hash-prefixed prose, and a macro which deliberately emitted a
# hash to comment out GENERIC_SMALL lines. Keep those translations here,
# outside the source and external build trees, so the generated config can be
# recreated without editing either tree.

source_root=${SOURCE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
build_root=${BUILD_ROOT:-/mnt/kingston/builds/rebroad/src/SunOS-4.1.4.build}
config_name=${1:-SUN4M_IDLE}
shift || true
if [[ $config_name =~ [0-9] ]]; then
    qname="\"$config_name\""
else
    qname=$config_name
fi
if (($# == 0)); then
    set -- GENERIC_SMALL
fi
cpp_options=()
for option in "$@"; do
    case "$option" in
        -*) cpp_options+=("$option") ;;
        *) cpp_options+=("-D${option}=__${option}__") ;;
    esac
done
config_dir="$build_root/sys/sun4m/conf"
output="$config_dir/$config_name"
tmp="$output.tmp"
errors="$output.cpp.err"

mkdir -p "$config_dir"
mkdir -p "$build_root/sys/sun4m/$config_name"

# The old generator programs include SunOS's stdio.h.  Keep this small host
# compatibility declaration in the generated tree rather than polluting the
# source tree or allowing host libc declarations to collide with SunOS ones.
cat > "$build_root/sys/sun4m/$config_name/stdio.h" <<'EOF'
#ifndef _SUNOS_BUILD_STDIO_H
#define _SUNOS_BUILD_STDIO_H
typedef struct _sun_build_FILE FILE;
FILE *fopen(const char *, const char *);
int fclose(FILE *);
int fprintf(FILE *, const char *, ...);
int printf(const char *, ...);
int time(int *);
char *ctime(const int *);
int strcmp(const char *, const char *);
void exit(int);
#endif
EOF

set -o pipefail
awk '
/^%#/ { print; next }
$0 ~ /^#(define|if|ifdef|ifndef|elif|else|endif|include|undef|line)/ {
  if ($0 ~ /^#define[[:space:]]+_GSCOMM_/) sub(/[[:space:]]#[[:space:]]*$/, " CONFIG_HASH")
  print; next
}
$0 ~ /^#[[:space:]]/ { sub(/^#[[:space:]]*/, "/* "); print $0 " */"; next }
$0 ~ /^#[[:space:]]*$/ { print "/* */"; next }
{ if (substr($0, 1, 1) == "+") $0 = " " substr($0, 2); print }
' "$source_root/sys/conf.common/master" |
    cpp -E -P -undef -D_NAME_="$config_name" -D_QNAME_="$qname" \
        -D_ARCH_=sun4m '-D_QARCH_="sun4m"' -Dsun4m=__sun4m__ \
        "${cpp_options[@]}" -x c - \
        > "$tmp" 2> "$errors"

if grep -q 'error:' "$errors"; then
    cat "$errors" >&2
    rm -f "$tmp"
    exit 1
fi

sed 's/^%#/CONFIG_HASH /; s/^CONFIG_HASH /#/; s/^=$//' "$tmp" > "$output"
rm -f "$tmp"
printf '%s: %s lines\n' "$output" "$(wc -l < "$output")"
