import Foundation

struct HTTPResponse: Sendable {
    let statusCode: Int
    let data: Data
}
