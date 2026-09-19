#!/usr/bin/env bash
set -euo pipefail

ORIGINAL_SHA="$(git rev-parse HEAD)"
RUN_ID="${GITHUB_RUN_ID:-manual}"
BACKUP_BRANCH="backup/pre-upstream-sync-${RUN_ID}"

rm -rf /tmp/current-workflows
mkdir -p /tmp/current-workflows
cp -R .github/workflows/. /tmp/current-workflows/
cp scripts/sync-upstream-once.sh /tmp/sync-upstream-once.sh

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

git branch "$BACKUP_BRANCH" "$ORIGINAL_SHA"
git push origin "$BACKUP_BRANCH"

git remote remove upstream 2>/dev/null || true
git remote add upstream https://github.com/alam00000/bentopdf.git
git fetch upstream main

# Apply the latest upstream tree as one squashed update on top of this fork.
# This preserves our branch history and avoids importing upstream workflow
# commits that GitHub Actions is not permitted to push.
git read-tree --reset -u upstream/main

# Keep this fork's existing GitHub Actions definitions unchanged.
rm -rf .github/workflows
mkdir -p .github/workflows
cp -R /tmp/current-workflows/. .github/workflows/

mkdir -p scripts
cp /tmp/sync-upstream-once.sh scripts/sync-upstream-once.sh
chmod +x scripts/sync-upstream-once.sh

python3 <<'PY'
from pathlib import Path

def replace_once(path, old, new, label):
    p = Path(path)
    s = p.read_text()
    if old not in s:
        raise SystemExit(f"{label}: expected source text not found in {path}")
    p.write_text(s.replace(old, new, 1))

replace_once(
    "src/js/i18n/i18n.ts",
    "'zh-TW': '繁體中文（台灣）'",
    "'zh-TW': '繁體中文'",
    "zh-TW label",
)

replace_once(
    "src/partials/navbar.html",
    '      <div class="hidden lg:flex items-center flex-shrink-0">\n        <a',
    '      <div class="hidden lg:flex items-center flex-shrink-0 gap-2">\n'
    '        <div id="navbar-language-switcher" class="flex items-center"></div>\n'
    '        <a',
    "desktop navbar mount",
)

replace_once(
    "src/partials/navbar.html",
    '      <div class="lg:hidden flex items-center gap-4">\n        <a',
    '      <div class="lg:hidden flex items-center gap-2">\n'
    '        <div id="mobile-navbar-language-switcher" class="flex items-center"></div>\n'
    '        <a',
    "mobile navbar mount",
)

replace_once(
    "src/partials/navbar-simple.html",
    '    <div class="flex justify-start items-center h-16">',
    '    <div class="flex justify-between items-center h-16">',
    "simple navbar alignment",
)

replace_once(
    "src/partials/navbar-simple.html",
    '      </div>\n    </div>\n  </div>\n</nav>\n',
    '      </div>\n'
    '      <div id="simple-mode-language-switcher" class="flex items-center"></div>\n'
    '    </div>\n'
    '  </div>\n'
    '</nav>\n',
    "simple navbar mount",
)

p = Path("src/js/i18n/language-switcher.ts")
s = p.read_text()

old = "export const createLanguageSwitcher = (): HTMLElement => {\n  const currentLang = getLanguageFromUrl();"
new = "export const createLanguageSwitcher = (\n  id = 'language-switcher',\n  compact = false\n): HTMLElement => {\n  const currentLang = getLanguageFromUrl();"
if old not in s:
    raise SystemExit("language switcher signature not found")
s = s.replace(old, new, 1)

if "  container.id = 'language-switcher';" not in s:
    raise SystemExit("language switcher container id not found")
s = s.replace("  container.id = 'language-switcher';", "  container.id = id;", 1)

if "    px-3 py-1.5 rounded-full transition-colors duration-200" not in s:
    raise SystemExit("language switcher button padding not found")
s = s.replace(
    "    px-3 py-1.5 rounded-full transition-colors duration-200",
    "    ${compact ? 'px-2 py-1.5' : 'px-3 py-1.5'} rounded-full transition-colors duration-200",
    1,
)

old = """  const textSpan = document.createElement('span');
  textSpan.className = 'font-medium';
  textSpan.textContent = languageNames[currentLang];
"""
new = """  const globe = document.createElement('span');
  globe.className = 'text-base leading-none';
  globe.textContent = '🌐';
  globe.setAttribute('aria-hidden', 'true');

  const textSpan = document.createElement('span');
  textSpan.className = compact ? 'sr-only' : 'font-medium';
  textSpan.textContent = languageNames[currentLang];

  button.setAttribute('aria-label', `Language: ${languageNames[currentLang]}`);
"""
if old not in s:
    raise SystemExit("language switcher label block not found")
s = s.replace(old, new, 1)

old = """  button.appendChild(textSpan);
  button.appendChild(chevron);
"""
new = """  button.appendChild(globe);
  button.appendChild(textSpan);
  if (!compact) {
    button.appendChild(chevron);
  }
"""
if old not in s:
    raise SystemExit("language switcher button children block not found")
s = s.replace(old, new, 1)

old = """export const injectLanguageSwitcher = (): void => {
  const simpleModeContainer = document.getElementById(
    'simple-mode-language-switcher'
  );
  if (simpleModeContainer) {
    const switcher = createLanguageSwitcher();
    simpleModeContainer.appendChild(switcher);
    return;
  }

  const footer = document.querySelector('footer');
"""
new = """export const injectLanguageSwitcher = (): void => {
  const desktopNavbarContainer = document.getElementById(
    'navbar-language-switcher'
  );
  if (desktopNavbarContainer) {
    desktopNavbarContainer.appendChild(
      createLanguageSwitcher('language-switcher-desktop')
    );
  }

  const mobileNavbarContainer = document.getElementById(
    'mobile-navbar-language-switcher'
  );
  if (mobileNavbarContainer) {
    mobileNavbarContainer.appendChild(
      createLanguageSwitcher('language-switcher-mobile', true)
    );
  }

  const simpleModeContainer = document.getElementById(
    'simple-mode-language-switcher'
  );
  if (simpleModeContainer) {
    simpleModeContainer.appendChild(
      createLanguageSwitcher('language-switcher-simple')
    );
  }

  const footer = document.querySelector('footer');
"""
if old not in s:
    raise SystemExit("language switcher injection block not found")
s = s.replace(old, new, 1)
p.write_text(s)
PY

npm ci
npm run build
npm run test:run

git add -A
git commit -m "Sync upstream BentoPDF v2.8.8 and preserve local i18n UI"
git push origin HEAD:main
