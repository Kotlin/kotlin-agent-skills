#!/usr/bin/env bash
# Phase 6 build checks for a Swift Export migration. Prints PASS/FAIL/WARN per check and RESULT=PASS|FAIL.
# Exit code: 0 if every check passed, 1 otherwise, 2 on usage errors. bash 3.2 / BSD tools.
#
# Usage:
#   verify.sh --project <App.xcodeproj> --scheme <Scheme> --shared-dir <shared module dir> --scratch <dir>
#             [--destination '<xcodebuild -destination>'] [--basename <old framework baseName>]
#             [--targets 'TargetA,TargetB'] [--configuration Debug] [--workspace <App.xcworkspace>]
#             [--integration xcode|spm] [--pbxproj-only] [--repo-root <dir>] [--kotlin-platforms ios,macos]
#
#   --shared-dir   dir of <SHARED_MODULE> (where build/xcode-frameworks of the old ObjC framework lived)
#   --basename     <BASENAME>; default: last path component of --shared-dir
#   --targets      <APP_TARGETS> to check in project.pbxproj; default: the scheme's targets (shared scheme
#                  file), else the target named like the scheme. Other targets are listed as INFO only.
#   --destination  default: a booted iPhone simulator, else the first available one
#   --integration  spm = swiftPackageIntegration() (no Run Script; skips the embedSwiftExportForXcode log check)
#   --pbxproj-only only the project.pbxproj + build-file checks (no build, nothing removed); never a Phase 6 PASS
#   --repo-root    where to look for a leftover deprecated swiftExport { } block (build files, buildSrc, build-logic);
#                  default: the git top level of --project, else the parent of --shared-dir
#   --kotlin-platforms  Apple platforms Kotlin builds (deployment targets are enforced only for these); default:
#                  from the Apple targets named in <shared-dir>/build.gradle(.kts), else every platform
#
# What it does: rm -rf <shared-dir>/build/xcode-frameworks; clean xcodebuild with a fresh derivedData under
# <SCRATCH>/verify-dd; checks the exit code, the log (embedSwiftExportForXcode ran, embedAndSignAppleFrameworkForXcode
# did not, no Swift Export DSL diagnostics), project.pbxproj per target (leftovers, Run Script order, and
# sandboxing + deployment target in EVERY build configuration), no deprecated swiftExport { } block left in the
# repo, and prints an ANSI-stripped error summary plus the built .app path and bundle id.
# It does not run the app: do the Maestro check from SKILL.md Phase 6 afterwards.
# Never read stdin: a grep whose file list expands to nothing would otherwise wait forever.
exec </dev/null
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
PROJECT="" WORKSPACE="" SCHEME="" SHARED_DIR="" SCRATCH="" DEST="" BASENAME="" TARGETS="" CONFIG="Debug" INTEGRATION="xcode" BUILD=1 REPO="" KPLATS=""

usage() { sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2 ;;
    --workspace) WORKSPACE="$2"; shift 2 ;;
    --scheme) SCHEME="$2"; shift 2 ;;
    --shared-dir) SHARED_DIR="$2"; shift 2 ;;
    --scratch) SCRATCH="$2"; shift 2 ;;
    --destination) DEST="$2"; shift 2 ;;
    --basename) BASENAME="$2"; shift 2 ;;
    --targets) TARGETS="$2"; shift 2 ;;
    --configuration) CONFIG="$2"; shift 2 ;;
    --integration) INTEGRATION="$2"; shift 2 ;;
    --pbxproj-only) BUILD=0; shift ;;
    --repo-root) REPO="$2"; shift 2 ;;
    --kotlin-platforms) KPLATS="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done
[ -n "$PROJECT" ] && [ -n "$SCHEME" ] && [ -n "$SHARED_DIR" ] && [ -n "$SCRATCH" ] || usage
PBX="$PROJECT/project.pbxproj"
[ -f "$PBX" ] || { echo "not found: $PBX" >&2; exit 2; }
[ -d "$SHARED_DIR" ] || { echo "not a directory: $SHARED_DIR" >&2; exit 2; }
[ -n "$BASENAME" ] || BASENAME="$(basename "$SHARED_DIR")"
mkdir -p "$SCRATCH" || exit 2
if [ -z "$REPO" ]; then
  REPO=$(git -C "$(dirname "$PROJECT")" rev-parse --show-toplevel 2>/dev/null) || REPO=""
  [ -n "$REPO" ] || REPO=$(cd "$SHARED_DIR/.." && pwd)
