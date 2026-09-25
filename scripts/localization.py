#!/usr/bin/env python3
"""Validate native localization resources and generate typed Swift accessors.

The zh-Hans .strings files are the source of truth. Each entry declares its
accessor with @symbol and its ordered text/integer/decimal parameters with
@args. Preserve keys when editing text. Use .stringsdict for plural variants.
Run without flags to regenerate Swift, or --check in builds and CI.
Only complete .lproj directories are included in the supported language list.
"""
import argparse
import json
from pathlib import Path
import plistlib
import re
import sys
sys.dont_write_bytecode = True
from lib.localization import check_source_literals, check_bundle

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / 'Sources/RuriLocalization/Resources'
OUTPUT = ROOT / 'Sources/RuriLocalization/Generated'
ENTRY = re.compile(r'/\*\s*@symbol\s+(\w+)\.(\w+)\s+@args\s+([a-z,\-]+)\s*\*/\s*("(?:\\.|[^"\\])*")\s*=\s*("(?:\\.|[^"\\])*")\s*;', re.S)
FORMAT = re.compile(r'%(?:(\d+)\$)?(lld|@|g|f|d|%)')


def quoted(value):
    return json.dumps(value, ensure_ascii=False)


def documentation(value, table, key):
    # Keep the source text visible in code completion and Quick Help without
    # asking callers to duplicate it in source comments.
    lines = [('        /// ' + line).rstrip() for line in value.replace('%%', '%').splitlines()]
    lines += ['        ///', f'        /// Resource: `{table}.{key}`.']
    return lines


def signature(value):
    result = {}
    position = 0
    cursor = 0
    for match in FORMAT.finditer(value):
        if '%' in value[cursor:match.start()]:
            raise ValueError('Unsupported format token in ' + value)
        cursor = match.end()
        index, kind = match.groups()
        if kind == '%':
            continue
        position += 1
        index = int(index) if index else position
        resolved = 'integer' if kind in ('lld', 'd') else 'text' if kind == '@' else 'decimal'
        if index in result and result[index] != resolved:
            raise ValueError('Inconsistent argument in ' + value)
        result[index] = resolved
    if '%' in value[cursor:]:
        raise ValueError('Unescaped percent in ' + value)
    return result


def entries(path):
    text = path.read_text()
    matches = list(ENTRY.finditer(text))
    remainder = ENTRY.sub('', text)
    remainder = re.sub(r'/\*.*?\*/|//[^\n]*', '', remainder, flags=re.S)
    if remainder.strip():
        raise ValueError(f'{path}: invalid entry or missing @symbol/@args metadata')
    for m in matches:
        group, name, kinds, key, value = m.groups()
        yield group, name, [] if kinds == '-' else kinds.split(','), json.loads(key), json.loads(value)


