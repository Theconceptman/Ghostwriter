import SwiftUI

struct OnboardingView: View {
    let onReadyToTest: () -> Void
    let onComplete: () -> Void
    var body: some View {   // replaced in Task 17
        VStack(spacing: 20) {
            Button("Enable dictation") { onReadyToTest() }
            Button("Finish") { onComplete() }
        }.padding(80)
    }
}
