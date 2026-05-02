# ViewModels — pattern guide (#166)

This directory holds `@MainActor`-isolated `ObservableObject` view-models
that own each screen's business logic and async lifecycle. Views stay
purely declarative — they bind to view-model `@Published` properties
and call methods, rather than performing service calls inline.

## When to add a ViewModel

Add one when a view exhibits at least two of:

- **Long-running async work** — network calls, video render, downloads.
- **State that must outlive a re-render** — generation tasks,
  cancellable jobs, paginated cursors.
- **Logic the test suite should exercise without launching the UI**
  — pipeline construction, error mapping, side-effect ordering.

If a view is just composing existing services with simple bindings
(e.g. `Settings → toggles`), a VM is overkill. Bind directly.

## Conventions

```swift
@MainActor
final class FooViewModel: ObservableObject {
    // Published — drives the view.
    @Published var isLoading = false
    @Published var items: [Foo] = []
    @Published var errorMessage: String?

    // Private — internal lifecycle (cancellable tasks, timers).
    private var fetchTask: Task<Void, Never>?

    // Dependencies — accept defaults pointing at production singletons,
    // override in tests via init.
    private let service: FooService

    init(service: FooService = .shared) {
        self.service = service
    }

    func load() {
        fetchTask?.cancel()
        fetchTask = Task { [weak self] in
            // … async work, update @Published on the main actor
        }
    }

    func cancel() {
        fetchTask?.cancel()
        fetchTask = nil
    }
}
```

Views attach via `@StateObject` (when they own the VM lifetime) or
`@ObservedObject` (when the VM is passed in):

```swift
struct FooView: View {
    @StateObject private var vm = FooViewModel()

    var body: some View {
        if vm.isLoading {
            ProgressView()
        } else {
            List(vm.items, id: \.id) { … }
        }
    }
}
```

## Error surfacing

VMs **do not** present alerts directly. Either:

- Set `errorMessage` and let the view render an inline error state, OR
- Call `ErrorReporter.shared.report(...)` (#167) to surface a global
  alert via the `ContentView` observer.

The split: VM error state for screen-local recovery flows (e.g. "Try
Again" on a generation failure); `ErrorReporter` for "out of band"
failures the user wasn't actively waiting on (drag-drop import
glitches, sync errors, decode failures).

## Cancellation

Use Swift `Task` and `Task.checkCancellation()` for cooperative
cancel. Hold `private var fooTask: Task<Void, Never>?` and provide
both the start method and a `cancel()` method. Wire the view's
"Cancel" button to `vm.cancel()` and `.onDisappear { vm.cancel() }`
when the work shouldn't outlive the screen.

## Examples in this directory

- `AIGenerateViewModel` — fal.ai pipeline + history persistence + library
  import. Complete extraction of generation lifecycle from
  `AIGenerateView`. Use as the reference implementation.
