# Minimal reader for Xcode project.pbxproj files (the old-style plist that Xcode writes).
# Used by preflight.sh and verify.sh. POSIX/BSD awk. Read-only.
#
# Usage: awk -f pbxproj.awk path/to/project.pbxproj
# Output, one tab-separated record per line ("-" = not set):
#   TARGET  name  productType  platforms  deploymentTargets  gradleTasks  scriptBeforeSources
#           linkedFrameworks  frameworkSearchPaths  userScriptSandboxing  xcconfig  packageProducts  bundleId
#   PACKAGE kind(remote|local)  location
# platforms: ios,macos,tvos,watchos,visionos (from SUPPORTED_PLATFORMS, else SDKROOT; union of all configurations)
# Per-configuration settings (deploymentTargets per platform, userScriptSandboxing, bundleId): the target's value,
# else the project's value of the same configuration, else "-". One value if every configuration agrees
# (ios=18.0, NO), otherwise every configuration: ios=Debug:18.0;Release:17.0, Debug:NO;Release:-
# linkedFrameworks / frameworkSearchPaths: union of all configurations
# gradleTasks: Gradle task names found in the target's Run Script phases (e.g. :common:embedAndSignAppleFrameworkForXcode)
# scriptBeforeSources: yes if the first Gradle Run Script phase comes before "Compile Sources"; "-" if no Gradle phase

function strip(s) {
  gsub(/\/\*[^*]*\*\//, "", s)
  sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s)
  sub(/[;,]$/, "", s); sub(/[ \t]+$/, "", s)
  if (s ~ /^".*"$/) s = substr(s, 2, length(s) - 2)
  return s
}
function path(d,   p, i) { p = ""; for (i = 3; i < d; i++) p = p (p == "" ? "" : ".") key[i]; return p }
function nitems(lst, arr) { if (lst == "") return 0; return split(lst, arr, "|") }
function addu(lst, v) {   # append v to a comma list if not present
  if (v == "" || v == "-") return lst
  if (index("," lst ",", "," v ",") > 0) return lst
  return lst == "" ? v : lst "," v
}
function cfgval(target, s,   n, arr, i, c, nm, v, pv, out) {
  out = ""
  n = nitems(attr[attr[target, "buildConfigurationList"], "buildConfigurations"], arr)
  for (i = 1; i <= n; i++) {
    c = arr[i]; nm = attr[c, "name"]
    v = attr[c, "buildSettings." s]
    if (v == "") { pv = projcfg[nm]; if (pv != "") v = attr[pv, "buildSettings." s] }
    if (v == "") continue
    if (out == "") out = v
    else if (index(" / " out " / ", " / " v " / ") == 0) out = out " / " v
  }
  return out
}
function cfgper(target, s,   n, arr, i, c, nm, v, pv, out, first, same) {   # per-configuration value
  out = ""; same = 1
  n = nitems(attr[attr[target, "buildConfigurationList"], "buildConfigurations"], arr)
  for (i = 1; i <= n; i++) {
    c = arr[i]; nm = attr[c, "name"]
    v = attr[c, "buildSettings." s]
    if (v == "") { pv = projcfg[nm]; if (pv != "") v = attr[pv, "buildSettings." s] }
    if (v == "") v = "-"
    if (i == 1) first = v; else if (v != first) same = 0
    out = out (i == 1 ? "" : ";") nm ":" v
  }
  if (n == 0) return ""
  if (same) return first == "-" ? "" : first
  return out
}
function platmap(p) {
  if (p ~ /^iphone/) return "ios"
  if (p ~ /^macosx/) return "macos"
  if (p ~ /^appletv/) return "tvos"
  if (p ~ /^watch/) return "watchos"
  if (p ~ /^xr/) return "visionos"
  return ""
}
function dtkey(p) {
  if (p == "ios") return "IPHONEOS_DEPLOYMENT_TARGET"
  if (p == "macos") return "MACOSX_DEPLOYMENT_TARGET"
  if (p == "tvos") return "TVOS_DEPLOYMENT_TARGET"
  if (p == "watchos") return "WATCHOS_DEPLOYMENT_TARGET"
  if (p == "visionos") return "XROS_DEPLOYMENT_TARGET"
  return ""
}
function or_dash(s) { return s == "" ? "-" : s }

BEGIN { depth = 0; cur = "" }

