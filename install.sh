#!/bin/sh
# One-command installer for the DAG skill for Claude Code.
#
#   ./install.sh [--prefix DIR] [--skip-lean]
#
# Defaults: prefix ~/.claude/skills/DAG, and the Lean checker is built (installing
# the elan toolchain if needed). --skip-lean installs the skill without the
# checker: every /dag workflow works, but dagcheck commands stay unavailable
# until you build checker/ yourself (lake build).
#
# Safety contract:
#   - Idempotent: re-running refreshes the same files. Before the first overwrite
#     in a run, any pre-existing install is copied to <prefix>.backup-<timestamp>.
#   - It NEVER deletes files outside the copy set, and NEVER touches any .dag
#     directory anywhere (project registries are user data, not skill files).
#   - A failed Lean build leaves the skill installed and says so; it does not
#     pretend the checker exists.

set -u

PREFIX="$HOME/.claude/skills/DAG"
SKIP_LEAN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    --skip-lean) SKIP_LEAN=1; shift ;;
    *) echo "usage: $0 [--prefix DIR] [--skip-lean]" >&2; exit 2 ;;
  esac
done

SRC=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
COPYSET="SKILL.md README.md LICENSE references checker graph hooks benchmarks"

# .dag guard: refuse to run if the source tree somehow sits inside a registry
case "$SRC" in
  */.dag|*/.dag/*) echo "install.sh: refusing to run from inside a .dag directory" >&2; exit 2 ;;
esac

CHANGED=0
for item in $COPYSET; do
  if [ ! -e "$SRC/$item" ]; then
    echo "install.sh: source tree is missing $item (run from the repo root)" >&2
    exit 2
  fi
done

if [ -d "$PREFIX" ]; then
  # back up before the first overwrite in this run
  DIFFERS=0
  for item in $COPYSET; do
    # exclude build artifacts and test-generated provenance: they are stripped from
    # the install below, so comparing against the source tree must ignore them too
    if ! diff -rq -x .lake -x provenance.json "$SRC/$item" "$PREFIX/$item" >/dev/null 2>&1; then
      DIFFERS=1; break
    fi
  done
  if [ "$DIFFERS" = "1" ]; then
    TS=$(date +%Y%m%d-%H%M%S)-$$
    BACKUP="$PREFIX.backup-$TS"
    cp -R "$PREFIX" "$BACKUP"
    echo "install.sh: existing install backed up to $BACKUP"
  fi
else
  mkdir -p "$PREFIX"
fi

for item in $COPYSET; do
  rm -rf "${PREFIX:?}/$item"
  cp -R "$SRC/$item" "$PREFIX/$item"
done
# never ship build artifacts or test-generated provenance into the install
rm -rf "$PREFIX/checker/.lake" "$PREFIX/checker/tests/fixtures"/*/provenance.json 2>/dev/null || true
CHANGED=1

echo "install.sh: skill installed to $PREFIX"

CHECKER_STATE="skipped (--skip-lean)"
if [ "$SKIP_LEAN" = "0" ]; then
  if command -v lake >/dev/null 2>&1; then
    LAKE=lake
  elif [ -x "$HOME/.elan/bin/lake" ]; then
    LAKE="$HOME/.elan/bin/lake"
  else
    echo "install.sh: no Lean toolchain found; installing elan (leanprover toolchain, reads checker/lean-toolchain)..."
    if curl -sSf https://elan.lean-lang.org/elan-init.sh | sh -s -- -y >/dev/null 2>&1; then
      LAKE="$HOME/.elan/bin/lake"
    else
      LAKE=""
    fi
  fi
  if [ -n "${LAKE:-}" ]; then
    if (cd "$PREFIX/checker" && "$LAKE" build >/dev/null 2>&1); then
      CHECKER_STATE="built ($PREFIX/checker/.lake/build/bin/dagcheck)"
    else
      CHECKER_STATE="BUILD FAILED - skill installed, dagcheck unavailable; run 'cd $PREFIX/checker && lake build' to retry"
    fi
  else
    CHECKER_STATE="TOOLCHAIN INSTALL FAILED - skill installed, dagcheck unavailable; install elan and run 'cd $PREFIX/checker && lake build'"
  fi
fi
echo "install.sh: checker: $CHECKER_STATE"
echo "install.sh: done. In any project, run /dag init to start a registry."
echo "install.sh: optional git hooks: cp $PREFIX/hooks/pre-commit $PREFIX/hooks/post-commit <project>/.git/hooks/"
