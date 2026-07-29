#!/usr/bin/env bash
# zorskill-dev.sh — aggregation-side release tooling for the zorskill marketplace.
#   check                 audit version drift / JSON / both-format / submodule health
#   release <name> <x.y.z> [--push] [--marketplace-version <x.y.z>]
#   new <name> [--repo-url <url>] [--create-remote]
# Operates ONLY on the monorepo aggregation side. Never pushes to a plugin's own repo.
set -uo pipefail

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$*"; }

is_semver(){ [[ "${1:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; }

# _semver_gt A B → exit 0 iff A > B, compared NUMERICALLY per component (so 0.10.0 > 0.9.0).
_semver_gt(){
  local a1 a2 a3 b1 b2 b3
  IFS=. read -r a1 a2 a3 <<<"$1"; IFS=. read -r b1 b2 b3 <<<"$2"
  if [[ "$a1" -ne "$b1" ]]; then [[ "$a1" -gt "$b1" ]]; return; fi
  if [[ "$a2" -ne "$b2" ]]; then [[ "$a2" -gt "$b2" ]]; return; fi
  [[ "$a3" -gt "$b3" ]]
}

# The aggregate root marketplace has BOTH a .plugins array AND a top-level semver .version.
# Requiring the semver .version skips per-plugin outliers (e.g. kf-cli's stray marketplace.json,
# which carries .plugins but a metadata.version instead of a top-level .version).
_is_market_root(){ [[ -f "$1/.claude-plugin/marketplace.json" ]] && jq -e '.plugins and (.version|type=="string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))' "$1/.claude-plugin/marketplace.json" >/dev/null 2>&1; }

resolve_root(){
  if [[ -n "${ZORSKILL_ROOT:-}" ]] && _is_market_root "$ZORSKILL_ROOT"; then echo "$ZORSKILL_ROOT"; return 0; fi
  local d="$PWD"
  while [[ "$d" != "/" ]]; do
    if _is_market_root "$d"; then echo "$d"; return 0; fi
    d="$(dirname "$d")"
  done
  local sp; sp="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-superproject-working-tree 2>/dev/null || true)"
  if [[ -n "$sp" ]] && _is_market_root "$sp"; then echo "$sp"; return 0; fi
  return 1
}

# Emit each plugin's name + source path, one "name<TAB>path" per line.
# Emit "name<TAB>src" per plugin. src = the string source (e.g. ./plugins/<name>) for a local entry,
# or empty when .source is an OBJECT (remote-sourced: github/url/git-subdir/npm). @tsv keeps object
# sources from corrupting the tab-delimited stream. Consumers classify with _is_submodule.
_plugins(){ jq -r '.plugins[] | [.name, (if (.source|type)=="string" then .source else "" end)] | @tsv' "$1/.claude-plugin/marketplace.json"; }

# A marketplace is now MIXED-SOURCE. A plugin is SUBMODULE-MANAGED iff its .source is a local "./"
# string path AND it is registered in .gitmodules; everything else (object source github/url/…, or a
# string path not in .gitmodules) is REMOTE-SOURCED — it has no submodule on disk and installs at
# `/plugin install` time with the user's own creds, so it may be public OR private.
_is_submodule(){ # $1 root, $2 name → 0 if submodule-managed
  [[ "$(jq -r --arg n "$2" '.plugins[]|select(.name==$n)|.source|type' "$1/.claude-plugin/marketplace.json")" == "string" ]] \
    && [[ "$(jq -r --arg n "$2" '.plugins[]|select(.name==$n)|.source' "$1/.claude-plugin/marketplace.json")" == ./* ]] \
    && git config -f "$1/.gitmodules" --get "submodule.plugins/$2.path" >/dev/null 2>&1
}
# https repo URL for a remote-sourced plugin (github .repo → github.com/<repo>, else .url), or empty.
_remote_source_url(){ jq -r --arg n "$2" '.plugins[]|select(.name==$n)|.source | if type=="object" then (if .repo then "https://github.com/"+.repo elif .url then .url else "" end) else "" end' "$1/.claude-plugin/marketplace.json"; }
# Short descriptor for info lines, e.g. "github:ZorCorp/gcp-bq".
_remote_source_desc(){ jq -r --arg n "$2" '.plugins[]|select(.name==$n)|.source | if type=="object" then ((.source // "remote")+":"+(.repo // .url // "?")) else "remote" end' "$1/.claude-plugin/marketplace.json"; }
# owner/name for a remote GITHUB source (to probe visibility), empty otherwise.
_remote_repo(){ jq -r --arg n "$2" '.plugins[]|select(.name==$n)|.source | if type=="object" then (.repo // "") else "" end' "$1/.claude-plugin/marketplace.json"; }

check_json(){
  local root="$1" fail=0 f name src   # name/src MUST be local: check_json runs inside
  for f in "$root/.claude-plugin/marketplace.json"; do   # check_release's scope (which holds
    jq -e . "$f" >/dev/null 2>&1 || { red "  ✗ invalid JSON: ${f#$root/}"; fail=1; }  # local name).
  done
  while IFS=$'\t' read -r name src; do
    _is_submodule "$root" "$name" || continue   # remote-sourced: no local plugin.json to validate
    f="$root/plugins/$name/.claude-plugin/plugin.json"
    [[ -f "$f" ]] || continue
    jq -e . "$f" >/dev/null 2>&1 || { red "  ✗ invalid JSON: plugins/$name/.claude-plugin/plugin.json"; fail=1; }
  done < <(_plugins "$root")
  [[ $fail -eq 0 ]] && green "  ✓ JSON valid"
  return $fail
}

check_versions(){
  local root="$1" fail=0 agg name src pj_ver root_ver
  agg="$(jq -r '.version // ""' "$root/.claude-plugin/marketplace.json")"
  if is_semver "$agg"; then green "  ✓ aggregate .version present ($agg)"
  else red "  ✗ aggregate top-level .version missing or not semver: '$agg'"; fail=1; fi
  while IFS=$'\t' read -r name src; do
    if ! _is_submodule "$root" "$name"; then echo "  · $name: remote-sourced ($(_remote_source_desc "$root" "$name")) — not submodule-managed"; continue; fi
    root_ver="$(jq -r --arg n "$name" '.plugins[]|select(.name==$n)|.version' "$root/.claude-plugin/marketplace.json")"
    local pj="$root/plugins/$name/.claude-plugin/plugin.json"
    if [[ ! -f "$pj" ]]; then red "  ✗ $name: missing .claude-plugin/plugin.json"; fail=1; continue; fi
    pj_ver="$(jq -r '.version // ""' "$pj")"
    if [[ "$root_ver" == "$pj_ver" ]] && is_semver "$root_ver"; then green "  ✓ $name @ $root_ver"
    else red "  ✗ $name VERSION DRIFT — root marketplace='$root_ver' vs plugin.json='$pj_ver'"; fail=1; fi
  done < <(_plugins "$root")
  return $fail
}

check_both_format(){
  # Severity: missing plugin.json = ERROR (a plugin must have the Claude-plugin manifest);
  # missing SKILL.md = WARNING (some plugins are intentionally Claude-only, e.g. code-to-video).
  local root="$1" fail=0 name src d
  while IFS=$'\t' read -r name src; do
    _is_submodule "$root" "$name" || continue   # remote-sourced: no local files to check
    d="$root/plugins/$name"
    [[ -f "$d/SKILL.md" ]] || yellow "  ⚠ $name: no SKILL.md (agent-skill format) — Claude-only plugin, not blocking"
    [[ -f "$d/.claude-plugin/plugin.json" ]] || { red "  ✗ $name: missing .claude-plugin/plugin.json (Claude-plugin format)"; fail=1; }
  done < <(_plugins "$root")
  [[ $fail -eq 0 ]] && green "  ✓ every submodule plugin has .claude-plugin/plugin.json (SKILL.md optional — warnings above, if any)"
  return $fail
}

check_submodules(){
  local root="$1" fail=0 line flag rest path
  # Lines: " <sha> path (desc)" normal; "-<sha>" uninit; "+<sha>" moved; "U<sha>" conflict.
  while read -r line; do
    [[ -z "$line" ]] && continue
    flag="${line:0:1}"; rest="${line:1}"; path="$(echo "$rest" | awk '{print $2}')"
    case "$flag" in
      '-') red "  ✗ submodule not initialized: $path (run: git submodule update --init $path)"; fail=1;;
      'U') red "  ✗ submodule has merge conflict: $path"; fail=1;;
      '+') yellow "  ⚠ submodule pointer differs from index (uncommitted pointer move): $path";;
    esac
  done < <(git -C "$root" submodule status 2>/dev/null)
  # Dirty worktrees inside plugin submodules (submodule-managed only)
  local name src d
  while IFS=$'\t' read -r name src; do
    _is_submodule "$root" "$name" || continue
    d="$root/plugins/$name"
    [[ -d "$d/.git" || -f "$d/.git" ]] || continue
    if [[ -n "$(git -C "$d" status --porcelain 2>/dev/null)" ]]; then
      yellow "  ⚠ uncommitted changes inside plugins/$name (commit/push to its own repo before releasing)"
    fi
  done < <(_plugins "$root")
  [[ $fail -eq 0 ]] && green "  ✓ submodules initialized, no conflicts"
  return $fail
}

# ---- README Skills-table sync (managed block) ----------------------------------
# The root README.md carries a human-facing Skills table. Only the block between
# these markers is tool-managed: the ROSTER is authoritative from marketplace.json,
# but curated descriptions of already-listed plugins are preserved.
README_BEGIN='<!-- BEGIN SKILLS (managed by zorskill-dev) -->'
README_END='<!-- END SKILLS -->'

_plugin_repo_url(){ # $1 root, $2 name → repo URL (from .gitmodules; .git stripped)
  local url; url="$(git config -f "$1/.gitmodules" --get "submodule.plugins/$2.url" 2>/dev/null || true)"
  [[ -z "$url" ]] && url="https://github.com/ZorCorp/$2.git"
  echo "${url%.git}"
}
_repo_label(){ echo "$1" | sed -E 's#^https?://[^/]+/##; s#\.git$##'; }   # owner/name
_first_sentence(){ printf '%s' "$1" | sed -E 's/([.])[[:space:]].*/\1/'; }  # up to first ". "
# Extract the managed block (between markers, exclusive) from $1 to stdout.
_readme_block(){ awk -v b="$README_BEGIN" -v e="$README_END" 'index($0,b){f=1;next} index($0,e){f=0} f' "$1"; }
# Description column for plugin $2 from a block file $1 (empty if no row).
_existing_desc(){
  awk -F'|' -v n="$2" 'NF>=4 { k=$2; gsub(/[ \t`]/,"",k); if(k==n){ d=$3; sub(/^[ \t]+/,"",d); sub(/[ \t]+$/,"",d); print d; exit } }' "$1"
}
# Plugin names present as managed rows in block file $1 (excludes the header row).
_block_rows(){ awk -F'|' 'NF>=4 && $2 ~ /`/ { k=$2; gsub(/[ \t`]/,"",k); if(k!="Skill") print k }' "$1"; }

_readme_has_markers(){ grep -qF "$README_BEGIN" "$1" && grep -qF "$README_END" "$1"; }

sync_readme(){ # $1 root — regenerate the managed Skills table
  local root="$1" readme="$1/README.md" name src url label desc old block tmp
  [[ -f "$readme" ]] || { red "  ✗ README.md not found at $readme"; return 1; }
  _readme_has_markers "$readme" || { red "  ✗ README.md missing managed markers — add '$README_BEGIN' / '$README_END' around the Skills table"; return 1; }
  old="$(mktemp)"; _readme_block "$readme" > "$old"
  block="$(mktemp)"
  { echo "| Skill | Description | Source |"
    echo "|-------|-------------|--------|"
    while IFS=$'\t' read -r name src; do
      # Source link: submodule → .gitmodules URL; remote → marketplace source.repo/url.
      if _is_submodule "$root" "$name"; then url="$(_plugin_repo_url "$root" "$name")"
      else url="$(_remote_source_url "$root" "$name")"; fi
      if [[ -n "$url" ]]; then label="$(_repo_label "$url")"; else label="$name"; fi
      desc="$(_existing_desc "$old" "$name")"
      [[ -z "$desc" ]] && desc="$(_first_sentence "$(jq -r --arg n "$name" '.plugins[]|select(.name==$n)|.description // ""' "$root/.claude-plugin/marketplace.json")")"
      # Best-effort 🔒 marker on a confirmed-private plugin's row (skip if gh absent/offline).
      # Idempotent: once the row description starts with 🔒, re-syncs don't add another.
      if _have_gh && ! _has_lock "$desc"; then
        local prepo; prepo="$(_plugin_probe_repo "$root" "$name")"
        [[ -n "$prepo" && "$(_repo_visibility "$prepo" 2>/dev/null || true)" == "private" ]] && desc="🔒 $desc"
      fi
      if [[ -n "$url" ]]; then printf '| `%s` | %s | [%s](%s) |\n' "$name" "$desc" "$label" "$url"
      else printf '| `%s` | %s | %s |\n' "$name" "$desc" "$label"; fi
    done < <(_plugins "$root")
  } > "$block"
  tmp="$(mktemp)"
  awk -v b="$README_BEGIN" -v e="$README_END" -v bf="$block" '
    index($0,b){ print; while((getline line < bf)>0) print line; close(bf); skip=1; next }
    index($0,e){ skip=0; print; next }
    !skip { print }
  ' "$readme" > "$tmp" && mv "$tmp" "$readme"
  rm -f "$old" "$block"
  green "  ✓ README Skills table synced ($(_plugins "$root" | grep -c . ) plugins)"
}

check_readme(){ # $1 root — README roster drift is an ERROR
  local root="$1" readme="$1/README.md" fail=0 name src old rn
  [[ -f "$readme" ]] || { red "  ✗ README.md not found (run: zorskill-dev.sh sync)"; return 1; }
  _readme_has_markers "$readme" || { red "  ✗ README.md missing managed markers (run: zorskill-dev.sh sync)"; return 1; }
  old="$(mktemp)"; _readme_block "$readme" > "$old"
  while IFS=$'\t' read -r name src; do
    grep -qF "\`$name\`" "$old" || { red "  ✗ README missing managed row for: $name (run: zorskill-dev.sh sync)"; fail=1; }
  done < <(_plugins "$root")
  while read -r rn; do
    [[ -z "$rn" ]] && continue
    jq -e --arg n "$rn" '.plugins[]|select(.name==$n)' "$root/.claude-plugin/marketplace.json" >/dev/null 2>&1 \
      || { red "  ✗ README lists delisted/unknown plugin: $rn (run: zorskill-dev.sh sync)"; fail=1; }
  done < <(_block_rows "$old")
  rm -f "$old"
  [[ $fail -eq 0 ]] && green "  ✓ README Skills table in sync"
  return $fail
}

cmd_sync(){ # regenerate the README managed block, then re-validate
  local root; root="$(resolve_root)" || { red "cannot locate zorskill root (set ZORSKILL_ROOT)"; return 1; }
  echo "▸ Sync README Skills table"; sync_readme "$root" || return 1
  echo "▸ Re-validate"; ( cd "$root" && cmd_check )
}

# Repo visibility guardrail. A PRIVATE plugin repo breaks `/plugin marketplace add` for EVERY end
# user (Claude Code recursively clones every plugin submodule and 404s on any it can't reach).
# Best-effort + network-dependent, so it degrades gracefully: no gh / API failure / offline → skip
# with a note (never fails check on lack of network). Only a CONFIRMED `private` is an ERROR.
_have_gh(){ command -v gh >/dev/null 2>&1; }                       # overridable in tests
_repo_visibility(){ gh api "repos/$1" --jq '.visibility' 2>/dev/null; }  # prints public|private|internal or empty; overridable in tests

# Private-label convention: an access-gated (private) plugin's marketplace description is prefixed
# with this literal marker so users see it in the listing.
LOCK_MARKER='🔒 Private (ZorCorp members only) — '
_has_lock(){ case "$1" in '🔒'*) return 0;; *) return 1;; esac; }   # description starts with the 🔒 icon?
# The repo (owner/name) to probe visibility for a plugin, whichever source kind.
_plugin_probe_repo(){ # $1 root, $2 name
  if _is_submodule "$1" "$2"; then _repo_label "$(_plugin_repo_url "$1" "$2")"; else _remote_repo "$1" "$2"; fi
}

check_visibility(){ # $1 root — a PRIVATE repo is an ERROR only for a SUBMODULE-managed plugin
  # (a private submodule breaks `/plugin marketplace add` — recursive clone 404s). A private REMOTE
  # source is FINE (it installs per-access at `/plugin install`) — noted, never an error.
  local root="$1" fail=0 name src url path vis
  if ! _have_gh; then yellow "  · repo visibility not checked (gh not installed) — ensure every SUBMODULE plugin repo is PUBLIC"; return 0; fi
  while IFS=$'\t' read -r name src; do
    if _is_submodule "$root" "$name"; then
      url="$(_plugin_repo_url "$root" "$name")"; path="$(_repo_label "$url")"
      vis="$(_repo_visibility "$path" || true)"
      case "$vis" in
        private) red "  ✗ $name: SUBMODULE repo is PRIVATE — this breaks \`/plugin marketplace add\` for end users (recursive clone 404s). Make it public, or relist it as a REMOTE source."; fail=1;;
        public)  : ;;
        "")      yellow "  · $name: visibility unknown (gh api failed/offline) — skipped";;
        *)       yellow "  · $name: visibility '$vis' (not public) — verify end users can clone it";;
      esac
    else
      # remote-sourced: private is expected/allowed (per-access install). Best-effort note only.
      local rp; rp="$(_remote_repo "$root" "$name")"
      vis="$([[ -n "$rp" ]] && _repo_visibility "$rp" || true)"
      case "$vis" in
        private) echo "  · $name: remote private ($(_remote_source_desc "$root" "$name")) — installs per-access, OK";;
        public)  echo "  · $name: remote public ($(_remote_source_desc "$root" "$name")) — OK";;
        *)       echo "  · $name: remote-sourced ($(_remote_source_desc "$root" "$name")) — installs per-access";;
      esac
    fi
  done < <(_plugins "$root")
  [[ $fail -eq 0 ]] && green "  ✓ no confirmed-private SUBMODULE plugin repos"
  return $fail
}

