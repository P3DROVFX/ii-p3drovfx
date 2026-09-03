#!/usr/bin/env python3
"""preset_store.py -- the community preset store, over plain git and GitHub.

There is no server and no central index. A preset is a public GitHub repo
carrying a `preset.json` manifest next to the config it ships; the store is
whatever GitHub returns for the `ii-p3drovfx-preset` topic. Installing is a
clone, updating is a fast-forward pull, and publishing is `gh repo create`
followed by `gh repo edit --add-topic`, so a preset can be written, shipped
and updated without ever opening a browser tab.

Every command prints exactly one JSON line on stdout, failures included, so a
QML caller never has to tell "it broke" apart from "it printed nothing". The
one exception is `auth login`, which streams one JSON line per step because
the user has to be shown a code while the flow is still waiting.

Commands:
  auth status
  auth login
  discover [--limit N] [--query TEXT]
  fetch-manifest <owner/repo>
  install <owner/repo> [--name NAME] [--force]
  check-updates
  pull <name>
  diff <name> [--incoming]
  preview <name>
  publish <name> [--repo NAME] [--description TEXT] [--notes TEXT] [--private]
  push-update <name> [--version V | --bump major|minor|patch] [--notes TEXT]
  links
  unlink <name>
  uninstall <name>
"""
import concurrent.futures
import datetime
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import presets_helper  # noqa: E402

TOPIC = 'ii-p3drovfx-preset'
MANIFEST_NAME = 'preset.json'
MANIFEST_SCHEMA = 1
CONFIG_NAME = 'config.json'
INDEX_NAME = 'index.json'
INDEX_SCHEMA = 1
DEFAULT_REPO_NAME = 'ii-presets'
USER_AGENT = 'ii-preset-store/1.0'

# The device flow needs an OAuth app that belongs to the shell, and its client
# id is public by design -- it is not a secret and nothing can be done with it
# alone. Until the fork registers one, `auth login` says so and hands back the
# `gh auth login` line to run instead, rather than pretending to work.
GITHUB_CLIENT_ID = os.environ.get('II_PRESET_STORE_CLIENT_ID', '').strip()
DEVICE_CODE_URL = 'https://github.com/login/device/code'
DEVICE_TOKEN_URL = 'https://github.com/login/oauth/access_token'
REQUIRED_SCOPES = ('repo',)

# Where a slug is cloned from. Overridable so the install/update path can be
# exercised against local repositories instead of the real GitHub.
GIT_BASE = os.environ.get('II_PRESET_STORE_GIT_BASE', 'https://github.com/')

GIT_TIMEOUT = 180
GH_TIMEOUT = 120
HTTP_TIMEOUT = 20
DIFF_LIMIT = 40
SCREENSHOT_DIR = 'screenshots'
# Git keeps every version of a binary forever, so a preset that reships eight
# large captures on every patch release grows a clone nobody wants to pull.
MAX_SCREENSHOTS = 6
MAX_SCREENSHOT_BYTES = 8 * 1024 * 1024
# The wallpaper and the banner get the same treatment for the same reason,
# with more room because a wallpaper is the whole point of most presets.
# GitHub refuses a file over 100 MB outright, and it would refuse it at the
# push -- after the repository already exists -- so the size is checked here.
MAX_ASSET_BYTES = 25 * 1024 * 1024

# Parentheses belong here: a name collision on install produces "Name (2)",
# and a name this program generates itself has to be one it accepts back.
NAME_RE = re.compile(r'^[A-Za-z0-9][A-Za-z0-9 ()_.-]*$')
REPO_NAME_RE = re.compile(r'^[A-Za-z0-9][A-Za-z0-9_.-]*$')
PRESET_ID_RE = re.compile(r'^[A-Za-z0-9][A-Za-z0-9_.-]*$')
SLUG_RE = re.compile(r'^[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*$')
IMAGE_EXTS = ('.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp')


class StoreError(Exception):
    """Anything the user should be told about in prose."""


# ---------------------------------------------------------------------------
# Paths and small helpers
# ---------------------------------------------------------------------------

def home():
    return presets_helper.user_home()


def config_dir():
    return os.path.join(home(), '.config', 'illogical-impulse')


def presets_dir():
    return os.path.join(config_dir(), 'presets')


def store_dir():
    return os.path.join(config_dir(), 'preset-store')


def config_file():
    return os.path.join(config_dir(), 'config.json')


def links_file():
    return os.path.join(store_dir(), 'links.json')


def scripts_dir():
    return os.path.dirname(os.path.abspath(__file__))


def emit(payload):
    print(json.dumps(payload))


def run(args, cwd=None, timeout=GIT_TIMEOUT, stdin_text=None):
    """Run a command and hand back (code, stdout, stderr), never raising."""
    try:
        proc = subprocess.run(args, cwd=cwd, input=stdin_text, capture_output=True,
                              text=True, timeout=timeout)
        return proc.returncode, proc.stdout.strip(), proc.stderr.strip()
    except FileNotFoundError:
        return 127, '', '%s is not installed' % args[0]
    except subprocess.TimeoutExpired:
        return 124, '', '%s timed out' % args[0]
    except Exception as exc:
        return 1, '', str(exc)


def git(args, cwd, timeout=GIT_TIMEOUT):
    return run(['git'] + list(args), cwd=cwd, timeout=timeout)


def gh(args, timeout=GH_TIMEOUT, stdin_text=None):
    return run(['gh'] + list(args), timeout=timeout, stdin_text=stdin_text)


def check_name(name):
    """Preset names become filenames, so they get checked before they are used."""
    if not name:
        raise StoreError('No preset name was given.')
    if '/' in name or '\\' in name or '..' in name or name.startswith('.'):
        raise StoreError('That preset name cannot be used as a file name.')
    if not NAME_RE.match(name):
        raise StoreError('Preset names may only hold letters, numbers, spaces, brackets, '
                         'dots, dashes and underscores.')
    return name


def check_slug(slug):
    slug = (slug or '').strip()
    slug = re.sub(r'^https?://github\.com/', '', slug)
    slug = re.sub(r'\.git$', '', slug).strip('/')
    preset_id = None
    if ':' in slug:
        repo_part, preset_id = slug.split(':', 1)
    else:
        repo_part = slug
    if not SLUG_RE.match(repo_part):
        raise StoreError('Expected a repository in owner/name form.')
    if preset_id is not None and (not preset_id or not PRESET_ID_RE.match(preset_id)):
        raise StoreError('Expected a valid preset identifier in owner/repo:preset form.')
    return slug


def parse_slug(slug):
    slug = check_slug(slug)
    if ':' in slug:
        repo_part, preset_id = slug.split(':', 1)
        return repo_part, preset_id
    return slug, None


def slug_dir(slug):
    base_slug, _ = parse_slug(slug)
    return os.path.join(store_dir(), base_slug.replace('/', '__'))


def repo_name_from_preset(name):
    slug = re.sub(r'[^A-Za-z0-9._-]+', '-', name.strip().lower()).strip('-.')
    slug = re.sub(r'-{2,}', '-', slug)
    return slug or 'ii-preset'


def version_key(value):
    numbers = re.findall(r'\d+', str(value or ''))[:3]
    numbers += ['0'] * (3 - len(numbers))
    return tuple(int(n) for n in numbers)


def bump_version(value, part='patch'):
    numbers = list(version_key(value))
    index = {'major': 0, 'minor': 1, 'patch': 2}.get(part, 2)
    numbers[index] += 1
    for i in range(index + 1, 3):
        numbers[i] = 0
    return '.'.join(str(n) for n in numbers)


def today():
    return datetime.date.today().isoformat()


def read_json(path):
    with open(path, 'r', encoding='utf-8') as handle:
        return json.load(handle)


def image_ext(path):
    ext = os.path.splitext(path)[1].lower()
    return ext if ext in IMAGE_EXTS else None