def run(check):
    check_source_literals(ROOT)
    groups = {}
    catalogs = {}
    symbols = set()
    for path in sorted((RESOURCES / 'zh-Hans.lproj').glob('*.strings')):
        table = path.stem
        for group, name, kinds, key, value in entries(path):
            identity = table + ':' + key
            if identity in catalogs or (group, name) in symbols:
                raise ValueError('Duplicate key or symbol: ' + identity)
            if signature(value) != {i + 1: kind for i, kind in enumerate(kinds)}:
                raise ValueError('Argument declaration does not match format: ' + identity)
            symbols.add((group, name))
            catalogs[identity] = (value, kinds)
            groups.setdefault(group, []).append((name, kinds, key, value, table))
    languages = sorted(RESOURCES.glob('*.lproj'))
    for language in languages:
        translated_keys = set()
        for path in language.glob('*.strings'):
            for _, _, kinds, key, value in entries(path):
                identity = path.stem + ':' + key
                if identity in translated_keys:
                    raise ValueError('Duplicate translation: ' + identity)
                translated_keys.add(identity)
                if identity not in catalogs:
                    raise ValueError('Unknown translation: ' + identity)
                if signature(value) != {i + 1: kind for i, kind in enumerate(catalogs[identity][1])}:
                    raise ValueError('Translation changes parameters: ' + identity)
        for path in language.glob('*.stringsdict'):
            for key, spec in plistlib.loads(path.read_bytes()).items():
                identity = path.stem + ':' + key
                if identity not in catalogs:
                    raise ValueError('Unknown plural: ' + identity)
                if not isinstance(spec.get('NSStringLocalizedFormatKey'), str):
                    raise ValueError('Missing plural format: ' + identity)
                variables = set(re.findall(r'%\d*\$?#@([^@]+)@', spec['NSStringLocalizedFormatKey']))
                if not variables:
                    raise ValueError('Plural format has no variable: ' + identity)
                expanded = re.sub(r'%(\d*\$?)#@([^@]+)@', lambda m: '%' + m[1] + 'lld', spec['NSStringLocalizedFormatKey'])
                expected_signature = {i + 1: kind for i, kind in enumerate(catalogs[identity][1])}
                if signature(expanded) != expected_signature:
                    raise ValueError('Plural format changes parameters: ' + identity)
                for variable in variables:
                    rule = spec[variable]
                    if rule.get('NSStringFormatSpecTypeKey') != 'NSStringPluralRuleType' or rule.get('NSStringFormatValueTypeKey') != 'lld' or 'other' not in rule:
                        raise ValueError('Invalid plural rule: ' + identity)
                    for category, text in rule.items():
                        if category.startswith('NSString'): continue
                        if category not in ['zero', 'one', 'two', 'few', 'many', 'other']:
                            raise ValueError('Invalid plural category: ' + identity)
                        variant_signature = signature(text)
                        if any(kind != 'integer' for kind in variant_signature.values()):
                            raise ValueError('Plural variants must format their numeric argument: ' + identity)
        if translated_keys != set(catalogs):
            raise ValueError(f'{language.name}: translations must be complete before shipping; missing {len(set(catalogs) - translated_keys)} keys')
    expected = {}
    for group, items in groups.items():
        lines = ['// Generated by scripts/localization.py. Edit the resource files instead.', 'import Foundation', '', 'extension Messages {', f'    public enum {group} {{']
        for name, kinds, key, value, table in items:
            lines += documentation(value, table, key)
            if not kinds:
                lines += [f'        public static var {name}: LocalizedMessage {{', f'            .init(key: {quoted(key)}, table: {quoted(table)}, fallback: {quoted(value)})', '        }']
            else:
                types = {'text': 'String', 'integer': 'Int64', 'decimal': 'Double'}
                args = ', '.join(f'_ value{i}: {types[kind]}' for i, kind in enumerate(kinds))
                values = ', '.join(f'.{kind}(value{i})' for i, kind in enumerate(kinds))
                lines += [f'        public static func {name}({args}) -> LocalizedMessage {{', f'            .init(key: {quoted(key)}, table: {quoted(table)}, fallback: {quoted(value)}, arguments: [{values}])', '        }']
        lines.append('        static let definitions: [String: MessageDefinition] = [')
        for name, kinds, key, value, table in items:
            args = ', '.join('.' + kind for kind in kinds)
            lines.append(f'            {quoted(table + ":" + key)}: .init({quoted(value)}, [{args}]),')
        lines += ['        ]', '    }', '}', '']
        expected[group + '.swift'] = '\n'.join(lines)
    lines = ['// Generated by scripts/localization.py. Edit the resource files instead.', 'public enum Messages {}', '', 'enum MessageCatalog {', '    static let definitions: [String: MessageDefinition] = {', '        var result: [String: MessageDefinition] = [:]']
    for group in sorted(groups):
        lines.append(f'        result.merge(Messages.{group}.definitions) {{ first, _ in first }}')
    lines += ['        return result', '    }()', '}', '']
    expected['MessageCatalog.swift'] = '\n'.join(lines)
    expected['SupportedLocalizations.swift'] = '// Generated by scripts/localization.py.\nenum SupportedLocalizations {\n    static let languages = [' + ', '.join(quoted(p.stem) for p in languages) + ']\n}\n'
    stale = []
    for name, text in expected.items():
        path = OUTPUT / name
        if not path.exists() or path.read_text() != text:
            if check: stale.append(str(path.relative_to(ROOT)))
            else: path.write_text(text)
    for path in OUTPUT.glob('*.swift'):
        if path.name not in expected:
            if check: stale.append(str(path.relative_to(ROOT)))
            else: path.unlink()
    if stale:
        raise ValueError('Generated code is stale. Run scripts/localization.py:\n' + '\n'.join(stale))
    print(f'Localization: {len(catalogs)} messages, {len(groups)} accessor groups, resources valid.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--check', action='store_true')
    mode.add_argument('--bundle', type=Path, help='Verify resources in a built app after relocation')
    parser.add_argument('--cli', type=Path, help='Also verify a standalone CLI with --bundle')
    options = parser.parse_args()
    if options.cli and not options.bundle:
        parser.error('--cli requires --bundle')
    try:
        if options.bundle:
            check_bundle(options.bundle.resolve(), options.cli.resolve() if options.cli else None)
        else:
            run(options.check)
    except (ValueError, KeyError, OSError) as error:
        sys.exit(str(error))
