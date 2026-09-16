public enum AlertTone: String, Codable, CaseIterable, Identifiable, Sendable {
    case pop, tink, glass, ping

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .pop: return "Pop"
        case .tink: return "Tink"
        case .glass: return "Chime"
        case .ping: return "Ping"
        }
    }
}
