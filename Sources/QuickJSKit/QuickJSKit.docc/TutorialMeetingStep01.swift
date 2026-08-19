import QuickJSKit

struct MeetingNote: Codable, Sendable {
    let project: String
    let title: String
    let actionItems: [String]
}

struct FollowUpTask: Codable, Sendable {
    let title: String
}

struct FollowUpPlan: Codable, Sendable {
    let title: String
    let ownerID: String?
    let tasks: [FollowUpTask]
}
