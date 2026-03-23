import Foundation

struct EventPayloadDecoder {
    func decode(_ payload: String) throws -> EventPayload {
        guard let data = payload.data(using: .utf8) else {
            throw EventPayloadDecodingError.invalidEncoding
        }

        return try JSONDecoder().decode(EventPayload.self, from: data)
    }
}

enum EventPayloadDecodingError: LocalizedError {
    case invalidEncoding

    var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "The event payload could not be decoded as UTF-8."
        }
    }
}

extension EventPayload {
    var propertyObject: [String: JSONValue] {
        properties?.objectValue ?? [:]
    }

    func string(_ key: EventPropertyKey) -> String? {
        propertyObject[key.rawValue]?.stringValue
    }

    func json(_ key: EventPropertyKey) -> JSONValue? {
        propertyObject[key.rawValue]
    }

    func object(_ key: EventPropertyKey) -> [String: JSONValue]? {
        propertyObject[key.rawValue]?.objectValue
    }
}
