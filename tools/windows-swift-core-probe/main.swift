import Foundation
let good = try OpenVPNProfile(ovpnText: "client\nremote example.invalid 1194\nproto udp\n")
let bad = try OpenVPNProfile(ovpnText: "client\nproto udp\n")
let linked = OpenVPNNativeBridge.isOpenVPNCoreLinked
let valid = OpenVPNNativeBridge.validateProfile(good)
let invalid = OpenVPNNativeBridge.validateProfile(bad)
print("SWIFT_CORE_LINKED=\(linked ? 1 : 0)")
print("SWIFT_VALID=\(valid == .valid ? 1 : 0)")
print("SWIFT_INVALID_REJECTED=\(invalid == .invalidProfile ? 1 : 0)")
guard linked && valid == .valid && invalid == .invalidProfile else { fatalError("Swift to OpenVPN 3 Core integration failed") }
print("SWIFT_TO_OPENVPN3_PASSED")