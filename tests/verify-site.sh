#!/usr/bin/env bash
# Builds the site into a temp dir and checks the built output.
# Usage: tests/verify-site.sh [check ...]   (default: all checks)
# Never writes to the repo's public/ or resources/ (builds a copy).
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

BASE_URL="https://moshalan.dev"
POSITIONING="Senior mobile engineer helping teams adopt AI agents safely."
DOOR1="Hiring a senior or lead mobile engineer?"
DOOR2="Bringing AI agents into your mobile team?"
EMAIL="mohamed.sh3lan.93@gmail.com"
LINKEDIN="https://www.linkedin.com/in/mohamedsh3lan93/"
NAV_EXPECTED="/posts/ /projects/ /work-with-me/ /about/"
ALL_CHECKS="urls og home case_study_toggle mermaid posthog meta no_old_email no_dead_links pages rss no_internal_notes resume analytics work_with_me"

FAILS=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1: $2"; FAILS=$((FAILS + 1)); }

copy_site() { # copy_site <dest>
  mkdir -p "$1"
  rsync -a --exclude .git --exclude public --exclude resources \
    --exclude .superpowers --exclude docs "$ROOT/" "$1/"
}

build() { # build <srcdir> <outdir>
  (cd "$1" && hugo --gc --minify -e production -d "$2" --cacheDir "$TMP/cache" --logLevel error) >"$TMP/build.log" 2>&1
}

# Decode the HTML entities Hugo/minify emit for our copy.
text() { sed -e "s/&#39;/'/g; s/&rsquo;/'/g; s/&#x27;/'/g; s/&amp;/\&/g; s/&#43;/+/g; s/&middot;/·/g" "$1"; }

path_file() { # map a URL path to a file in $2
  local p=${1#"$BASE_URL"}
  [[ $p == */ ]] && p="${p}index.html"
  echo "$2$p"
}

is_alias() { grep -q 'http-equiv=\(refresh\|"refresh"\)' "$1"; }

og_image() { grep -oE 'property="?og:image"? content="?[^" >]+' "$1" | head -1 | sed -E 's/.*content="?//'; }

img_dims() { # prints "W H"
  if command -v sips >/dev/null 2>&1; then
    sips -g pixelWidth -g pixelHeight "$1" 2>/dev/null | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w, h}'
  else
    file "$1" | grep -oE '[0-9]+ ?x ?[0-9]+' | head -1 | tr -d ' ' | tr 'x' ' '
  fi
}

