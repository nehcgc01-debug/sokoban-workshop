"""Linux: python tests/run_tests.py /path/to/godot
Imports clean ZIP resources first. Every engine error, failed exit, timeout or
missing suite completion marker fails the run. Saves use disposable directories.
"""
import os, pathlib, re, shutil, subprocess, sys, tempfile
if os.name == 'nt':
    raise SystemExit('Automated runner is validated on Linux only. Use manual acceptance on Windows; never run individual write tests against your real saves.')
source_project = pathlib.Path(__file__).resolve().parents[1]
project_workspace = tempfile.TemporaryDirectory(prefix='kuro_project_')
project = pathlib.Path(project_workspace.name) / 'project'
shutil.copytree(source_project, project, ignore=shutil.ignore_patterns('.godot','__pycache__','test_evidence'))
godot = sys.argv[1] if len(sys.argv) > 1 else shutil.which('godot') or shutil.which('godot4')
if not godot:
    raise SystemExit('Pass the path to your Godot 4.6 executable.')

def isolated_env(folder):
    root = pathlib.Path(folder)
    env = os.environ.copy()
    env['HOME'] = env['USERPROFILE'] = folder
    for key, sub in [('XDG_CONFIG_HOME','config'),('XDG_CACHE_HOME','cache'),('XDG_DATA_HOME','data'),('APPDATA','appdata'),('LOCALAPPDATA','localappdata')]:
        env[key] = str(root/sub)
        (root/sub).mkdir(exist_ok=True)
    return env

def checked_run(command, env=None, marker=None):
    result = subprocess.run(command, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
    print(result.stdout, end='', flush=True)
    plain = re.sub(r'\x1b\[[0-9;]*m', '', result.stdout)
    if result.returncode != 0 or re.search(r'(?m)^\s*(?:SCRIPT ERROR:|ERROR:|Parse Error:)', plain):
        raise SystemExit('FAILED: nonzero exit or engine error; not a passing test run.')
    if marker and marker not in plain:
        raise SystemExit('FAILED: missing completion marker: ' + marker)

# Godot loads a global GUI theme before first import. Bootstrap the isolated
# copy without that setting, restore it, then require a clean normal import.
config = project / 'project.godot'
original_config = config.read_bytes()
config.write_text(re.sub(r'(?m)^theme/custom=.*\n?', '', original_config.decode('utf-8')))
try:
    with tempfile.TemporaryDirectory(prefix='kuro_bootstrap_') as folder:
        checked_run([godot,'--headless','--path',str(project),'--editor','--import'],isolated_env(folder))
finally:
    config.write_bytes(original_config)
with tempfile.TemporaryDirectory(prefix='kuro_import_') as folder:
    checked_run([godot,'--headless','--path',str(project),'--editor','--import'],isolated_env(folder))

suites = {
 'storage':'STORAGE TESTS: 24/24', 'gameplay':'GAMEPLAY TESTS: 14/14',
 'editor':'EDITOR TESTS PASSED: 16', 'editor_more':'MORE EDITOR TESTS PASSED: 4',
 'navigation':'NAVIGATION TESTS: 14/14', 'demo':'DEMO TESTS: 3/3',
 'product':'PRODUCT TESTS: 9', 'menu_focus':'MENU FOCUS TESTS: 10/10',
 'editor_pull':'EDITOR PULL TESTS PASSED: 6', 'pull':'PULL TESTS: 34/34',
 'animation':'ANIMATION TESTS: 17/17', 'audio':'AUDIO TESTS: 16/16', 'modal_cancel':'MODAL CANCEL TESTS: 8/8', 'tutorial_state':'TUTORIAL STATE TESTS: 10/10', 'keyboard_progress':'KEYBOARD PROGRESS TESTS: 21/21', 'copy_review':'COPY REVIEW TESTS: 12/12', 'append_levels':'APPEND LEVELS TESTS: 24/24', 'guidance':'GUIDANCE TESTS: 21/21', 'feedback':'FEEDBACK TESTS: 8/8', 'workshop_ending':'WORKSHOP ENDING TESTS: 10/10', 'dead_state':'DEAD STATE SUITE PASSED'
}
for suite, marker in suites.items():
    with tempfile.TemporaryDirectory(prefix='kuro_test_') as folder:
        checked_run([godot,'--headless','--path',str(project),'--script',f'res://tests/{suite}_tests.gd'],isolated_env(folder),marker)
checked_run([sys.executable,str(project/'tests/solve_levels.py')], marker='All 7 curated demo levels are solvable.')
print('All 307 assertions (281 + 26 dead-state/V7.8) passed with isolated save directories and clean resource import.')
