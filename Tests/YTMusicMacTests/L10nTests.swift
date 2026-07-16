import XCTest
@testable import YTMusicMac

/// The catalogs are plain dictionaries, so nothing about them is checked at
/// compile time. These tests are the whole safety net: a missing translation,
/// a placeholder that doesn't match its counterpart, or two domains claiming
/// the same key are all silent failures without them.
final class L10nTests: XCTestCase {

    override func tearDown() {
        L10n._testLanguageOverride = nil
        super.tearDown()
    }

    // MARK: - Catalog integrity

    func testEnglishAndTurkishDefineTheSameKeys() {
        let en = Set(Strings.en.keys)
        let tr = Set(Strings.tr.keys)
        XCTAssertEqual(en, tr,
                       "Untranslated: \(en.subtracting(tr).sorted()) — Stray Turkish-only: \(tr.subtracting(en).sorted())")
    }

    func testCatalogIsNotEmpty() {
        XCTAssertGreaterThan(Strings.en.count, 200)
    }

    func testNoEmptyValues() {
        for (key, value) in Strings.en where value.isEmpty {
            XCTFail("Empty English value for \(key)")
        }
        for (key, value) in Strings.tr where value.isEmpty {
            XCTFail("Empty Turkish value for \(key)")
        }
    }

    /// `merged` keeps the first table's winner and only asserts in debug, so a
    /// collision between two domains would quietly drop one side's string in a
    /// release build.
    func testDomainTablesAreDisjoint() {
        for (tables, name) in [(Strings.enTables, "en"), (Strings.trTables, "tr")] {
            var seen: [String: Int] = [:]
            for (index, table) in tables.enumerated() {
                for key in table.keys {
                    if let first = seen[key] {
                        XCTFail("\(name): key '\(key)' defined in both table \(first) and table \(index)")
                    }
                    seen[key] = index
                }
            }
        }
    }

    // MARK: - Placeholders

    /// `String(format:)` reads its varargs positionally by type. A key whose
    /// translations disagree on placeholder order or type reads garbage off
    /// the stack — a crash or corrupted text, not a visible typo.
    func testPlaceholdersMatchAcrossLanguages() {
        for (key, enValue) in Strings.en {
            guard let trValue = Strings.tr[key] else { continue }
            XCTAssertEqual(Self.placeholders(in: enValue), Self.placeholders(in: trValue),
                           "Placeholder mismatch for '\(key)': en=\(enValue) tr=\(trValue)")
        }
    }

    /// Ordered list of format specifiers, so "%@ %d" and "%d %@" don't compare
    /// equal. `%%` is a literal percent and carries no argument.
    private static func placeholders(in value: String) -> [String] {
        var found: [String] = []
        var rest = Substring(value)
        while let percent = rest.firstIndex(of: "%") {
            let after = rest.index(after: percent)
            guard after < rest.endIndex else { break }
            let specifier = rest[after]
            if specifier != "%" { found.append("%\(specifier)") }
            rest = rest[rest.index(after: after)...]
        }
        return found
    }

    // MARK: - Plurals

    /// `L10n.plural` derives ".one"/".other" by string concatenation, so a
    /// half-defined pair fails only for a specific count at runtime.
    func testPluralKeysComeInPairs() {
        for table in [Strings.en, Strings.tr] {
            let oneKeys = table.keys.filter { $0.hasSuffix(".one") }
            for oneKey in oneKeys {
                let base = String(oneKey.dropLast(4))
                XCTAssertNotNil(table["\(base).other"], "\(base) has .one but no .other")
            }
            let otherKeys = table.keys.filter { $0.hasSuffix(".other") }
            for otherKey in otherKeys {
                let base = String(otherKey.dropLast(6))
                XCTAssertNotNil(table["\(base).one"], "\(base) has .other but no .one")
            }
        }
    }

    // MARK: - Lookup behaviour

