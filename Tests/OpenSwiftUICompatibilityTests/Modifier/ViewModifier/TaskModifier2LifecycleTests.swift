//
//  TaskModifier2LifecycleTests.swift
//  OpenSwiftUICompatibilityTests

import OpenSwiftUITestsSupport
import Testing

@MainActor
struct TaskModifier2LifecycleTests {
    @Test
    func taskStartsOnAppear() async throws {
        struct ContentView: View {
            let confirmation: Confirmation
            var continuation: UnsafeContinuation<Void, Never>

            var body: some View {
                Color.red.modifier(_TaskModifier2(
                    name: "start",
                    executorPreference: nil,
                    priority: .userInitiated,
                    action: {
                        confirmation()
                        continuation.resume()
                    }
                ))
            }
        }

        try await triggerLayoutWithWindow { confirmation, continuation in
            PlatformHostingController(
                rootView: ContentView(
                    confirmation: confirmation,
                    continuation: continuation
                )
            )
        }
    }

    @Test
    func taskCancelsAndRestartsOnIDChange() async throws {
        struct ContentView: View {
            @State private var value = 0
            let confirmation: Confirmation
            var continuation: UnsafeContinuation<Void, Never>

            var body: some View {
                Color.red
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            value += 1
                        }
                    }
                    .modifier(_TaskValueModifier2(
                        id: value,
                        name: "restart",
                        executorPreference: nil,
                        priority: .userInitiated,
                        action: { [value] in
                            confirmation()
                            if value == 0 {
                                // Stays alive until the id change cancels it.
                                while !Task.isCancelled {
                                    try? await Task.sleep(nanoseconds: 10_000_000)
                                }
                            } else {
                                continuation.resume()
                            }
                        }
                    ))
            }
        }

        try await triggerLayoutWithWindow(expectedCount: 2) { confirmation, continuation in
            PlatformHostingController(
                rootView: ContentView(
                    confirmation: confirmation,
                    continuation: continuation
                )
            )
        }
    }
}
