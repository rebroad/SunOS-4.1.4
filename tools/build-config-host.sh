#!/bin/bash
set -euo pipefail

# Build the historical SunOS config utility as a host program.  The original
# utility expects Sun libc headers and an old yacc; keep the compatibility
# copies and generated parser in the external build tree.

source_root=${SOURCE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
build_root=${BUILD_ROOT:-/mnt/kingston/builds/rebroad/src/SunOS-4.1.4.build}
config_root="$build_root/usr.etc/config"

mkdir -p "$config_root/hostinclude/sun"
cp "$source_root/usr.etc/config/config.h" "$config_root/config.h"
cp "$source_root/usr.etc/config/"*.c "$config_root/"
sed -i '/char[[:space:]]*\*malloc/d; /char[[:space:]]*\*sprintf/d' \
    "$config_root/config.h"
sed -i '1i#include <stdlib.h>\n#include <string.h>' "$config_root/config.h"

# sccsnames.c carries pre-ANSI declarations which conflict with modern libc.
sed -i '/^char[[:space:]]*\*malloc(),/,/^void[[:space:]]*setname();/c\char *copys();\nvoid setname();' \
    "$config_root/sccsnames.c"
sed -i '1i#include <stdlib.h>\n#include <string.h>' "$config_root/sccsnames.c"

sed -E \
    -e 's/^([[:space:]]*)= /\1/' \
    -e 's/([[:alnum:]_]) = \{/\1 {/' \
    -e '/^char[[:space:]]*\*malloc\(\);/d' \
    -e '/struct file_list \*newfile\(\);/a struct device *find_scsibus();\nchar *ns();' \
    "$source_root/usr.etc/config/config.y" > "$config_root/config.y.host"

bison -y -d -o "$config_root/y.tab.c" "$config_root/config.y.host"
flex -o "$config_root/lex.yy.c" "$source_root/usr.etc/config/config.l"
cp "$source_root/sys/sun/autoconf.h" "$config_root/hostinclude/sun/autoconf.h"

cd "$config_root"
gcc -std=gnu89 -fcommon \
    -Wno-endif-labels -Wno-implicit-function-declaration \
    -Ihostinclude -I../../sys/sun4m \
    -o config \
    y.tab.c main.c lex.yy.c mkioconf.c mkmakefile.c mkglue.c \
    mkheaders.c mkbootconf.c sccsnames.c -lfl
printf '%s\n' "$config_root/config"
