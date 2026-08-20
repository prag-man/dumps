import Foundation

struct Bucket: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var name: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?

    var isArchived: Bool {
        archivedAt != nil
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        sortOrder: Int,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case sortOrder
        case createdAt
        case updatedAt
        case archivedAt
    }
}
