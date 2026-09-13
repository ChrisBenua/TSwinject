//
//  Portions derived from Swinject (https://github.com/Swinject/Swinject)
//  Copyright © 2023 Swinject Contributors. All rights reserved.
//  Licensed under the MIT License — see NOTICE.
//

import Foundation

final class ThreadSafeDictionary<KeyType: Hashable, ValueType> {
    private var internalDictionary = [KeyType: ValueType]()
    private let lock = ReadWriteLock()

    init() {}

    subscript(key: KeyType) -> ValueType? {
        get { lock.read { internalDictionary[key] } }
        set { lock.write { internalDictionary[key] = newValue } }
    }

    func removeAll() {
        lock.write { internalDictionary.removeAll() }
    }

    func contains(where predicate: ((key: KeyType, value: ValueType)) -> Bool) -> Bool {
        lock.read { internalDictionary.contains(where: predicate) }
    }

    var isEmpty: Bool {
        lock.read { internalDictionary.isEmpty }
    }

    var values: [ValueType] {
        lock.read { internalDictionary.values.map { $0 } }
    }
}
