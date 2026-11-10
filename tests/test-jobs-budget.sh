#!/bin/sh
# Tests for bin/jobs-budget.
#
# The real executable runs under a PATH that holds ONLY stubs, so a tool that is
# not stubbed is genuinely absent and the fallbacks are exercised for real. The
# Linux probe reads a fake /proc/stat through the documented JOBS_BUDGET_PROC_STAT
# seam; the stub `sleep` swaps in the "after" snapshot, which keeps every case
# instant and deterministic. One live smoke test runs against the real machine.
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
SCRIPT=$ROOT/bin/jobs-budget
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-jobs-budget.XXXXXX")

cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT HUP INT TERM

PASS=0
FAIL=0

ok() {
    printf 'PASS: %s\n' "$1"
    PASS=$((PASS + 1))
}

bad() {
    printf 'FAIL: %s\n' "$1" >&2
    FAIL=$((FAIL + 1))
}

check() { # check <description> <condition-as-shell-word...>
    desc=$1
    shift
    if "$@"; then ok "$desc"; else bad "$desc"; fi
}

# stub_dir <name>: fresh stub directory, printed on stdout.
stub_dir() {
    dir=$TMP_ROOT/$1
    mkdir -p "$dir"
    printf '%s\n' "$dir"
}

# stub <dir> <tool> <shell-body>
stub() {
    printf '#!/bin/sh\n%s\n' "$3" >"$1/$2"
    chmod 755 "$1/$2"
}

# stat_line <user> <nice> <system> <idle> <iowait> <irq> <softirq> <steal>: the
# aggregate cpu line of /proc/stat, first line only (that is all the helper reads).
stat_line() {
    printf 'cpu  %s %s %s %s %s %s %s %s 0 0' "$@"
}

# iostat_body <interval-row>: shell body of a stub iostat that prints the header,
# the since-boot row (always mostly idle) and then <interval-row>.
iostat_body() {
    printf "printf '      cpu    load average\n us sy id   1m   5m   15m\n  2  1 97  1.00 1.00 1.00\n%%s\n' '%s'" "$1"
}

# run <stub-dir> [ENV=value...]: run the real script with only the stubs on PATH.
# RUN_ARGS optionally supplies whitespace-separated script arguments for one run.
# Environment values, including spaces and empty values, remain separate arguments.
# Sets OUT (stdout), ERR (stderr), RC (exit status), then clears RUN_ARGS.
run() {
    stubs=$1
    shift
    RC=0
    # shellcheck disable=SC2086 # RUN_ARGS intentionally supplies separate arguments.
    env -i PATH="$stubs" "$@" /bin/sh "$SCRIPT" ${RUN_ARGS:-} >"$TMP_ROOT/out" 2>"$TMP_ROOT/err" || RC=$?
    OUT=$(cat "$TMP_ROOT/out")
    ERR=$(cat "$TMP_ROOT/err")
    RUN_ARGS=
}

# linux_case <name> <ncpu> <before-line> <after-line> [sleep-status [ENV=value...]]:
# a Linux box whose /proc/stat changes across the helper's sleep. To supply an
# environment override, explicitly supply sleep-status first (normally 0).
linux_case() {
    lc_dir=$(stub_dir "$1")
    printf '%s\n' "$3" >"$lc_dir/stat.before"
    printf '%s\n' "$4" >"$lc_dir/stat.after"
    cp "$lc_dir/stat.before" "$lc_dir/proc-stat"
    stub "$lc_dir" uname 'echo Linux'
    stub "$lc_dir" nproc "echo $2"
    lc_sleep_status=${5:-0}
    if [ "$#" -ge 5 ]; then shift 5; else shift 4; fi
    # Builtins only: the stub PATH holds no cp or cat.
    stub "$lc_dir" sleep "IFS= read -r l <'$lc_dir/stat.after'; printf '%s\\n' \"\$l\" >'$lc_dir/proc-stat'; exit $lc_sleep_status"
    run "$lc_dir" "JOBS_BUDGET_PROC_STAT=$lc_dir/proc-stat" "$@"
}

# darwin_case <name> <ncpu> <iostat-interval-row> [ENV=value...]
darwin_case() {
    dc_dir=$(stub_dir "$1")
    stub "$dc_dir" uname 'echo Darwin'
    stub "$dc_dir" sysctl "echo $2"
    stub "$dc_dir" iostat "$(iostat_body "$3")"
    shift 3
    run "$dc_dir" "$@"
}

is_int_line() {
    case $OUT in
    '' | *[!0-9]*) return 1 ;;
    esac
}