# Reconcile the 🔒 private label vs a plugin's ACTUAL repo visibility. WARN only (descriptions are
# curated — never auto-edited); orthogonal to source kind (applies by actual visibility). Graceful:
# no gh / offline → skip. A private repo whose description isn't 🔒-labeled, or a public repo that
# still carries a stale 🔒 label, is flagged.
check_labels(){ # $1 root
  local root="$1" name src repo vis desc warned=0
  if ! _have_gh; then yellow "  · private-label reconciliation skipped (gh not installed)"; return 0; fi
  while IFS=$'\t' read -r name src; do
    repo="$(_plugin_probe_repo "$root" "$name")"; [[ -n "$repo" ]] || continue
    vis="$(_repo_visibility "$repo" || true)"
    desc="$(jq -r --arg n "$name" '.plugins[]|select(.name==$n)|.description // ""' "$root/.claude-plugin/marketplace.json")"
    case "$vis" in
      private) if ! _has_lock "$desc"; then yellow "  ⚠ $name: private but not labeled — prefix its description with '${LOCK_MARKER}'"; warned=1; fi;;
      public)  if   _has_lock "$desc"; then yellow "  ⚠ $name: labeled private but its repo is public — drop the 🔒 marker"; warned=1; fi;;
    esac
  done < <(_plugins "$root")
  [[ $warned -eq 0 ]] && green "  ✓ private labels match repo visibility"
  return 0   # WARNINGS only — never fails check
}

