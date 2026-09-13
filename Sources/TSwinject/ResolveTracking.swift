//
//  ResolveTracking — opt-in hook for observing per-resolve timing.
//  The library emits one event per top-level resolve to a host-supplied sink.
//  All aggregation, thresholding, and formatting are the host's responsibility.
//

import Foundation

// MARK: - Public surface

/// Which thread a resolve was initiated from.
public enum ResolveThreadKind: Sendable {
    /// The resolve was initiated on the main thread.
    case main
    /// The resolve was initiated on any other thread.
    case background
}

/// Data emitted for a single top-level resolve call.
public struct ResolveEvent {
    /// The type that was resolved.
    public let serviceType: Any.Type
    /// The registration name, or `nil` for an unnamed registration.
    public let name: String?
    /// Wall-clock duration of the whole resolve, including every nested resolve
    /// its factory triggered.
    public let durationNanoseconds: UInt64
    /// Which thread the resolve was initiated from.
    public let thread: ResolveThreadKind
}

/// Host-supplied sink that receives one event per top-level resolve.
///
/// Declared as `AnyObject` so `Container` holds it without copy semantics.
/// The library never aggregates, thresholds, or prints — that is the host's
/// responsibility.
public protocol ResolveTracker: AnyObject {
    /// Called once per top-level resolve, after it completes.
    ///
    /// Nested resolves triggered from inside a factory do not produce their own
    /// events; their cost is included in the enclosing event's duration. Called
    /// synchronously on the resolving thread, so keep the implementation cheap.
    ///
    /// - Parameter event: What was resolved, and how long it took.
    func didResolve(_ event: ResolveEvent)
}

// MARK: - Re-entrancy guard

/// Per-thread re-entrancy guard for ResolveTracking. A resolution graph is built
/// synchronously on a single thread, so "am I already inside a tracked resolve?"
/// is a thread-local question — independent of which `Container` owns the entry.
///
/// Gating on this (rather than `Container.resolutionDepth`, which is incremented
/// on the entry's *owner*, not on the resolver) is what keeps a nested resolve
/// through a child / synchronized resolver from being mis-reported as a second
/// top-level event.
enum TrackingReentrancy {
    private static let key = "TSwinject.trackingDepth"
    static var depth: Int {
        get { Thread.current.threadDictionary[key] as? Int ?? 0 }
        set {
            if newValue <= 0 {
                Thread.current.threadDictionary.removeObject(forKey: key)
            } else {
                Thread.current.threadDictionary[key] = newValue
            }
        }
    }
}

// MARK: - Process-wide factory

/// Process-wide tracker factory — the primary entry point for enabling tracking.
///
/// Install a closure at app startup:
/// ```swift
/// ResolveTracking.factory = { MyMetricsTracker.shared }
/// ```
/// The library calls the closure exactly once per newly-created `Container`
/// and caches the returned tracker. Pass `nil` from the closure to opt a
/// particular container out of tracking.
///
/// Access to the `factory` property is lock-protected. The factory closure
/// itself is invoked outside the lock (at `Container.init` time, not on the
/// resolve hot path), so a slow factory does not block other containers
/// being constructed in parallel.
public enum ResolveTracking {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var _factory: (() -> (any ResolveTracker)?)?

    /// The installed factory, or `nil` when tracking is globally disabled.
    public static var factory: (() -> (any ResolveTracker)?)? {
        get { lock.lock(); defer { lock.unlock() }; return _factory }
        set { lock.lock(); defer { lock.unlock() }; _factory = newValue }
    }

    /// Snapshot the factory under the lock, then invoke it outside the lock.
    /// Returns `nil` when no factory is installed or the factory returns `nil`.
    @usableFromInline
    static func makeTracker() -> (any ResolveTracker)? {
        lock.lock()
        let f = _factory
        lock.unlock()
        return f?()
    }
}
