#!/usr/bin/env bash
# Install the pair / pair-review skills into ~/.claude/skills/
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)/skills"
DEST="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"

mkdir -p "$DEST"
for skill in pair pair-review; do
  rm -rf "$DEST/$skill"
  cp -R "$SRC/$skill" "$DEST/$skill"
  echo "installed $DEST/$skill"
done

# WORKFLOW.md lives at the repo root (README links to it there) but the pair
# skill reads it from its own directory, so it has to be copied in separately.
cp "$(dirname "$SRC")/WORKFLOW.md" "$DEST/pair/WORKFLOW.md"
echo "installed $DEST/pair/WORKFLOW.md"

echo "Done. /pair and /pair-review are now available in Claude Code."