cmd_check(){
  local root; root="$(resolve_root)" || { red "cannot locate zorskill root (set ZORSKILL_ROOT)"; exit 1; }
  local rc=0
  echo "▸ JSON validity";                        check_json        "$root" || rc=1
  echo "▸ Version consistency (per-plugin)";      check_versions    "$root" || rc=1
  echo "▸ Both-format presence";                  check_both_format "$root" || rc=1
  echo "▸ README roster sync";                    check_readme      "$root" || rc=1
  echo "▸ Repo visibility (must be public)";      check_visibility  "$root" || rc=1
  echo "▸ Private-label reconciliation";          check_labels      "$root"          # WARN-only
  echo "▸ Submodule health";                      check_submodules  "$root" || rc=1
  echo
  if [[ $rc -eq 0 ]]; then green "PASS — marketplace is consistent ($root)"; else red "FAIL — fix the ✗ items above"; fi
  return $rc
}

_sub_branch(){ # $1 root, $2 name → tracking branch (from .gitmodules or remote HEAD)
  local br; br="$(git config -f "$1/.gitmodules" --get "submodule.plugins/$2.branch" 2>/dev/null || true)"
  if [[ -z "$br" ]]; then
    br="$(git -C "$1/plugins/$2" remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p')"
  fi
  echo "${br:-main}"
}