{
  t = $0; sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
  if (t == "" || t ~ /^\/\//) next

  if (t ~ /^[})][;,]?$/) {                         # closer
    depth--; if (depth < 0) depth = 0
    if (depth <= 2) cur = ""
    next
  }
  if (t ~ /[{(]$/ && t !~ /^"[^"]*$/) {            # opener: `key = {` / `key = (`
    k = t; sub(/[ \t]*=[ \t]*[{(]$/, "", k); k = strip(k)
    if (depth == 2) cur = k
    else if (depth >= 3) key[depth] = k
    inlist[depth + 1] = (t ~ /\($/)
    depth++
    next
  }
  if (depth == 2) {                                  # single-line object: ID = {isa = X; k = v; };
    eq = index(t, "= {"); if (eq == 0) next
    id = strip(substr(t, 1, eq - 1)); body = substr(t, eq + 3)
    n = split(body, parts, ";")
    for (i = 1; i <= n; i++) {
      e = index(parts[i], " = "); if (e == 0) continue
      kk = strip(substr(parts[i], 1, e - 1)); vv = strip(substr(parts[i], e + 3))
      if (kk ~ /^(isa|name|path|productName|package|repositoryURL|relativePath)$/) attr[id, kk] = vv
    }
    next
  }
  if (depth >= 3 && cur != "") {
    p = path(depth)
    if (inlist[depth]) {                             # list item
      v = strip(t)
      attr[cur, p] = (attr[cur, p] == "" ? v : attr[cur, p] "|" v)
    } else {                                         # key = value;
      e = index(t, " = "); if (e == 0) next
      kk = strip(substr(t, 1, e - 1)); vv = strip(substr(t, e + 3))
      attr[cur, (p == "" ? kk : p "." kk)] = vv
    }
  }
}

END {
  proj = ""
  for (ik in attr) {
    split(ik, kp, SUBSEP)
    if (kp[2] == "isa" && attr[ik] == "PBXProject") proj = kp[1]
  }
  if (proj == "") exit 1
  n = nitems(attr[attr[proj, "buildConfigurationList"], "buildConfigurations"], pc)
  for (i = 1; i <= n; i++) projcfg[attr[pc[i], "name"]] = pc[i]

  nt = nitems(attr[proj, "targets"], tg)
  for (ti = 1; ti <= nt; ti++) {
    tid = tg[ti]
    name = attr[tid, "name"]; ptype = attr[tid, "productType"]

    plats = ""
    sp = cfgval(tid, "SUPPORTED_PLATFORMS")
    if (sp != "") { m = split(sp, sw, /[ \/]+/); for (j = 1; j <= m; j++) plats = addu(plats, platmap(sw[j])) }
    if (plats == "") { sdk = cfgval(tid, "SDKROOT"); m = split(sdk, sw, /[ \/]+/); for (j = 1; j <= m; j++) plats = addu(plats, platmap(sw[j])) }
    dts = ""
    m = split(plats, pw, ",")
    for (j = 1; j <= m; j++) { dv = cfgper(tid, dtkey(pw[j])); dts = (dts == "" ? "" : dts ",") pw[j] "=" or_dash(dv) }

    tasks = ""; firstScript = 0; sourcesAt = 0
    np = nitems(attr[tid, "buildPhases"], ph)
    for (j = 1; j <= np; j++) {
      pisa = attr[ph[j], "isa"]
      if (pisa == "PBXSourcesBuildPhase" && sourcesAt == 0) sourcesAt = j
      if (pisa != "PBXShellScriptBuildPhase") continue
      sc = attr[ph[j], "shellScript"]
      if (sc !~ /gradlew|gradle /) continue
      if (firstScript == 0) firstScript = j
      rest = sc
      while (match(rest, /(:[A-Za-z0-9_.-]+)+:[A-Za-z0-9_]+|[A-Za-z]+ForXcode|syncFramework|podInstall/)) {
        tk = substr(rest, RSTART, RLENGTH)
        tasks = addu(tasks, tk)
        rest = substr(rest, RSTART + RLENGTH)
      }
    }
    before = "-"
    if (firstScript > 0) before = (sourcesAt == 0 || firstScript < sourcesAt) ? "yes" : "no"

    fw = ""
    ld = cfgval(tid, "OTHER_LDFLAGS")
    gsub(/\|/, " ", ld); gsub(/"/, "", ld)
    m = split(ld, lw, /[ \/]+/)
    for (j = 1; j < m; j++) if (lw[j] == "-framework") fw = addu(fw, lw[j + 1])
    for (j = 1; j <= m; j++) if (lw[j] ~ /^-l[A-Za-z0-9_+.-]+$/) fw = addu(fw, lw[j])

    fsp = cfgval(tid, "FRAMEWORK_SEARCH_PATHS"); gsub(/\|/, " ", fsp); gsub(/\\n/, "", fsp)
    sb = cfgper(tid, "ENABLE_USER_SCRIPT_SANDBOXING")
    bid = cfgper(tid, "PRODUCT_BUNDLE_IDENTIFIER")

    xc = ""
    nc = nitems(attr[attr[tid, "buildConfigurationList"], "buildConfigurations"], cf)
    for (j = 1; j <= nc; j++) { r = attr[cf[j], "baseConfigurationReference"]; if (r != "") xc = addu(xc, attr[r, "path"] != "" ? attr[r, "path"] : r) }

    prods = ""
    npp = nitems(attr[tid, "packageProductDependencies"], pp)
    for (j = 1; j <= npp; j++) prods = addu(prods, attr[pp[j], "productName"])

    printf "TARGET\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", name, or_dash(ptype), or_dash(plats), or_dash(dts), \
      or_dash(tasks), before, or_dash(fw), or_dash(fsp), or_dash(sb), or_dash(xc), or_dash(prods), or_dash(bid)
  }

  npk = nitems(attr[proj, "packageReferences"], pk)
  for (j = 1; j <= npk; j++) {
    if (attr[pk[j], "repositoryURL"] != "") printf "PACKAGE\tremote\t%s\n", attr[pk[j], "repositoryURL"]
    else if (attr[pk[j], "relativePath"] != "") printf "PACKAGE\tlocal\t%s\n", attr[pk[j], "relativePath"]
  }
}
