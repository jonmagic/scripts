import Foundation

/// Decodes the Projects V2 REST item payload into `FocusTask` values.
///
/// The REST API returns one `fields` array per item where the shape of `value`
/// depends on `data_type`:
///
/// - `title`/`text`: `{"raw": "...", "html": "..."}`
/// - `single_select`: `{"id": "...", "name": {"raw": "..."}, "color": "..."}`
/// - `iteration`: `{"id": "...", "start_date": "YYYY-MM-DD", "title": {"raw": "..."}}`
/// - `number`: a bare JSON number
/// - `date`: an ISO 8601 string
public enum ProjectsV2Decoder {
    struct Item: Decodable {
        let id: Int
        let nodeID: String
        let fields: [Field]

        enum CodingKeys: String, CodingKey {
            case id
            case nodeID = "node_id"
            case fields
        }
    }

    struct Field: Decodable {
        let id: Int
        let name: String
        let dataType: String
        let value: Value?

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case dataType = "data_type"
            case value
        }
    }

    /// A decoded field value, normalized across the shapes above.
    enum Value: Decodable {
        case text(String)
        case number(Double)
        case option(id: String, name: String)
        case iteration(id: String, title: String, startDate: String)
        case unknown

        private enum CodingKeys: String, CodingKey {
            case raw
            case id
            case name
            case title
            case startDate = "start_date"
        }

        private struct Localized: Decodable {
            let raw: String
        }

        init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer() {
                if let number = try? single.decode(Double.self) {
                    self = .number(number)
                    return
                }

                if let string = try? single.decode(String.self) {
                    self = .text(string)
                    return
                }
            }

            guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                self = .unknown
                return
            }

            // Iterations also carry an `id`, so check for `start_date` first.
            if let startDate = try? container.decode(String.self, forKey: .startDate) {
                let id = (try? container.decode(String.self, forKey: .id)) ?? ""
                let title = (try? container.decode(Localized.self, forKey: .title))?.raw ?? ""
                self = .iteration(id: id, title: title, startDate: startDate)
                return
            }

            if let id = try? container.decode(String.self, forKey: .id),
               let name = try? container.decode(Localized.self, forKey: .name) {
                self = .option(id: id, name: name.raw)
                return
            }

            if let raw = try? container.decode(String.self, forKey: .raw) {
                self = .text(raw)
                return
            }

            self = .unknown
        }

        var stringValue: String? {
            switch self {
            case .text(let value):
                return value.isEmpty ? nil : value
            case .option(_, let name):
                return name.isEmpty ? nil : name
            case .iteration(_, let title, _):
                return title.isEmpty ? nil : title
            case .number(let value):
                return String(Int(value))
            case .unknown:
                return nil
            }
        }
    }

    public static func tasks(from data: Data) throws -> [FocusTask] {
        let items = try JSONDecoder().decode([Item].self, from: data)
        return items.map(task(from:))
    }

    static func task(from item: Item) -> FocusTask {
        var title = ""
        var status = ""
        var statusOptionID: String?
        var focus: Int?
        var week: String?
        var weekStart: String?
        var source: String?
        var target: String?
        var area: String?

        for field in item.fields {
            switch field.id {
            case BrainBoard.Field.title:
                title = field.value?.stringValue ?? ""
            case BrainBoard.Field.status:
                if case .option(let id, let name) = field.value {
                    status = name
                    statusOptionID = id
                }
            case BrainBoard.Field.focus:
                if case .number(let value) = field.value {
                    focus = Int(value)
                }
            case BrainBoard.Field.week:
                if case .iteration(_, let title, let startDate) = field.value {
                    week = title
                    weekStart = startDate
                }
            case BrainBoard.Field.source:
                source = field.value?.stringValue
            case BrainBoard.Field.target:
                target = field.value?.stringValue
            case BrainBoard.Field.area:
                area = field.value?.stringValue
            default:
                continue
            }
        }

        return FocusTask(
            id: item.id,
            nodeID: item.nodeID,
            title: title,
            status: status,
            statusOptionID: statusOptionID,
            focus: focus,
            week: week,
            weekStart: weekStart,
            source: source,
            target: target,
            area: area
        )
    }
}