advance_pointer(){
  local root="$1" name="$2" sub="$1/plugins/$2" br
  [[ -d "$sub" ]] || { red "no such submodule: plugins/$name"; return 1; }
  git -C "$sub" -c protocol.file.allow=always fetch --quiet origin || { red "fetch failed: $name"; return 1; }
  br="$(_sub_branch "$root" "$name")"
  git -C "$sub" checkout --quiet "origin/$br" 2>/dev/null || git -C "$sub" checkout --quiet "$br" || { red "checkout failed: $name @ $br"; return 1; }
}

read_plugin_version(){ jq -r '.version // ""' "$1/plugins/$2/.claude-plugin/plugin.json"; }

_bump_patch(){ local v="$1"; IFS=. read -r a b c <<<"$v"; echo "$a.$b.$((c+1))"; }

apply_release_versions(){
  local root="$1" name="$2" ver="$3" agg="${4:-}" cur tmp mf="$1/.claude-plugin/marketplace.json"
  is_semver "$ver" || { red "version must be x.y.z: $ver" >&2; return 2; }
  cur="$(jq -r '.version' "$mf")"
  if [[ -z "$agg" ]]; then agg="$(_bump_patch "$cur")"; fi
  is_semver "$agg" || { red "aggregate must be x.y.z: $agg" >&2; return 2; }
  tmp=$(mktemp)
  jq --arg n "$name" --arg v "$ver" --arg a "$agg" \
     '.version=$a | (.plugins[]|select(.name==$n)|.version)=$v' "$mf" > "$tmp" && mv "$tmp" "$mf"
  echo "$agg"
}