# ---------------------------------------------------------------------------
# Compatibility
#
# "Migrate up, block newer", decided in presets_helper so the store and the
# apply path can never disagree about which presets this build can take.
# ---------------------------------------------------------------------------

def current_config_version():
    return presets_helper.current_config_version()


def compatibility(preset_version):
    return presets_helper.compatibility(preset_version)


# ---------------------------------------------------------------------------
# The link index
#
# One file mapping installed preset names to the repos they came from. It is
# the only durable state the store keeps; everything else can be re-derived
# from the clones themselves.
# ---------------------------------------------------------------------------

def load_links():
    try:
        data = read_json(links_file())
    except Exception:
        return {}
    presets = data.get('presets') if isinstance(data, dict) else None
    return presets if isinstance(presets, dict) else {}


def save_links(presets):
    presets_helper.atomic_write_json(links_file(), {'schema': 1, 'presets': presets})


def get_link(name):
    link = load_links().get(name)
    if not link:
        raise StoreError('"%s" did not come from the store.' % name)
    return link


def set_link(name, link):
    presets = load_links()
    presets[name] = link
    save_links(presets)


def drop_link(name):
    presets = load_links()
    if name in presets:
        del presets[name]
        save_links(presets)


def _other_links_use_dir(name, directory):
    for other_name, other_link in load_links().items():
        if other_name != name and other_link.get('path') == directory:
            return True
    return False


# ---------------------------------------------------------------------------
# Manifests
# ---------------------------------------------------------------------------

def validate_manifest(manifest, source='preset.json'):
    if not isinstance(manifest, dict):
        raise StoreError('%s is not a JSON object.' % source)
    name = manifest.get('name')
    if not isinstance(name, str) or not name.strip():
        raise StoreError('%s does not name the preset.' % source)
    config = manifest.get('config') or CONFIG_NAME
    if not isinstance(config, str) or config.startswith('/') or '..' in config:
        raise StoreError('%s points its config outside the repository.' % source)
    manifest['config'] = config
    return manifest


def read_manifest(directory):
    path = os.path.join(directory, MANIFEST_NAME)
    if not os.path.exists(path):
        raise StoreError('This repository carries no %s, so it is not a preset.' % MANIFEST_NAME)
    try:
        manifest = read_json(path)
    except Exception as exc:
        raise StoreError('%s could not be read: %s' % (MANIFEST_NAME, exc))
    return validate_manifest(manifest, MANIFEST_NAME)


def validate_index(index, source='index.json'):
    if not isinstance(index, dict):
        raise StoreError('%s is not a JSON object.' % source)
    presets = index.get('presets')
    if not isinstance(presets, list):
        raise StoreError('%s carries no presets list.' % source)
    return index


def read_index(directory):
    path = os.path.join(directory, INDEX_NAME)
    if not os.path.exists(path):
        return None
    try:
        data = read_json(path)
        return validate_index(data, INDEX_NAME)
    except Exception:
        return None


def manifest_summary(manifest, slug=''):
    return {
        'name': manifest.get('name', ''),
        'author': manifest.get('author', slug.split('/')[0] if slug else ''),
        'description': manifest.get('description', '') or '',
        'version': str(manifest.get('version', '') or ''),
        'configVersion': manifest.get('configVersion'),
        'screenshots': [s for s in (manifest.get('screenshots') or []) if isinstance(s, str)],
        'changelog': manifest.get('changelog') or [],
        'repo': slug,
    }


# ---------------------------------------------------------------------------
# GitHub, unauthenticated
# ---------------------------------------------------------------------------

def http_json(url, token=None, timeout=HTTP_TIMEOUT):
    headers = {
        'Accept': 'application/vnd.github+json',
        'User-Agent': USER_AGENT,
        'X-GitHub-Api-Version': '2022-11-28',
    }
    if token:
        headers['Authorization'] = 'Bearer %s' % token
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode('utf-8'))


def http_text(url, timeout=HTTP_TIMEOUT):
    request = urllib.request.Request(url, headers={'User-Agent': USER_AGENT})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read().decode('utf-8')


def gh_token():
    code, out, _ = gh(['auth', 'token'], timeout=20)
    return out if code == 0 and out else None


# ---------------------------------------------------------------------------
# auth
# ---------------------------------------------------------------------------

def cmd_auth_status():
    if not shutil.which('gh'):
        return {
            'ok': True, 'hasGh': False, 'authenticated': False, 'login': '',
            'scopes': [], 'missingScopes': list(REQUIRED_SCOPES),
            'deviceFlow': bool(GITHUB_CLIENT_ID),
            'hint': 'Publishing needs the GitHub CLI. Install the "github-cli" package.',
        }
    # -i so the granted scopes come back in the response headers; `gh auth
    # status` only prints them for tokens it stored itself.
    code, out, err = gh(['api', '-i', 'user'], timeout=30)
    if code != 0:
        return {
            'ok': True, 'hasGh': True, 'authenticated': False, 'login': '',
            'scopes': [], 'missingScopes': list(REQUIRED_SCOPES),
            'deviceFlow': bool(GITHUB_CLIENT_ID),
            'hint': err or 'Not signed in to GitHub.',
        }
    scopes = []
    for line in out.splitlines():
        if line.lower().startswith('x-oauth-scopes:'):
            scopes = [s.strip() for s in line.split(':', 1)[1].split(',') if s.strip()]
            break
    login = ''
    body = out.split('\n\n', 1)[-1]
    try:
        login = json.loads(body).get('login', '')
    except Exception:
        pass
    # A fine-grained token reports no scopes at all. Treating that as "missing
    # everything" would block a token that works perfectly well, so an empty
    # scope list is taken at face value and the publish itself decides.
    missing = [s for s in REQUIRED_SCOPES if scopes and s not in scopes]
    return {
        'ok': True, 'hasGh': True, 'authenticated': True, 'login': login,
        'scopes': scopes, 'missingScopes': missing,
        # Whether the in-shell device code can work at all. With no OAuth app
        # registered the panel has to offer the terminal instead of a button
        # that can only ever fail.
        'deviceFlow': bool(GITHUB_CLIENT_ID),
        'hint': 'The token cannot create repositories. Sign in again with the "repo" scope.' if missing else '',
    }


def post_form(url, fields):
    data = '&'.join('%s=%s' % (k, urllib.parse.quote(str(v))) for k, v in fields.items())
    request = urllib.request.Request(url, data=data.encode('utf-8'), headers={
        'Accept': 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': USER_AGENT,
    })
    with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT) as response:
        return json.loads(response.read().decode('utf-8'))


