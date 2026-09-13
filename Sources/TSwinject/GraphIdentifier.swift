//
//  Portions derived from Swinject (https://github.com/Swinject/Swinject)
//  Copyright © 2019 Swinject Contributors. All rights reserved.
//  Licensed under the MIT License — see NOTICE.
//

// no universal UUID impl on Linux

#if os(iOS) || os(macOS) || os(tvOS) || os(watchOS)
    import Foundation

    /// Unique identifier of an object graph during a resolution process.
    ///
    /// A graph begins at a top-level `resolve` and ends when that call returns.
    /// ``ObjectScope/graph`` registrations key their cached instance by this
    /// value, which is what makes a dependency shared within one resolve and
    /// freshly built on the next. A new identifier is minted per graph; it is
    /// not stable across calls and is not meaningful to persist.
    public struct GraphIdentifier: Identifiable {
        /// The underlying unique value. Compare `GraphIdentifier`s directly
        /// rather than relying on the representation, which is platform-specific.
        public let id = UUID()
    }
#else
    /// Unique identifier of an object graph during a resolution process.
    ///
    /// A graph begins at a top-level `resolve` and ends when that call returns.
    /// ``ObjectScope/graph`` registrations key their cached instance by this
    /// value, which is what makes a dependency shared within one resolve and
    /// freshly built on the next. A new identifier is minted per graph; it is
    /// not stable across calls and is not meaningful to persist.
    public struct GraphIdentifier: Identifiable {
        /// The underlying unique value. Compare `GraphIdentifier`s directly
        /// rather than relying on the representation, which is platform-specific.
        public let id = UInt.random(in: 0 ..< UInt.max)
    }
#endif

extension GraphIdentifier: Equatable, Hashable {}
