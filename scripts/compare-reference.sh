#!/bin/bash
# Compare a freshly packed core with the verified reference core.
#
# Usage: scripts/compare-reference.sh <new.tar.gz> <reference.tar.gz> [output.txt]
#
# Reports, for each target in TARGETS, files under tools/sdk/<target>/ that are
# only in one archive or whose contents differ, the sizes of the key libraries,
# and a diff of the esp32s3 qio_qspi/qio_opi sdkconfig.h.
set -euo pipefail
cd "$(dirname "$0")/.."
source versions.env

NEW=${1:?usage: compare-reference.sh <new.tar.gz> <reference.tar.gz> [out.txt]}
REF=${2:?usage: compare-reference.sh <new.tar.gz> <reference.tar.gz> [out.txt]}
OUT=${3:-}

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/new" "$TMP/ref"

new_top=$(tar -tzf "$NEW" | head -1 | cut -d/ -f1)
ref_top=$(tar -tzf "$REF" | head -1 | cut -d/ -f1)
echo "new top: $new_top"
echo "ref top: $ref_top"

tar -xzf "$NEW" -C "$TMP/new" --strip-components=1 --wildcards "*/tools/sdk/*"
tar -xzf "$REF" -C "$TMP/ref" --strip-components=1 --wildcards "*/tools/sdk/*"

emit() { [ -n "$OUT" ] && tee "$OUT" || cat; }

{
  echo "=== comparison: new=$NEW"
  echo "===             ref=$REF"
  echo

  for T in $TARGETS; do
    echo "########## tools/sdk/$T ##########"
    ( cd "$TMP/new" && find "tools/sdk/$T" -type f | sort ) > "$TMP/new-$T.names"
    ( cd "$TMP/ref" && find "tools/sdk/$T" -type f | sort ) > "$TMP/ref-$T.names"
    only_new=$(comm -23 "$TMP/new-$T.names" "$TMP/ref-$T.names")
    only_ref=$(comm -13 "$TMP/new-$T.names" "$TMP/ref-$T.names")
    echo "-- only in new: $(printf '%s\n' "$only_new" | grep -c . || true)"
    [ -n "$only_new" ] && printf '%s\n' "$only_new" | sed 's/^/   + /'
    echo "-- only in ref: $(printf '%s\n' "$only_ref" | grep -c . || true)"
    [ -n "$only_ref" ] && printf '%s\n' "$only_ref" | sed 's/^/   - /'

    # content hashes for files present in both
    comm -12 "$TMP/new-$T.names" "$TMP/ref-$T.names" > "$TMP/common-$T.names"
    ( cd "$TMP/new" && xargs -r -a "$TMP/common-$T.names" sha256sum ) > "$TMP/new-$T.sums"
    ( cd "$TMP/ref" && xargs -r -a "$TMP/common-$T.names" sha256sum ) > "$TMP/ref-$T.sums"
    differing=$(diff <(sort "$TMP/new-$T.sums") <(sort "$TMP/ref-$T.sums") | grep '^[<>]' | awk '{print $3}' | sort -u || true)
    echo "-- differing contents: $(printf '%s\n' "$differing" | grep -c . || true)"
    [ -n "$differing" ] && printf '%s\n' "$differing" | sed 's/^/   ~ /'
    echo
  done

  echo "########## key library sizes ##########"
  for T in $TARGETS; do
    for lib in libesp_pm.a libfreertos.a libbt.a; do
      n=$(stat -c%s "$TMP/new/tools/sdk/$T/lib/$lib" 2>/dev/null || echo -)
      r=$(stat -c%s "$TMP/ref/tools/sdk/$T/lib/$lib" 2>/dev/null || echo -)
      printf '  %-8s %-16s new=%-10s ref=%-10s\n' "$T" "$lib" "$n" "$r"
    done
  done
  echo

  echo "########## esp32s3 sdkconfig.h diff ##########"
  for v in qio_qspi qio_opi; do
    echo "-- $v"
    if diff "$TMP/ref/tools/sdk/esp32s3/$v/include/sdkconfig.h" \
            "$TMP/new/tools/sdk/esp32s3/$v/include/sdkconfig.h" > "$TMP/sdk-$v.diff"; then
      echo "   identical"
    else
      echo "   $(grep -c '^[<>]' "$TMP/sdk-$v.diff") differing lines"
      sed 's/^/   /' "$TMP/sdk-$v.diff"
    fi
  done
} | emit
