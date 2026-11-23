// Copyright 2025–2026 Skip
// SPDX-License-Identifier: MPL-2.0
import SkipBridge
import SkipUI

/* @frozen */ @propertyWrapper public struct Environment<Value> : DynamicProperty {
    private let defaultValue: /* @Sendable */ () -> Value
    private let valueBox: Box<Box<Value>?> = Box(nil)

    /* @inlinable */ public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {
        self.key = EnvironmentValues.key(for: keyPath)
        self.defaultValue = { EnvironmentValues.shared[keyPath: keyPath] }
    }

    /* @inlinable */ public var wrappedValue: Value {
        return valueBox.value!.value
    }

    public var projectedValue: Self {
        return self
    }

    public let key: String

    public func Java_syncEnvironmentSupport(_ support: EnvironmentSupport?) {
        if let support {
            let valueHolder = support.valueHolder
            if valueHolder != SwiftObjectNil {
                valueBox.value = valueHolder.pointee()!
            } else {
                valueBox.value = Box(EnvironmentValues.builtin(key: key, bridgedValue: support.builtinValue) as! Value)
            }
        } else {
            valueBox.value = Box(defaultValue())
        }
    }
}

//extension Environment : Sendable where Value : Sendable {
//}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension Environment {
    public init(_ objectType: Value.Type) where Value : AnyObject, Value : Observable {
        self.key = EnvironmentValues.key(for: objectType)
        self.defaultValue = { EnvironmentValues.shared[objectType]! }
    }

    public init<T>(_ objectType: T.Type) where Value == T?, T : AnyObject, T : Observable {
        self.key = EnvironmentValues.key(for: objectType)
        self.defaultValue = { EnvironmentValues.shared[objectType] }
    }
}

@_cdecl("Java_skip_ui_EnvironmentSupport_Swift_1release")
public func EnvironmentSupport_Swift_release(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_valueHolder: SwiftObjectPointer) -> SwiftObjectPointer {
    Swift_valueHolder.release(as: Box<Any>.self)
    return SwiftObjectNil
}

#if os(Android) || ROBOLECTRIC
/// Compare the values held by two `EnvironmentSupport` value holders.
///
/// The Compose side calls this from `EnvironmentSupport.equals` to decide whether a bridged
/// environment value that was provided again is actually a different value. Without it every
/// evaluation of `.environment(_:_:)` or `.environment(_:)` looks like a change, because each
/// evaluation boxes the value anew, and every reader of the key is invalidated.
///
/// Two holders match when their values are `Equatable` and equal, or are the same class
/// instance, or are both `nil`. Anything else (closures, non-`Equatable` structs) does not
/// match, which is the behavior before this function existed.
@_cdecl("Java_skip_ui_EnvironmentSupport_Swift_1isSameValue")
public func EnvironmentSupport_Swift_isSameValue(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ Swift_valueHolder: SwiftObjectPointer, _ Swift_other: SwiftObjectPointer) -> Int64 {
    guard Swift_valueHolder != SwiftObjectNil, Swift_other != SwiftObjectNil else {
        return Swift_valueHolder == Swift_other ? 1 : 0
    }
    if Swift_valueHolder == Swift_other {
        return 1
    }
    let lhs: AnyObject? = Swift_valueHolder.pointee()
    let rhs: AnyObject? = Swift_other.pointee()
    guard let lhsBox = lhs as? any EnvironmentValueBox, let rhs else {
        return 0
    }
    return lhsBox.holdsSameEnvironmentValue(as: rhs) ? 1 : 0
}

/// Type-erased access to a boxed environment value for comparison.
protocol EnvironmentValueBox: AnyObject {
    func holdsSameEnvironmentValue(as other: AnyObject) -> Bool
}

extension Box: EnvironmentValueBox {
    func holdsSameEnvironmentValue(as other: AnyObject) -> Bool {
        guard let other = other as? Box<Value> else {
            return false
        }
        return environmentValuesMatch(value, other.value)
    }
}

private func environmentValuesMatch(_ lhs: Any, _ rhs: Any) -> Bool {
    if let lhs = lhs as? any Equatable {
        return lhs.isEqualEnvironmentValue(rhs)
    }
    // Not `Equatable`: look through optionals, then compare class instances by identity.
    let lhsUnwrapped = unwrapEnvironmentOptional(lhs)
    let rhsUnwrapped = unwrapEnvironmentOptional(rhs)
    switch (lhsUnwrapped, rhsUnwrapped) {
    case (nil, nil):
        return true
    case (let lhsValue?, let rhsValue?):
        guard type(of: lhsValue) is AnyClass, type(of: rhsValue) is AnyClass else {
            return false
        }
        return (lhsValue as AnyObject) === (rhsValue as AnyObject)
    default:
        return false
    }
}

private func unwrapEnvironmentOptional(_ value: Any) -> Any? {
    guard let optional = value as? any EnvironmentOptional else {
        return value
    }
    guard let wrapped = optional.environmentWrapped else {
        return nil
    }
    return unwrapEnvironmentOptional(wrapped)
}

private protocol EnvironmentOptional {
    var environmentWrapped: Any? { get }
}

extension Optional: EnvironmentOptional {
    fileprivate var environmentWrapped: Any? {
        switch self {
        case .none:
            return nil
        case .some(let wrapped):
            return wrapped
        }
    }
}

extension Equatable {
    fileprivate func isEqualEnvironmentValue(_ other: Any) -> Bool {
        guard let other = other as? Self else {
            return false
        }
        return self == other
    }
}
#endif
