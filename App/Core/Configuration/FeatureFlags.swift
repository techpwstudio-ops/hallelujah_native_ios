struct FeatureFlags: Sendable {
    let aiAssistantEnabled: Bool
    let carPlayEnabled: Bool
    let adsEnabled: Bool
    let adsPreviewMode: Bool
    let downloadsEnabled: Bool
    /// The "support the artist" tip button on the player. Hidden from
    /// listeners until the offering flow is signed off (`AppConfig.showTipButton`,
    /// on in dev/QA builds, off in production).
    let tipButtonEnabled: Bool
}