# Release-time validation, SCOPED so plugin X's release is never blocked by plugin Y's
# pre-existing debt. Hard-fails ONLY on (a) repo-wide JSON validity and (b) the TARGET
# plugin's own consistency (plugin.json present; plugin.json == root entry == requested).
# Every other plugin's non-uniformity/drift is printed as a non-fatal WARNING.
check_release(){
  local root="$1" name="$2" ver="$3" rc=0 n s d p pjver rootver rv pv
  echo "  • repo-wide JSON validity"
  if check_json "$root" >/dev/null 2>&1; then green "  ✓ JSON valid (repo-wide)"
  else red "  ✗ repo has invalid JSON — fix before releasing:"; check_json "$root"; rc=1; fi
  echo "  • target plugin: $name"
  p="$root/plugins/$name/.claude-plugin/plugin.json"
  if [[ ! -f "$p" ]]; then
    red "  ✗ $name: missing .claude-plugin/plugin.json"; rc=1
  else
    pjver="$(jq -r '.version // ""' "$p")"
    rootver="$(jq -r --arg n "$name" '.plugins[]|select(.name==$n)|.version' "$root/.claude-plugin/marketplace.json")"
    if [[ "$pjver" == "$ver" && "$rootver" == "$ver" ]] && is_semver "$ver"; then
      green "  ✓ $name @ $ver (plugin.json == marketplace == requested)"
    else
      red "  ✗ $name version mismatch — plugin.json='$pjver' marketplace='$rootver' requested='$ver'"; rc=1
    fi
    [[ -f "$root/plugins/$name/SKILL.md" ]] || yellow "  ⚠ $name: no SKILL.md (Claude-only plugin) — not blocking"
  fi
  # Other plugins: report pre-existing non-uniformity/drift as WARNINGS only — never gate.
  while IFS=$'\t' read -r n s; do
    [[ "$n" == "$name" ]] && continue
    d="$root/${s#./}"; p="$d/.claude-plugin/plugin.json"
    if [[ ! -f "$p" ]]; then yellow "  ⚠ other plugin $n: missing plugin.json (pre-existing; not blocking $name)"; continue; fi
    rv="$(jq -r --arg m "$n" '.plugins[]|select(.name==$m)|.version' "$root/.claude-plugin/marketplace.json")"
    pv="$(jq -r '.version // ""' "$p")"
    [[ "$rv" == "$pv" ]] || yellow "  ⚠ other plugin $n: version drift root='$rv' plugin.json='$pv' (pre-existing; not blocking $name)"
  done < <(_plugins "$root")
  return $rc
}

cmd_release(){
  local name="${1:-}" ver="${2:-}" push=0 agg_override="" a
  shift 2 2>/dev/null || { red "usage: release <name> <x.y.z> [--push] [--marketplace-version <x.y.z>]"; return 2; }
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --push) push=1;;
      --marketplace-version) agg_override="${2:-}"; shift;;
      *) red "unknown flag: $1"; return 2;;
    esac; shift
  done
  is_semver "$ver" || { red "version must be x.y.z: $ver"; return 2; }
  local root; root="$(resolve_root)" || { red "cannot locate zorskill root (set ZORSKILL_ROOT)"; return 1; }
  jq -e --arg n "$name" '.plugins[]|select(.name==$n)' "$root/.claude-plugin/marketplace.json" >/dev/null 2>&1 \
    || { red "not a registered plugin: $name"; return 1; }
  # Refuse a remote-sourced plugin BEFORE any git submodule op (prevents an orphan plugins/<name> gitlink).
  if ! _is_submodule "$root" "$name"; then
    red "✗ $name is remote-sourced ($(_remote_source_desc "$root" "$name")), not a submodule — release manages submodules only."
    red "  Edit its marketplace version by hand, or convert it to a submodule. (No submodule was created.)"
    return 1
  fi

  echo "▸ 1/5 advance submodule pointer"; advance_pointer "$root" "$name" || return 1
  local declared; declared="$(read_plugin_version "$root" "$name")"
  echo "▸ 2/5 verify plugin repo declares $ver"
  if [[ "$declared" != "$ver" ]]; then
    red "  ✗ plugins/$name declares '$declared', you asked for '$ver'."
    red "    Bump + push $name's own repo to $ver first, then re-run. (This tool never edits a plugin's repo.)"
    return 1
  fi
  echo "▸ 3/5 sync marketplace versions"; a="$(apply_release_versions "$root" "$name" "$ver" "$agg_override")" || return 1
  local sync_readme_done=0
  if [[ -f "$root/README.md" ]] && _readme_has_markers "$root/README.md"; then
    echo "▸ 3b/5 sync README roster"; sync_readme "$root" && sync_readme_done=1
  fi
  echo "▸ 4/5 validate (scoped to $name + repo-wide JSON; other plugins' drift is non-blocking)"
  check_release "$root" "$name" "$ver" || { red "check failed for target/JSON — aborting (files bumped; revert or fix)"; return 1; }
  echo "▸ 5/5 commit"
  git -C "$root" add "plugins/$name" ".claude-plugin/marketplace.json"
  [[ $sync_readme_done -eq 1 ]] && git -C "$root" add README.md
  git -C "$root" commit -q -m "zorskill: $name v$ver (marketplace $a)" || yellow "  (nothing to commit?)"
  if [[ $push -eq 1 ]]; then
    git -C "$root" push origin main && green "Released $name v$ver (marketplace $a) — pushed to main."
  else
    green "Released $name v$ver (marketplace $a) — committed locally."
    echo "  Push when ready:  git -C \"$root\" push origin main"
  fi
}