def cmd_auth_login():
    """Sign in without handing the browser the whole flow.

    Streams one JSON line per step: the caller shows the code as soon as it
    arrives and keeps reading until the last line says how it ended.
    """
    if not shutil.which('gh'):
        emit({'ok': False, 'event': 'error', 'error': 'The GitHub CLI is not installed.'})
        return 1
    if not GITHUB_CLIENT_ID:
        # No OAuth app is configured for this build, so there is no honest way
        # to run the flow here. Hand back the command that does work.
        emit({
            'ok': False, 'event': 'unavailable',
            'command': 'gh auth login --scopes repo',
            'error': 'This build has no GitHub app configured, so signing in has to be done '
                     'once with the GitHub CLI: run "gh auth login --scopes repo" in a terminal.',
        })
        return 1

    try:
        start = post_form(DEVICE_CODE_URL, {
            'client_id': GITHUB_CLIENT_ID,
            'scope': ' '.join(REQUIRED_SCOPES),
        })
    except Exception as exc:
        emit({'ok': False, 'event': 'error', 'error': 'Could not reach GitHub: %s' % exc})
        return 1

    device_code = start.get('device_code')
    user_code = start.get('user_code')
    if not device_code or not user_code:
        emit({'ok': False, 'event': 'error', 'error': start.get('error_description') or 'GitHub refused the request.'})
        return 1

    emit({
        'ok': True, 'event': 'code',
        'userCode': user_code,
        'verificationUri': start.get('verification_uri', 'https://github.com/login/device'),
        'expiresIn': start.get('expires_in', 900),
    })
    sys.stdout.flush()

    interval = max(int(start.get('interval', 5) or 5), 1)
    deadline = time.time() + int(start.get('expires_in', 900) or 900)
    while time.time() < deadline:
        time.sleep(interval)
        try:
            result = post_form(DEVICE_TOKEN_URL, {
                'client_id': GITHUB_CLIENT_ID,
                'device_code': device_code,
                'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
            })
        except Exception as exc:
            emit({'ok': False, 'event': 'error', 'error': 'Could not reach GitHub: %s' % exc})
            return 1
        token = result.get('access_token')
        if token:
            # Hand the token to gh rather than keeping a second copy: one
            # credential store means signing out actually signs out.
            code, _, err = gh(['auth', 'login', '--hostname', 'github.com',
                               '--git-protocol', 'https', '--with-token'],
                              timeout=60, stdin_text=token + '\n')
            if code != 0:
                emit({'ok': False, 'event': 'error', 'error': err or 'Could not store the token.'})
                return 1
            status = cmd_auth_status()
            emit({'ok': True, 'event': 'done', 'login': status.get('login', '')})
            return 0
        error = result.get('error')
        if error == 'authorization_pending':
            continue
        if error == 'slow_down':
            interval = max(interval + int(result.get('interval', 5) or 5), interval + 1)
            continue
        emit({'ok': False, 'event': 'error',
              'error': result.get('error_description') or error or 'Sign-in was refused.'})
        return 1

    emit({'ok': False, 'event': 'error', 'error': 'The code expired before it was entered.'})
    return 1


# ---------------------------------------------------------------------------
# discover / fetch-manifest
# ---------------------------------------------------------------------------

def probe_repo_index(repo, token=None):
    slug = repo.get('full_name', '')
    branch = repo.get('default_branch', 'main')
    raw_url = 'https://raw.githubusercontent.com/%s/%s/%s' % (slug, branch, INDEX_NAME)
    try:
        text = http_text(raw_url, timeout=HTTP_TIMEOUT)
        data = json.loads(text)
        if isinstance(data, dict) and isinstance(data.get('presets'), list):
            return slug, branch, data
    except Exception:
        pass
    return slug, branch, None


def cmd_discover(limit=30, query=''):
    limit = max(1, min(int(limit or 30), 100))
    search = 'topic:%s' % TOPIC
    if query:
        search = '%s %s' % (query.strip(), search)
    url = ('https://api.github.com/search/repositories?q=%s&sort=stars&order=desc&per_page=%d'
           % (urllib.parse.quote(search), limit))
    # Signed in, the rate limit is 30 searches a minute instead of 10, which
    # is the difference between a store that reloads and one that stops.
    try:
        data = http_json(url, token=gh_token())
    except urllib.error.HTTPError as exc:
        if exc.code in (403, 429):
            raise StoreError('GitHub is rate-limiting the search. Try again in a minute.')
        raise StoreError('GitHub returned %s.' % exc.code)
    except urllib.error.URLError as exc:
        raise StoreError('Could not reach GitHub: %s' % exc.reason)

    installed = {link.get('repo'): name for name, link in load_links().items()}
    items = data.get('items', [])

    # Probe for index.json in parallel across repositories
    indexes = {}
    if items:
        token = gh_token()
        with concurrent.futures.ThreadPoolExecutor(max_workers=min(10, len(items))) as executor:
            futures = [executor.submit(probe_repo_index, repo, token) for repo in items]
            for future in concurrent.futures.as_completed(futures):
                slug, branch, idx_data = future.result()
                if idx_data:
                    indexes[slug] = idx_data

    results = []
    for repo in items:
        slug = repo.get('full_name', '')
        branch = repo.get('default_branch', 'main')
        if slug in indexes:
            # Mono-repo collection: expose each individual preset
            idx = indexes[slug]
            for p in idx.get('presets', []):
                p_id = p.get('id') or repo_name_from_preset(p.get('name', ''))
                full_slug = '%s:%s' % (slug, p_id)
                p_path = p.get('path', 'presets/%s' % p_id)
                results.append({
                    'repo': full_slug,
                    'name': p.get('name', '') or p_id,
                    'description': p.get('description') or repo.get('description') or '',
                    'author': p.get('author') or (repo.get('owner') or {}).get('login', ''),
                    'avatarUrl': (repo.get('owner') or {}).get('avatar_url', ''),
                    'stars': repo.get('stargazers_count', 0),
                    'repoUrl': '%s/tree/%s/%s' % (repo.get('html_url', ''), branch, p_path),
                    'updatedAt': repo.get('pushed_at') or repo.get('updated_at') or '',
                    'defaultBranch': branch,
                    'installedAs': installed.get(full_slug, ''),
                })
        else:
            # Legacy single-preset repository
            results.append({
                'repo': slug,
                'name': repo.get('name', ''),
                'description': repo.get('description') or '',
                'author': (repo.get('owner') or {}).get('login', ''),
                'avatarUrl': (repo.get('owner') or {}).get('avatar_url', ''),
                'stars': repo.get('stargazers_count', 0),
                'repoUrl': repo.get('html_url', ''),
                'updatedAt': repo.get('pushed_at') or repo.get('updated_at') or '',
                'defaultBranch': branch,
                'installedAs': installed.get(slug, ''),
            })
    return {'ok': True, 'topic': TOPIC, 'total': len(results), 'results': results}


def cmd_fetch_manifest(slug):
    slug = check_slug(slug)
    base_slug, preset_id = parse_slug(slug)
    try:
        repo = http_json('https://api.github.com/repos/%s' % base_slug, token=gh_token())
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            raise StoreError('No such repository: %s' % base_slug)
        raise StoreError('GitHub returned %s.' % exc.code)
    except urllib.error.URLError as exc:
        raise StoreError('Could not reach GitHub: %s' % exc.reason)

    branch = repo.get('default_branch') or 'main'
    subpath = ''
    if preset_id:
        subpath = 'presets/%s' % preset_id
        index_raw = 'https://raw.githubusercontent.com/%s/%s/%s' % (base_slug, branch, INDEX_NAME)
        try:
            index_data = json.loads(http_text(index_raw))
            for p in index_data.get('presets', []):
                p_id = p.get('id') or repo_name_from_preset(p.get('name', ''))
                if p_id == preset_id:
                    subpath = p.get('path', subpath)
                    break
        except Exception:
            pass

    manifest_url = ('https://raw.githubusercontent.com/%s/%s/%s/%s' % (base_slug, branch, subpath, MANIFEST_NAME)
                    if subpath else
                    'https://raw.githubusercontent.com/%s/%s/%s' % (base_slug, branch, MANIFEST_NAME))
    try:
        manifest = validate_manifest(json.loads(http_text(manifest_url)), MANIFEST_NAME)
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            raise StoreError('%s carries no %s, so it is not a preset.' % (slug, MANIFEST_NAME))
        raise StoreError('GitHub returned %s.' % exc.code)
    except StoreError:
        raise
    except Exception as exc:
        raise StoreError('%s could not be read: %s' % (MANIFEST_NAME, exc))

    summary = manifest_summary(manifest, slug)
    summary['defaultBranch'] = branch
    summary['stars'] = repo.get('stargazers_count', 0)
    summary['repoUrl'] = repo.get('html_url', '')
    summary['updatedAt'] = repo.get('pushed_at') or repo.get('updated_at') or ''
    summary['screenshotUrls'] = [
        ('https://raw.githubusercontent.com/%s/%s/%s/%s' % (base_slug, branch, subpath, path.lstrip('/'))
         if subpath else
         'https://raw.githubusercontent.com/%s/%s/%s' % (base_slug, branch, path.lstrip('/')))
        for path in summary['screenshots']
    ]
    return {'ok': True, 'manifest': summary,
            'compatibility': compatibility(summary.get('configVersion'))}


