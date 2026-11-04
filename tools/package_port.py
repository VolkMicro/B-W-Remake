"""Package only this project's original sources and the local Godot build.

Never traverses the required Black & White installation or scratch/tools dumps.
This is a local development archive, not proof of a passing gameplay test.
"""
import hashlib
import json
import argparse
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--version', default='0.2.0')
args = parser.parse_args()
version = args.version
if not all(c.isdigit() or c == '.' for c in version):
    raise SystemExit('Invalid local version')
build = root / 'build' / ('preservation-' + version)
files = {
    'GodotIsland/GodotIsland.exe': build / 'GodotIsland.exe',
    'GodotIsland/bw_audio_decode.exe': build / 'bw_audio_decode.exe',
    'GodotIsland/README.md': root / 'README.md',
    'GodotIsland/GODOT-NOTICES.txt': build / 'GODOT-NOTICES.txt',
    'GodotIsland/MINIMP3-LICENSE.txt': root / 'tools/vendor/minimp3/LICENSE',
    'GodotIsland/Source/tools/bw_audio_decode.c': root / 'tools/bw_audio_decode.c',
    'GodotIsland/Source/tools/vendor/minimp3/minimp3.h': root / 'tools/vendor/minimp3/minimp3.h',
    'GodotIsland/Source/tools/vendor/minimp3/LICENSE': root / 'tools/vendor/minimp3/LICENSE',
    'GodotIsland/Source/tools/vendor/minimp3/SOURCE.json': root / 'tools/vendor/minimp3/SOURCE.json',
}
for directory, extensions in [('design', {'.json'}), ('game/scripts', {'.gd'}), ('game/shaders', {'.gdshader'})]:
    for file in (root / directory).iterdir():
        if file.is_file() and file.suffix in extensions:
            files['GodotIsland/Source/' + file.relative_to(root).as_posix()] = file
for path in ['game/main.tscn', 'game/project.godot', 'game/export_presets.cfg', 'tools/gen.py']:
    files['GodotIsland/Source/' + path] = root / path
for name, path in files.items():
    if not path.is_file():
        raise SystemExit(f'Missing own build input: {name}')
archive = root / 'build' / f'GodotIsland-{version}-development.zip'
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
    for name, file in files.items():
        z.write(file, name)
report = {
    'version': version + '-development',
    'status': 'local-unverified-in-game',
    'fileName': archive.name,
    'sizeBytes': archive.stat().st_size,
    'sha256': hashlib.file_digest(archive.open('rb'), 'sha256').hexdigest(),
    'entries': [{'path': name, 'sizeBytes': path.stat().st_size} for name, path in files.items()],
    'containsOriginalGameAssets': False,
    'requiresGame': 'Black & White',
    'requiresStoryImplementation': True,
}
(root / 'build' / f'package-{version}.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print(f'Local development package: {len(files)} entries; {report["sizeBytes"]} bytes; sha256 {report["sha256"]}')
