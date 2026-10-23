/// Curated, reversible tweaks. Applying one goes through `ChangeEngine`, so the previous values land in a restore point.
public enum TweakLibrary {
    public static func available(for platform: Platform, snapshot: DeviceSnapshot) -> [Tweak] {
        var all = [animations, privateDNS, screenTimeout, screensaver, limitAdTracking]
        if let physical = snapshot.physicalDensity { all.append(density(physical: physical)) }
        return all.filter { $0.platforms.contains(platform) }
    }

    /// The option whose changes the device already reflects, if any.
    public static func currentOption(for tweak: Tweak, in snapshot: DeviceSnapshot) -> TweakOption? {
        tweak.options.first { $0.changes.allSatisfy(snapshot.satisfies) }
    }

    private static func set(_ ns: SettingNamespace, _ key: String, _ value: String) -> Change {
        .setSetting(ns: ns, key: key, value: value)
    }

    private static let both: [Platform] = [.android, .fireOS]

    private static let animations: Tweak = {
        func scale(_ v: String) -> [Change] {
            ["window_animation_scale", "transition_animation_scale", "animator_duration_scale"].map { set(.global, $0, v) }
        }
        return Tweak(id: "animations", title: "Animation speed", summary: "Faster or no window animations make older devices feel quicker.",
                     platforms: both, options: [.init(label: "Off", changes: scale("0")), .init(label: "Fast", changes: scale("0.5")), .init(label: "Default", changes: scale("1.0"))])
    }()

    private static func density(physical: Int) -> Tweak {
        func dpi(_ factor: Double) -> Int { Int((Double(physical) * factor / 8).rounded()) * 8 }
        return Tweak(id: "density", title: "Screen density", summary: "Changes how much fits on screen. Reset if anything looks wrong.", platforms: both, options: [
            .init(label: "Default", changes: [.setDensity(nil)]),
            .init(label: "Larger UI (−15%)", changes: [.setDensity(dpi(0.85))]),
            .init(label: "Smaller UI (+15%)", changes: [.setDensity(dpi(1.15))]),
            .init(label: "Smaller UI (+30%)", changes: [.setDensity(dpi(1.3))]),
        ])
    }

    private static let privateDNS: Tweak = {
        func host(_ name: String) -> [Change] { [set(.global, "private_dns_mode", "hostname"), set(.global, "private_dns_specifier", name)] }
        return Tweak(id: "private-dns", title: "Private DNS", summary: "Encrypts DNS lookups; ad-blocking resolvers also drop tracker domains for every app.",
                     platforms: both, options: [
                        .init(label: "Off", changes: [set(.global, "private_dns_mode", "off")]),
                        .init(label: "Automatic", changes: [set(.global, "private_dns_mode", "opportunistic")]),
                        .init(label: "Cloudflare (1.1.1.1)", changes: host("one.one.one.one")),
                        .init(label: "Quad9", changes: host("dns.quad9.net")),
                        .init(label: "AdGuard (ad blocking)", changes: host("dns.adguard-dns.com")),
                     ])
    }()

    private static let screenTimeout = Tweak(id: "screen-timeout", title: "Screen timeout", summary: "How long the screen stays on when idle.", platforms: [.android],
        options: [("30 seconds", "30000"), ("1 minute", "60000"), ("5 minutes", "300000"), ("30 minutes", "1800000")]
            .map { TweakOption(label: $0.0, changes: [set(.system, "screen_off_timeout", $0.1)]) })

    private static let screensaver = Tweak(id: "screensaver", title: "Screensaver", summary: "Turns the idle screensaver on or off.", platforms: [.android],
        options: [.init(label: "On", changes: [set(.secure, "screensaver_enabled", "1")]), .init(label: "Off", changes: [set(.secure, "screensaver_enabled", "0")])])

    private static let limitAdTracking = Tweak(id: "limit-ad-tracking", title: "Limit ad tracking",
        summary: "Experimental: sets the ad-tracking flag Fire OS may honour. Not confirmed on every model; check Settings → Preferences → Privacy afterwards.",
        platforms: [.fireOS],
        options: [.init(label: "Limit", changes: [set(.secure, "limit_ad_tracking", "1")]), .init(label: "Default", changes: [set(.secure, "limit_ad_tracking", "0")])])
}
