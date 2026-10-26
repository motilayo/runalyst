#!/usr/bin/env bash
set -euo pipefail

# Configuration
CORE_DIR="RunalystCore/Sources"
TEST_DIR="RunalystCore/Tests"
MAX_LOC=500
ASSAY_PASSED=true

echo "⚖️  [THE ASSAY] Testing Runalyst specimen purity and mass..."
echo "------------------------------------------------------------"

# 1. Purity Audit (Framework Air-Gap)
echo "🔍 Checking Directory Air-Gap Purity..."
if grep -rE "(HealthKit|SwiftData|CoreML|SwiftUI|FoundationModels)" "$CORE_DIR" --include=\*.swift; then
    echo "🚨 [IMPURE] Illegal iOS framework detected in RunalystCore!"
    ASSAY_PASSED=false
else
    echo "✅ [PURE] Zero Apple infrastructure frameworks found in Core."
fi

# 1b. Determinism Audit (Zero Wall-Clock Date() & Calendar.current)
echo "⏱️  Checking Determinism Air-Gap (Zero Date() or Calendar.current)..."
if grep -rE "Date\(\)|Calendar\.current" "$CORE_DIR" --include=\*.swift; then
    echo "🚨 [IMPURE] Wall-clock time or dynamic Calendar detected in RunalystCore!"
    ASSAY_PASSED=false
else
    echo "✅ [PURE] Zero wall-clock time or dynamic Calendar found in Core."
fi

# 2. Syntax & Lint Audit
echo "🧹 Running strict SwiftLint..."
if swiftlint --strict "$CORE_DIR"; then
    echo "✅ [CLEAN] Zero lint violations."
else
    echo "🚨 [SLAG] SwiftLint violations detected."
    ASSAY_PASSED=false
fi

# 3. Mass Audit (< 500 LOC)
echo "------------------------------------------------------------"
printf "%-35s | %-12s | %-10s\n" "CORE INGOT" "MASS (LOC)" "STATUS"
echo "------------------------------------------------------------"

while IFS= read -r file; do
    loc=$(wc -l < "$file" | tr -d ' ')
    filename=$(basename "$file")
    
    if [ "$loc" -gt "$MAX_LOC" ]; then
        status="⚠️ SLAG"
        ASSAY_PASSED=false
    else
        status="✅ PURE"
    fi
    printf "%-35s | %-12s | %-10s\n" "$filename" "${loc}/${MAX_LOC}" "$status"
done < <(find "$CORE_DIR" -name "*.swift")

echo "------------------------------------------------------------"

# 4. Crucible Burn (Sub-5ms Testing)
echo "🔥 [CRUCIBLE BURN] Subjecting RunalystCore to extreme heat..."
if time swift test --package-path RunalystCore --quiet; then
    echo "✅ [SURVIVED] Crucible verification passed."
else
    echo "🚨 [FRACTURE] Core modules failed Crucible invariant tests."
    ASSAY_PASSED=false
fi

echo "------------------------------------------------------------"

# Final Verdict
if [ "$ASSAY_PASSED" = true ]; then
    echo "👑 [HALLMARK GRANTED] Specimen passed The Assay. Ready to strike Touchstone."
    exit 0
else
    echo "❌ [FOOL'S GOLD] Specimen failed The Assay. Recast required."
    exit 1
fi