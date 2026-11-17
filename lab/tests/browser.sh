#!/usr/bin/env bash
# Question: can an agent use a browser on this machine, outside and inside
# the agent sandbox? Inside, does the website list still apply, and does the
# browser exit by itself when the work is done?
#
# A small Playwright script opens a page, reads its title, takes a screenshot
# and closes the browser. It runs in six situations. Writes
# data/runs/<time>-browser/: result.json and, if the page loaded inside the
# sandbox, inside-sandbox.png.
#
# Chromium has a sandbox of its own (the "inner" one). Playwright switches it
# off by default on Linux; both settings are tried.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

readonly TEST_NAME="browser"
readonly QUESTION="Can an agent drive a browser outside and inside the sandbox, with the website list applied and a clean exit?"
readonly LAB_SCREENSHOT="/var/tmp/browser-inside-sandbox.png"

measure() {
  cat <<'IN_LAB'
readonly PROJECT="$HOME/t/browser-test"
readonly ALLOWED_SITE="https://example.com"
readonly UNLISTED_SITE="https://www.wikipedia.org"
readonly CASE_TIMEOUT_SECONDS=75
readonly BROWSER_PROCESS='headless_shell|chrome-headless-shell|chrome_crashpad'
readonly SCREENSHOT_COPY="/var/tmp/browser-inside-sandbox.png"

rm -rf "$PROJECT" "$SCREENSHOT_COPY" && mkdir -p "$PROJECT" && cd "$PROJECT"

cat >drive.mjs <<'SCRIPT'
// Usage: node drive.mjs <url> <inner sandbox: on|off> <screenshot file> <result file> [proxy: split|address-only]
import { writeFileSync } from 'node:fs';
import { chromium } from 'playwright';

const NAVIGATION_TIMEOUT_MS = 20000;
const [url, innerSandbox, screenshotFile, resultFile, proxyMode = 'split'] = process.argv.slice(2);
const started = Date.now();
const result = { loaded: false, title: null, error: null };

// The sandbox announces its proxy as http://user:password@host:port. Chromium
// ignores a user and password written inside the address, so they have to be
// handed over separately ("split"). "address-only" passes the address as it
// is, to record that this does not work.
function proxySettings() {
  const address = process.env.HTTPS_PROXY || process.env.https_proxy;
  if (!address) return {};
  if (proxyMode !== 'split') return { proxy: { server: address } };
  const parsed = new URL(address);
  return {
    proxy: {
      server: `${parsed.protocol}//${parsed.host}`,
      username: decodeURIComponent(parsed.username),
      password: decodeURIComponent(parsed.password),
    },
  };
}

let browser;
try {
  browser = await chromium.launch({
    headless: true,
    chromiumSandbox: innerSandbox === 'on',
    ...proxySettings(),
  });
  const page = await browser.newPage();
  await page.goto(url, { timeout: NAVIGATION_TIMEOUT_MS, waitUntil: 'domcontentloaded' });
  result.title = await page.title();
  await page.screenshot({ path: screenshotFile });
  result.loaded = true;
} catch (error) {
  result.error = String(error.message).split('\n')[0].slice(0, 200);
} finally {
  if (browser) await browser.close().catch(() => {});
}
result.ms = Date.now() - started;
writeFileSync(resultFile, JSON.stringify(result));
SCRIPT

install_started=$(date +%s)
npm init -y >/dev/null 2>&1
npm install --silent playwright >/dev/null 2>&1
fact playwright_installed "$(yes_no test -d node_modules/playwright)"
npx playwright install --with-deps chromium-headless-shell >/var/tmp/browser-install.log 2>&1
fact browser_installed "$(yes_no sh -c 'ls ~/.cache/ms-playwright | grep -q chromium')"
fact install_seconds "$(( $(date +%s) - install_started ))"
fact browser_download_mb "$(du -sm ~/.cache/ms-playwright 2>/dev/null | cut -f1)"
fact playwright_version "$(node -p "require('./node_modules/playwright/package.json').version" 2>/dev/null)"

printf '{"network":{"allowedDomains":["example.com"],"deniedDomains":[]},"filesystem":{"denyRead":[],"allowWrite":[".","/tmp"],"denyWrite":[]}}\n' >sandbox.json
field() { python3 -c 'import json, sys
try:
    value = json.load(open(sys.argv[1])).get(sys.argv[2])
except (OSError, ValueError):
    value = None
print("" if value is None else str(value).lower() if isinstance(value, bool) else value)' "$1" "$2"; }
browser_processes() { pgrep -f "$BROWSER_PROCESS" 2>/dev/null | wc -l; }

# run_case <name> <where: outside|inside> <url> <inner sandbox: on|off> [proxy: split|address-only]
run_case() {
  local name="$1" where="$2" url="$3" inner="$4" proxy="${5:-split}" status=0
  local command="node drive.mjs $url $inner $name.png $name.json $proxy"
  rm -f "$name.json" "$name.png"
  if [[ "$where" == inside ]]; then
    # The sandbox sets TMPDIR to a directory that does not exist until something
    # creates it; Playwright fails at launch without it.
    timeout "$CASE_TIMEOUT_SECONDS" /usr/bin/node /usr/local/bin/srt --settings sandbox.json -c 'mkdir -p "${TMPDIR:-/tmp}" && '"$command" >"$name.log" 2>&1 || status=$?
  else
    timeout "$CASE_TIMEOUT_SECONDS" bash -c "$command" >"$name.log" 2>&1 || status=$?
  fi
  fact "${name}_page_loaded" "$(field "$name.json" loaded)"
  fact "${name}_milliseconds" "$(field "$name.json" ms)"
  fact "${name}_exited_by_itself" "$([[ $status -ne 124 ]] && echo true || echo false)"
  fact "${name}_browser_processes_left" "$(browser_processes)"
  fact "${name}_error" "$(field "$name.json" error)"
  pkill -f "$BROWSER_PROCESS" 2>/dev/null
  return 0
}

in_sandbox() { /usr/bin/node /usr/local/bin/srt --settings sandbox.json -c "$1" 2>/dev/null; }
# /tmp is on disk, so a directory left by an earlier run would still be there.
# Remove it to see what a first run finds.
readonly SANDBOX_TMPDIR="$(in_sandbox 'echo "$TMPDIR"')"
[[ "$SANDBOX_TMPDIR" == /tmp/* ]] && rm -rf "$SANDBOX_TMPDIR"
fact sandbox_temporary_directory "$SANDBOX_TMPDIR"
fact sandbox_temporary_directory_exists_at_start "$(yes_no in_sandbox 'test -d "$TMPDIR"')"

run_case outside_inner_off outside "$ALLOWED_SITE" off
run_case outside_inner_on outside "$ALLOWED_SITE" on
run_case inside_inner_off_listed_site inside "$ALLOWED_SITE" off
run_case inside_inner_on_listed_site inside "$ALLOWED_SITE" on
run_case inside_inner_off_unlisted_site inside "$UNLISTED_SITE" off
run_case inside_proxy_address_only_listed_site inside "$ALLOWED_SITE" off address-only
run_case outside_unlisted_site_control outside "$UNLISTED_SITE" off

fact inside_page_title "$(field inside_inner_off_listed_site.json title)"
[[ -s inside_inner_off_listed_site.png ]] && cp inside_inner_off_listed_site.png "$SCREENSHOT_COPY"
fact inside_screenshot_bytes "$(stat -c %s inside_inner_off_listed_site.png 2>/dev/null || echo 0)"
IN_LAB
}

save_screenshot() {
  local run_dir="$TEST_REPO_DIR/data/runs/$TEST_RUN_STAMP-$TEST_NAME"
  if wsl.exe -d "$TEST_LAB_NAME" --cd / -- cat "$LAB_SCREENSHOT" </dev/null >"$run_dir/inside-sandbox.png" 2>/dev/null && [[ -s "$run_dir/inside-sandbox.png" ]]; then
    echo "screenshot: data/runs/$TEST_RUN_STAMP-$TEST_NAME/inside-sandbox.png"
  else
    rm -f "$run_dir/inside-sandbox.png"
  fi
}

main() {
  reset_facts
  as_user measure
  write_test_record "$TEST_NAME" "$QUESTION"
  save_screenshot
}

main "$@"
