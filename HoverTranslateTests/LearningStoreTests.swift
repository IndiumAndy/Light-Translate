import XCTest
@testable import HoverTranslate

/// v0.4: the user's own saved list. Every case uses a temporary directory and
/// synthetic text; no real user data is involved.
final class LearningStoreTests: XCTestCase {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("HoverTranslateTests-" + UUID().uuidString, isDirectory: true)
    }

    func testExplicitSaveAndDeleteRoundTrip() throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LearningStore(directory: dir)
        XCTAssertTrue(try store.all().isEmpty)
        try store.save(SavedEntry(source: "Settings",
                                  translation: "设置",
                                  context: "Open Settings"))
        let reloaded = LearningStore(directory: dir)
        XCTAssertEqual(try reloaded.all().count, 1)
        try reloaded.removeAll()
        XCTAssertTrue(try LearningStore(directory: dir).all().isEmpty)
    }

    func testNothingIsWrittenUntilSomethingIsSaved() throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try LearningStore(directory: dir).all()
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent(LearningStore.fileName).path),
                       "reading an empty list must not create a file")
    }

    func testEntriesAndTheirIdentitySurviveARestart() throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = SavedEntry(source: "charge", translation: "收费", context: "a service charge")
        let store = LearningStore(directory: dir)
        try store.save(first)
        try store.save(SavedEntry(source: "charge", translation: "充电", context: "battery charge"))

        let afterRestart = try LearningStore(directory: dir).all()
        XCTAssertEqual(afterRestart.count, 2)
        XCTAssertEqual(afterRestart.first, first, "the stored entry keeps its id and date")
        XCTAssertEqual(afterRestart.map(\.translation), ["收费", "充电"])
    }

    /// The same word in a different context is a different entry, and removing
    /// one must not remove the other.
    func testTheSameSourceWithADifferentContextIsKeptSeparately() throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LearningStore(directory: dir)
        let battery = SavedEntry(source: "charge", translation: "充电", context: "charge the battery")
        let fee = SavedEntry(source: "charge", translation: "收费", context: "a service charge")
        try store.save(battery)
        try store.save(fee)

        try store.remove(id: battery.id)
        let remaining = try store.all()
        XCTAssertEqual(remaining, [fee])
    }

    func testACorruptFileIsReportedAndNeverOverwritten() throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(LearningStore.fileName)
        let garbage = "{ this is not the saved list"
        try Data(garbage.utf8).write(to: file)

        let store = LearningStore(directory: dir)
        XCTAssertThrowsError(try store.all()) { error in
            XCTAssertEqual(error as? LearningStoreError, .unreadable)
        }
        XCTAssertThrowsError(try store.save(SavedEntry(source: "a", translation: "b", context: "")),
                             "a save must not silently replace a file it could not read")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), garbage)
    }

    func testClearingRecoversFromACorruptFile() throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(LearningStore.fileName)
        try Data("[[[".utf8).write(to: file)

        let store = LearningStore(directory: dir)
        try store.removeAll()
        XCTAssertTrue(try store.all().isEmpty)
        try store.save(SavedEntry(source: "Settings", translation: "设置", context: ""))
        XCTAssertEqual(try store.all().count, 1)
    }

    func testTheDirectoryIsCreatedOnFirstSave() throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try LearningStore(directory: dir).save(SavedEntry(source: "a", translation: "b", context: ""))
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }
}
