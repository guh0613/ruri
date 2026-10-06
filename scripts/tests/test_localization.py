import json
from pathlib import Path
import sys
import tempfile
import unittest
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.localization import candidates, localized_concatenations
from lib.localization_catalog import (catalog_text, localization_value, read_catalogs, read_json, signature,
                                      coverage, source_hash, accept_translations, read_baseline,
                                      validate_policy, shipping_languages, check_completeness, REQUIRED_COMPLETE)


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
            entry = {'comment': 'File count test fixture.', 'extractionState': 'manual', 'localizations': {'zh-Hans': unit('%1$lld files'), 'en': unit('%1$@ files')}}
            catalog = {'sourceLanguage': 'zh-Hans', 'version': '1.0', 'strings': {'Test.files': entry}}
            path.write_text(catalog_text(catalog))
            with self.assertRaisesRegex(ValueError, 'changes parameters'):
                read_catalogs(root)
            del entry['localizations']['zh-Hans']
            path.write_text(catalog_text(catalog))
            with self.assertRaisesRegex(ValueError, 'without a source'):
                read_catalogs(root)


class CoverageTests(unittest.TestCase):
    def setUp(self):
        required = set(REQUIRED_COMPLETE)
        REQUIRED_COMPLETE.clear()
        self.addCleanup(lambda: REQUIRED_COMPLETE.update(required))
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.resources = self.root / 'Sources/RuriLocalization/Resources'
        self.resources.mkdir(parents=True)
        (self.root / 'scripts/lib').mkdir(parents=True)

    def catalog(self, entries, table='Test'):
        data = {'sourceLanguage': 'zh-Hans', 'version': '1.0', 'strings': {
            key: {'comment': 'Translation test fixture.', 'extractionState': 'manual', 'localizations': localizations} for key, localizations in entries.items()
        }}
        (self.resources / (table + '.xcstrings')).write_text(catalog_text(data))
        return read_catalogs(self.root)

    def test_threshold_staleness_and_selective_acceptance(self):
        entries = {f'Test.message{i}': {'zh-Hans': unit(f'Source {i}'), 'fr': unit(f'Translation {i}')} for i in range(20)}
        del entries['Test.message19']['fr']
        catalogs = self.catalog(entries)
        before = coverage(catalogs, {})['fr']
        self.assertEqual((len(before['missing']), len(before['stale'])), (1, 19))
        self.assertEqual(shipping_languages(self.root), ['zh-Hans'])
        self.assertEqual(accept_translations(self.root, catalogs, 'fr', accept_all=True), 19)
        self.assertEqual(shipping_languages(self.root), ['fr', 'zh-Hans'])
        entries['Test.message0']['zh-Hans'] = unit('Revised source')
        catalogs = self.catalog(entries)
        self.assertEqual(shipping_languages(self.root), ['zh-Hans'])
        self.assertEqual(coverage(catalogs, read_baseline(self.root))['fr']['stale'], ['Test:Test.message0'])
        accept_translations(self.root, catalogs, 'fr', keys=['Test.message0'])
        self.assertEqual(shipping_languages(self.root), ['fr', 'zh-Hans'])
        with self.assertRaisesRegex(ValueError, 'missing translation'):
            accept_translations(self.root, catalogs, 'fr', keys=['Test.message19'])
        with self.assertRaisesRegex(ValueError, 'missing translation'):
            accept_translations(self.root, catalogs, 'fr', keys=['Unknown.key'])

    def test_required_english_and_cli_are_checked_separately(self):
        catalogs = self.catalog({'Test.title': {'zh-Hans': unit('Title')}})
        status = validate_policy(self.root, catalogs)
        check_completeness(catalogs, status)
        REQUIRED_COMPLETE.add('en')
        try:
            with self.assertRaisesRegex(ValueError, 'required localization'):
                check_completeness(catalogs, status)
        finally:
            REQUIRED_COMPLETE.discard('en')
        catalogs = self.catalog({'CLISetup.title': {'zh-Hans': unit('CLI'), 'en': unit('CLI')}}, 'CLISetup')
        with self.assertRaisesRegex(ValueError, 'stale CLI'):
            check_completeness(catalogs, validate_policy(self.root, catalogs))
        accept_translations(self.root, catalogs, 'en', keys=['CLISetup.title'])
        check_completeness(catalogs, validate_policy(self.root, catalogs))

    def test_integer_categories_and_other_only_languages(self):
        entries = {'Test.files': {'zh-Hans': plural(other='%lld files'), 'fr': plural(one='%lld file', other='%lld files')}}
        catalogs = self.catalog(entries)
        with self.assertRaisesRegex(ValueError, 'missing plural categories'):
            validate_policy(self.root, catalogs)
        entries['Test.files']['fr'] = plural(one='%lld file', many='%lld files', other='%lld files')
        entries['Test.files']['ja'] = unit('%lld files')
        validate_policy(self.root, self.catalog(entries))
        entries['Test.files']['fr'] = unit('%lld files')
        with self.assertRaisesRegex(ValueError, 'must pluralize'):
            validate_policy(self.root, self.catalog(entries))
        del entries['Test.files']['fr']
        entries['Test.files']['xx'] = unit('%lld files')
        with self.assertRaisesRegex(ValueError, 'CLDR'):
            validate_policy(self.root, self.catalog(entries))

    def test_source_hash_tracks_structure_but_not_editor_state(self):
        catalogs = self.catalog({'Test.files': {'zh-Hans': unit('%lld files')}})
        item = catalogs['Test:Test.files']
        original = source_hash(item)
        item['entry']['localizations']['zh-Hans']['stringUnit']['state'] = 'needs_review'
        self.assertEqual(source_hash(item), original)
        item['entry']['localizations']['zh-Hans'] = plural(other='%lld files')
        self.assertNotEqual(source_hash(item), original)
        with self.assertRaisesRegex(ValueError, 'reviewed exemption'):
            validate_policy(self.root, self.catalog({'Test.files': {'zh-Hans': unit('%lld files')}}))
        path = self.root / 'scripts/lib/localization-plural-exempt.json'
        path.write_text(json.dumps([{'key': 'Test:Test.files', 'reason': ''}]))
        with self.assertRaisesRegex(ValueError, 'exemption'):
            validate_policy(self.root, catalogs)


class SourceScanTests(unittest.TestCase):
    def test_full_width_punctuation_and_interpolated_literals(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'Sources').mkdir()
            (root / 'Sources/Test.swift').write_text('let text = "\\(label)：\\(value)"\n// "，"\nlet brand = "Java"\n')
            found = list(candidates(root))
            self.assertEqual(len(found), 1)
            self.assertIn('：', found[0]['literal'])

    def test_composition_scan_ignores_comments_and_machine_data(self):
        cases = [
            ('let text = Messages.Common.cancel.localized + suffix', True),
            ('let text = prefix + Messages.Common.filesAndSize(count, size).localized', True),
            ('let text = prefix + message.localized', True),
            ('let text = Messages.Common.cancel.localized\n + suffix', True),
            ('// Messages.Common.cancel.localized + suffix', False),
            ('let text = "value.localized + suffix"', False),
            ('rows += [Messages.Common.cancel.localized]', False),
            ('let value = count + 1; print(Messages.Common.cancel.localized)', False),
        ]
        for source, expected in cases:
            with self.subTest(source=source):
                self.assertEqual(bool(localized_concatenations(source)), expected)


if __name__ == '__main__':
    unittest.main()
