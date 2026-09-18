import Foundation

/// Authentication endpoints are fixed trusted services. They are not download
/// sources and are never replaced by a mirror or user-supplied base URL.
enum AuthenticationEndpoints {
    private static let microsoft = URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/")!
    private static let minecraft = URL(string: "https://api.minecraftservices.com")!
    static let deviceCode = microsoft.appending(component: "devicecode")
    static let token = microsoft.appending(component: "token")
    static let xboxAuthenticate = URL(string: "https://user.auth.xboxlive.com/user/authenticate")!
    static let xstsAuthorize = URL(string: "https://xsts.auth.xboxlive.com/xsts/authorize")!
    static let minecraftLogin = minecraft.appending(path: "authentication/login_with_xbox")
    static let entitlements = minecraft.appending(path: "entitlements/mcstore")
    static let license = minecraft.appending(path: "entitlements/license")
    static let profile = minecraft.appending(path: "minecraft/profile")
    static let scope = "XboxLive.signin offline_access"
    static let xboxSite = "user.auth.xboxlive.com"
    // Protocol audience identifiers, not HTTP request destinations. Their
    // schemes are prescribed by Xbox and must not be rewritten to HTTPS.
    static let xboxRelyingParty = "http://auth.xboxlive.com"
    static let minecraftRelyingParty = "rp://api.minecraftservices.com/"
}
