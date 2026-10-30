#!/usr/bin/env bash
# Pass 1 of the PRD §8 external validation gate. Runs
# PropertyLawDiscoveryTool against an external Swift package's source
# files without requiring SwiftPropertyLaws to be added as a dep on
# the target.
#
# Usage:
#   Validation/run.sh <package-path> <target-name> [<sources-subdir>]
#
# Defaults sources-subdir to "Sources/<target-name>". Output lands in
# Validation/results/<target-name>.generated.swift; the tool's stdout
# summary goes to Validation/results/<target-name>.summary.txt.
set -euo pipefail

PACKAGE_PATH="${1:?package path required}"
TARGET="${2:?target name required}"
SOURCES_SUBDIR="${3:-Sources/$TARGET}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_DIR="$ROOT/Validation/results"
OUTPUT="$RESULTS_DIR/$TARGET.generated.swift"
SUMMARY="$RESULTS_DIR/$TARGET.summary.txt"

mkdir -p "$RESULTS_DIR"

SOURCES_DIR="$PACKAGE_PATH/$SOURCES_SUBDIR"
if [[ ! -d "$SOURCES_DIR" ]]; then
    echo "error: $SOURCES_DIR is not a directory"
    exit 1
fi

# Build the tool from this package, then invoke directly.
cd "$ROOT"
swift build --product PropertyLawDiscoveryTool -c release 2>&1 | tail -3
TOOL=$(swift build --product PropertyLawDiscoveryTool -c release --show-bin-path)/PropertyLawDiscoveryTool

# Collect every .swift file under the target's source dir.
SOURCE_FILES=()
while IFS= read -r -d '' file; do
    SOURCE_FILES+=("$file")
done < <(find "$SOURCES_DIR" -name "*.swift" -type f -print0 | sort -z)

if [[ ${#SOURCE_FILES[@]} -eq 0 ]]; then
    echo "error: no .swift files under $SOURCES_DIR"
    exit 1
fi

echo "package: $PACKAGE_PATH"
echo "target:  $TARGET"
echo "sources: ${#SOURCE_FILES[@]} files under $SOURCES_DIR"
echo "output:  $OUTPUT"

"$TOOL" \
    --target "$TARGET" \
    --output "$OUTPUT" \
    --source-files "${SOURCE_FILES[@]}" \
    | tee "$SUMMARY"

echo
echo "Generated file:"
echo "  $OUTPUT"
echo "Summary:"
echo "  $SUMMARY"
