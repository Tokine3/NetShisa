import SwiftUI

struct ServiceRow: View {
    let result: ServiceCheckResult

    var body: some View {
        HStack(spacing: 10) {
            Text(result.definition.name)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 90, alignment: .leading)

            Spacer()

            // IPv4
            protocolBadge(label: "v4", supported: result.definition.supportsIPv4, reachable: result.ipv4Reachable)

            // IPv6
            protocolBadge(label: "v6", supported: result.definition.supportsIPv6, reachable: result.ipv6Reachable)

            // Latency
            if let latency = result.ipv4LatencyMs ?? result.ipv6LatencyMs {
                Text("\(Int(latency))ms")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 44, alignment: .trailing)
            } else {
                Text("—")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func protocolBadge(label: String, supported: Bool, reachable: Bool?) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(badgeTextColor(supported: supported, reachable: reachable))

            if supported {
                Image(systemName: reachable == true ? "checkmark" : (reachable == false ? "xmark" : "questionmark"))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(badgeIconColor(reachable: reachable))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(badgeBackground(supported: supported, reachable: reachable))
        )
        .frame(width: 52)
    }

    private func badgeTextColor(supported: Bool, reachable: Bool?) -> Color {
        guard supported else { return .gray.opacity(0.3) }
        switch reachable {
        case .some(true): return .green
        case .some(false): return .red
        default: return .secondary
        }
    }

    private func badgeIconColor(reachable: Bool?) -> Color {
        switch reachable {
        case .some(true): return .green
        case .some(false): return .red
        default: return .secondary
        }
    }

    private func badgeBackground(supported: Bool, reachable: Bool?) -> Color {
        guard supported else { return .clear }
        switch reachable {
        case .some(true): return .green.opacity(0.1)
        case .some(false): return .red.opacity(0.1)
        default: return .secondary.opacity(0.08)
        }
    }
}
