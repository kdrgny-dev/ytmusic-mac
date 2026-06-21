import XCTest
@testable import YTMusicMac

/// State-machine tests for NativeShellViewModel. We exercise the
/// pure-logic paths (ownQueue mutations, history stack, save-check) and
/// accept that webView-loading calls are no-ops in tests because the
/// shared WKWebView is never instantiated.
@MainActor
final class NativeShellViewModelTests: XCTestCase {

    var vm: NativeShellViewModel!

    override func setUp() async throws {
        try await super.setUp()
        vm = NativeShellViewModel.shared
        vm._testReset()
    }

    // MARK: - Own queue

    func testAddToQueueAppendsAtEnd() {
        vm.addToQueue(videoId: "a", title: "A", artist: "X", thumbnailURL: nil)
        vm.addToQueue(videoId: "b", title: "B", artist: "Y", thumbnailURL: nil)
        XCTAssertEqual(vm.ownQueue.map(\.videoId), ["a", "b"])
    }

    func testAddToQueuePlayNextInsertsAtFront() {
        vm.addToQueue(videoId: "a", title: "A")
        vm.addToQueue(videoId: "b", title: "B", playNext: true)
        XCTAssertEqual(vm.ownQueue.map(\.videoId), ["b", "a"],
                       "playNext should jump the queue, not append")
    }

    func testConsumeOwnQueueNextRemovesHeadAndReturnsTrue() {
        vm.addToQueue(videoId: "a", title: "A")
        vm.addToQueue(videoId: "b", title: "B")
        XCTAssertTrue(vm.consumeOwnQueueNext())
        XCTAssertEqual(vm.ownQueue.map(\.videoId), ["b"])
    }

    func testConsumeOwnQueueNextOnEmptyReturnsFalse() {
        XCTAssertFalse(vm.consumeOwnQueueNext(),
                       "no items means caller should fall through to YT's next")
        XCTAssertEqual(vm.ownQueue.count, 0)
    }

    func testRemoveFromOwnQueueRemovesById() {
        vm.addToQueue(videoId: "a", title: "A")
        vm.addToQueue(videoId: "b", title: "B")
        let b = vm.ownQueue.first(where: { $0.videoId == "b" })!
        vm.removeFromOwnQueue(b)
        XCTAssertEqual(vm.ownQueue.map(\.videoId), ["a"])
    }

    func testClearOwnQueueDropsEverything() {
        vm.addToQueue(videoId: "a", title: "A")
        vm.addToQueue(videoId: "b", title: "B")
        vm.clearOwnQueue()
        XCTAssertTrue(vm.ownQueue.isEmpty)
    }

    // MARK: - Navigation history

    func testOpenPlaylistPushesPreviousSectionOntoBackStack() {
        // We start at .home. Open a playlist -> back stack should have .home.
        let p = NativeShellViewModel.PlaylistSummary(
            id: "VLPLone", title: "One", thumbnailURL: nil)
        vm.openPlaylist(p)
        XCTAssertEqual(vm.mainSection, .playlist(p))
        XCTAssertTrue(vm.canGoBack, "back must be enabled after a navigation")
        XCTAssertFalse(vm.canGoForward, "forward stays disabled until we goBack")
    }

    func testGoBackRestoresPreviousSectionAndEnablesForward() {
        let p1 = NativeShellViewModel.PlaylistSummary(
            id: "VLPLone", title: "One", thumbnailURL: nil)
        vm.openPlaylist(p1)            // home -> playlist
        XCTAssertEqual(vm.mainSection, .playlist(p1))

        vm.goBack()                    // back to home
        XCTAssertEqual(vm.mainSection, .home)
        XCTAssertFalse(vm.canGoBack)
        XCTAssertTrue(vm.canGoForward)
    }

    func testGoForwardReplaysTheLastGoBack() {
        let p1 = NativeShellViewModel.PlaylistSummary(
            id: "VLPLone", title: "One", thumbnailURL: nil)
        vm.openPlaylist(p1)
        vm.goBack()                    // now on .home, forward = playlist
        vm.goForward()
        XCTAssertEqual(vm.mainSection, .playlist(p1))
        XCTAssertTrue(vm.canGoBack)
        XCTAssertFalse(vm.canGoForward)
    }

    func testNewNavigationClearsForwardStack() {
        // home -> playlist1 -> back to home -> open playlist2
        // Forward should NOT still point at playlist1 because we made
        // a fresh navigation from home.
        let p1 = NativeShellViewModel.PlaylistSummary(
            id: "VLPLone", title: "One", thumbnailURL: nil)
        let p2 = NativeShellViewModel.PlaylistSummary(
            id: "VLPLtwo", title: "Two", thumbnailURL: nil)
        vm.openPlaylist(p1)
        vm.goBack()
        XCTAssertTrue(vm.canGoForward)
        vm.openPlaylist(p2)
        XCTAssertFalse(vm.canGoForward,
                       "a new navigation invalidates the forward history")
    }

    func testGoBackOnEmptyStackIsNoOp() {
        let initialSection = vm.mainSection
        vm.goBack()
        XCTAssertEqual(vm.mainSection, initialSection)
        XCTAssertFalse(vm.canGoBack)
    }

    // MARK: - Save / library detection

    func testIsPlaylistSavedChecksAgainstSidebarList() {
        let saved = NativeShellViewModel.PlaylistSummary(
            id: "VLPLsaved", title: "Saved", thumbnailURL: nil)
        let other = NativeShellViewModel.PlaylistSummary(
            id: "VLPLother", title: "Other", thumbnailURL: nil)
        vm._testSetPlaylists([saved])
        XCTAssertTrue(vm.isPlaylistSaved(saved))
        XCTAssertFalse(vm.isPlaylistSaved(other))
    }

    // MARK: - Search tab state

    func testToggleSearchClearsQueryAndResetsTab() {
        vm.isSearchVisible = true
        vm.searchQuery = "Some query"
        vm.searchTab = .album
        vm.toggleSearch()   // closes
        XCTAssertFalse(vm.isSearchVisible)
        XCTAssertEqual(vm.searchQuery, "")
        XCTAssertEqual(vm.searchTab, .playlist,
                       "tab should reset to default on close")
    }
}