fi
# Apple platforms Kotlin builds: from the shared module's build file (else enforce every platform)
if [ -z "$KPLATS" ]; then
  KPLATS=$(cat "$SHARED_DIR"/build.gradle.kts "$SHARED_DIR"/build.gradle 2>/dev/null \
    | grep -oE '\b(ios|macos|tvos|watchos)(X64|Arm64|SimulatorArm64|DeviceArm64|Arm32)\b' \
    | sed -E 's/(X64|Arm64|SimulatorArm64|DeviceArm64|Arm32)$//' | sort -u | paste -sd, -)
fi

FAILS=0
pass() { printf 'PASS %s: %s\n' "$1" "$2"; }
fail() { printf 'FAIL %s: %s\n' "$1" "$2"; FAILS=$((FAILS + 1)); }
warn() { printf 'WARN %s: %s\n' "$1" "$2"; }
info() { printf 'INFO %s: %s\n' "$1" "$2"; }

# --- targets in scope -----------------------------------------------------------------------------
if [ -z "$TARGETS" ]; then
  SCHEME_FILE=$(find "$PROJECT" -name "$SCHEME.xcscheme" 2>/dev/null | head -n 1)
  if [ -n "$SCHEME_FILE" ]; then
    TARGETS=$(grep -A8 '<BuildActionEntry' "$SCHEME_FILE" | grep -o 'BlueprintName = "[^"]*"' \
      | sed 's/BlueprintName = "\(.*\)"/\1/' | grep -vE 'Tests$' | sort -u | paste -sd, -)
  fi
  [ -n "$TARGETS" ] || TARGETS="$SCHEME"
fi
info targets "checking $TARGETS (override with --targets)"

