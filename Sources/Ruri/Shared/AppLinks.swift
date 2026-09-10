import Foundation

/// Browser destinations used by the app. API endpoints and project-specific
/// links belong to their corresponding core service.
enum AppLinks {
    static let curseForgeAPI = URL(string: "https://support.curseforge.com/support/solutions/articles/9000208346")!
    static let microsoftRegistration = URL(string: "https://learn.microsoft.com/entra/identity-platform/quickstart-register-app")!
    static let bmclapiDocumentation = URL(string: "https://bmclapidoc.bangbang93.com/")!
    static let azulJavaDownloads = URL(string: "https://www.azul.com/downloads/?package=jdk#zulu")!
    static let temurinJavaDownloads = URL(string: "https://adoptium.net/temurin/releases/?os=mac")!
}