# ---------------------------------------------------------------------------
# Materialising a clone into the presets folder
#
# An installed preset is a normal preset: same folder, same file names, so
# every existing path -- the list, the scan, the apply, the revert -- keeps
# working without knowing the store exists.
# ---------------------------------------------------------------------------

def clear_preset_assets(name):
    for pattern in ('%s.*' % name, '%s_profile.*' % name, '%s_banner.*' % name):
        for path in glob.glob(os.path.join(presets_dir(), pattern)):
            if not path.lower().endswith('.json'):
                os.remove(path)


def repo_asset(directory, declared, stem):
    """Locate a shipped image, by name if the manifest gives one.

    A preset written by hand often just drops wallpaper.png at the repo root
    without listing it, and losing the wallpaper over a missing manifest line
    would be the most visible possible failure.
    """
    if isinstance(declared, str) and declared and not declared.startswith('/') and '..' not in declared:
        path = os.path.join(directory, declared)
        if image_ext(path) and os.path.isfile(path):
            return path
    for candidate in sorted(glob.glob(os.path.join(directory, '%s.*' % stem))):
        if image_ext(candidate) and os.path.isfile(candidate):
            return candidate
    return None


def materialise(directory, manifest, name):
    """Copy a clone's payload into the presets folder under `name`."""
    os.makedirs(presets_dir(), exist_ok=True)
    source = os.path.join(directory, manifest['config'])
    if not os.path.exists(source):
        raise StoreError('The preset names a config file (%s) the repository does not carry.'
                         % manifest['config'])
    try:
        read_json(source)
    except Exception as exc:
        raise StoreError('The preset ships a config that is not valid JSON: %s' % exc)

    clear_preset_assets(name)
    target = os.path.join(presets_dir(), '%s.json' % name)
    # Sanitised on the way in as well as on the way out: a preset published
    # from a raw config would otherwise hand its author's tokens to everyone
    # who installed it.
    presets_helper.sanitize(source, target)

    for key, suffix in (('wallpaper', ''), ('banner', '_banner')):
        asset = repo_asset(directory, manifest.get(key), key)
        if not asset:
            continue
        ext = image_ext(asset)
        shutil.copy2(asset, os.path.join(presets_dir(), '%s%s%s' % (name, suffix, ext)))
    return target


def unique_preset_name(preferred):
    existing = {os.path.splitext(os.path.basename(p))[0]
                for p in glob.glob(os.path.join(presets_dir(), '*.json'))}
    if preferred not in existing:
        return preferred
    for index in range(2, 100):
        candidate = '%s (%d)' % (preferred, index)
        if candidate not in existing:
            return candidate
    raise StoreError('Too many presets already share that name.')


def clone(slug, directory):
    if os.path.exists(directory):
        shutil.rmtree(directory, ignore_errors=True)
    os.makedirs(store_dir(), exist_ok=True)
    # Deliberately not --depth 1: a shallow clone cannot show what changed
    # between the version installed and the version being offered.
    code, _, err = git(['clone', '%s%s.git' % (GIT_BASE, slug), directory], cwd=store_dir())
    if code != 0:
        shutil.rmtree(directory, ignore_errors=True)
        raise StoreError(err.splitlines()[-1] if err else 'Could not download the preset.')


def head_commit(directory):
    code, out, _ = git(['rev-parse', 'HEAD'], cwd=directory, timeout=30)
    return out if code == 0 else ''


def cmd_install(slug, name=None, force=False):
    slug = check_slug(slug)
    base_slug, preset_id = parse_slug(slug)
    for existing, link in load_links().items():
        if link.get('repo') == slug:
            raise StoreError('"%s" is already installed from that repository.' % existing)

    directory = slug_dir(base_slug)
    is_new_clone = False
    if not os.path.isdir(os.path.join(directory, '.git')):
        clone(base_slug, directory)
        is_new_clone = True
    else:
        # Clone already exists on disk; pull fast-forward to get latest commits
        code, _, _ = git(['fetch', '--quiet', 'origin'], cwd=directory)
        if code == 0:
            git(['pull', '--ff-only', '--quiet'], cwd=directory)

    subpath = ''
    if preset_id:
        subpath = os.path.join('presets', preset_id)
        index = read_index(directory)
        if index:
            for p in index.get('presets', []):
                p_id = p.get('id') or repo_name_from_preset(p.get('name', ''))
                if p_id == preset_id:
                    subpath = p.get('path', subpath)
                    break
        preset_dir = os.path.join(directory, subpath)
    else:
        preset_dir = directory

    try:
        manifest = read_manifest(preset_dir)
        compat = compatibility(manifest.get('configVersion'))
        if not compat['ok'] and not force:
            raise StoreError(compat['reason'])
        preset_name = check_name(name) if name else check_name(manifest['name'].strip())
        preset_name = unique_preset_name(preset_name)
        materialise(preset_dir, manifest, preset_name)
    except Exception:
        if is_new_clone and not _other_links_use_dir('', directory):
            shutil.rmtree(directory, ignore_errors=True)
        raise

    set_link(preset_name, {
        'repo': slug,
        'baseRepo': base_slug,
        'subpath': subpath,
        'path': directory,
        'commit': head_commit(directory),
        'version': str(manifest.get('version', '') or ''),
        'configVersion': manifest.get('configVersion'),
        'owned': False,
        'installedAt': today(),
    })
    return {'ok': True, 'name': preset_name, 'repo': slug,
            'manifest': manifest_summary(manifest, slug), 'compatibility': compat}


# ---------------------------------------------------------------------------
# Updates
# ---------------------------------------------------------------------------

def upstream_ref(directory):
    code, out, _ = git(['rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}'],
                       cwd=directory, timeout=30)
    if code == 0 and out:
        return out
    code, out, _ = git(['rev-parse', '--abbrev-ref', 'HEAD'], cwd=directory, timeout=30)
    return 'origin/%s' % out if code == 0 and out else 'origin/main'


def remote_manifest(directory, ref, path=MANIFEST_NAME):
    code, out, _ = git(['show', '%s:%s' % (ref, path)], cwd=directory, timeout=30)
    if code != 0:
        return {}
    try:
        return json.loads(out)
    except Exception:
        return {}


def cmd_check_updates():
    links = load_links()
    updates = []
    problems = []
    fetched_dirs = set()
    for name, link in sorted(links.items(), key=lambda kv: kv[0].lower()):
        directory = link.get('path') or slug_dir(link.get('repo', ''))
        subpath = link.get('subpath', '')
        if not os.path.isdir(os.path.join(directory, '.git')):
            problems.append({'name': name, 'repo': link.get('repo', ''),
                             'error': 'Its local copy is gone.'})
            continue
        if directory not in fetched_dirs:
            code, _, err = git(['fetch', '--quiet', 'origin'], cwd=directory, timeout=90)
            if code != 0:
                problems.append({'name': name, 'repo': link.get('repo', ''),
                                 'error': err.splitlines()[-1] if err else 'Could not reach GitHub.'})
                continue
            fetched_dirs.add(directory)
        ref = upstream_ref(directory)
        rev_args = ['rev-list', '--count', 'HEAD..%s' % ref]
        if subpath:
            rev_args += ['--', subpath]
        code, out, _ = git(rev_args, cwd=directory, timeout=30)
        behind = int(out) if code == 0 and out.isdigit() else 0
        if behind <= 0:
            continue
        manifest_file = os.path.join(subpath, MANIFEST_NAME) if subpath else MANIFEST_NAME
        manifest = remote_manifest(directory, ref, manifest_file)
        version = str(manifest.get('version', '') or '')
        # Only the entries newer than what is installed: a preset that has
        # shipped ten times should not read like ten pending updates.
        installed_version = str(link.get('version', '') or '')
        changelog = [entry for entry in (manifest.get('changelog') or [])
                     if isinstance(entry, dict)
                     and version_key(entry.get('version')) > version_key(installed_version)]
        updates.append({
            'name': name,
            'repo': link.get('repo', ''),
            'commits': behind,
            'installedVersion': installed_version,
            'availableVersion': version,
            'configVersion': manifest.get('configVersion'),
            'compatibility': compatibility(manifest.get('configVersion')),
            'changelog': changelog[:10],
            'owned': bool(link.get('owned')),
        })
    return {'ok': True, 'updates': updates, 'problems': problems, 'checked': len(links)}