# --- destination ------------------------------------------------------------------------------------
if [ $BUILD -eq 1 ] && [ -z "$DEST" ]; then
  UDID=$(xcrun simctl list devices available 2>/dev/null | grep -E 'iPhone' | grep -E '\(Booted\)' | head -n 1 \
    | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
  [ -n "$UDID" ] || UDID=$(xcrun simctl list devices available 2>/dev/null | grep -E 'iPhone' | head -n 1 \
    | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
  [ -n "$UDID" ] || { echo "no available iPhone simulator; pass --destination" >&2; exit 2; }
  DEST="platform=iOS Simulator,id=$UDID"
fi
DD="$SCRATCH/verify-dd"; LOG="$SCRATCH/verify-build.log"; CLEAN="$SCRATCH/verify-build.clean.log"
if [ $BUILD -eq 1 ]; then
info destination "$DEST"

# --- 1. stale ObjC framework ---------------------------------------------------------------------------
STALE="$SHARED_DIR/build/xcode-frameworks"
if [ -e "$STALE" ]; then rm -rf "$STALE"; info stale-framework "removed $STALE"; else info stale-framework "none at $STALE"; fi

# --- 2. clean build ----------------------------------------------------------------------------------
rm -rf "$DD"
if [ -n "$WORKSPACE" ]; then SRC=(-workspace "$WORKSPACE"); else SRC=(-project "$PROJECT"); fi
echo "Building (log: $LOG) ..."
xcodebuild "${SRC[@]}" -scheme "$SCHEME" -configuration "$CONFIG" -destination "$DEST" \
  -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO clean build > "$LOG" 2>&1
RC=$?
sed $'s/\x1b\\[[0-9;]*[A-Za-z]//g' "$LOG" > "$CLEAN"
if [ $RC -eq 0 ]; then pass build "xcodebuild exit 0"; else fail build "xcodebuild exit $RC"; fi

# --- 3./4. which integration ran -------------------------------------------------------------------------
if [ "$INTEGRATION" = "spm" ]; then
  info log-swift-export "skipped (--integration spm)"
elif grep -q 'embedSwiftExportForXcode' "$CLEAN"; then
  pass log-swift-export "embedSwiftExportForXcode ran"
elif [ -n "$(find "$DD/Build/Products" -maxdepth 2 -name 'ExportedKotlinPackages.swiftmodule' 2>/dev/null | head -n 1)" ]; then
  # Gradle run quietly (-q / --quiet in the Run Script): no task names in the log, but the fresh derived data
  # holds Swift Export's output, so it ran in this build (the Run Script itself is checked per target below)
  pass log-swift-export "Swift Export output (ExportedKotlinPackages.swiftmodule) in the fresh derived data; task name not logged (quiet Gradle?)"
else
  fail log-swift-export "embedSwiftExportForXcode not in the build log and no Swift Export output in $DD (Run Script missing, not run, or build stopped earlier)"
fi
DSLDIAG=$(grep -E "DeprecatedSwiftExportDsl|ConflictingSwiftExportDsls|Deprecated 'swiftExport \{ \}' DSL|Both Swift Export DSLs are configured" "$CLEAN" | sort -u | head -n 3)
if [ -n "$DSLDIAG" ]; then fail log-swift-export-dsl "KGP reports the deprecated swiftExport { } DSL (migrate it to export { swift { } } and delete it):"; printf '%s\n' "$DSLDIAG" | sed 's/^/    /'
else pass log-swift-export-dsl "no DeprecatedSwiftExportDsl / ConflictingSwiftExportDsls in the log"; fi
if grep -q 'embedAndSignAppleFrameworkForXcode' "$CLEAN"; then
  fail log-no-objc-export "embedAndSignAppleFrameworkForXcode ran: an old Run Script phase is still active"
else
  pass log-no-objc-export "embedAndSignAppleFrameworkForXcode did not run"
fi
else
  info build "skipped (--pbxproj-only): this is not a Phase 6 PASS"
fi

# --- 5. project.pbxproj per target -------------------------------------------------------------------
in_scope() { case ",$TARGETS," in *",$1,"*) return 0 ;; esac; return 1; }
v_major() { printf '%s' "$1" | sed -E 's/[^0-9.].*$//; s/\..*$//'; }
SEEN="" BUNDLES=""
while IFS=$'\t' read -r kind name ptype plats dts tasks before fws fsp sb xc prods bid; do
  [ "$kind" = "TARGET" ] || continue
  leftovers=""
  case "$tasks" in *embedAndSign*|*syncFramework*) leftovers="$leftovers Run Script calls $tasks;" ;; esac
  case "$fsp" in *xcode-frameworks*) leftovers="$leftovers FRAMEWORK_SEARCH_PATHS has xcode-frameworks;" ;; esac
  case ",$fws," in *",$BASENAME,"*) leftovers="$leftovers OTHER_LDFLAGS has -framework $BASENAME;" ;; esac
  if ! in_scope "$name"; then
    [ -n "$leftovers" ] && info "pbxproj-$name" "not in scope, still on ObjC export:$leftovers (fine only if deliberately left out; report it)"
    continue
  fi
  SEEN="$SEEN,$name"; BUNDLES="$BUNDLES$name=$bid"$'\n'
  if [ -n "$leftovers" ]; then fail "pbxproj-$name" "leftovers:$leftovers"; else pass "pbxproj-$name" "no embedAndSign / xcode-frameworks / -framework $BASENAME"; fi
  if [ "$INTEGRATION" != "spm" ]; then
    case "$tasks" in
      *embedSwiftExportForXcode*)
        if [ "$before" = "yes" ]; then pass "runscript-$name" "$tasks, before Compile Sources"
        else fail "runscript-$name" "$tasks runs after Compile Sources"; fi ;;
      *) fail "runscript-$name" "no Run Script phase calls embedSwiftExportForXcode" ;;
    esac
    # per configuration: "NO" when all agree, else e.g. "Debug:NO;Release:-" ("-" = not set)
    if [ "$sb" = "NO" ]; then pass "sandboxing-$name" "ENABLE_USER_SCRIPT_SANDBOXING = NO in every configuration"
    else fail "sandboxing-$name" "ENABLE_USER_SCRIPT_SANDBOXING = ${sb/#-/not set} (- = not set): write ENABLE_USER_SCRIPT_SANDBOXING = NO explicitly into every configuration (KGP fails the build when Xcode sandboxing is on)"; fi
  fi
  # deployment targets per platform and configuration: ios=18.0 or ios=Debug:18.0;Release:17.0
  ok=1; IFS=',' read -r -a dtl <<< "$dts"
  for d in "${dtl[@]}"; do
    p=${d%%=*}; min=18; [ "$p" = macos ] && min=15; [ "$p" = watchos ] && min=11
    # a platform the target supports but Kotlin doesn't build (e.g. macOS in SUPPORTED_PLATFORMS, no macos*() target)
    if [ -n "$KPLATS" ]; then case ",$KPLATS," in *",$p,"*) ;; *) info "deployment-$name" "$p not enforced: Kotlin builds only $KPLATS (--kotlin-platforms)"; continue ;; esac; fi
    IFS=';' read -r -a cvl <<< "${d#*=}"
    for cv in "${cvl[@]}"; do
      case "$cv" in *:*) cn=${cv%%:*}; v=${cv#*:} ;; *) cn="all configurations"; v=$cv ;; esac
      maj=$(v_major "$v")
      if [ -z "$maj" ]; then warn "deployment-$name" "$p deployment target not set for $cn in the target or project (xcconfig? else the SDK default)"; [ $ok -eq 1 ] && ok=2
      elif [ "$maj" -lt "$min" ]; then fail "deployment-$name" "$p $cn: $v < $min.0"; ok=0; fi
    done
  done
  [ $ok -eq 1 ] && pass "deployment-$name" "$dts"
  [ "$xc" != "-" ] && warn "xcconfig-$name" "settings may be overridden in $xc — check it by hand"
done < <(awk -f "$HERE/lib/pbxproj.awk" "$PBX")
IFS=',' read -r -a want <<< "$TARGETS"
for t in "${want[@]}"; do case "$SEEN," in *",$t,"*) ;; *) fail "pbxproj-$t" "target not found in $PBX" ;; esac; done