# Version declared at a plugin repo's tracked-branch TIP, read tolerantly (grep, not jq)
# so a version bump lands even when the rest of that commit's plugin.json is malformed —
# the strict check gate (check_json) then catches structural breakage and aborts.
_repo_tip_version(){ # $1 root, $2 name, $3 branch
  git -C "$1/plugins/$2" show "origin/$3:.claude-plugin/plugin.json" 2>/dev/null \
    | grep -oE '"version"[[:space:]]*:[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' | head -1 \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'
}

# Revert ONLY what drift touched (not `.`), so an abort never disturbs unrelated
# working-tree state (e.g. a locally-dirty sibling plugin).
# Scoped drift gate — like check_release, but over the DRIFTED SET. Hard-fails ONLY on:
#   (a) repo-wide JSON validity, (b) each drifted plugin's own consistency (plugin.json exists +
#   plugin.json == marketplace == carried-in version), (c) README roster sync (checkout-independent).
# Uninitialized/unreachable submodules the scan skipped, and other plugins' pre-existing drift, are
# NON-blocking warnings — so a public plugin carries in even while a private one is uninitialized.
check_drift_gate(){ # $1 root, $2 space-separated drifted names
  local root="$1" drifted="$2" rc=0 nm pj pjver rootver n s d
  echo "  • repo-wide JSON validity"
  if check_json "$root" >/dev/null 2>&1; then green "  ✓ JSON valid (repo-wide)"
  else red "  ✗ repo has invalid JSON — fix before committing:"; check_json "$root"; rc=1; fi
  echo "  • drifted plugin(s):$drifted"
  for nm in $drifted; do
    pj="$root/plugins/$nm/.claude-plugin/plugin.json"
    rootver="$(jq -r --arg n "$nm" '.plugins[]|select(.name==$n)|.version' "$root/.claude-plugin/marketplace.json")"
    if [[ ! -f "$pj" ]]; then red "  ✗ $nm: missing .claude-plugin/plugin.json"; rc=1; continue; fi
    pjver="$(jq -r '.version // ""' "$pj")"
    if [[ "$pjver" == "$rootver" ]] && is_semver "$rootver"; then green "  ✓ $nm @ $rootver (plugin.json == marketplace)"
    else red "  ✗ $nm version mismatch — plugin.json='$pjver' marketplace='$rootver'"; rc=1; fi
  done
  echo "  • README roster sync"; check_readme "$root" || rc=1
  # Non-blocking: note any plugin the scan skipped (remote-sourced, or uninitialized/unreachable).
  while IFS=$'\t' read -r n s; do
    case " $drifted " in *" $n "*) continue;; esac
    if ! _is_submodule "$root" "$n"; then yellow "  ⚠ $n: remote-sourced — not submodule-managed (non-blocking)"; continue; fi
    d="$root/plugins/$n"
    [[ ! -e "$d/.git" && ! -f "$d/.claude-plugin/plugin.json" ]] && yellow "  ⚠ $n: uninitialized/unreachable — not validated (non-blocking)"
  done < <(_plugins "$root")
  return $rc
}

_drift_revert(){ # $1 root, $2 space-separated drifted names
  local root="$1" nm
  git -C "$root" checkout -- .claude-plugin/marketplace.json 2>/dev/null || true
  [[ -f "$root/README.md" ]] && git -C "$root" checkout -- README.md 2>/dev/null || true
  for nm in $2; do
    git -C "$root" checkout -- "plugins/$nm" 2>/dev/null || true
    git -C "$root" -c protocol.file.allow=always submodule update --checkout "plugins/$nm" 2>/dev/null || true
  done
}

