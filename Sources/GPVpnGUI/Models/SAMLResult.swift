import Foundation

/// The credentials harvested from a successful SAML login.
struct SAMLResult {
    let username: String
    let cookie: String
    let usergroup: String   // e.g. "gateway:prelogin-cookie"
    let server: String      // final server host to connect to
}
