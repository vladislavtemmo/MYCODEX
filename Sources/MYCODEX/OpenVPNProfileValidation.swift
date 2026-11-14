import COpenVPNBridge

public enum OpenVPNProfileValidationResult: Sendable, Equatable {
    case valid
    case invalidProfile
    case invalidArgument
    case coreUnavailable
    case nativeError
    case unexpectedStatus(Int32)
}

extension OpenVPNNativeBridge {
    public static func validateProfile(_ profile: OpenVPNProfile) -> OpenVPNProfileValidationResult {
        profile.withRawConfiguration { configuration in
            let byteCount = configuration.utf8.count
            let status = configuration.withCString { pointer in
                mycodex_bridge_validate_profile(pointer, byteCount)
            }
            switch status {
            case 0: return .valid
            case 1: return .invalidProfile
            case -1: return .invalidArgument
            case -2: return .coreUnavailable
            case -3: return .nativeError
            default: return .unexpectedStatus(status)
            }
        }
    }
}