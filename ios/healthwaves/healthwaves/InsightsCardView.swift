import SwiftUI

struct InsightsOverlayCard: View {
    @ObservedObject var vm: InsightsViewModel
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            // Dimmed backdrop
            if isPresented {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { dismiss() }
            }

            // Floating card
            if isPresented {
                VStack {
                    Spacer()

                    card
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: isPresented)
    }

    private var card: some View {
        VStack(spacing: 14) {
            header

            content

            footerButtons
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial) // frosted overlay look
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.purple)

            VStack(alignment: .leading, spacing: 2) {
                Text("AI Insights")
                    .font(.system(size: 18, weight: .bold))
                Text("Active Energy (28 days)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(10)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
    }

    private var content: some View {
        Group {
            if vm.isLoading {
                loadingView
            } else if !vm.errorText.isEmpty {
                errorView(vm.errorText)
            } else if vm.blurbs.isEmpty {
                emptyView
            } else {
                blurbsView
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var blurbsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(vm.blurbs, id: \.self) { blurb in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "sparkle")
                            .foregroundColor(.purple)
                            .padding(.top, 2)

                        Text(blurb)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)

                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.purple.opacity(0.10))
                    )
                }
            }
            .padding(.top, 2)
        }
        .frame(height: 220) // control overlay height
    }

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No insights yet.")
                .font(.system(size: 14, weight: .semibold))
            Text("Tap Analyze to generate a few quick blurbs about your last 28 days.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.10))
        )
    }

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14)
                    .frame(height: 44)
                    .foregroundColor(Color.white.opacity(0.10))
            }
        }
        .redacted(reason: .placeholder)
    }

    private func errorView(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Couldn’t generate insights")
                .font(.system(size: 14, weight: .semibold))
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.10))
        )
    }

    private var footerButtons: some View {
        HStack(spacing: 10) {
            Button {
                vm.analyzeActiveEnergyLast28Days()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: vm.isLoading ? "hourglass" : "sparkles")
                    Text(vm.isLoading ? "Analyzing..." : "Analyze")
                }
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundColor(.purple)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.purple.opacity(0.12))
                )
            }
            .disabled(vm.isLoading)

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundColor(.primary)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.10))
                    )
            }
        }
    }

    private func dismiss() {
        withAnimation {
            isPresented = false
        }
    }
}