def cmd_pull(name, force=False):
    name = check_name(name)
    link = get_link(name)
    directory = link.get('path') or slug_dir(link.get('repo', ''))
    subpath = link.get('subpath', '')
    if not os.path.isdir(os.path.join(directory, '.git')):
        raise StoreError('The local copy of "%s" is gone. Reinstall it from the store.' % name)

    code, _, err = git(['fetch', '--quiet', 'origin'], cwd=directory, timeout=90)
    if code != 0:
        raise StoreError(err.splitlines()[-1] if err else 'Could not reach GitHub.')
    ref = upstream_ref(directory)
    manifest_file = os.path.join(subpath, MANIFEST_NAME) if subpath else MANIFEST_NAME
    incoming = remote_manifest(directory, ref, manifest_file)
    compat = compatibility(incoming.get('configVersion'))
    if incoming and not compat['ok'] and not force:
        raise StoreError(compat['reason'])

    before = head_commit(directory)
    # --ff-only, always: a preset the author force-pushed should fail loudly
    # rather than leave a half-merged config behind.
    code, _, err = git(['pull', '--ff-only', '--quiet'], cwd=directory, timeout=120)
    if code != 0:
        raise StoreError('The preset\'s history was rewritten, so it cannot be updated in place. '
                         'Remove it and install it again.')
    preset_dir = os.path.join(directory, subpath) if subpath else directory
    manifest = read_manifest(preset_dir)
    materialise(preset_dir, manifest, name)

    link.update({
        'commit': head_commit(directory),
        'version': str(manifest.get('version', '') or ''),
        'configVersion': manifest.get('configVersion'),
        'updatedAt': today(),
    })
    set_link(name, link)
    return {'ok': True, 'name': name, 'repo': link.get('repo', ''),
            'changed': before != link['commit'],
            'version': link['version'], 'compatibility': compat,
            'manifest': manifest_summary(manifest, link.get('repo', ''))}


# ---------------------------------------------------------------------------
# diff
# ---------------------------------------------------------------------------

def flatten(node, prefix=()):
    if isinstance(node, dict):
        for key, value in node.items():
            for item in flatten(value, prefix + (str(key),)):
                yield item
    else:
        yield prefix, node


def json_diff(before, after):
    """Dotted-path differences between two configs, newest key order first."""
    old = dict(flatten(before if isinstance(before, dict) else {}))
    new = dict(flatten(after if isinstance(after, dict) else {}))
    changes = []
    for path in sorted(set(old) | set(new)):
        was = old.get(path, presets_helper._MISSING)
        now = new.get(path, presets_helper._MISSING)
        if was is presets_helper._MISSING:
            kind = 'added'
        elif now is presets_helper._MISSING:
            kind = 'removed'
        elif was == now:
            continue
        else:
            kind = 'changed'
        changes.append({
            'path': '.'.join(path),
            'kind': kind,
            'from': '' if was is presets_helper._MISSING else presets_helper._preview(was),
            'to': '' if now is presets_helper._MISSING else presets_helper._preview(now),
        })
    return changes


def sanitized_copy(path):
    """Read a config the way publishing would write it."""
    with tempfile.NamedTemporaryFile('w', suffix='.json', delete=False) as handle:
        staged = handle.name
    try:
        presets_helper.sanitize(path, staged)
        return read_json(staged)
    finally:
        os.unlink(staged)


def cmd_diff(name, incoming=False):
    name = check_name(name)
    link = get_link(name)
    directory = link.get('path') or slug_dir(link.get('repo', ''))
    subpath = link.get('subpath', '')
    if not os.path.isdir(os.path.join(directory, '.git')):
        raise StoreError('The local copy of "%s" is gone.' % name)
    preset_dir = os.path.join(directory, subpath) if subpath else directory
    manifest = read_manifest(preset_dir)
    config_file_name = manifest.get('config') or CONFIG_NAME
    repo_config_rel = os.path.join(subpath, config_file_name) if subpath else config_file_name

    if incoming:
        code, _, err = git(['fetch', '--quiet', 'origin'], cwd=directory, timeout=90)
        if code != 0:
            raise StoreError(err.splitlines()[-1] if err else 'Could not reach GitHub.')
        ref = upstream_ref(directory)
        code, out, _ = git(['show', 'HEAD:%s' % repo_config_rel], cwd=directory, timeout=30)
        before = json.loads(out) if code == 0 and out else {}
        code, out, _ = git(['show', '%s:%s' % (ref, repo_config_rel)], cwd=directory, timeout=30)
        after = json.loads(out) if code == 0 and out else {}
        direction = 'incoming'
    else:
        local = os.path.join(presets_dir(), '%s.json' % name)
        if not os.path.exists(local):
            raise StoreError('"%s" is no longer in your presets.' % name)
        published = os.path.join(directory, repo_config_rel)
        # Both sides go through the same sanitiser first. The working copy is
        # sanitised when it is published, so comparing it raw would report
        # every personal path as a change that publishing would never make.
        before = sanitized_copy(published) if os.path.exists(published) else {}
        after = sanitized_copy(local)
        direction = 'outgoing'

    changes = json_diff(before, after)
    return {'ok': True, 'name': name, 'repo': link.get('repo', ''), 'direction': direction,
            'total': len(changes), 'changes': changes[:DIFF_LIMIT],
            'truncated': max(0, len(changes) - DIFF_LIMIT)}


# ---------------------------------------------------------------------------
# preview
#
# Publishing creates a public repository, and a repository is public the
# moment the topic lands on it. The list of stripped paths is a promise, and
# a promise that has been wrong before, so this is the promise made checkable
# before anything exists: every value that would be uploaded, what the
# sanitiser took out, and the warning an installer will be shown.
# ---------------------------------------------------------------------------

# Values worth a second look wherever they turn up. A key named innocently can
# still hold an address, and the sanitiser only knows the keys it was told.
IDENTITY_VALUE_RE = re.compile(
    r'\b\d{1,3}(?:\.\d{1,3}){3}\b'                    # an address on a network
    r'|\b[0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5}\b'         # a MAC
    r'|[\w.+-]+@[\w-]+\.[\w.]+'                         # an email
    r'|/home/[^/\s]+'                                    # a path still naming its owner
    r'|\bhttps?://'                                      # anything that phones somewhere
)


