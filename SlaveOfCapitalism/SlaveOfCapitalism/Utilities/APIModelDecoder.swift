import Foundation

enum APIModelDecoder {
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = configuredDecoder()
        var currentData = data
        var normalizedPaths = Set<String>()

        do {
            while true {
                do {
                    return try decoder.decode(T.self, from: currentData)
                } catch let DecodingError.typeMismatch(type, context) where isDecimalType(type) {
                    let pathKey = codingPathKey(context.codingPath)
                    guard normalizedPaths.insert(pathKey).inserted,
                          let normalizedData = try normalizeDecimalString(at: context.codingPath, in: currentData) else {
                        throw DecodingError.typeMismatch(type, context)
                    }
                    currentData = normalizedData
                }
            }
        } catch {
            throw error
        }
    }

    private static func configuredDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private static func normalizeDecimalString(at codingPath: [CodingKey], in data: Data) throws -> Data? {
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        var normalized = object
        guard applyDecimalNormalization(to: &normalized, path: ArraySlice(codingPath)) else {
            return nil
        }
        guard JSONSerialization.isValidJSONObject(normalized) else {
            return nil
        }
        return try JSONSerialization.data(withJSONObject: normalized, options: [])
    }

    private static func applyDecimalNormalization(to value: inout Any, path: ArraySlice<CodingKey>) -> Bool {
        guard let head = path.first else {
            if let string = value as? String, isNumericString(string) {
                value = NSDecimalNumber(string: string)
                return true
            }
            return false
        }

        if let index = head.intValue, var array = value as? [Any], array.indices.contains(index) {
            var child = array[index]
            let changed = applyDecimalNormalization(to: &child, path: path.dropFirst())
            if changed {
                array[index] = child
                value = array
            }
            return changed
        }

        if let dictionary = value as? [String: Any] {
            for candidateKey in jsonKeyCandidates(for: head.stringValue) {
                guard var child = dictionary[candidateKey] else { continue }
                let changed = applyDecimalNormalization(to: &child, path: path.dropFirst())
                if changed {
                    var updated = dictionary
                    updated[candidateKey] = child
                    value = updated
                }
                return changed
            }
        }

        return false
    }

    private static func codingPathKey(_ codingPath: [CodingKey]) -> String {
        codingPath.map { key in
            if let index = key.intValue {
                return "[\(index)]"
            }
            return key.stringValue
        }.joined(separator: ".")
    }

    private static func isDecimalType(_ type: Any.Type) -> Bool {
        String(reflecting: type).contains("Decimal")
    }

    private static func jsonKeyCandidates(for codingKey: String) -> [String] {
        let snakeCase = snakeCaseKey(from: codingKey)
        if snakeCase == codingKey {
            return [codingKey]
        }
        return [codingKey, snakeCase]
    }

    private static func snakeCaseKey(from key: String) -> String {
        guard !key.isEmpty else { return key }

        var result = ""
        result.reserveCapacity(key.count + 4)

        for character in key {
            if character.isUppercase {
                if !result.isEmpty {
                    result.append("_")
                }
                result.append(character.lowercased())
            } else {
                result.append(character)
            }
        }

        return result
    }

    private static func isNumericString(_ value: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"^-?\d+(\.\d+)?$"#) else {
            return false
        }
        let range = NSRange(value.startIndex..., in: value)
        return regex.firstMatch(in: value, options: [], range: range) != nil
    }
}
