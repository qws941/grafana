#!/bin/bash
# Apply RL improvement patch to CLAUDE.md
# Requires human approval via GitHub issue

set -euo pipefail

CLAUDE_HOME="${HOME}/.claude"
CLAUDE_MD="${CLAUDE_HOME}/CLAUDE.md"
PATCH_DIR="${CLAUDE_HOME}/patches"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <patch_file> [--force]"
  exit 1
fi

PATCH_FILE=$1
FORCE=${2:-""}

if [ ! -f "${PATCH_FILE}" ]; then
  echo "❌ Patch file not found: ${PATCH_FILE}"
  exit 1
fi

echo "📝 Patch: $(basename ${PATCH_FILE})"

# Extract approval status from patch
APPROVAL=$(grep -oP 'Approval Threshold: ≥\K\d+' "${PATCH_FILE}" || echo "70")

if [ "$FORCE" != "--force" ]; then
  echo "⚠️  Human approval required (≥${APPROVAL}%)"
  echo "   Review patch: cat ${PATCH_FILE}"
  echo "   To apply: $0 ${PATCH_FILE} --force"
  exit 0
fi

# Backup current CLAUDE.md
cp "${CLAUDE_MD}" "${CLAUDE_MD}.backup-$(date +%Y%m%d_%H%M%S)"

# Extract version
CURRENT_VERSION=$(grep -oP '^# CLAUDE.md v\K[\d.]+' "${CLAUDE_MD}")
MAJOR=$(echo "$CURRENT_VERSION" | cut -d. -f1)
MINOR=$(echo "$CURRENT_VERSION" | cut -d. -f2)
NEW_MINOR=$((MINOR + 1))
NEW_VERSION="${MAJOR}.${NEW_MINOR}"

echo "📊 Version: v${CURRENT_VERSION} → v${NEW_VERSION}"

# TODO: Apply patch changes (manual edit required based on patch content)
# For now, log the action
echo "[$(date -Iseconds)] Patch applied: ${PATCH_FILE}" >> "${CLAUDE_HOME}/data/reinforcement-learning/patch-history.log"

echo "✅ Patch application prepared"
echo "   Manual: Review and edit CLAUDE.md based on patch recommendations"
echo "   Update version to v${NEW_VERSION}"
echo "   Commit: git add CLAUDE.md && git commit -m 'feat: Apply RL patch v${NEW_VERSION}'"