check_urls() {
  local missing=() p
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    [ -f "$(path_file "$p" "$OUT")" ] || missing+=("$p")
  done <"$ROOT/tests/baseline-urls.txt"
  if [ ${#missing[@]} -eq 0 ]; then pass urls; else fail urls "missing ${missing[*]}"; fi
}

check_og() {
  local bad=() f img
  while IFS= read -r f; do
    is_alias "$f" && continue
    img=$(og_image "$f")
    if [ -z "$img" ]; then bad+=("${f#"$OUT"}(none)"); continue; fi
    [ -f "$(path_file "$img" "$OUT")" ] || bad+=("${f#"$OUT"}->$img")
  done < <(find "$OUT" -name index.html)
  local home
  home=$(og_image "$OUT/index.html")
  [ "$home" = "$BASE_URL/images/og-default.png" ] || bad+=("home og:image is '$home'")
  if [ -f "$OUT/images/og-default.png" ]; then
    [ "$(img_dims "$OUT/images/og-default.png")" = "1200 630" ] || bad+=("og-default.png not 1200x630")
  fi
  if [ ${#bad[@]} -eq 0 ]; then pass og; else fail og "${bad[*]}"; fi
}

check_home() {
  local h="$TMP/home.txt" s miss=()
  text "$OUT/index.html" >"$h"
  for s in "$POSITIONING" "$DOOR1" "$DOOR2"; do grep -qF "$s" "$h" || miss+=("'$s'"); done
  if [ ${#miss[@]} -eq 0 ]; then pass home; else fail home "not in raw HTML: ${miss[*]}"; fi
}

has_case_study() { grep -qE 'data-proof="?case-study' "$1"; }

check_case_study_toggle() {
  if has_case_study "$OUT/index.html"; then fail case_study_toggle "rendered without any caseStudy post"; return; fi
  local s="$TMP/site-cs" o="$TMP/out-cs"
  copy_site "$s"
  cp "$ROOT/tests/fixtures/case-study.md" "$s/content/posts/fixture-case-study.md"
  if ! build "$s" "$o"; then fail case_study_toggle "fixture build failed"; return; fi
  if has_case_study "$o/index.html" && grep -qE 'data-proof="?case-study"?[^>]*href="?[^" >]*/posts/fixture-case-study/|href="?[^" >]*/posts/fixture-case-study/"?[^>]*data-proof="?case-study' "$o/index.html"; then
    pass case_study_toggle
  else
    fail case_study_toggle "fixture caseStudy post not linked with data-proof=case-study"
  fi
}

check_mermaid() {
  local m="$OUT/posts/code-review-in-ai-era/index.html" n="$OUT/posts/my-ai-news-feed/index.html" bad=()
  grep -qE 'class="?mermaid' "$m" || bad+=("no mermaid block")
  grep -q 'mermaid.esm.min.mjs' "$m" || bad+=("mermaid script not loaded")
  grep -q 'mermaid.esm.min.mjs' "$n" && bad+=("mermaid loaded on a post without diagrams")
  if [ ${#bad[@]} -eq 0 ]; then pass mermaid; else fail mermaid "${bad[*]}"; fi
}

KOUT="$TMP/out-ph"
keyed_build() { # build once with a dummy PostHog key, the way CI injects the real one
  [ -f "$KOUT/index.html" ] && return 0
  local s="$TMP/site-ph"
  copy_site "$s"
  perl -pi -e 's/apiKey = ""/apiKey = "phc_test"/' "$s/hugo.toml"
  grep -q 'apiKey = "phc_test"' "$s/hugo.toml" || return 2
  build "$s" "$KOUT"
}

check_posthog() {
  if grep -rq 'posthog.init' "$OUT"; then fail posthog "loaded without an API key"; return; fi
  keyed_build; case $? in 0) ;; 2) fail posthog "CI key substitution did not match hugo.toml"; return ;; *) fail posthog "keyed build failed"; return ;; esac
  local o="$KOUT"
  grep -qE "posthog\.init\(['\"]phc_test['\"]" "$o/index.html" || { fail posthog "posthog.init('phc_test' missing"; return; }
  # page views must be captured (the minifier may print true as !0)
  if grep -qE "capture_pageview: ?(true|!0)" "$o/index.html"; then pass posthog; else fail posthog "capture_pageview is not true"; fi
}

check_analytics() {
  local bad=() post
  node --test "$ROOT/tests/" >"$TMP/node.log" 2>&1 || bad+=("unit tests failed (see node --test tests/)")
  grep -rqE 'js/analytics[^"]*\.js' "$OUT" && bad+=("analytics script loads without an API key")
  if keyed_build; then
    grep -qE 'src="?/js/analytics[^" >]*\.js' "$KOUT/index.html" || bad+=("analytics script missing on home")
    post="$KOUT/posts/code-review-in-ai-era/index.html"
    grep -qE 'id="?article-meta' "$post" || bad+=("article meta missing on a post")
    grep -qE 'id="?article-meta' "$KOUT/work-with-me/index.html" && bad+=("article meta on a non-post page")
  else bad+=("keyed build failed"); fi
  if [ ${#bad[@]} -eq 0 ]; then pass analytics; else fail analytics "${bad[*]}"; fi
}

check_meta() {
  local h="$TMP/meta.txt" bad=() nav
  text "$OUT/index.html" >"$h"
  grep -oE '<title>[^<]*' "$h" | grep -q 'Senior mobile engineer' || bad+=("title")
  grep -oE 'property="?og:description"? content="[^"]*' "$h" | grep -q 'Senior mobile engineer' || bad+=("og:description")
  nav=$(sed -n 's/.*id="\{0,1\}menu"\{0,1\}[^>]*>\(.*\)/\1/p' "$h" | sed 's#</ul>.*##' |
    grep -oE 'href="?[^" >]+' | sed -E 's/href="?//; s#^'"$BASE_URL"'##' | tr '\n' ' ' | sed 's/ $//')
  [ "$nav" = "$NAV_EXPECTED" ] || bad+=("nav is '$nav'")
  if [ ${#bad[@]} -eq 0 ]; then pass meta; else fail meta "${bad[*]}"; fi
}

check_no_old_email() {
  local hits
  hits=$(grep -rl 'outlook.com' "$OUT" | sed "s#^$OUT##" | tr '\n' ' ')
  if [ -z "$hits" ]; then pass no_old_email; else fail no_old_email "found in $hits"; fi
}

check_no_dead_links() {
  local f bad=()
  for f in "$OUT/index.html" "$OUT/work-with-me/index.html" "$OUT/experience/index.html"; do
    [ -f "$f" ] || continue
    grep -qE 'href=(""|"#"|#[ >])' "$f" && bad+=("${f#"$OUT"}")
  done
  if [ ${#bad[@]} -eq 0 ]; then pass no_dead_links; else fail no_dead_links "empty/# href in ${bad[*]}"; fi
}

check_pages() {
  local p bad=()
  for p in work-with-me experience projects; do [ -f "$OUT/$p/index.html" ] || bad+=("/$p/ missing"); done
  [ -f "$OUT/work-with-me/index.html" ] && ! grep -q "$EMAIL" "$OUT/work-with-me/index.html" && bad+=("email not on work-with-me")
  [ -f "$OUT/experience/index.html" ] && ! grep -q "$LINKEDIN" "$OUT/experience/index.html" && bad+=("LinkedIn not on experience")
  if [ ${#bad[@]} -eq 0 ]; then pass pages; else fail pages "${bad[*]}"; fi
}

check_rss() {
  local bad=() f link
  # feed items must be posts only (no About/Experience/Projects/Work with me)
  while IFS= read -r link; do
    case "$link" in "$BASE_URL/posts/"*) ;; *) bad+=("feed item $link") ;; esac
  done < <(sed -n "s#.*<item>.*<link>\([^<]*\)</link>.*#\1#p" <(tr -d "\n" <"$OUT/index.xml" | sed "s#<item>#\n<item>#g"))
  f=$(grep -rl "0001-01-01\|01 Jan 0001" "$OUT" | sed "s#^$OUT##" | tr "\n" " ")
  [ -n "$f" ] && bad+=("year-1 dates in $f")
  if [ ${#bad[@]} -eq 0 ]; then pass rss; else fail rss "${bad[*]}"; fi
}

check_no_internal_notes() {
  local f
  f=$(grep -rlE "DRAFT|data/[a-z]+\.yaml" "$OUT" | sed "s#^$OUT##" | tr "\n" " ")
  if [ -z "$f" ]; then pass no_internal_notes; else fail no_internal_notes "internal notes published in $f"; fi
}

# Cut-over gate (spec: one switch-over only after owner inputs). Not in the default set;
# CI runs it explicitly so main cannot deploy a half-finished site.
check_resume() {
  # Public resume: must exist, be published, and carry only public data.
  local src="$ROOT/assets/resume/resume.html" pdf="$ROOT/static/resume.pdf" bad=() t
  [ -f "$src" ] || bad+=("assets/resume/resume.html missing")
  [ -f "$pdf" ] || bad+=("static/resume.pdf missing")
  [ -f "$OUT/resume.pdf" ] || bad+=("/resume.pdf not published")
  t="$TMP/resume.txt"; : >"$t"
  [ -f "$src" ] && sed 's/<[^>]*>//g' "$src" >>"$t"
  if [ -f "$pdf" ] && command -v pdftotext >/dev/null; then pdftotext "$pdf" - >>"$t"; fi
  grep -qiE '\+971|outlook\.com|nationality|visa status|plaintext' "$t" && bad+=("private text: $(grep -oiE '\+971|outlook\.com|nationality|visa status|plaintext' "$t" | sort -u | tr '\n' ',')")
  [ -s "$t" ] && ! grep -q "$EMAIL" "$t" && bad+=("public email missing")
  # headline is mobile, not Android-only (an older role may still be titled Android)
  [ -f "$src" ] && ! grep -q 'class="headline">Senior Mobile Software Engineer<' "$src" && bad+=("headline is not Senior Mobile Software Engineer")
  if [ ${#bad[@]} -eq 0 ]; then pass resume; else fail resume "${bad[*]}"; fi
}

check_work_with_me() {
  # Layout "C with A's headline": tap-to-open services, numbers, 3 steps (audit optional), phone booking bar.
  local h="$TMP/wwm.txt" bad=() n bar
  text "$OUT/work-with-me/index.html" >"$h"
  grep -q "Let's make that safe." "$h" || bad+=("headline missing")
  n=$(grep -oE '<details[^>]*data-service=' "$h" | wc -l | tr -d ' ')
  [ "$n" = 2 ] || bad+=("expected 2 tap-to-open services, found $n")
  [ "$(grep -oE '<summary' "$h" | wc -l | tr -d ' ')" -ge 2 ] || bad+=("service summaries missing")
  for v in "10M+" "20+"; do grep -q "class=\"\{0,1\}brand-stat__value\"\{0,1\}>$v<" "$h" || bad+=("stat $v missing"); done
  [ "$(grep -oE 'class="?brand-step[ ">]' "$h" | wc -l | tr -d ' ')" = 3 ] || bad+=("expected 3 steps")
  grep -qE 'data-optional' "$h" || bad+=("no step marked optional")
  bar=$(grep -oE '<div class="?brand-sticky.*' "$h" | sed 's#</div>.*##')
  echo "$bar" | grep -q 'cal.com' || bad+=("booking bar has no Cal.com link")
  echo "$bar" | grep -q "mailto:$EMAIL" || bad+=("booking bar has no email link")
  if [ ${#bad[@]} -eq 0 ]; then pass work_with_me; else fail work_with_me "${bad[*]}"; fi
}

check_cutover() {
  local bad=()
  grep -qE "^roles: *\[\]" "$ROOT/data/experience.yaml" && bad+=("experience roles empty")
  grep -qE "^ *resumePDF = \"\"" "$ROOT/hugo.toml" && bad+=("resumePDF empty")
  grep -qE "^ *calcomURL = \"\"" "$ROOT/hugo.toml" && bad+=("calcomURL empty")
  local d; d=$(grep -rl "DRAFT" "$ROOT/content" "$ROOT/data" | sed "s#^$ROOT/##" | tr "\n" " ")
  [ -n "$d" ] && bad+=("DRAFT markers in $d")
  if [ ${#bad[@]} -eq 0 ]; then pass cutover; else fail cutover "${bad[*]}"; fi
}

CHECKS=${*:-$ALL_CHECKS}
SITE="$TMP/site"
OUT="$TMP/out"
copy_site "$SITE"
if ! build "$SITE" "$OUT"; then
  echo "FAIL build: hugo failed"
  cat "$TMP/build.log"
  exit 1
fi
for c in $CHECKS; do "check_$c"; done
echo "---"
echo "$FAILS check(s) failed"
[ "$FAILS" -eq 0 ]
