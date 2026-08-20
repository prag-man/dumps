import Foundation

struct Dump: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var bucketId: String
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    var isDeleted: Bool {
        deletedAt != nil
    }

    var trimmedContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isWhitespaceOnly: Bool {
        trimmedContent.isEmpty
    }

    init(
        id: String = UUID().uuidString,
        bucketId: String,
        content: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.bucketId = bucketId
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case bucketId
        case content
        case createdAt
        case updatedAt
        case deletedAt
    }
}
