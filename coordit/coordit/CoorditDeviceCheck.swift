import DeviceCheck
import Foundation

#if os(iOS)
enum CoorditDeviceCheckError: LocalizedError {
    case unavailable
    case missingToken

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "이 기기에서는 최초 실타래 지급 여부를 확인할 수 없어요."
        case .missingToken:
            "기기 확인 토큰을 만들지 못했어요."
        }
    }
}

enum CoorditDeviceCheck {
    static func token() async throws -> String {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--coordit-devicecheck-fixture") {
            return "coordit-ui-test-device-token"
        }
        #endif

        guard DCDevice.current.isSupported else {
            throw CoorditDeviceCheckError.unavailable
        }
        return try await withCheckedThrowingContinuation { continuation in
            DCDevice.current.generateToken { data, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data else {
                    continuation.resume(throwing: CoorditDeviceCheckError.missingToken)
                    return
                }
                continuation.resume(returning: data.base64EncodedString())
            }
        }
    }
}
#endif
