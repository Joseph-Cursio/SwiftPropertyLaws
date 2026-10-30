#!/usr/bin/env bash
# Pass 1 of the PRD §8 external validation gate. Runs the discovery plugin,
# `swift package propertylawcheck discover`, against an external Swift
# package exactly as an adopter would, so the scan sees what theirs does:
# the target's files, plus its transitive dependencies' sources as context.
#
# The external checkout is not touched. The package is copied (without
# .build and .git) to .build/validation-pass1/<target-name>/ in this repo,
# SwiftPropertyLaws is added to the copy's dependencies by local path, and the
# plugin runs there. The copy is kept between runs so its build is
# incremental; `swift package clean` here removes it. The first run per
# package resolves its dependencies and builds the tool, which takes minutes.
#
# Usage:
#   Validation/run.sh <package-path> <target-name>
#
# Output lands in Validation/results/<target-name>.generated.swift, and the
# tool's summary in Validation/results/<target-name>.summary.txt. Paths in
# both are rewritten from the copy back to <package-path>.
set -euo pipefail

PACKAGE_PATH="$(cd "${1:?package path required}" && pwd -P)"
TARGET="${2:?target name required}"

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
RESULTS_DIR="$ROOT/Validation/results"
OUTPUT="$RESULTS_DIR/$TARGET.generated.swift"
SUMMARY="$RESULTS_DIR/$TARGET.summary.txt"
WORK="$ROOT/.build/validation-pass1/$TARGET"

if [[ ! -f "$PACKAGE_PATH/Package.swift" ]]; then
    echo "error: $PACKAGE_PATH has no Package.swift"
    exit 1
fi
mkdir -p "$RESULTS_DIR" "$WORK"

# Mirror the package into the copy. --delete keeps it an exact mirror, and
# the excludes keep the copy's own build products and resolution out of it.
rsync -a --delete \
    --exclude .build --exclude .git --exclude .swiftpm --exclude Package.resolved \
    "$PACKAGE_PATH/" "$WORK/"
if [[ -f "$PACKAGE_PATH/Package.resolved" ]]; then
    cp "$PACKAGE_PATH/Package.resolved" "$WORK/Package.resolved"
fi

# The plugin is reachable only from a package that depends on SwiftPropertyLaws.
# Every manifest SwiftPM might pick (Package.swift or a Package@swift-*.swift)
# gets the dependency. `package` is a class instance, so appending works
# whether the manifest declares it with `let` or `var`.
for manifest in "$WORK"/Package.swift "$WORK"/Package@swift-*.swift; do
    [[ -f "$manifest" ]] || continue
    if ! grep -qE '^(let|var) package *= *Package\(' "$manifest"; then
        echo "error: $manifest does not declare a top-level \`package\`; cannot add the dependency"
        exit 1
    fi
    printf '\npackage.dependencies.append(.package(path: "%s"))\n' "$ROOT" >> "$manifest"
done

GENERATED_IN_COPY="$WORK/.propertylaw-pass1.generated.swift"
rm -f "$GENERATED_IN_COPY"

echo "package: $PACKAGE_PATH"
echo "target:  $TARGET"
echo "copy:    $WORK"

LOG="$WORK/.propertylaw-pass1.log"
if ! (cd "$WORK" && swift package --allow-writing-to-package-directory \
        propertylawcheck discover --target "$TARGET" --output "$GENERATED_IN_COPY") \
        > "$LOG" 2>&1; then
    tail -20 "$LOG"
    echo "error: the plugin failed; the full log is $LOG"
    exit 1
fi

# The plugin hands the tool the copy's paths. Point them back at the original
# package, so the results read as if the plugin had run there.
rewrite_paths() {
    sed -e "s#$WORK/#$PACKAGE_PATH/#g" -e "s#$WORK\$#$PACKAGE_PATH#g"
}

rewrite_paths < "$GENERATED_IN_COPY" > "$OUTPUT"

# SwiftPM's build output comes first; the tool's summary starts at its
# "wrote" line, which names the results file rather than the copy's.
awk '/^PropertyLawDiscoveryTool: wrote /{found=1} found' "$LOG" \
    | rewrite_paths \
    | sed -e "1s#^PropertyLawDiscoveryTool: wrote .*#PropertyLawDiscoveryTool: wrote $OUTPUT#" \
    | tee "$SUMMARY"

echo
echo "Generated file:"
echo "  $OUTPUT"
echo "Summary:"
echo "  $SUMMARY"