# --- 5b. no deprecated swiftExport { } block anywhere (module build files, buildSrc, build-logic) ---------------
OLD=$(find "$REPO" \( -name build -o -name .gradle -o -name .kotlin -o -name .git -o -name Pods -o -name DerivedData \
    -o -name .build -o -name node_modules -o -name xcuserdata \) -prune -o -type f \
    \( -name '*.gradle.kts' -o -name '*.gradle' -o \( -name '*.kt' \( -path '*/buildSrc/*' -o -path '*/build-logic/*' -o -path '*/convention-plugins/*' \) \) \) \
    -print0 2>/dev/null | xargs -0 grep -nE 'swiftExport *\{' /dev/null 2>/dev/null | awk -v r="$REPO/" 'index($0, r) == 1 { $0 = substr($0, length(r) + 1) } { print }')
if [ -n "$OLD" ]; then
  fail old-swift-export-dsl "deprecated swiftExport { } block left (migrate to export { swift { } } and delete it, gradle-and-xcode.md §1b):"
  printf '%s\n' "$OLD" | head -n 10 | sed 's/^/    /'
else pass old-swift-export-dsl "no swiftExport { } block under $REPO"; fi

# --- 6. errors / suspicious warnings -------------------------------------------------------------------
if [ $BUILD -eq 1 ]; then
ERRS=$(grep -E '^e: | error: |^error: |What went wrong|BUILD FAILED|\*\* BUILD FAILED' "$CLEAN" | grep -vE '^ *export ' | sort -u)
NERR=0; [ -n "$ERRS" ] && NERR=$(printf '%s\n' "$ERRS" | wc -l | tr -d ' ')
if [ "$NERR" -eq 0 ]; then pass errors "no error lines in the log"
else
  fail errors "$NERR distinct error lines; first ones (full context: grep -n -A6 'What went wrong\\| error: ' $CLEAN):"
  printf '%s\n' "$ERRS" | head -n 30 | sed 's/^/    /'
fi
CASTS=$(grep -E "cast from .* always fails" "$CLEAN" | sort -u | head -n 10)
[ -n "$CASTS" ] && { warn casts-always-fail "casts that always fail (runtime crashes / dead branches: real bugs, fix them):"; printf '%s\n' "$CASTS" | sed 's/^/    /'; }
NOEFF=$(grep -E "forced cast .* has no effect|conditional cast from .* always succeeds" "$CLEAN" | sort -u)
[ -n "$NOEFF" ] && info casts-no-effect "$(printf '%s\n' "$NOEFF" | wc -l | tr -d ' ') casts with no effect (expected with KMP-NC compatibility mode / typed flows; harmless)"
# what Phase 6 step 2 installs and launches
find "$DD/Build/Products" -maxdepth 2 -name '*.app' -type d 2>/dev/null | sort | while IFS= read -r app; do info app "$app"; done
fi
printf '%s' "$BUNDLES" | while IFS= read -r b; do [ -n "$b" ] && info "bundle-id-${b%%=*}" "${b#*=} (per configuration if they differ; launch the $CONFIG one)"; done

echo
if [ $FAILS -eq 0 ] && [ $BUILD -eq 0 ]; then echo "RESULT=PBXPROJ-PASS  (pbxproj checks only; run without --pbxproj-only for Phase 6)"; exit 0
elif [ $FAILS -eq 0 ]; then echo "RESULT=PASS  (next: run the app + Maestro flow, SKILL.md Phase 6)"; exit 0
elif [ $BUILD -eq 0 ]; then echo "RESULT=FAIL ($FAILS failed, pbxproj checks only)"; exit 1
else echo "RESULT=FAIL ($FAILS failed)  log: $CLEAN"; exit 1; fi
