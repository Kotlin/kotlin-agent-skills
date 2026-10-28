#!/usr/bin/env bash
# Runs the same checks locally that CI (.github/workflows/validate-skills.yml) runs:
#   1. Directory name matches kotlin-<category>-<functional-name>
#   2. <category> is listed in the CATEGORIES file
#   3. <functional-name> is kebab-case
#   4. SKILL.md passes Flash-Brew-Digital/validate-skill (Agent Skills spec compliance)
#
# Usage:
#   scripts/validate-skills.sh                      # validate every skill under skills/
#   scripts/validate-skills.sh skills/kotlin-...    # validate specific skill directories
#
# Requirements: bash, git, node (>= 20).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATOR_REPO="https://github.com/Flash-Brew-Digital/validate-skill.git"
VALIDATOR_REF="v1"
VALIDATOR_DIR="${VALIDATE_SKILL_DIR:-${TMPDIR:-/tmp}/validate-skill-${VALIDATOR_REF}}"

if [ "$#" -gt 0 ]; then
  SKILLS=("$@")
else
  SKILLS=("$REPO_ROOT"/skills/*/)
fi

if ! command -v node >/dev/null 2>&1; then
  echo "Error: node is required (the CI validator is a Node 20 GitHub Action)." >&2
  exit 1
fi

if [ ! -f "$VALIDATOR_DIR/dist/index.js" ]; then
  echo "Fetching $VALIDATOR_REPO@$VALIDATOR_REF into $VALIDATOR_DIR"
  rm -rf "$VALIDATOR_DIR"
  git clone --quiet --depth 1 --branch "$VALIDATOR_REF" "$VALIDATOR_REPO" "$VALIDATOR_DIR"
fi

failed=0

for skill in "${SKILLS[@]}"; do
  skill="${skill%/}"
  skill_dir="$(basename "$skill")"
  echo "==> $skill_dir"

  # --- Checks 1-3: directory naming (mirrors the CI shell step) ---
  if [[ ! $skill_dir =~ ^kotlin-([a-z0-9]+)-([a-z0-9-]+)$ ]]; then
    echo "  Error: directory name '$skill_dir' does not follow 'kotlin-<category>-<functional-name>'"
    failed=1
    continue
  fi
  category="${BASH_REMATCH[1]}"
  functional_name="${BASH_REMATCH[2]}"

  if ! grep -Fxq "$category" "$REPO_ROOT/CATEGORIES"; then
    echo "  Error: category '$category' is not listed in CATEGORIES ($(paste -sd, "$REPO_ROOT/CATEGORIES"))"
    failed=1
  fi

  if [[ ! $functional_name =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    echo "  Error: functional name '$functional_name' must be kebab-case (lowercase, digits, hyphens)"
    failed=1
  fi

  # --- Check 4: SKILL.md spec compliance via the same action CI uses ---
  # @actions/core reads inputs from INPUT_<NAME> environment variables.
  if ! (cd "$REPO_ROOT" && INPUT_PATH="$skill" INPUT_FAIL_ON_WARNING=false INPUT_IGNORE_RULES="" \
        INPUT_ENFORCE_DIRECTORIES="" INPUT_VALIDATE_REFERENCES=false \
        node "$VALIDATOR_DIR/dist/index.js"); then
    failed=1
  fi
done

if [ "$failed" -ne 0 ]; then
  echo
  echo "Validation FAILED."
  exit 1
fi

echo
echo "All skills passed."
