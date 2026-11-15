import Foundation

let validProfile = try OpenVPNProfile(ovpnText: "client\nremote example.invalid 1194\nproto udp\n")
let invalidProfile = try OpenVPNProfile(ovpnText: "client\nproto udp\n")
let client = try OpenVPNClient()
try client.configure(validProfile)
print("SWIFT_CLIENT_CREATED=1")
print("SWIFT_CLIENT_CONFIGURED=1")
guard try client.pollEvent() == nil else { fatalError("Unexpected events before connect") }
print("SWIFT_EVENT_QUEUE_EMPTY=1")
try client.provideCredentials(username: "probe-user", password: "probe-nonsecret")
print("SWIFT_CREDENTIALS_PROVIDED=1")
do {
    try client.configure(validProfile)
    fatalError("Second configuration unexpectedly accepted")
} catch OpenVPNClientError.invalidState {
    print("SWIFT_DUPLICATE_CONFIG_REJECTED=1")
}
let unconfiguredClient = try OpenVPNClient()
do {
    try unconfiguredClient.provideCredentials(username: "probe-user", password: "probe-nonsecret")
    fatalError("Credentials accepted before configure")
} catch OpenVPNClientError.invalidState {
    print("SWIFT_EARLY_CREDENTIALS_REJECTED=1")
}
let invalidClient = try OpenVPNClient()
do {
    try invalidClient.configure(invalidProfile)
    fatalError("Invalid profile unexpectedly accepted")
} catch OpenVPNClientError.invalidProfile {
    print("SWIFT_CLIENT_INVALID_REJECTED=1")
}
print("MYCODEX_NATIVE_CLIENT_PREPARATION_PASSED")
