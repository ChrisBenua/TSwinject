//
//  Portions derived from Swinject (https://github.com/Swinject/Swinject)
//  Copyright © 2019 Swinject Contributors. All rights reserved.
//  Licensed under the MIT License — see NOTICE.
//

import Foundation

struct ServiceKey: Hashable, Sendable {
    let serviceType: Any.Type
    let argumentsType: Any.Type
    let name: String?

    init(serviceType: Any.Type, argumentsType: Any.Type = Resolver.self, name: String? = nil) {
        self.serviceType = serviceType
        self.argumentsType = argumentsType
        self.name = name
    }

    func hash(into hasher: inout Hasher) {
        ObjectIdentifier(serviceType).hash(into: &hasher)
        ObjectIdentifier(argumentsType).hash(into: &hasher)
        name?.hash(into: &hasher)
    }

    static func == (lhs: ServiceKey, rhs: ServiceKey) -> Bool {
        return lhs.serviceType == rhs.serviceType
            && lhs.argumentsType == rhs.argumentsType
            && lhs.name == rhs.name
    }
}
