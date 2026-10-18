#if os(iOS)
    import SwiftUI
    import UIKit

    struct MobileAppIcon: View {
        // MARK: Internal

        var body: some View {
            if let image = Self.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: Self.size, height: Self.size)
                    .clipShape(.rect(cornerRadius: Self.cornerRadius))
                    .accessibilityHidden(true)
            }
        }

        // MARK: Private

        private static let size: CGFloat = 22
        private static let cornerRadius: CGFloat = 5
        private static let image: UIImage? = {
            guard let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
                  let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
                  let files = primary["CFBundleIconFiles"] as? [String],
                  let name = files.last
            else {
                return nil
            }

            return UIImage(named: name)
        }()
    }
#endif
