import Foundation

/// Minimal Projects V2 client built on `URLSession`.
///
/// Reads and field updates use the REST Projects API, which is roughly twice as fast
/// as GraphQL for reads and lets several field writes ride in a single `PATCH`.
/// Creating a draft item is the one operation REST cannot express -- it only accepts
/// existing issues and pull requests -- so that path falls back to GraphQL.
public struct ProjectsV2Client: Sendable {
    public struct FetchResult: Sendable {
        /// `nil` when the server answered 304 and the cached copy is still current.
        public let tasks: [FocusTask]?
        public let etag: String?
    }

    public struct FieldUpdate: Sendable {
        public let id: Int
        public let value: String?

        public init(id: Int, value: String?) {
            self.id = id
            self.value = value
        }
    }

    public enum Failure: LocalizedError {
        case http(status: Int, body: String)
        case malformedResponse

        public var errorDescription: String? {
            switch self {
            case .http(let status, let body):
                return "GitHub returned \(status): \(body.prefix(300))"
            case .malformedResponse:
                return "Unexpected response from GitHub"
            }
        }
    }

    private let token: String
    private let session: URLSession
    private let baseURL: URL

    public init(
        token: String,
        session: URLSession = .shared,
        baseURL: URL = BrainBoard.apiBaseURL()
    ) {
        self.token = token
        self.session = session
        self.baseURL = baseURL
    }

    var itemsBase: String {
        "\(baseURL.absoluteString)/users/\(BrainBoard.owner)/projectsV2/\(BrainBoard.projectNumber)/items"
    }

    var graphQLURL: URL {
        URL(string: "\(baseURL.absoluteString)/graphql")!
    }

    private func request(_ url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("weekly-focus", forHTTPHeaderField: "User-Agent")
        return request
    }

    /// Fetches board items, optionally filtered server-side with the board's `q` syntax.
    ///
    /// Passing the previously seen `etag` turns an unchanged board into a cheap 304
    /// that does not count against the rate limit.
    public func fetchItems(query: String? = nil, etag: String? = nil) async throws -> FetchResult {
        var components = URLComponents(string: itemsBase)!
        var queryItems = [
            URLQueryItem(name: "per_page", value: "100"),
            URLQueryItem(name: "fields", value: BrainBoard.Field.all.map(String.init).joined(separator: ","))
        ]
        if let query, !query.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: query))
        }
        components.queryItems = queryItems

        var urlRequest = request(components.url!)
        if let etag, !etag.isEmpty {
            urlRequest.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw Failure.malformedResponse
        }

        if http.statusCode == 304 {
            return FetchResult(tasks: nil, etag: etag)
        }

        guard (200..<300).contains(http.statusCode) else {
            throw Failure.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }

        var tasks = try ProjectsV2Decoder.tasks(from: data)
        let freshETag = http.value(forHTTPHeaderField: "ETag")

        // The API paginates with Link-header cursors rather than page numbers.
        var next = Self.nextLink(from: http)
        var guardrail = 0
        while let link = next, guardrail < 10 {
            guardrail += 1
            let (pageData, pageResponse) = try await session.data(for: request(link))
            guard let pageHTTP = pageResponse as? HTTPURLResponse,
                  (200..<300).contains(pageHTTP.statusCode)
            else {
                break
            }

            tasks.append(contentsOf: try ProjectsV2Decoder.tasks(from: pageData))
            next = Self.nextLink(from: pageHTTP)
        }

        return FetchResult(tasks: tasks, etag: freshETag)
    }

    /// Updates one or more fields on an item. Batching matters: GitHub charges about the
    /// same for a multi-field `PATCH` as for a single-field one, while GraphQL would need
    /// a separate round trip per field.
    public func update(itemID: Int, fields: [FieldUpdate]) async throws {
        guard !fields.isEmpty else {
            return
        }

        let url = URL(string: "\(itemsBase)/\(itemID)")!
        var urlRequest = request(url, method: "PATCH")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "fields": fields.map { field -> [String: Any] in
                ["id": field.id, "value": field.value as Any? ?? NSNull()]
            }
        ]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw Failure.malformedResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            throw Failure.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    /// Creates a draft item. REST cannot do this, so it goes through GraphQL and then
    /// applies field values over REST in one follow-up `PATCH`.
    @discardableResult
    public func createDraft(title: String, fields: [FieldUpdate] = []) async throws -> Int {
        let mutation = """
        mutation($project: ID!, $title: String!) {
          addProjectV2DraftIssue(input: {projectId: $project, title: $title}) {
            projectItem { databaseId }
          }
        }
        """

        var urlRequest = request(graphQLURL, method: "POST")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "query": mutation,
            "variables": ["project": BrainBoard.projectNodeID, "title": title]
        ])

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw Failure.malformedResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            throw Failure.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.malformedResponse
        }

        if let errors = root["errors"] as? [[String: Any]], !errors.isEmpty {
            let message = errors.compactMap { $0["message"] as? String }.joined(separator: "; ")
            throw Failure.http(status: 200, body: message)
        }

        guard let payload = root["data"] as? [String: Any],
              let mutationResult = payload["addProjectV2DraftIssue"] as? [String: Any],
              let item = mutationResult["projectItem"] as? [String: Any],
              let databaseID = item["databaseId"] as? Int
        else {
            throw Failure.malformedResponse
        }

        if !fields.isEmpty {
            try await update(itemID: databaseID, fields: fields)
        }

        return databaseID
    }

    static func nextLink(from response: HTTPURLResponse) -> URL? {
        guard let header = response.value(forHTTPHeaderField: "Link") else {
            return nil
        }

        for part in header.components(separatedBy: ",") {
            let segments = part.components(separatedBy: ";")
            guard segments.count >= 2,
                  segments.contains(where: { $0.contains("rel=\"next\"") })
            else {
                continue
            }

            let trimmed = segments[0].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("<"), trimmed.hasSuffix(">") else {
                continue
            }

            return URL(string: String(trimmed.dropFirst().dropLast()))
        }

        return nil
    }
}
