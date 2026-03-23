import Foundation

enum APIModelDecoder {
    static func decode<T: Decodable>(_ type: T.Type, from data: Data, endpoint: String) throws -> T {
        do {
            return try configuredDecoder().decode(T.self, from: data)
        } catch {
            let normalizedData = try normalizeNumberStrings(in: data)
            return try configuredDecoder().decode(T.self, from: normalizedData)
        }
    }

    private static func configuredDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private static func normalizeNumberStrings(in data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        let normalized = normalizeJSONValue(object)
        guard JSONSerialization.isValidJSONObject(normalized) else {
            return data
        }
        return try JSONSerialization.data(withJSONObject: normalized, options: [])
    }

    private static func normalizeJSONValue(_ value: Any) -> Any {
        if let array = value as? [Any] {
            return array.map(normalizeJSONValue)
        }

        if let dictionary = value as? [String: Any] {
            var normalized: [String: Any] = [:]
            normalized.reserveCapacity(dictionary.count)
            for (key, nestedValue) in dictionary {
                normalized[key] = normalizeJSONValue(nestedValue)
            }
            return normalized
        }

        if let string = value as? String, isNumericString(string) {
            return NSDecimalNumber(string: string)
        }

        return value
    }

    private static func isNumericString(_ value: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"^-?\d+(\.\d+)?$"#) else {
            return false
        }
        let range = NSRange(value.startIndex..., in: value)
        return regex.firstMatch(in: value, options: [], range: range) != nil
    }
}