# out_is <n>: exit 0 and stdout is byte-for-byte "<n>\n". $OUT alone cannot show
# that: command substitution strips trailing newlines.
out_is() {
    [ "$OUT" = "$1" ] && [ "$RC" -eq 0 ] &&
        [ "$(wc -c <"$TMP_ROOT/out" | tr -d ' ')" -eq $((${#OUT} + 1)) ] &&
        [ "$(wc -l <"$TMP_ROOT/out" | tr -d ' ')" -eq 1 ]
}

err_has() {
    printf '%s' "$ERR" | grep -Fq -- "$1"
}

BASE=$(stat_line 1000 0 500 8000 0 0 0 0)

# --- Linux probe --------------------------------------------------------------

# Each "after" line adds exactly 1000 ticks to BASE unless noted.
linux_case lin-idle 16 "$BASE" "$(stat_line 1000 0 500 9000 0 0 0 0)"
check "linux: idle machine uses the reserve cap" out_is 14

linux_case lin-half 16 "$BASE" "$(stat_line 1250 0 750 8500 0 0 0 0)"
check "linux: half busy leaves half" out_is 8

linux_case lin-busy 16 "$BASE" "$(stat_line 1500 100 800 8100 0 0 0 0)"
check "linux: 10% idle of 16 is ceil(1.6) = 2" out_is 2

linux_case lin-full 16 "$BASE" "$(stat_line 1900 0 1100 8000 0 0 0 0)"
check "linux: saturated machine yields the floor of 2" out_is 2

linux_case lin-exact 10 "$BASE" "$(stat_line 1250 0 750 8500 0 0 0 0)"
check "linux: an exact division is not rounded up (500/1000 of 10 = 5)" out_is 5

# With reserve 0, the unchanged ceiling boundary remains observable.
# 18 CPUs: 944/1000 idle is 16.992 cores -> 17; 945/1000 is 17.01 -> 18.
linux_case lin-below 18 "$BASE" "$(stat_line 1040 0 516 8944 0 0 0 0)" 0 JOBS_BUDGET_RESERVE=0
check "linux: reserve 0, 94.4% idle of 18 gives 17" out_is 17
linux_case lin-above 18 "$BASE" "$(stat_line 1040 0 515 8945 0 0 0 0)" 0 JOBS_BUDGET_RESERVE=0
check "linux: reserve 0, 94.5% idle of 18 gives 18" out_is 18
linux_case lin-below-default 18 "$BASE" "$(stat_line 1040 0 516 8944 0 0 0 0)"
check "linux: default reserve clamps 94.4% idle to 16" out_is 16
linux_case lin-above-default 18 "$BASE" "$(stat_line 1040 0 515 8945 0 0 0 0)"
check "linux: default reserve clamps 94.5% idle to 16" out_is 16

# iowait is idle for scheduling purposes; steal is not.
linux_case lin-iowait 16 "$BASE" "$(stat_line 1000 0 500 8000 1000 0 0 0)"
check "linux: iowait counts as idle" out_is 14
linux_case lin-steal 16 "$BASE" "$(stat_line 1000 0 500 8000 0 0 0 1000)"
check "linux: steal counts as busy" out_is 2

linux_case lin-one 1 "$BASE" "$(stat_line 1900 0 1100 8000 0 0 0 0)"
check "linux: one CPU: the floor clamps down to ncpu" out_is 1

# --- Darwin probe -------------------------------------------------------------

darwin_case mac-idle 18 ' 1  1 98  9.00 9.00 9.00'
check "darwin: 98% idle uses the reserve cap" out_is 16
darwin_case mac-100 18 ' 0  0 100  9.00 9.00 9.00'
check "darwin: fully idle uses the reserve cap" out_is 16
darwin_case mac-40 18 '35 25 40  9.00 9.00 9.00'
check "darwin: 40% idle of 18 is ceil(7.2) = 8" out_is 8
darwin_case mac-zero 18 '65 35  0  9.00 9.00 9.00'
check "darwin: 0% idle yields the floor of 2" out_is 2
darwin_case mac-exact 10 '25 25 50  9.00 9.00 9.00'
check "darwin: an exact division is not rounded up (50% of 10 = 5)" out_is 5
darwin_case mac-below 18 ' 3  3 94  9.00 9.00 9.00' JOBS_BUDGET_RESERVE=0
check "darwin: reserve 0, 94% idle of 18 gives 17" out_is 17
darwin_case mac-above 18 ' 3  2 95  9.00 9.00 9.00' JOBS_BUDGET_RESERVE=0
check "darwin: reserve 0, 95% idle of 18 gives 18" out_is 18
darwin_case mac-below-default 18 ' 3  3 94  9.00 9.00 9.00'
check "darwin: default reserve clamps 94% idle to 16" out_is 16
darwin_case mac-above-default 18 ' 3  2 95  9.00 9.00 9.00'
check "darwin: default reserve clamps 95% idle to 16" out_is 16

# The load average in that row is 114 on an 18-core machine: it must not be read.
darwin_case mac-overload 18 '65 34  1  114.00 90.00 60.00'
check "darwin: oversubscribed machine yields 2, not a larger number" out_is 2

# Idle right now, while the load average still remembers the caller's own run.
darwin_case mac-own-run 18 ' 1  1 98  57.00 40.00 12.00'
check "darwin: ignores the 1-min load average (own run just ended)" out_is 16

# --- Failure never breaks a run -----------------------------------------------

garbage_dir=$(stub_dir mac-garbage)
stub "$garbage_dir" uname 'echo Darwin'
stub "$garbage_dir" sysctl 'echo 18'
stub "$garbage_dir" iostat 'echo "bananas and other things"'
run "$garbage_dir"
check "garbage iostat output: prints cap, exit 0" out_is 16
check "garbage iostat output: diagnostic on stderr only" err_has 'iostat probe failed'

# A plausible reading of a saturated machine (which would give 2) must be
# ignored when iostat itself reports failure.
failplaus_dir=$(stub_dir mac-fail-plausible)
stub "$failplaus_dir" uname 'echo Darwin'
stub "$failplaus_dir" sysctl 'echo 18'
stub "$failplaus_dir" iostat "$(iostat_body '65 35  0  9.00 9.00 9.00'); exit 1"
run "$failplaus_dir"
check "iostat exits non-zero after plausible rows: distrusted, prints cap" out_is 16

absent_dir=$(stub_dir mac-iostat-absent)
stub "$absent_dir" uname 'echo Darwin'
stub "$absent_dir" sysctl 'echo 18'
run "$absent_dir"
check "iostat missing: prints cap, exit 0" out_is 16

one_dir=$(stub_dir mac-one-row)
stub "$one_dir" uname 'echo Darwin'
stub "$one_dir" sysctl 'echo 18'
stub "$one_dir" iostat "printf ' us sy id\n 65 35 0\n'"
run "$one_dir"
check "iostat with a single data row (no interval): prints cap" out_is 16

three_dir=$(stub_dir mac-three-rows)
stub "$three_dir" uname 'echo Darwin'
stub "$three_dir" sysctl 'echo 18'
stub "$three_dir" iostat "printf ' us sy id\n 2 1 97\n 2 1 97\n 65 35 0\n'"
run "$three_dir"
check "iostat with three data rows: prints cap" out_is 16

short_dir=$(stub_dir mac-short)
stub "$short_dir" uname 'echo Darwin'
stub "$short_dir" sysctl 'echo 18'
stub "$short_dir" iostat "printf ' us sy id\n 2 1 97\n 1 1\n'"
run "$short_dir"
check "iostat row with too few columns: prints cap" out_is 16

darwin_case mac-range 18 ' 1  1 250  9.00 9.00 9.00'
check "idle percent above 100: prints cap" out_is 16
darwin_case mac-sum 18 '10 10  5  9.00 9.00 9.00'
check "us+sy+id far from 100: prints cap" out_is 16
# iostat rounds each column on its own, so the sum may be 99..101.
darwin_case mac-sum-99 10 '30 30 39  9.00 9.00 9.00'
check "us+sy+id = 99 is accepted (39% of 10 -> 4)" out_is 4
darwin_case mac-sum-101 10 '30 30 41  9.00 9.00 9.00'
check "us+sy+id = 101 is accepted (41% of 10 -> 5)" out_is 5
darwin_case mac-sum-98 18 '30 30 38  9.00 9.00 9.00'
check "us+sy+id = 98 is rejected: prints cap" out_is 16
darwin_case mac-sum-102 18 '30 30 42  9.00 9.00 9.00'
check "us+sy+id = 102 is rejected: prints cap" out_is 16
# The since-boot row is validated like the interval row: a garbage first row with
# a plausible (saturated, would give 2) second row must not be trusted.
garbage1_dir=$(stub_dir mac-garbage-first-row)
stub "$garbage1_dir" uname 'echo Darwin'
stub "$garbage1_dir" sysctl 'echo 18'
stub "$garbage1_dir" iostat "printf ' us sy id\n 200 300 999\n 65 35 0\n'"
run "$garbage1_dir"
check "garbage first (since-boot) row with a valid busy interval: prints cap" out_is 16
check "garbage first row: diagnostic on stderr" err_has 'iostat probe failed'
garbage1b_dir=$(stub_dir mac-first-row-sum)
stub "$garbage1b_dir" uname 'echo Darwin'
stub "$garbage1b_dir" sysctl 'echo 18'
stub "$garbage1b_dir" iostat "printf ' us sy id\n 10 10 5\n 65 35 0\n'"
run "$garbage1b_dir"
check "first row with an inconsistent sum, busy interval: prints cap" out_is 16

darwin_case mac-negative 18 ' 1  1 -5  9.00 9.00 9.00'
check "non-numeric idle column: prints cap" out_is 16

# The probe is run once, with the documented arguments, in the C locale.
argv_dir=$(stub_dir mac-argv)
stub "$argv_dir" uname 'echo Darwin'
stub "$argv_dir" sysctl 'echo 18'
stub "$argv_dir" iostat "echo \"\$*\" >'$argv_dir/argv'; echo \"\$LC_ALL\" >'$argv_dir/lc'; $(iostat_body ' 1  1 98  9.00 9.00 9.00')"
run "$argv_dir" LC_ALL=de_DE.UTF-8
check "iostat is called as 'iostat -n 0 -c 2 -w 1'" test "$(cat "$argv_dir/argv")" = '-n 0 -c 2 -w 1'
check "probe runs with LC_ALL=C whatever the caller exported" test "$(cat "$argv_dir/lc")" = C

linux_case lin-no-stat 16 "$BASE" "$BASE"
rm -f "$TMP_ROOT/lin-no-stat/proc-stat"
run "$TMP_ROOT/lin-no-stat" "JOBS_BUDGET_PROC_STAT=$TMP_ROOT/lin-no-stat/proc-stat"
check "linux: unreadable /proc/stat prints cap" out_is 14

linux_case lin-zero-delta 16 "$BASE" "$BASE"
check "linux: no ticks elapsed prints cap" out_is 14

linux_case lin-reset 16 "$BASE" "$(stat_line 10 0 5 80 0 0 0 0)"
check "linux: counters that went backwards print cap" out_is 14

# Total grows by 999 and the "idle" share looks tiny, but user went down by 1:
# trusting it would give 2, so a single decreasing counter must reject the sample.
linux_case lin-one-down 16 "$BASE" "$(stat_line 999 0 1400 8100 0 0 0 0)"
check "linux: one counter decreasing rejects the sample" out_is 14

linux_case lin-garbage 16 "$BASE" 'cpu  a b c d e f g h'
check "linux: non-numeric /proc/stat prints cap" out_is 14

linux_case lin-missing 16 "$BASE" 'cpu  1900 0 1100 8000 0 0 0'
check "linux: missing steal field prints cap" out_is 14

linux_case lin-label 16 "$BASE" 'intr 1 2 3 4 5 6 7 8 9 10'
check "linux: wrong first line prints cap" out_is 14

# The "after" snapshot says saturated (would be 2); the failed sleep voids it.
linux_case lin-sleep-fails 16 "$BASE" "$(stat_line 1900 0 1100 8000 0 0 0 0)" 1
check "linux: failing sleep is distrusted even with a plausible snapshot" out_is 14

# --- Digit garbage must not abort the shell -----------------------------------
# `$((08))` is an octal error in the shell and would end the script before it
# prints anything, so leading zeros and oversized integers are normalised or
# rejected before any arithmetic.

LONG=123456789012345678901234567890

darwin_case mac-zero-fields 18 '03 02 095  9.00 9.00 9.00'
check "iostat columns with leading zeros: 095 is 95%, clamped to cap 16" out_is 16
darwin_case mac-zero-08 10 '00 50 050  9.00 9.00 9.00'
check "iostat columns 08/09-style octal traps: 050 is 50% -> 5" out_is 5
darwin_case mac-long-field 18 "1 1 $LONG"
check "iostat column of 30 digits: prints cap, exit 0" out_is 16

lz_dir=$(stub_dir ncpu-leading-zero)
stub "$lz_dir" uname 'echo Darwin'
stub "$lz_dir" sysctl 'echo 010'
stub "$lz_dir" iostat "$(iostat_body ' 0  0 100  9.00 9.00 9.00')"
run "$lz_dir"
check "ncpu 010 means ten CPUs and cap 9, not octal eight" out_is 9

lz8_dir=$(stub_dir ncpu-08)
stub "$lz8_dir" uname 'echo Darwin'
stub "$lz8_dir" sysctl 'echo 08'
stub "$lz8_dir" iostat "$(iostat_body ' 0  0 100  9.00 9.00 9.00')"
run "$lz8_dir"
check "ncpu 08 means eight CPUs and cap 7, not an octal error" out_is 7

longcpu_dir=$(stub_dir ncpu-long)
stub "$longcpu_dir" uname 'echo Linux'
stub "$longcpu_dir" nproc "echo $LONG"
stub "$longcpu_dir" getconf 'echo 6'
run "$longcpu_dir"
check "ncpu of 30 digits is refused, next source gives six CPUs and cap 5" out_is 5

hugecpu_dir=$(stub_dir ncpu-huge)
stub "$hugecpu_dir" uname 'echo Plan9'
stub "$hugecpu_dir" nproc 'echo 1000000'
run "$hugecpu_dir"
check "implausible ncpu 1000000 is refused: assumes four CPUs and prints cap 3" out_is 3

linux_case lin-zero-counters 16 "$(stat_line 01000 000 0500 08000 0 0 0 0)" "$(stat_line 01250 00 0750 08500 00 0 0 0)"
check "linux: counters with leading zeros: half idle -> 8" out_is 8

linux_case lin-long-counters 16 "$BASE" "cpu  $LONG 0 0 $LONG 0 0 0 0"
check "linux: 30-digit counters: prints cap, exit 0" out_is 14

linux_case lin-huge-delta 16 "$BASE" "$(stat_line 1000 0 500 8000000000 0 0 0 0)"
check "linux: more ticks than one second can hold: prints cap" out_is 14

# GNU nproc lets OMP_THREAD_LIMIT / OMP_NUM_THREADS cap or replace its answer. The
# stub reproduces that, so an exported value must not reach it through the helper.
omp_dir=$(stub_dir omp)
printf '%s\n' "$BASE" >"$omp_dir/proc-stat"
printf '%s\n' "$(stat_line 1000 0 500 9000 0 0 0 0)" >"$omp_dir/stat.after"
stub "$omp_dir" uname 'echo Linux'
# shellcheck disable=SC2016 # the stub body must expand at ITS run time
stub "$omp_dir" nproc 'echo "${OMP_THREAD_LIMIT:-${OMP_NUM_THREADS:-16}}"'
stub "$omp_dir" sleep "IFS= read -r l <'$omp_dir/stat.after'; printf '%s\\n' \"\$l\" >'$omp_dir/proc-stat'"
run "$omp_dir" "JOBS_BUDGET_PROC_STAT=$omp_dir/proc-stat" OMP_THREAD_LIMIT=1
check "OMP_THREAD_LIMIT=1 does not alter the 16-core host cap of 14" out_is 14
printf '%s\n' "$BASE" >"$omp_dir/proc-stat"
run "$omp_dir" "JOBS_BUDGET_PROC_STAT=$omp_dir/proc-stat" OMP_NUM_THREADS=64
check "OMP_NUM_THREADS=64 does not inflate the CPU count" out_is 14

os_dir=$(stub_dir unknown-os)
stub "$os_dir" uname 'echo Plan9'
stub "$os_dir" nproc 'echo 12'
run "$os_dir"
check "unknown OS: prints cap, exit 0" out_is 11
check "unknown OS: diagnostic on stderr" err_has 'unsupported OS'

nouname_dir=$(stub_dir no-uname)
stub "$nouname_dir" getconf 'echo 6'
run "$nouname_dir"
check "no uname, getconf answers six CPUs: prints cap 5" out_is 5

nocpu_dir=$(stub_dir no-ncpu)
stub "$nocpu_dir" uname 'echo Plan9'
stub "$nocpu_dir" nproc 'exit 1'
stub "$nocpu_dir" getconf 'echo garbage'
run "$nocpu_dir"
check "CPU count unknown everywhere: prints default cap 3, exit 0" out_is 3

# Unknown CPU count assumes four CPUs: print cap 3 at once, do not sample. The
# saturated reading would give 2 if the sampler ran, and leaves a marker if it does.
nocpu_mac_dir=$(stub_dir no-ncpu-mac)
stub "$nocpu_mac_dir" uname 'echo Darwin'
stub "$nocpu_mac_dir" sysctl 'exit 1'
stub "$nocpu_mac_dir" iostat ": >'$nocpu_mac_dir/iostat-ran'; $(iostat_body '65 35  0  9.00 9.00 9.00')"
run "$nocpu_mac_dir"
check "CPU count unknown, saturated probe: prints cap 3, not 2" out_is 3
check "CPU count unknown: the sampler is not even started" test ! -e "$nocpu_mac_dir/iostat-ran"
check "CPU count unknown: diagnostic on stderr" err_has 'cannot determine CPU count'

nocpu_bad_dir=$(stub_dir no-ncpu-bad-probe)
stub "$nocpu_bad_dir" uname 'echo Darwin'
stub "$nocpu_bad_dir" sysctl 'exit 1'
stub "$nocpu_bad_dir" iostat 'exit 1'
run "$nocpu_bad_dir"
check "CPU count unknown and probe failing: prints cap 3, exit 0" out_is 3

nproc_zero_dir=$(stub_dir nproc-zero)
stub "$nproc_zero_dir" uname 'echo Plan9'
stub "$nproc_zero_dir" nproc 'echo 0'
stub "$nproc_zero_dir" getconf 'echo 8'
run "$nproc_zero_dir"
check "nproc reports 0: getconf gives eight CPUs and cap 7" out_is 7

# --- Output shape and portability ---------------------------------------------

darwin_case shape 18 '35 25 40  9.00 9.00 9.00'
check "stdout is exactly one integer line" is_int_line
check "stdout carries no diagnostics on the success path" test -z "$ERR"

check "shebang is #!/bin/sh" test "$(head -n 1 "$SCRIPT")" = '#!/bin/sh'
check "script is executable" test -x "$SCRIPT"

if command -v dash >/dev/null 2>&1; then
    dash_dir=$(stub_dir dash-run)
    stub "$dash_dir" uname 'echo Darwin'
    stub "$dash_dir" sysctl 'echo 18'
    stub "$dash_dir" iostat "$(iostat_body '30 30 40  9.00 9.00 9.00')"
    dash_out=$(env -i PATH="$dash_dir" "$(command -v dash)" "$SCRIPT")
    check "dash runs the script identically" test "$dash_out" = 8
else
    printf 'SKIP: dash not installed\n'
fi

# --- Reserve contract ---------------------------------------------------------

# Literal input/output pairs from the frozen spec, not from jobs-budget code.
while read -r table_ncpu table_cap; do
    darwin_case "reserve-table-$table_ncpu" "$table_ncpu" ' 0 0 100'
    check "reserve table: $table_ncpu CPUs -> $table_cap jobs" out_is "$table_cap"
    check "reserve table: $table_ncpu CPUs produce no warning" test -z "$ERR"
done <<EOF
1 1
2 2
3 2
4 3
6 5
7 6
8 7
10 9
12 11
15 14
16 14
18 16
24 21
31 28
32 28
64 60
65535 65531
EOF

while read -r reserve_value reserve_cap; do
    darwin_case "reserve-valid-$reserve_value" 18 ' 0 0 100' "JOBS_BUDGET_RESERVE=$reserve_value"
    check "reserve override $reserve_value -> $reserve_cap jobs" out_is "$reserve_cap"
    check "valid reserve $reserve_value produces no warning" test -z "$ERR"
done <<EOF
0 18
1 17
4 14
007 11
17 1
18 1
99 1
00018 1
999999999999999 1
9999999999999999 1
12345678901234567890 1
9999999999999999999999999999999999999999 1
0000000000000000000000000000000000000000 18
0000000000000000000000000000000000000007 11
0000999999999999999999999999999999999999 1
EOF

for reserve_value in abc -1 1.5 2x 'two words' +2 ' 2' '2 '; do
    darwin_case "reserve-invalid-$PASS" 18 ' 0 0 100' "JOBS_BUDGET_RESERVE=$reserve_value"
    check "invalid reserve '$reserve_value' uses default cap 16" out_is 16
    check "invalid reserve '$reserve_value' names the override on stderr" err_has JOBS_BUDGET_RESERVE
    check "invalid reserve '$reserve_value' produces one warning" test "$(wc -l <"$TMP_ROOT/err" | tr -d ' ')" -eq 1
done

darwin_case reserve-empty 18 ' 0 0 100' JOBS_BUDGET_RESERVE=
check "empty reserve uses default cap 16" out_is 16
check "empty reserve produces no warning" test -z "$ERR"

darwin_case reserve-busy 18 '35 25 40' JOBS_BUDGET_RESERVE=4
check "reserve is not subtracted again from the sampled idle share" out_is 8
darwin_case reserve-floor 18 '65 35 0' JOBS_BUDGET_RESERVE=18
check "reserve at ncpu clamps a saturated machine's floor to 1" out_is 1
darwin_case reserve-two-cpus 2 '65 35 0' JOBS_BUDGET_RESERVE=1
check "two CPUs with reserve 1 use floor 1" out_is 1
darwin_case reserve-three-cpus 3 '65 35 0'
check "three CPUs with the default reserve use floor 2" out_is 2
darwin_case reserve-one-cpu 1 '65 35 0'
check "one CPU with the default reserve uses floor 1" out_is 1
linux_case lin-reserve-floor 16 "$BASE" "$(stat_line 1900 0 1100 8000 0 0 0 0)" 0 JOBS_BUDGET_RESERVE=16
check "linux: reserve at ncpu clamps a saturated machine's floor to 1" out_is 1

# The override also constrains fallback output, not just successful samples.
run "$garbage_dir" JOBS_BUDGET_RESERVE=4
check "failed Darwin probe honours reserve 4 on 18 CPUs" out_is 14
check "failed Darwin probe retains its diagnostic" err_has 'iostat probe failed'
run "$os_dir" JOBS_BUDGET_RESERVE=99
check "unsupported OS honours an override larger than ncpu" out_is 1
check "unsupported OS retains its diagnostic" err_has 'unsupported OS'
run "$TMP_ROOT/lin-no-stat" "JOBS_BUDGET_PROC_STAT=$TMP_ROOT/lin-no-stat/proc-stat" JOBS_BUDGET_RESERVE=16
check "failed Linux probe honours an override equal to ncpu" out_is 1
check "failed Linux probe retains its diagnostic" err_has '/proc/stat probe failed'

while read -r reserve_value reserve_cap; do
    run "$nocpu_mac_dir" "JOBS_BUDGET_RESERVE=$reserve_value"
    check "unknown CPU count with reserve $reserve_value -> $reserve_cap jobs" out_is "$reserve_cap"
    check "unknown CPU count retains its diagnostic with an override" err_has 'cannot determine CPU count'
    check "unknown CPU count with an override never starts iostat" test ! -e "$nocpu_mac_dir/iostat-ran"
done <<EOF
0 4
1 3
4 1
99 1
12345678901234567890 1
EOF
run "$nocpu_mac_dir" JOBS_BUDGET_RESERVE=
check "unknown CPU count with an empty reserve uses default cap 3" out_is 3
check "empty reserve adds no warning to the unknown-count diagnostic" test "$(wc -l <"$TMP_ROOT/err" | tr -d ' ')" -eq 1

# --- --max never samples -------------------------------------------------------

max_mac_dir=$(stub_dir max-darwin)
stub "$max_mac_dir" uname 'echo Darwin'
stub "$max_mac_dir" sysctl 'echo 18'
stub "$max_mac_dir" iostat ": >'$max_mac_dir/iostat-ran'; $(iostat_body '35 25 40')"
RUN_ARGS=--max
run "$max_mac_dir"
check "--max on Darwin prints the default cap, not sampled idle jobs" out_is 16
check "--max on Darwin never starts iostat" test ! -e "$max_mac_dir/iostat-ran"
check "--max on Darwin produces no warning" test -z "$ERR"
RUN_ARGS=--max
run "$max_mac_dir" JOBS_BUDGET_RESERVE=0
check "--max with reserve 0 prints ncpu" out_is 18
check "--max with reserve 0 never starts iostat" test ! -e "$max_mac_dir/iostat-ran"
RUN_ARGS=--max
run "$max_mac_dir" JOBS_BUDGET_RESERVE=12345678901234567890
check "--max with a huge valid reserve prints 1" out_is 1
check "--max with a huge valid reserve produces no warning" test -z "$ERR"
check "--max with a huge valid reserve never starts iostat" test ! -e "$max_mac_dir/iostat-ran"
RUN_ARGS=--max
run "$max_mac_dir" JOBS_BUDGET_RESERVE=abc
check "--max with an invalid reserve uses default cap 16" out_is 16
check "--max with an invalid reserve warns on stderr" err_has JOBS_BUDGET_RESERVE
check "--max with an invalid reserve produces one warning" test "$(wc -l <"$TMP_ROOT/err" | tr -d ' ')" -eq 1
check "--max with an invalid reserve never starts iostat" test ! -e "$max_mac_dir/iostat-ran"

max_linux_dir=$(stub_dir max-linux)
printf '%s\n' "$BASE" >"$max_linux_dir/proc-stat"
stub "$max_linux_dir" uname 'echo Linux'
stub "$max_linux_dir" nproc 'echo 16'
stub "$max_linux_dir" sleep ": >'$max_linux_dir/sleep-ran'; exit 0"
RUN_ARGS=--max
run "$max_linux_dir" "JOBS_BUDGET_PROC_STAT=$max_linux_dir/proc-stat"
check "--max on Linux prints default cap 14" out_is 14
check "--max on Linux never starts sleep" test ! -e "$max_linux_dir/sleep-ran"
check "--max on Linux produces no warning" test -z "$ERR"
RUN_ARGS=--max
run "$max_linux_dir" "JOBS_BUDGET_PROC_STAT=$max_linux_dir/proc-stat" JOBS_BUDGET_RESERVE=0
check "--max on Linux with reserve 0 prints 16" out_is 16
check "--max on Linux with reserve 0 never starts sleep" test ! -e "$max_linux_dir/sleep-ran"
RUN_ARGS=--max
run "$max_linux_dir" "JOBS_BUDGET_PROC_STAT=$max_linux_dir/proc-stat" JOBS_BUDGET_RESERVE=16
check "--max on Linux with reserve at ncpu prints 1" out_is 1
check "--max on Linux with reserve at ncpu never starts sleep" test ! -e "$max_linux_dir/sleep-ran"

RUN_ARGS=--max
run "$os_dir"
check "--max on an unsupported OS prints cap 11" out_is 11
RUN_ARGS=--max
run "$nocpu_mac_dir"
check "--max with unknown CPU count prints default cap 3" out_is 3
check "--max with unknown CPU count keeps the count diagnostic" err_has 'cannot determine CPU count'
check "--max with unknown CPU count never starts iostat" test ! -e "$nocpu_mac_dir/iostat-ran"
while read -r reserve_value reserve_cap; do
    RUN_ARGS=--max
    run "$nocpu_mac_dir" "JOBS_BUDGET_RESERVE=$reserve_value"
    check "--max with unknown CPU count and reserve $reserve_value -> $reserve_cap" out_is "$reserve_cap"
    check "--max with unknown CPU count and override never starts iostat" test ! -e "$nocpu_mac_dir/iostat-ran"
done <<EOF
0 4
4 1
12345678901234567890 1
EOF

# Unknown arguments warn without breaking output or bypassing normal sampling.
for unknown_arg in --bogus nonsense -1; do
    RUN_ARGS=$unknown_arg
    run "$max_mac_dir"
    check "unknown argument $unknown_arg keeps normal sampled output" out_is 8
    check "unknown argument $unknown_arg is named on stderr" err_has "$unknown_arg"
    check "unknown argument $unknown_arg produces one warning" test "$(wc -l <"$TMP_ROOT/err" | tr -d ' ')" -eq 1
    check "unknown argument $unknown_arg does not skip sampling" test -e "$max_mac_dir/iostat-ran"
    rm -f "$max_mac_dir/iostat-ran"
done
RUN_ARGS='--max --bogus'
run "$max_mac_dir"
check "--max plus an unknown argument prints cap 16" out_is 16
check "--max plus an unknown argument warns" err_has --bogus
check "--max plus an unknown argument produces one warning" test "$(wc -l <"$TMP_ROOT/err" | tr -d ' ')" -eq 1
check "--max plus an unknown argument never starts iostat" test ! -e "$max_mac_dir/iostat-ran"
RUN_ARGS='--alpha --beta'
run "$max_mac_dir"
check "two unknown arguments retain sampled output" out_is 8
check "the first unknown argument is named on stderr" err_has --alpha
check "the second unknown argument is named on stderr" err_has --beta
check "two unknown arguments produce two warnings" test "$(wc -l <"$TMP_ROOT/err" | tr -d ' ')" -eq 2
rm -f "$max_mac_dir/iostat-ran"
RUN_ARGS='--max --max'
run "$max_mac_dir"
check "repeated --max still prints cap 16" out_is 16
check "repeated --max produces no warning" test -z "$ERR"
check "repeated --max never starts iostat" test ! -e "$max_mac_dir/iostat-ran"

# --- Live smoke ---------------------------------------------------------------

live=$(env -i PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}" /bin/sh "$SCRIPT")
live_ncpu=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
# Independent computation from the frozen reserve rule, never from --max.
if [ "$live_ncpu" -le 2 ]; then
    live_reserve=0
else
    live_reserve=$((live_ncpu / 8))
    [ "$live_reserve" -ge 1 ] || live_reserve=1
    [ "$live_reserve" -le 4 ] || live_reserve=4
fi
live_cap=$((live_ncpu - live_reserve))
[ "$live_cap" -ge 1 ] || live_cap=1
live_min=2
[ "$live_cap" -ge "$live_min" ] || live_min=$live_cap
live_in_range() {
    case $live in
    '' | *[!0-9]*) return 1 ;;
    esac
    [ "$live" -ge "$live_min" ] && [ "$live" -le "$live_cap" ]
}
check "live: integer in [$live_min, $live_cap] (got $live)" live_in_range

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
