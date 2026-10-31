import AppKit

/// An image handed between tasks and actors, such as a thumbnail made off
/// the main thread for a view. NSImage is not Sendable. Wrap only an image
/// that nobody changes after it is made; reading it from another task is
/// then safe.
struct SendableImage: @unchecked Sendable {
    let image: NSImage
}
