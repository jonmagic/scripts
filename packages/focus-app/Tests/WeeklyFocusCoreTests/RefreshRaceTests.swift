import XCTest
@testable import WeeklyFocusCore

/// Intercepts board traffic so the test can hold a fetch open while a write lands.
final class GatedProtocol: URLProtocol {
    nonisolated(unsafe) static let fetchStarted = DispatchSemaphore(value: 0)
    nonisolated(unsafe) static let releaseFetch = DispatchSemaphore(value: 0)
    nonisolated(unsafe) static var itemsBody = Data()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        // Blocking here would stall the whole session, including the write this
        // test needs to interleave, so the wait happens off the loading thread.
        guard request.httpMethod == "GET" else {
            finish(with: Data("{}".utf8))
            return
        }

        DispatchQueue.global().async { [self] in
            Self.fetchStarted.signal()
            Self.releaseFetch.wait()
            finish(with: Self.itemsBody)
        }
    }

    private func finish(with body: Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["ETag": "\"stale\""]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class RefreshRaceTests: XCTestCase {
    func testAFetchThatOverlapsACompletionDoesNotResurrectTheTask() async throws {
        let task = FocusTask(id: 1, nodeID: "n", title: "still open", status: "Todo", focus: 1)

        // What the server would have said before the completion was written.
        GatedProtocol.itemsBody = Data("""
        [{"id":1,"node_id":"n","fields":[
          {"id":\(BrainBoard.Field.title),"name":"Title","data_type":"title",
           "value":{"raw":"still open","html":"still open"}},
          {"id":\(BrainBoard.Field.status),"name":"Status","data_type":"single_select",
           "value":{"id":"\(BrainBoard.Status.todo)","name":{"raw":"Todo","html":"Todo"},"color":"BLUE"}}
        ]}]
        """.utf8)

        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("weekly-focus-race-\(UUID().uuidString)")
            .appendingPathComponent("board.json")
        defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
        BoardCache.save(CachedBoard(tasks: [task], etag: nil, fetchedAt: Date()), to: cacheURL)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GatedProtocol.self]
        let store = BoardTaskStore(
            client: ProjectsV2Client(
                token: "t",
                session: URLSession(configuration: configuration),
                baseURL: URL(string: "https://example.invalid")!
            ),
            cacheURL: cacheURL
        )

        let refresh = Task { try await store.refresh() }
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                GatedProtocol.fetchStarted.wait()
                continuation.resume()
            }
        }

        try await store.complete(task)
        GatedProtocol.releaseFetch.signal()
        _ = try await refresh.value

        XCTAssertEqual(store.cachedTasks?.first?.status, "Done")
        XCTAssertEqual(BoardCache.load(from: cacheURL)?.tasks.first?.status, "Done")
    }
}