def cmd_preview(name):
    name = check_name(name)
    source = os.path.join(presets_dir(), '%s.json' % name)
    if not os.path.exists(source):
        raise StoreError('"%s" is no longer in your presets.' % name)

    raw = read_json(source)
    with tempfile.NamedTemporaryFile('w', suffix='.json', delete=False) as handle:
        staged = handle.name
    try:
        presets_helper.sanitize(source, staged)
        sanitized = read_json(staged)
        config_bytes = os.path.getsize(staged)
        try:
            risks = presets_helper.scan(staged)
        except Exception:
            # A preview that cannot say "and here is the warning" is still
            # worth showing; it must not be the reason publishing stops.
            risks = {}
    finally:
        os.unlink(staged)

    kept = dict(flatten(sanitized))
    entries = []
    for path in sorted(kept):
        value = kept[path]
        text = presets_helper._preview(value)
        flagged = isinstance(value, str) and bool(
            IDENTITY_VALUE_RE.search(value) or presets_helper.COMMAND_HINT_RE.search(value))
        entries.append({'path': '.'.join(path), 'value': text, 'flagged': flagged})

    dropped = sorted('.'.join(path) for path in set(dict(flatten(raw))) - set(kept))

    files = [{'name': CONFIG_NAME, 'bytes': config_bytes, 'kind': 'config'}]
    for kind, asset in (('wallpaper', presets_helper.find_wallpaper_fallback(presets_dir(), name)),
                        ('banner', presets_helper.find_banner_fallback(presets_dir(), name))):
        if not asset or not image_ext(asset) or not os.path.isfile(asset):
            continue
        files.append({'name': '%s%s' % (kind, image_ext(asset)),
                      'bytes': os.path.getsize(asset), 'kind': kind})

    return {'ok': True, 'name': name, 'total': len(entries),
            'entries': entries, 'flagged': [e for e in entries if e['flagged']],
            'dropped': dropped, 'files': files,
            'risks': risks.get('groups', []) if isinstance(risks, dict) else []}


# ---------------------------------------------------------------------------
# publish / push-update
# ---------------------------------------------------------------------------

def require_login():
    status = cmd_auth_status()
    if not status.get('hasGh'):
        raise StoreError('Publishing needs the GitHub CLI. Install the "github-cli" package.')
    if not status.get('authenticated'):
        raise StoreError('Sign in to GitHub first.')
    if status.get('missingScopes'):
        raise StoreError('Your GitHub token cannot create repositories. '
                         'Sign in again with the "repo" scope.')
    return status['login']


