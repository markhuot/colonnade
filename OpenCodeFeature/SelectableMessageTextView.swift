import Foundation
import SwiftUI

struct SelectableMessageTextView: View {
    let attributedText: NSAttributedString
    let linkColor: PlatformColor
    var onInteraction: (() -> Void)? = nil

    var body: some View {
        Group {
            if let swiftUIAttributedText = try? AttributedString(attributedText, including: \ .foundation) {
                Text(swiftUIAttributedText)
                    .textSelection(.enabled)
            } else {
                Text(attributedText.string)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onTapGesture {
            onInteraction?()
        }
    }
}