    func testMissingKeyFallsBackToTheKeyItself() {
        XCTAssertEqual(L10n.t("this.key.does.not.exist"), "this.key.does.not.exist")
    }

    func testLookupFollowsTheActiveLanguage() {
        L10n._testLanguageOverride = .english
        XCTAssertEqual(L10n.t("common.cancel"), "Cancel")
        L10n._testLanguageOverride = .turkish
        XCTAssertEqual(L10n.t("common.cancel"), "İptal")
    }

    /// The cache is keyed by language; a stale cache would keep serving the
    /// previous language's strings after a switch.
    func testSwitchingLanguageInvalidatesTheCache() {
        L10n._testLanguageOverride = .turkish
        XCTAssertEqual(L10n.t("transport.play"), "Çal")
        L10n._testLanguageOverride = .english
        XCTAssertEqual(L10n.t("transport.play"), "Play")
        L10n._testLanguageOverride = .turkish
        XCTAssertEqual(L10n.t("transport.play"), "Çal")
    }

    func testInterpolationSubstitutesArguments() {
        L10n._testLanguageOverride = .english
        XCTAssertEqual(L10n.t("update.available", "1.2.3"), "New version available: v1.2.3")
    }

    func testPluralPicksSingularOnlyForExactlyOne() {
        L10n._testLanguageOverride = .english
        XCTAssertEqual(L10n.plural("sleep.minutes", 1), "1 minute")
        XCTAssertEqual(L10n.plural("sleep.minutes", 5), "5 minutes")
        XCTAssertEqual(L10n.plural("sleep.minutes", 0), "0 minutes")
    }

    /// Turkish takes no plural suffix after a numeral, so both branches must
    /// render the same noun — a "5 şarkılar" would be wrong.
    func testTurkishPluralHasNoSuffixChange() {
        L10n._testLanguageOverride = .turkish
        XCTAssertEqual(L10n.plural("sleep.minutes", 1), "1 dakika")
        XCTAssertEqual(L10n.plural("sleep.minutes", 5), "5 dakika")
    }

    // MARK: - AppLanguage

    func testExplicitLanguagesResolveToThemselves() {
        XCTAssertEqual(AppLanguage.english.resolved, .english)
        XCTAssertEqual(AppLanguage.turkish.resolved, .turkish)
        XCTAssertEqual(AppLanguage.english.code, "en")
        XCTAssertEqual(AppLanguage.turkish.code, "tr")
    }

    func testSystemResolvesToAShippedLanguage() {
        // Whatever the test machine's locale is, .system must land on a
        // language we actually have strings for rather than passing e.g. "fr"
        // through to InnerTube's hl.
        let resolved = AppLanguage.system.resolved
        XCTAssertTrue([.english, .turkish].contains(resolved))
    }

    func testLanguageNamesAreNotTranslated() {
        // A user stranded in a language they can't read must still recognise
        // their own language in the picker.
        XCTAssertEqual(AppLanguage.english.label, "English")
        XCTAssertEqual(AppLanguage.turkish.label, "Türkçe")
    }

    // MARK: - AppRegion

    func testExplicitRegionCodeIsItsRawValue() {
        XCTAssertEqual(AppRegion.TR.code, "TR")
        XCTAssertEqual(AppRegion.US.code, "US")
        XCTAssertEqual(AppRegion.JP.code, "JP")
    }

    func testSystemRegionNeverResolvesToEmpty() {
        // YT rejects a missing gl, so .system must always produce something.
        XCTAssertFalse(AppRegion.system.code.isEmpty)
    }

    func testRegionLabelsFollowTheGivenLanguage() {
        XCTAssertEqual(AppRegion.DE.label(in: .english), "Germany")
        XCTAssertEqual(AppRegion.DE.label(in: .turkish), "Almanya")
    }

    func testRegionListHasNoDuplicates() {
        let codes = AppRegion.allCases.map(\.rawValue)
        XCTAssertEqual(codes.count, Set(codes).count)
    }
}