def stage_screenshots(directory, manifest, screenshots):
    """Replace the shipped screenshots.

    `None` means the caller is not touching them, which is what an update that
    only changes settings wants -- the pictures already published stay.
    An empty list is a deliberate "ship none".
    """
    if screenshots is None:
        return manifest
    shutil.rmtree(os.path.join(directory, SCREENSHOT_DIR), ignore_errors=True)
    shipped = []
    if screenshots:
        if len(screenshots) > MAX_SCREENSHOTS:
            raise StoreError('A preset may ship at most %d screenshots.' % MAX_SCREENSHOTS)
        os.makedirs(os.path.join(directory, SCREENSHOT_DIR), exist_ok=True)
        for index, source in enumerate(screenshots, start=1):
            if not os.path.isfile(source):
                raise StoreError('The screenshot %s is no longer there.' % os.path.basename(source))
            ext = image_ext(source)
            if not ext:
                raise StoreError('%s is not an image.' % os.path.basename(source))
            if os.path.getsize(source) > MAX_SCREENSHOT_BYTES:
                raise StoreError('%s is larger than %d MB.'
                                 % (os.path.basename(source), MAX_SCREENSHOT_BYTES // (1024 * 1024)))
            target = '%s/%d%s' % (SCREENSHOT_DIR, index, ext)
            shutil.copy2(source, os.path.join(directory, target))
            shipped.append(target)
    manifest['screenshots'] = shipped
    return manifest


def check_asset_size(path, what):
    """Refuse an image too big to publish, while nothing has been created yet.

    Git keeps every version of a binary forever, so an enormous wallpaper is
    not only a push that fails: it is a clone everyone who installs the preset
    pays for, on every release, for good.
    """
    size = os.path.getsize(path)
    if size <= MAX_ASSET_BYTES:
        return
    raise StoreError('The %s is %d MB, and a preset may ship at most %d MB. '
                     'Shrink it and save the preset again.'
                     % (what, size // (1024 * 1024), MAX_ASSET_BYTES // (1024 * 1024)))


def stage_payload(directory, name, manifest, screenshots=None):
    """Write the preset and its assets into the repo working tree."""
    source = os.path.join(presets_dir(), '%s.json' % name)
    if not os.path.exists(source):
        raise StoreError('"%s" is no longer in your presets.' % name)
    presets_helper.sanitize(source, os.path.join(directory, CONFIG_NAME))

    for existing in glob.glob(os.path.join(directory, 'wallpaper.*')) + \
            glob.glob(os.path.join(directory, 'banner.*')):
        os.remove(existing)
    manifest.pop('wallpaper', None)
    manifest.pop('banner', None)

    # The profile picture is never shipped. It is the author's own face, it
    # says nothing about the theme, and a published preset is public.
    for key, source in (('wallpaper', presets_helper.find_wallpaper_fallback(presets_dir(), name)),
                        ('banner', presets_helper.find_banner_fallback(presets_dir(), name))):
        if not source or not image_ext(source):
            continue
        check_asset_size(source, key)
        target = '%s%s' % (key, image_ext(source))
        shutil.copy2(source, os.path.join(directory, target))
        manifest[key] = target
    return stage_screenshots(directory, manifest, screenshots)


def write_readme(directory, manifest):
    lines = [
        '# %s' % manifest.get('name', ''),
        '',
        manifest.get('description', '') or 'An Illogical Impulse preset.',
        '',
        '## Install',
        '',
        'Open **Settings → Presets → Store** in the shell and search for this preset,',
        'or install it from a terminal:',
        '',
        '```',
        'python3 ~/.config/quickshell/ii/scripts/preset_store.py install %s'
        % manifest.get('_repo', ''),
        '```',
        '',
        '## What it ships',
        '',
        '- `%s` — the settings this preset applies' % CONFIG_NAME,
    ]
    if manifest.get('wallpaper'):
        lines.append('- `%s` — the wallpaper' % manifest['wallpaper'])
    if manifest.get('banner'):
        lines.append('- `%s` — the sidebar banner' % manifest['banner'])
    for shot in manifest.get('screenshots') or []:
        lines.append('- `%s` — a screenshot' % shot)
    lines += [
        '',
        'Applying a preset never replaces your whole configuration: it is layered over',
        'what you already have, and anything tied to your machine — monitors, folders,',
        'accounts, keys — is kept.',
        '',
        '_Topic: `%s`_' % TOPIC,
        '',
    ]
    with open(os.path.join(directory, 'README.md'), 'w', encoding='utf-8') as handle:
        handle.write('\n'.join(lines))


def check_repo_exists_remote(slug):
    if GIT_BASE != 'https://github.com/':
        remote_path = os.path.join(GIT_BASE, '%s.git' % slug)
        return os.path.exists(remote_path)
    code, _, _ = gh(['repo', 'view', slug, '--json', 'name'], timeout=30)
    return code == 0


def write_collection_readme(directory, index_data, slug):
    lines = [
        '# %s Presets Collection' % index_data.get('author', 'Community'),
        '',
        'Community presets collection for [Illogical Impulse](https://github.com/vaxerski/Hyprland).',
        '',
        '## Available Presets',
        '',
    ]
    for p in index_data.get('presets', []):
        p_name = p.get('name', 'Preset')
        p_desc = p.get('description', '')
        p_ver = p.get('version', '1.0.0')
        p_id = p.get('id', '')
        desc_part = (' — %s' % p_desc) if p_desc else ''
        lines.append('- **%s** (`%s`, v%s)%s' % (p_name, p_id, p_ver, desc_part))
    lines += [
        '',
        '## How to Install',
        '',
        'In the shell, navigate to **Settings → Presets → Store** and search for the preset,',
        'or install directly from a terminal:',
        '',
        '```bash',
        'python3 ~/.config/quickshell/ii/scripts/preset_store.py install %s:<preset_id>' % slug,
        '```',
        '',
        'Applying a preset never replaces your whole configuration: it is layered over',
        'what you already have, and anything tied to your machine — monitors, folders,',
        'accounts, keys — is kept.',
        '',
        '_Topic: `%s`_' % TOPIC,
        '',
    ]
    with open(os.path.join(directory, 'README.md'), 'w', encoding='utf-8') as handle:
        handle.write('\n'.join(lines))


def cmd_publish(name, repo=None, description='', notes='', private=False, screenshots=None):
    name = check_name(name)
    login = require_login()
    links = load_links()
    if name in links:
        raise StoreError('"%s" is already published. Use the update button instead.' % name)

    repo_name = (repo.strip() if (repo and repo.strip()) else DEFAULT_REPO_NAME)
    if not REPO_NAME_RE.match(repo_name):
        raise StoreError('Repository names may only hold letters, numbers, dots, dashes and underscores.')
    slug = '%s/%s' % (login, repo_name)
    preset_id = repo_name_from_preset(name)
    full_slug = '%s:%s' % (slug, preset_id)
    directory = slug_dir(slug)
    subpath = os.path.join('presets', preset_id)
    preset_dir = os.path.join(directory, subpath)

    remote_exists = check_repo_exists_remote(slug)
    is_existing_repo = remote_exists or (os.path.isdir(os.path.join(directory, '.git')))

    if is_existing_repo:
        if not os.path.isdir(os.path.join(directory, '.git')):
            clone(slug, directory)
        else:
            git(['fetch', '--quiet', 'origin'], cwd=directory)
            git(['checkout', '--quiet', 'main'], cwd=directory)
            git(['pull', '--ff-only', '--quiet'], cwd=directory)

        if os.path.exists(preset_dir):
            raise StoreError('A preset with identifier "%s" already exists in "%s".' % (preset_id, repo_name))
        os.makedirs(preset_dir, exist_ok=True)
    else:
        if os.path.exists(directory):
            shutil.rmtree(directory, ignore_errors=True)
        os.makedirs(preset_dir, exist_ok=True)

    try:
        preset = read_json(os.path.join(presets_dir(), '%s.json' % name))
        version = '1.0.0'
        manifest = {
            'schema': MANIFEST_SCHEMA,
            'name': name,
            'author': login,
            'description': description.strip(),
            'version': version,
            'configVersion': preset.get('configVersion', current_config_version()),
            'config': CONFIG_NAME,
            'screenshots': [],
            'changelog': [{'version': version, 'date': today(),
                           'notes': notes.strip() or 'First release.'}],
        }
        manifest = stage_payload(preset_dir, name, manifest, screenshots or [])
        presets_helper.atomic_write_json(os.path.join(preset_dir, MANIFEST_NAME), manifest)

        # Update or create index.json
        index_data = read_index(directory) or {
            'schema': INDEX_SCHEMA,
            'author': login,
            'presets': []
        }
        p_entry = {
            'id': preset_id,
            'name': name,
            'description': description.strip(),
            'version': version,
            'configVersion': manifest.get('configVersion'),
            'path': subpath,
        }
        if manifest.get('wallpaper'):
            p_entry['wallpaper'] = '%s/%s' % (subpath, manifest['wallpaper'])
        if manifest.get('banner'):
            p_entry['banner'] = '%s/%s' % (subpath, manifest['banner'])
        if manifest.get('screenshots'):
            p_entry['screenshots'] = ['%s/%s' % (subpath, s) for s in manifest['screenshots']]

        index_data['presets'] = [p for p in index_data.get('presets', []) if p.get('id') != preset_id]
        index_data['presets'].append(p_entry)
        presets_helper.atomic_write_json(os.path.join(directory, INDEX_NAME), index_data)

        write_collection_readme(directory, index_data, slug)

        topic_error = ''
        if not is_existing_repo:
            for args in (['init', '-b', 'main'], ['add', '-A']):
                code, _, err = git(args, cwd=directory, timeout=60)
                if code != 0:
                    raise StoreError(err or 'git %s failed.' % args[0])
            code, _, err = git(['commit', '-m', 'Add preset %s' % name], cwd=directory, timeout=60)
            if code != 0:
                raise StoreError(err.splitlines()[-1] if err else 'Could not make the first commit.')

            create = ['repo', 'create', slug, '--private' if private else '--public',
                      '--source', directory, '--push']
            code, _, err = gh(create, timeout=180)
            if code != 0:
                raise StoreError(err.splitlines()[-1] if err else 'Could not create the repository.')

            code, _, err = gh(['repo', 'edit', slug, '--add-topic', TOPIC], timeout=60)
            topic_error = '' if code == 0 else (err.splitlines()[-1] if err else 'Could not set the topic.')
        else:
            code, _, err = git(['add', '-A'], cwd=directory, timeout=60)
            if code != 0:
                raise StoreError(err or 'git add failed.')
            code, _, err = git(['commit', '-m', 'Add preset %s' % name], cwd=directory, timeout=60)
            if code != 0:
                raise StoreError(err.splitlines()[-1] if err else 'Could not commit the new preset.')
            code, _, err = git(['push', 'origin', 'HEAD'], cwd=directory, timeout=180)
            if code != 0:
                raise StoreError(err.splitlines()[-1] if err else 'Could not push to repository.')

            code, _, err = gh(['repo', 'edit', slug, '--add-topic', TOPIC], timeout=60)
            if code != 0 and err:
                topic_error = err.splitlines()[-1]
    except Exception:
        if not is_existing_repo:
            shutil.rmtree(directory, ignore_errors=True)
        else:
            git(['checkout', '--', '.'], cwd=directory)
            git(['clean', '-fd'], cwd=directory)
        raise

    set_link(name, {
        'repo': full_slug, 'baseRepo': slug, 'subpath': subpath, 'path': directory,
        'commit': head_commit(directory), 'version': manifest['version'],
        'configVersion': manifest.get('configVersion'), 'owned': True, 'installedAt': today(),
    })
    return {'ok': True, 'name': name, 'repo': full_slug,
            'repoUrl': 'https://github.com/%s' % slug,
            'version': manifest['version'], 'private': bool(private),
            'topic': TOPIC, 'topicError': topic_error}


def cmd_push_update(name, version=None, bump='patch', notes='', screenshots=None):
    name = check_name(name)
    link = get_link(name)
    if not link.get('owned'):
        raise StoreError('"%s" was installed from someone else\'s repository, so it cannot be updated from here.' % name)
    require_login()
    directory = link.get('path') or slug_dir(link.get('repo', ''))
    subpath = link.get('subpath', '')
    if not os.path.isdir(os.path.join(directory, '.git')):
        raise StoreError('The local copy of "%s" is gone.' % name)

    # Pull fast-forward first
    git(['fetch', '--quiet', 'origin'], cwd=directory)
    git(['pull', '--ff-only', '--quiet'], cwd=directory)

    preset_dir = os.path.join(directory, subpath) if subpath else directory
    manifest = read_manifest(preset_dir)
    manifest = stage_payload(preset_dir, name, manifest, screenshots)
    new_version = version.strip() if version and version.strip() else bump_version(manifest.get('version'), bump)
    if version_key(new_version) <= version_key(manifest.get('version')):
        raise StoreError('Version %s is not newer than the published %s.'
                         % (new_version, manifest.get('version')))
    manifest['version'] = new_version
    manifest['configVersion'] = read_json(os.path.join(preset_dir, CONFIG_NAME)).get(
        'configVersion', manifest.get('configVersion'))
    changelog = manifest.get('changelog')
    if not isinstance(changelog, list):
        changelog = []
    changelog.insert(0, {'version': new_version, 'date': today(), 'notes': notes.strip()})
    manifest['changelog'] = changelog[:50]
    presets_helper.atomic_write_json(os.path.join(preset_dir, MANIFEST_NAME), manifest)

    if subpath:
        index_data = read_index(directory)
        if index_data and isinstance(index_data.get('presets'), list):
            preset_id = os.path.basename(subpath)
            for p in index_data['presets']:
                if p.get('id') == preset_id or p.get('path') == subpath:
                    p['version'] = new_version
                    p['configVersion'] = manifest.get('configVersion')
                    if manifest.get('description'):
                        p['description'] = manifest['description']
                    if manifest.get('wallpaper'):
                        p['wallpaper'] = '%s/%s' % (subpath, manifest['wallpaper'])
                    if manifest.get('banner'):
                        p['banner'] = '%s/%s' % (subpath, manifest['banner'])
                    if manifest.get('screenshots'):
                        p['screenshots'] = ['%s/%s' % (subpath, s) for s in manifest['screenshots']]
                    break
            presets_helper.atomic_write_json(os.path.join(directory, INDEX_NAME), index_data)
            base_slug = link.get('baseRepo') or parse_slug(link.get('repo', ''))[0]
            write_collection_readme(directory, index_data, base_slug)
    else:
        write_readme(directory, dict(manifest, _repo=link.get('repo', '')))

    code, _, err = git(['add', '-A'], cwd=directory, timeout=60)
    if code != 0:
        raise StoreError(err or 'Could not stage the changes.')
    code, out, _ = git(['status', '--porcelain'], cwd=directory, timeout=30)
    if code == 0 and not out:
        return {'ok': True, 'name': name, 'repo': link.get('repo', ''), 'changed': False,
                'version': manifest['version'], 'message': 'Nothing has changed since the last release.'}

    message = 'Update to %s' % new_version
    if notes.strip():
        message += '\n\n%s' % notes.strip()
    code, _, err = git(['commit', '-m', message], cwd=directory, timeout=60)
    if code != 0:
        raise StoreError(err.splitlines()[-1] if err else 'Could not commit the update.')
    code, _, err = git(['push', 'origin', 'HEAD'], cwd=directory, timeout=180)
    if code != 0:
        raise StoreError(err.splitlines()[-1] if err else 'Could not push the update.')

    link.update({'commit': head_commit(directory), 'version': new_version,
                 'configVersion': manifest.get('configVersion'), 'updatedAt': today()})
    set_link(name, link)
    base_slug = link.get('baseRepo') or parse_slug(link.get('repo', ''))[0]
    return {'ok': True, 'name': name, 'repo': link.get('repo', ''), 'changed': True,
            'version': new_version, 'repoUrl': 'https://github.com/%s' % base_slug}


# ---------------------------------------------------------------------------
# links / unlink / uninstall
# ---------------------------------------------------------------------------

def cmd_links():
    links = load_links()
    rows = []
    for name, link in sorted(links.items(), key=lambda kv: kv[0].lower()):
        directory = link.get('path') or slug_dir(link.get('repo', ''))
        base_slug = link.get('baseRepo') or parse_slug(link.get('repo', ''))[0]
        rows.append({
            'name': name,
            'repo': link.get('repo', ''),
            'baseRepo': base_slug,
            'subpath': link.get('subpath', ''),
            'repoUrl': 'https://github.com/%s' % base_slug,
            'version': str(link.get('version', '') or ''),
            'configVersion': link.get('configVersion'),
            'owned': bool(link.get('owned')),
            'installedAt': link.get('installedAt', ''),
            'updatedAt': link.get('updatedAt', ''),
            'present': os.path.isdir(os.path.join(directory, '.git')),
            'installed': os.path.exists(os.path.join(presets_dir(), '%s.json' % name)),
        })
    return {'ok': True, 'total': len(rows), 'links': rows}


def cmd_unlink(name):
    name = check_name(name)
    link = get_link(name)
    directory = link.get('path') or slug_dir(link.get('repo', ''))
    drop_link(name)
    if not _other_links_use_dir(name, directory):
        shutil.rmtree(directory, ignore_errors=True)
    return {'ok': True, 'name': name, 'repo': link.get('repo', ''), 'keptPreset': True}


def cmd_uninstall(name):
    name = check_name(name)
    links = load_links()
    link = links.get(name, {})
    directory = link.get('path') or slug_dir(link.get('repo', ''))
    if link:
        drop_link(name)
        if not _other_links_use_dir(name, directory):
            shutil.rmtree(directory, ignore_errors=True)
    clear_preset_assets(name)
    preset = os.path.join(presets_dir(), '%s.json' % name)
    if os.path.exists(preset):
        os.remove(preset)
    return {'ok': True, 'name': name, 'repo': link.get('repo', '')}


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def take_flag(argv, flag):
    if flag in argv:
        argv.remove(flag)
        return True
    return False


def take_options(argv, flag):
    """Every occurrence of a repeatable flag, in the order they were given.

    Returns None when the flag is absent at all, which is how "leave what is
    published alone" is told apart from "ship none".
    """
    values = []
    seen = False
    while flag in argv:
        seen = True
        index = argv.index(flag)
        if index + 1 < len(argv):
            values.append(argv[index + 1])
            del argv[index:index + 2]
        else:
            del argv[index]
    return values if seen else None


def take_option(argv, flag, default=None):
    if flag in argv:
        index = argv.index(flag)
        if index + 1 < len(argv):
            value = argv[index + 1]
            del argv[index:index + 2]
            return value
        del argv[index]
    return default


def dispatch(argv):
    if not argv:
        raise StoreError('No command was given.')
    command = argv[0]
    rest = argv[1:]

    if command == 'auth':
        action = rest[0] if rest else 'status'
        if action == 'status':
            return cmd_auth_status()
        if action == 'login':
            sys.exit(cmd_auth_login())
        raise StoreError('Unknown auth command: %s' % action)
    if command == 'discover':
        limit = take_option(rest, '--limit', '30')
        query = take_option(rest, '--query', '')
        return cmd_discover(limit, query)
    if command == 'fetch-manifest':
        return cmd_fetch_manifest(rest[0] if rest else '')
    if command == 'install':
        force = take_flag(rest, '--force')
        name = take_option(rest, '--name')
        return cmd_install(rest[0] if rest else '', name, force)
    if command == 'check-updates':
        return cmd_check_updates()
    if command == 'pull':
        force = take_flag(rest, '--force')
        return cmd_pull(rest[0] if rest else '', force)
    if command == 'diff':
        incoming = take_flag(rest, '--incoming')
        return cmd_diff(rest[0] if rest else '', incoming)
    if command == 'preview':
        return cmd_preview(rest[0] if rest else '')
    if command == 'publish':
        private = take_flag(rest, '--private')
        repo = take_option(rest, '--repo')
        description = take_option(rest, '--description', '')
        notes = take_option(rest, '--notes', '')
        screenshots = take_options(rest, '--screenshot')
        return cmd_publish(rest[0] if rest else '', repo, description, notes, private, screenshots)
    if command == 'push-update':
        version = take_option(rest, '--version')
        bump = take_option(rest, '--bump', 'patch')
        notes = take_option(rest, '--notes', '')
        screenshots = take_options(rest, '--screenshot')
        return cmd_push_update(rest[0] if rest else '', version, bump, notes, screenshots)
    if command == 'links':
        return cmd_links()
    if command == 'unlink':
        return cmd_unlink(rest[0] if rest else '')
    if command == 'uninstall':
        return cmd_uninstall(rest[0] if rest else '')
    raise StoreError('Unknown command: %s' % command)


def main():
    try:
        emit(dispatch(sys.argv[1:]))
        return 0
    except StoreError as exc:
        emit({'ok': False, 'error': str(exc)})
        return 1
    except Exception as exc:
        # Nothing may escape as a traceback on stdout: the caller parses this
        # line and has to be able to show a reason even for a bug in here.
        emit({'ok': False, 'error': '%s: %s' % (type(exc).__name__, exc)})
        return 1


if __name__ == '__main__':
    sys.exit(main())
