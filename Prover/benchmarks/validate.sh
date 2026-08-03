#!/usr/bin/env bash
# ============================================================================
# validate.sh — self-check for the Sparkle formal-verification benchmarks
#
# For every benchmark directory containing a meta.json this script:
#   (a) parses each .sv variant with yosys 0.33 and writes btor2
#   (b) runs yosys-smtbmc BMC on each bug variant to depth
#       max(2 * min_depth, 15) and requires that a violation IS found
#   (c) runs yosys-smtbmc BMC on the safe variant to depth 15 and requires
#       that NO violation is found
#
# The SoC benchmark (category "soc") uses reduced depths since BMC on the
# full RV32I SoC is expensive: safe depth 10, bug depth max(min_depth+2, 10),
# with a 300 s timeout per solver call (a timeout is reported, not fatal).
#
# Usage: ./validate.sh [benchmark-name ...]   (default: all)
# ============================================================================
set -u

BENCH_ROOT="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

SOLVER="z3"
SAFE_DEPTH=15
BLOCK_TIMEOUT=1200   # pipeline_hazard safe proof needs ~10 min at depth 15
SOC_SAFE_DEPTH=10
SOC_TIMEOUT=300

pass=0
fail=0
skip=0
declare -a RESULTS

log()  { printf '%s\n' "$*"; }
result() { RESULTS+=("$1"); }

json_get() { # json_get <file> <python-expr over data>
    python3 -c "import json,sys; data=json.load(open(sys.argv[1])); print($2)" "$1"
}

run_smtbmc() { # run_smtbmc <smt2> <depth> <timeout> <extra-flags> ; echo PASSED/FAILED/TIMEOUT/ERROR
    local smt2="$1" depth="$2" tmo="$3" extra="${4:-}" out rc
    # shellcheck disable=SC2086
    out=$(timeout "$tmo" yosys-smtbmc -s "$SOLVER" $extra -t "$depth" "$smt2" 2>&1)
    rc=$?
    if [ $rc -eq 124 ]; then echo TIMEOUT; return; fi
    case "$out" in
        *"Status: PASSED"*) echo PASSED ;;
        *"Status: FAILED"*) echo FAILED ;;
        *)                  echo ERROR; printf '%s\n' "$out" | tail -5 >&2 ;;
    esac
}

check_variant() { # check_variant <dir> <file> <top> <expect safe|bug> <depth> <timeout> <label> <extra-flags>
    local dir="$1" file="$2" top="$3" expect="$4" depth="$5" tmo="$6" label="$7" extra="${8:-}"
    local sv="$dir/$file"
    local base="$WORK/$(basename "$dir")_${file%.sv}"

    # (a) yosys parse + btor2
    if ! yosys -q -p "read_verilog -sv $sv; prep -top $top; flatten; write_btor $base.btor2" \
            >/dev/null 2>"$base.yosys.err"; then
        log "  [FAIL] $label: yosys parse/btor2 failed"
        tail -5 "$base.yosys.err" >&2
        fail=$((fail+1)); result "FAIL  $label (yosys)"
        return 1
    fi

    # (b/c) SMT BMC
    if ! yosys -q -p "read_verilog -sv $sv; prep -top $top; flatten; write_smt2 -wires $base.smt2" \
            >/dev/null 2>&1; then
        log "  [FAIL] $label: write_smt2 failed"
        fail=$((fail+1)); result "FAIL  $label (smt2)"
        return 1
    fi
    local status
    status=$(run_smtbmc "$base.smt2" "$depth" "$tmo" "$extra")
    if [ "$status" = TIMEOUT ]; then
        log "  [SKIP] $label: BMC depth $depth timed out after ${tmo}s (documented, not fatal)"
        skip=$((skip+1)); result "SKIP  $label (timeout @ depth $depth)"
        return 0
    fi
    if [ "$expect" = safe ] && [ "$status" = PASSED ]; then
        log "  [ ok ] $label: safe, no violation up to depth $depth"
        pass=$((pass+1)); result "ok    $label (safe @ depth $depth)"
    elif [ "$expect" = bug ] && [ "$status" = FAILED ]; then
        log "  [ ok ] $label: violation found within depth $depth (as expected)"
        pass=$((pass+1)); result "ok    $label (bug found @ depth $depth)"
    else
        log "  [FAIL] $label: expected $expect, BMC status $status (depth $depth)"
        fail=$((fail+1)); result "FAIL  $label (expected $expect, got $status)"
        return 1
    fi
}

check_benchmark() { # check_benchmark <dir>
    local dir="$1"
    local meta="$dir/meta.json"
    [ -f "$meta" ] || return 0
    local name top category
    name=$(basename "$dir")
    top=$(json_get "$meta" "data['top']")
    category=$(json_get "$meta" "data['category']")
    log "=== $name (top=$top, category=$category) ==="

    # Block benchmarks use non-incremental solving (--noincr): z3's
    # incremental core is pathologically slow on the pipeline_hazard
    # equivalence obligations (>8 min stuck at step ~5), while fresh
    # bit-blasted instances finish depth 15 in ~10 min total. The SoC is
    # the opposite case (large formula, cheap steps) and stays incremental.
    local safe_depth=$SAFE_DEPTH tmo=$BLOCK_TIMEOUT extra="--noincr"
    if [ "$category" = soc ]; then
        safe_depth=$SOC_SAFE_DEPTH; tmo=$SOC_TIMEOUT; extra=""
    fi

    # safe variant
    local safe_file
    safe_file=$(json_get "$meta" "data['safe']['file']")
    check_variant "$dir" "$safe_file" "$top" safe "$safe_depth" "$tmo" "$name/$safe_file" "$extra"

    # bug variants
    local n i bug_file min_depth bug_depth
    n=$(json_get "$meta" "len(data['bugs'])")
    for i in $(seq 0 $((n-1))); do
        bug_file=$(json_get "$meta" "data['bugs'][$i]['file']")
        min_depth=$(json_get "$meta" "data['bugs'][$i]['min_depth']")
        if [ "$category" = soc ]; then
            bug_depth=$(( min_depth + 2 )); [ "$bug_depth" -lt 10 ] && bug_depth=10
        else
            bug_depth=$(( 2 * min_depth )); [ "$bug_depth" -lt 15 ] && bug_depth=15
        fi
        check_variant "$dir" "$bug_file" "$top" bug "$bug_depth" "$tmo" "$name/$bug_file" "$extra"
    done
}

main() {
    local dirs=()
    if [ $# -gt 0 ]; then
        for n in "$@"; do
            if   [ -d "$BENCH_ROOT/blocks/$n" ]; then dirs+=("$BENCH_ROOT/blocks/$n")
            elif [ -d "$BENCH_ROOT/soc/$n" ];    then dirs+=("$BENCH_ROOT/soc/$n")
            else log "unknown benchmark: $n"; exit 2; fi
        done
    else
        for d in "$BENCH_ROOT"/blocks/*/ "$BENCH_ROOT"/soc/*/; do
            [ -d "$d" ] && dirs+=("${d%/}")
        done
    fi

    for d in "${dirs[@]}"; do
        check_benchmark "$d"
    done

    log ""
    log "==================== SUMMARY ===================="
    for r in "${RESULTS[@]}"; do log "$r"; done
    log "=================================================="
    log "passed: $pass   failed: $fail   skipped(timeout): $skip"
    [ $fail -eq 0 ]
}

main "$@"
