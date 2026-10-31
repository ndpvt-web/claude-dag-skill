#!/bin/sh
# Behavioral test for install.sh: idempotent, backs up before overwrite, never
# touches .dag, honors --skip-lean. All writes in temp dirs. Exits 1 on failure.
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
FAIL=0
ok() { if [ "$2" = "0" ]; then echo "PASS $1"; else echo "FAIL $1  $3"; FAIL=1; fi }

PREFIX="$T/skills/DAG"
sh "$ROOT/install.sh" --prefix "$PREFIX" --skip-lean >/dev/null
ok "first-install-succeeds" "$?"
for f in SKILL.md README.md LICENSE references/registry-spec.md checker/Main.lean graph/index.html hooks/pre-commit benchmarks/README.md; do
  [ -f "$PREFIX/$f" ] || { echo "FAIL copied-$f"; FAIL=1; }
done
echo "PASS copyset-present"
[ -d "$PREFIX/checker/.lake" ] && { echo "FAIL lake-artifacts-excluded"; FAIL=1; } || echo "PASS lake-artifacts-excluded"

# idempotent: second run over identical tree makes no backup
sh "$ROOT/install.sh" --prefix "$PREFIX" --skip-lean >/dev/null
ok "second-install-succeeds" "$?"
ls -d "$PREFIX".backup-* >/dev/null 2>&1 && { echo "FAIL idempotent-no-backup"; FAIL=1; } || echo "PASS idempotent-no-backup"

# modified target -> backup with OLD content before overwrite
echo "local-edit" >> "$PREFIX/README.md"
sh "$ROOT/install.sh" --prefix "$PREFIX" --skip-lean >/dev/null
ok "third-install-succeeds" "$?"
B=$(ls -d "$PREFIX".backup-* 2>/dev/null | head -1)
[ -n "$B" ] && grep -q "local-edit" "$B/README.md" && echo "PASS backup-preserves-old-content" || { echo "FAIL backup-preserves-old-content"; FAIL=1; }
grep -q "local-edit" "$PREFIX/README.md" && { echo "FAIL target-refreshed"; FAIL=1; } || echo "PASS target-refreshed"

# .dag inside the prefix is user data: never deleted, never overwritten
mkdir -p "$PREFIX/.dag/registry"
echo '{"keep":true}' > "$PREFIX/.dag/registry/axioms.json"
sh "$ROOT/install.sh" --prefix "$PREFIX" --skip-lean >/dev/null
[ -f "$PREFIX/.dag/registry/axioms.json" ] && grep -q keep "$PREFIX/.dag/registry/axioms.json" \
  && echo "PASS dag-directory-untouched" || { echo "FAIL dag-directory-untouched"; FAIL=1; }

# checker binary absent under --skip-lean
[ -f "$PREFIX/checker/.lake/build/bin/dagcheck" ] && { echo "FAIL skip-lean-no-binary"; FAIL=1; } || echo "PASS skip-lean-no-binary"

exit $FAIL
