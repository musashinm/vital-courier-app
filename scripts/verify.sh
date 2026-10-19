#!/bin/sh
# Runs every local check in order and prints each step's time. Stops at the first failure
# and exits with that step's exit code.
# VERIFY_DESTINATION: simulator destination (default: iPhone 18 Pro, iOS 27.0).
# VERIFY_BASE_REF: ref the migrations are compared with (default: origin/main).
set -eu
if [ "$#" -ne 0 ]; then
    echo "usage: scripts/verify.sh (no arguments; set VERIFY_DESTINATION or VERIFY_BASE_REF instead)" >&2
    exit 64
fi
cd "$(dirname "$0")/.."
destination=${VERIFY_DESTINATION:-platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0}
base_ref=${VERIFY_BASE_REF:-origin/main}
derived_data_path=build/DerivedData
step_count=6
step_number=0
run_started_at=$(date +%s)

# Runs one step: run_step <name> <command> [args...]
run_step() {
    step_name=$1
    shift
    step_number=$((step_number + 1))
    echo "==> $step_number/$step_count $step_name"
    step_started_at=$(date +%s)
    if "$@"; then
        echo "<== $step_number/$step_count $step_name passed in $(($(date +%s) - step_started_at))s"
    else
        step_status=$?
        echo "<== $step_number/$step_count $step_name FAILED after $(($(date +%s) - step_started_at))s" >&2
        exit "$step_status"
    fi
}

run_step "package tests" swift test --package-path VitalCourierCore
run_step "generate project" scripts/generate-project.sh
run_step "simulator build" xcodebuild -project VitalCourier.xcodeproj -scheme VitalCourier \
    -destination "$destination" -derivedDataPath "$derived_data_path" -quiet build
run_step "app tests" xcodebuild test -project VitalCourier.xcodeproj -scheme VitalCourier \
    -destination "$destination" -derivedDataPath "$derived_data_path" -only-testing:VitalCourierTests -quiet
run_step "translations" scripts/check-translations.sh "$derived_data_path"
run_step "migrations" scripts/check-migrations.sh "$base_ref"

echo "All $step_count steps passed in $(($(date +%s) - run_started_at))s."