# drift — detect plugins whose OWN repo advanced to a new released version that was never
# carried into the marketplace, advance them, and (hard-gated on `check`) commit.
cmd_drift(){
  local push=0 dryrun=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --push) push=1;;
      --dry-run) dryrun=1;;
      *) red "unknown flag: $1"; return 2;;
    esac; shift
  done
  local root; root="$(resolve_root)" || { red "cannot locate zorskill root (set ZORSKILL_ROOT)"; return 1; }
  local name src sub br tipver curver drifted="" n=0 dr=""
  [[ $dryrun -eq 1 ]] && dr="(dry-run) "
  echo "▸ scanning ${dr}plugin repos for released-but-uncarried versions"
  while IFS=$'\t' read -r name src; do
    # Remote-sourced entries have no submodule to advance — never treat them as "missing submodule".
    if ! _is_submodule "$root" "$name"; then echo "  · $name: remote-sourced ($(_remote_source_desc "$root" "$name")) — not submodule-managed, skipped"; continue; fi
    sub="$root/plugins/$name"
    # Skip any submodule that isn't a usable git checkout here (uninitialized) OR whose remote
    # can't be fetched (private without a token / offline). General — no per-plugin special-casing.
    # The scheduled Action deliberately leaves private repos uninitialized; those are carried in
    # manually via `/zorskill-dev:release`. Non-fatal: not counted as drift, nothing mutated.
    if [[ ! -e "$sub/.git" ]] || ! git -C "$sub" rev-parse --git-dir >/dev/null 2>&1 \
       || ! git -C "$sub" -c protocol.file.allow=always fetch --quiet origin 2>/dev/null; then
      yellow "  ⚠ $name: submodule not initialized or unreachable — skipped"; continue
    fi
    br="$(_sub_branch "$root" "$name")"
    tipver="$(_repo_tip_version "$root" "$name" "$br")"
    curver="$(jq -r --arg n "$name" '.plugins[]|select(.name==$n)|.version' "$root/.claude-plugin/marketplace.json")"
    if is_semver "$tipver" && is_semver "$curver" && _semver_gt "$curver" "$tipver"; then
      # BEHIND: repo tip is older than the marketplace (revert/force-push, or marketplace manually
      # ahead). Forward-only — never downgrade. Warn, change nothing, do not count as drift.
      yellow "  ⚠ $name: repo tip $tipver is BEHIND marketplace $curver — possible revert/force-push; left unchanged, review manually"
    elif is_semver "$tipver" && _semver_gt "$tipver" "$curver"; then
      echo "  • $name: marketplace=$curver  repo-tip=$tipver  → DRIFT"
      drifted="$drifted $name"; n=$((n+1))
      if [[ $dryrun -eq 0 ]]; then
        if ! { git -C "$sub" checkout --quiet "origin/$br" 2>/dev/null || git -C "$sub" checkout --quiet "$br"; }; then
          red "  ✗ $name: checkout failed — reverting, committing nothing"; _drift_revert "$root" "$drifted"; return 1
        fi
        local tmp; tmp="$(mktemp)"
        jq --arg n "$name" --arg v "$tipver" '(.plugins[]|select(.name==$n)|.version)=$v' "$root/.claude-plugin/marketplace.json" > "$tmp" && mv "$tmp" "$root/.claude-plugin/marketplace.json"
      fi
    else
      echo "  • $name: marketplace=$curver  repo-tip=${tipver:-<unreadable>}  ok"
    fi
  done < <(_plugins "$root")

  if [[ $n -eq 0 ]]; then green "✓ no drift — all pointers current"; return 0; fi
  local names; names="$(echo $drifted | sed 's/ /, /g')"
  if [[ $dryrun -eq 1 ]]; then yellow "dry-run: $n plugin(s) would advance: $names (nothing changed)"; return 0; fi

  local cur agg tmp; cur="$(jq -r '.version' "$root/.claude-plugin/marketplace.json")"; agg="$(_bump_patch "$cur")"
  tmp="$(mktemp)"; jq --arg a "$agg" '.version=$a' "$root/.claude-plugin/marketplace.json" > "$tmp" && mv "$tmp" "$root/.claude-plugin/marketplace.json"
  [[ -f "$root/README.md" ]] && _readme_has_markers "$root/README.md" && sync_readme "$root" >/dev/null
  echo "▸ validate (scoped gate — drifted plugins + repo-wide JSON + README; uninitialized/other plugins non-blocking)"
  if ! check_drift_gate "$root" "$drifted"; then
    local bad="" nm
    for nm in $drifted; do jq -e . "$root/plugins/$nm/.claude-plugin/plugin.json" >/dev/null 2>&1 || bad="$bad $nm"; done
    red "✗ drift ABORTED — gate FAILED. Structurally broken tip(s):${bad:- (see the ✗ line(s) above)} (drifted set:$drifted). Reverting, committing nothing."
    _drift_revert "$root" "$drifted"
    return 1
  fi
  echo "▸ commit"
  for name in $drifted; do git -C "$root" add "plugins/$name"; done
  git -C "$root" add ".claude-plugin/marketplace.json"
  [[ -f "$root/README.md" ]] && _readme_has_markers "$root/README.md" && git -C "$root" add README.md
  git -C "$root" commit -q -m "chore(drift): advance $names to their released versions (marketplace $agg)"
  if [[ $push -eq 1 ]]; then
    git -C "$root" push origin main && green "Drift resolved: $names (marketplace $agg) — pushed to main."
  else
    green "Drift resolved: $names (marketplace $agg) — committed locally."
    echo "  Push when ready:  git -C \"$root\" push origin main"
  fi
}

render_template(){
  local tmpl="$1" name="$2" desc="$3"
  # sed with a safe delimiter; escape & and the delimiter in the replacement.
  local ename edesc
  ename="$(printf '%s' "$name" | sed 's/[&|]/\\&/g')"
  edesc="$(printf '%s' "$desc" | sed 's/[&|]/\\&/g')"
  sed -e "s|{{NAME}}|$ename|g" -e "s|{{DESCRIPTION}}|$edesc|g" "$tmpl"
}

_script_dir(){ cd "$(dirname "${BASH_SOURCE[0]}")" && pwd; }

