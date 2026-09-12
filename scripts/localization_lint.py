"""Find newly introduced user-facing literals; explicit exceptions document syntax/data."""
import json
from pathlib import Path
import re
from swift_strings import Scanner

HAN = re.compile(r'[\u3400-\u9fff]')
UI_ARGUMENT = re.compile(r'(?:Text|Button|Label|Section|Toggle|Picker|TextField|SecureField|ProgressView|ContentUnavailableView|LabeledContent|CommandMenu|navigationTitle|navigationSubtitle|help|accessibilityLabel|alert|confirmationDialog)\(\s*$')
BRANDS = {'Ruri', 'Minecraft', 'Java', 'Microsoft', 'Modrinth', 'CurseForge', 'Fabric', 'Legacy Fabric', 'Quilt', 'Forge', 'NeoForge', 'LiteLoader', 'OptiFine', 'JVM', 'Metaspace', 'PNG', 'UUID', 'API Key', 'Beta', 'Alpha'}


def candidates(root):
    for path in sorted((root / 'Sources').rglob('*.swift')):
        if 'RuriLocalization' in path.parts:
            continue
        source = path.read_text()
        scanner = Scanner(source)

        def walk(start=0, end=None):
            for node in scanner.nodes(start, end):
                yield node
                for kind, a, b in node['parts']:
                    if kind == 'expr':
                        yield from walk(a, b)

        for node in walk():
            content = ''.join(source[a:b] for kind, a, b in node['parts'] if kind == 'text')
            prefix = source[max(0, node['start'] - 150):node['start']]
            human = bool(HAN.search(content)) or bool(re.search('[A-Za-z]{3}', content) and ' ' in content)
            human |= bool(UI_ARGUMENT.search(prefix) and re.search('[A-Za-z]', content) and content not in BRANDS)
            if human:
                yield {'file': str(path.relative_to(root)), 'literal': source[node['start']:node['end']],
                       'line': source[:node['start']].count('\n') + 1}


def check(root):
    path = root / 'scripts/localization-exceptions.json'
    exceptions = json.loads(path.read_text())
    allowed = {(entry['file'], entry['literal']) for entry in exceptions if entry.get('reason', '').strip()}
    unresolved = [entry for entry in candidates(root) if (entry['file'], entry['literal']) not in allowed]
    if unresolved:
        raise ValueError('User-facing literals need resources or a reviewed syntax/data exception:\n' + '\n'.join(
            f"{entry['file']}:{entry['line']}: {entry['literal'][:100]}" for entry in unresolved))
