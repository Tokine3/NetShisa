import SwiftUI

struct StatusIndicator: View {
    let state: ConnectivityState?
    let reachable: Bool?

    init(state: ConnectivityState) {
        self.state = state
        self.reachable = nil
    }

    init(reachable: Bool) {
        self.state = nil
        self.reachable = reachable
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(indicatorColor.opacity(0.25))
                .frame(width: 14, height: 14)
            Circle()
                .fill(indicatorColor)
                .frame(width: 8, height: 8)
                .shadow(color: indicatorColor.opacity(0.6), radius: 3, x: 0, y: 0)
        }
    }

    private var indicatorColor: Color {
        if let state {
            return state.color
        }
        if let reachable {
            return reachable ? .green : .red
        }
        return .gray
    }
}
