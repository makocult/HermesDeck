import Foundation

extension String {
    func formattedMessageTime() -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: self) else { return "" }
        let output = DateFormatter()
        output.dateFormat = "h:mm a"
        return output.string(from: date).lowercased()
    }
}
