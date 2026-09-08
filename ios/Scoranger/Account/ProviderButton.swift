import SwiftUI

/// One sign-in provider, drawn the same way as the other.
///
/// Ali's report: *"make the 'Sign in with Google' and 'Sign in with Apple'
/// buttons consistent in size and presentation. Have a logo (google and apple)
/// for both, and make the buttons full width (like the apple one) for both."*
///
/// They were inconsistent because they came from two different places: Google
/// was one of the app's own `PanelButton`s and Apple was Apple's
/// `SignInWithAppleButton`, which brings its own geometry, its own corner
/// radius and its own type. Two components cannot be made to match by nudging
/// numbers -- so both providers are drawn by THIS one, and Apple's official
/// button is no longer used for layout.
///
/// **Both logos are the real marks, not approximations.** Apple's is the
/// `apple.logo` SF Symbol, which Apple ships for exactly this. Google's is
/// `google.png` out of `GoogleSignIn_GoogleSignIn.bundle`, which the SDK
/// already puts inside this app -- so the four-colour G is Google's own asset
/// rather than something hand-drawn, which their brand guidelines require and
/// which a drawn approximation would fail.
struct ProviderButton: View {
    enum Provider {
        case google, apple

        var title: String {
            switch self {
            case .google: return "Sign in with Google"
            case .apple:  return "Sign in with Apple"
            }
        }

        var identifier: String {
            switch self {
            case .google: return "sign-in-google"
            case .apple:  return "sign-in-apple"
            }
        }
    }

    let provider: Provider
    var enabled: Bool = true
    var action: () -> Void

    /// Apple's own button is 44-50pt tall with 8pt corners at this width, and
    /// both of these follow the app's hit target so they match each other AND
    /// every other control in Settings.
    private var height: CGFloat { Theme.Metric.hitTarget }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Metric.s8) {
                logo
                Text(provider.title)
                    .typeRole(.control)
                    .foregroundStyle(.white)
            }
            // FULL WIDTH, both of them: the frame is on the label rather than
            // the Button, so the whole bar is the tap target and not just the
            // text in the middle of it.
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(enabled ? 1 : 0.35))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        // Collapsed to ONE element: a Button whose label is a stack reports as
        // a container, and the identifier then lands on something untappable --
        // the lesson the selection chip taught three times (Screen.swift).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(provider.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(provider.identifier)
    }

    @ViewBuilder
    private var logo: some View {
        switch provider {
        case .apple:
            // Apple ships this symbol for this purpose. Sized by font so it
            // sits on the text's baseline the way their own button does.
            Image(systemName: "apple.logo")
                .font(.system(size: 17))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
        case .google:
            // The SDK's own bundle, already inside this app. If it is ever
            // absent the button still works and simply carries no mark --
            // a missing image must not cost somebody the ability to sign in.
            if let logo = Self.googleMark {
                Image(uiImage: logo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    // On the black bar the white-background mark needs its own
                    // tile, which is how Google's own dark button draws it.
                    .padding(3)
                    .background(RoundedRectangle(cornerRadius: 3).fill(.white))
                    .frame(width: 20, height: 20)
            } else {
                Color.clear.frame(width: 20, height: 20)
            }
        }
    }

    /// `google.png` from `GoogleSignIn_GoogleSignIn.bundle`.
    ///
    /// Loaded once and cached: `UIImage(contentsOfFile:)` on every redraw of a
    /// Settings screen is a file read per frame.
    private static let googleMark: UIImage? = {
        guard let bundleURL = Bundle.main.url(forResource: "GoogleSignIn_GoogleSignIn",
                                              withExtension: "bundle"),
              let bundle = Bundle(url: bundleURL) else { return nil }
        return UIImage(named: "google", in: bundle, compatibleWith: nil)
    }()
}