cmd_new(){
  local name="${1:-}" url="" desc="" create=0 allow_private=0
  [[ -n "$name" ]] || { red "usage: new <name> [--repo-url URL] [--create-remote] [--allow-private] [--description TEXT]"; return 2; }
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo-url) url="${2:-}"; shift;;
      --create-remote) create=1;;
      --allow-private) allow_private=1;;
      --description) desc="${2:-}"; shift;;
      *) red "unknown flag: $1"; return 2;;
    esac; shift
  done
  local root; root="$(resolve_root)" || { red "cannot locate zorskill root (set ZORSKILL_ROOT)"; return 1; }
  if jq -e --arg n "$name" '.plugins[]|select(.name==$n)' "$root/.claude-plugin/marketplace.json" >/dev/null 2>&1; then
    if _is_submodule "$root" "$name"; then red "plugin already registered: $name"
    else red "$name is already registered as a REMOTE source ($(_remote_source_desc "$root" "$name")), not a submodule — new/release manage submodules only. (No submodule was created.)"; fi
    return 1
  fi
  [[ -n "$url" ]] || url="https://github.com/ZorCorp/$name.git"
  [[ -n "$desc" ]] || desc="TODO one-line description of $name"

  if [[ $create -eq 1 ]]; then
    yellow "  --create-remote will run: gh repo create ZorCorp/$name --public"
    command -v gh >/dev/null 2>&1 || { red "gh not installed"; return 1; }
    gh repo create "ZorCorp/$name" --public || return 1
  fi

  # Guardrail: refuse a CONFIRMED-private repo (breaks `/plugin marketplace add` for end users),
  # unless --allow-private. Best-effort: gh absent / API failure → proceed (don't block on network).
  if [[ $allow_private -eq 0 && $create -eq 0 ]] && _have_gh; then
    local vis; vis="$(_repo_visibility "$(_repo_label "$url")" || true)"
    if [[ "$vis" == "private" ]]; then
      red "✗ $name: $(_repo_label "$url") is PRIVATE — a private plugin repo breaks \`/plugin marketplace add\`"
      red "  for every end user (Claude Code recursively clones each plugin submodule and 404s on it)."
      red "  Make the repo public, or pass --allow-private to add it to a private marketplace anyway."
      return 1
    fi
  fi

  local sub="$root/plugins/$name"
  echo "▸ add submodule"
  if ! git -C "$root" -c protocol.file.allow=always submodule add "$url" "plugins/$name"; then
    # An empty upstream repo has no commit to check out, so `submodule add` cannot
    # complete the gitlink (the clone still lands on disk). Register .gitmodules and
    # fall through to scaffolding; the human commits+pushes the plugin repo, after
    # which the pointer is recorded via /zorskill-dev:release.
    if [[ -e "$sub/.git" ]]; then
      git -C "$root" config -f "$root/.gitmodules" "submodule.plugins/$name.path" "plugins/$name"
      git -C "$root" config -f "$root/.gitmodules" "submodule.plugins/$name.url"  "$url"
      yellow "  ⚠ upstream $name is empty — scaffolded locally (pointer recorded later via release)."
    else
      red "submodule add failed: $name"; return 1
    fi
  fi

  local tdir; tdir="$(_script_dir)/../templates"
  if [[ ! -f "$sub/.claude-plugin/plugin.json" ]]; then
    echo "▸ scaffold plugin.json + SKILL.md (uncommitted in plugins/$name — push them from its own repo)"
    mkdir -p "$sub/.claude-plugin"
    render_template "$tdir/plugin.json.tmpl" "$name" "$desc" > "$sub/.claude-plugin/plugin.json"
    render_template "$tdir/SKILL.md.tmpl"   "$name" "$desc" > "$sub/SKILL.md"
  fi
  # Drop the tag-driven Release workflow into the plugin's own repo (uncommitted, like the
  # scaffolds above — the user commits+pushes it to ZorCorp/$name). Static template, no subst.
  if [[ ! -f "$sub/.github/workflows/release.yml" ]]; then
    echo "▸ scaffold .github/workflows/release.yml (uncommitted in plugins/$name — push it from its own repo)"
    mkdir -p "$sub/.github/workflows"
    cp "$tdir/release.yml" "$sub/.github/workflows/release.yml"
  fi
  # CLAUDE.md release rule — managed block, idempotent + NON-clobbering.
  local cmf="$sub/CLAUDE.md" blk="$tdir/claude-release-block.md"
  if [[ ! -f "$cmf" ]]; then
    echo "▸ scaffold CLAUDE.md release rule (uncommitted in plugins/$name — push it from its own repo)"
    cp "$blk" "$cmf"
  elif ! grep -qF "<!-- BEGIN zorskill-release" "$cmf"; then
    echo "▸ append CLAUDE.md release rule (preserving existing CLAUDE.md; push it from its own repo)"
    [[ -n "$(tail -c1 "$cmf")" ]] && printf '\n' >> "$cmf"   # ensure trailing newline
    printf '\n' >> "$cmf"; cat "$blk" >> "$cmf"               # blank-line separator + block
  fi
  # else: CLAUDE.md already carries the managed block — leave it untouched.

  echo "▸ register in root marketplace.json + bump aggregate"
  local cur agg tmp mf="$root/.claude-plugin/marketplace.json"
  cur="$(jq -r '.version' "$mf")"; agg="$(_bump_patch "$cur")"
  tmp=$(mktemp)
  jq --arg n "$name" --arg d "$desc" --arg a "$agg" \
    '.version=$a | .plugins += [{"name":$n,"description":$d,"version":"0.1.0","author":{"name":"ZorCorp","url":"https://github.com/ZorCorp"},"source":("./plugins/"+$n),"category":"productivity"}]' \
    "$mf" > "$tmp" && mv "$tmp" "$mf"

  if [[ -f "$root/README.md" ]] && _readme_has_markers "$root/README.md"; then
    echo "▸ sync README roster"; sync_readme "$root" && git -C "$root" add README.md
  fi

  git -C "$root" add "$root/.gitmodules" ".claude-plugin/marketplace.json" 2>/dev/null
  # Stage the gitlink only if the submodule has a commit checked out (empty upstreams don't).
  if git -C "$sub" rev-parse HEAD >/dev/null 2>&1; then git -C "$root" add "plugins/$name"; fi
  green "Scaffolded $name (marketplace $agg). Next:"
  echo "  1. Fill plugins/$name/SKILL.md + plugin.json + .github/workflows/release.yml + CLAUDE.md"
  echo "     (release rule), then commit+push all of them to ZorCorp/$name."
  echo "  2. In zorskill: git commit -m 'Add $name plugin' (already staged)."
  echo "  3. Release updates from the plugin repo:  gh workflow run release.yml -f version=<x.y.z>"
  echo "     (the drift Action carries it into the marketplace within ~30 min), or instantly"
  echo "     with:  /zorskill-dev:release $name <x.y.z>"
}

# ... (functions added in later tasks) ...

main(){
  case "${1:-check}" in
    check)   shift; cmd_check "$@";;
    release) shift; cmd_release "$@";;
    new)     shift; cmd_new "$@";;
    sync)    shift; cmd_sync "$@";;
    drift)   shift; cmd_drift "$@";;
    *) echo "usage: $0 {check|release <name> <x.y.z> [--push]|new <name> [--repo-url URL] [--create-remote]|sync|drift [--push] [--dry-run]}"; exit 2;;
  esac
}

# `source zorskill-dev.sh --lib` loads functions for tests without running main.
if [[ "${1:-}" != "--lib" ]]; then main "$@"; fi
