"""Reject bundled Mach-O dependencies that would load mutable Homebrew code as root."""
import pathlib
import subprocess
import sys

app = pathlib.Path(sys.argv[1]).resolve()
resources = app / 'Contents/Resources'
errors = []
for binary in [resources / 'openconnect', *(resources / 'lib').glob('*.dylib')]:
    dependencies = subprocess.check_output(['/usr/bin/otool', '-L', str(binary)], text=True)
    # dylib install names appear as the first entry and may contain the old build path.
    lines = dependencies.splitlines()[1:]
    if binary.suffix == '.dylib':
        lines = lines[1:]
    for line in lines:
        dependency = line.strip().split(' (compatibility version', 1)[0]
        if dependency.startswith(('/usr/lib/', '/System/Library/')):
            continue
        if dependency.startswith('@executable_path/'):
            target = resources / dependency.removeprefix('@executable_path/')
        elif dependency.startswith('@loader_path/'):
            target = binary.parent / dependency.removeprefix('@loader_path/')
        else:
            errors.append(f'{binary.name}: untrusted dependency {dependency}')
            continue
        if resources not in target.resolve().parents or not target.is_file():
            errors.append(f'{binary.name}: missing/external dependency {dependency}')
if errors:
    sys.exit('\n'.join(errors))
print('Bundled OpenConnect dependencies stay inside the app or Apple system libraries.')
