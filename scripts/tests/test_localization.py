import json
from pathlib import Path
import sys
import tempfile
import unittest
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.localization_catalog import catalog_text, localization_value, read_catalogs, read_json, signature


def unit(value):
    return {'stringUnit': {'state': 'translated', 'value': value}}


def plural(**variants):
    return {'variations': {'plural': {key: unit(value) for key, value in variants.items()}}}


class CatalogTests(unittest.TestCase):
    def test_formats_and_reordered_plurals(self):
        self.assertEqual(signature('%2$@ / %1$lld %%'), {2: 'text', 1: 'integer'})
        node = plural(one='%2$@ has %1$lld file', other='%2$@ has %1$lld files')
        self.assertEqual(localization_value(node)[1:], ({2: 'text', 1: 'integer'}, {1}))
        for invalid in ['100%', '%s', '%n', '%0$lld', '%1$@ %1$lld']:
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                signature(invalid)
        for invalid in [plural(one='one file', other='%lld files'), plural(other='files'), plural(other='%lld files', invalid='%lld files')]:
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                localization_value(invalid)

    def test_multiple_plural_substitutions_preserve_positions(self):
        node = {**unit('%1$#@selected@ / %2$#@total@'), 'substitutions': {
            'selected': {'argNum': 1, 'formatSpecifier': 'lld', **plural(one='%lld selected', other='%lld selected')},
            'total': {'argNum': 2, 'formatSpecifier': 'lld', **plural(one='%lld file', other='%lld files')},
        }}
        self.assertEqual(localization_value(node), ('%1$lld selected / %2$lld files', {1: 'integer', 2: 'integer'}, {1, 2}))
        node['substitutions']['total']['argNum'] = 3
        with self.assertRaisesRegex(ValueError, 'position'):
            localization_value(node)

    def test_duplicate_json_keys_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'test.json'
            path.write_text('{"key": 1, "key": 2}')
            with self.assertRaisesRegex(ValueError, 'duplicate'):
                read_json(path)

    def test_catalog_rejects_unknown_source_and_changed_arguments(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            resources = root / 'Sources/RuriLocalization/Resources'
            resources.mkdir(parents=True)
            path = resources / 'Test.xcstrings'
            entry = {'extractionState': 'manual', 'localizations': {'zh-Hans': unit('%1$lld files'), 'en': unit('%1$@ files')}}
            catalog = {'sourceLanguage': 'zh-Hans', 'version': '1.0', 'strings': {'Test.files': entry}}
            path.write_text(catalog_text(catalog))
            with self.assertRaisesRegex(ValueError, 'changes parameters'):
                read_catalogs(root)
            del entry['localizations']['zh-Hans']
            path.write_text(catalog_text(catalog))
            with self.assertRaisesRegex(ValueError, 'without a source'):
                read_catalogs(root)


if __name__ == '__main__':
    unittest.main()
