// The Swift Programming Language
// https://docs.swift.org/swift-book
import Foundation

@propertyWrapper
public struct ThreadSafe<T> {
    
    public var wrappedValue: T {
        get {
            lock.withReadLock { box.value }
        }
        set {
            lock.withWriteLock {
                if valueTypeCopyOnWrite {
                    let addrHash = withUnsafePointer(to: &self) { $0.hashValue }
                    if addrHash != lastAddressHash {
                        // addrHash changed - this is a copy
                        // make new box with new value
                        box = Box(newValue)
                        lastAddressHash = addrHash
                        // new lock for the copied property wrapper
                        lock = RWLock()
                    } else {
                        box.value = newValue
                    }
                } else {
                    box.value = newValue
                }
            }
        }
    }
    
    /***
     Regarding `valueTypeCopyOnWrite`:
     When `valueTypeCopyOnWrite` is `true` and the wrapped value type is a value type,\
     the property wrapper will do extra memory check on writes to determine if the current instance is under a copied struct,\
     and if so it will create a new box to ensure the original instance is not affected.\
     For reference types `valueTypeCopyOnWrite` does nothing.\
     You can disable it if you can be sure that maintaining value type copy isn't necessary, this will give you a back a tiny bit of performance as it won't need to check its memory address on writes anymore
     ```
     struct Example {
         // valueTypeCopyOnWrite enabled by default
         @ThreadSafe var string: String = "Hello"
         // valueTypeCopyOnWrite disabled
         @ThreadSafe(valueTypeCopyOnWrite: false) var anotherString: String = "Hello"
         // won't do anything as NSMutableString is a class
         @ThreadSafe(valueTypeCopyOnWrite: true) var nsString: NSMutableString = "Hello"
     }

     let example = Example()
     var copy = example
     copy.string.append(", World!")
     print(example.string) // Hello
     print(copy.string) // Hello, World!
     copy.anotherString.append(", World!")
     print(example.anotherString) // Hello, World!
     print(copy.anotherString) // Hello, World!
     copy.nsString.append(", World!")
     print(example.nsString) // Hello, World!
     print(copy.nsString) // Hello, World!
     ```
     */
    public init(wrappedValue: T, valueTypeCopyOnWrite: Bool = true) {
        self.box = Box(wrappedValue)
        self.valueTypeCopyOnWrite = valueTypeCopyOnWrite && !(T.self is AnyObject.Type)
        if self.valueTypeCopyOnWrite {
            lastAddressHash = withUnsafePointer(to: &self) { $0.hashValue }
        }
    }
    
    private final class Box {
        var value: T
        init(_ value: T) { self.value = value }
    }
    
    private var box: Box
    
    private var lock = RWLock()
    
    private let valueTypeCopyOnWrite: Bool
    private var lastAddressHash: Int!
    
}

final class RWLock {

    private var rwlock = pthread_rwlock_t()

    init() {
        // Initialize the read-write lock.
        // The second parameter is for attributes, which can be nil for default attributes.
        let status = pthread_rwlock_init(&rwlock, nil)
        assert(status == 0, "Failed to initialize read-write lock: \(status)")
    }

    deinit {
        let status = pthread_rwlock_destroy(&rwlock)
        assert(status == 0, "Failed to destroy read-write lock: \(status)")
    }

    @discardableResult @inline(__always)
    func withReadLock<Result>(_ body: () -> Result) -> Result {
        pthread_rwlock_rdlock(&rwlock)
        defer { pthread_rwlock_unlock(&rwlock) }
        return body()
    }

    @discardableResult @inline(__always)
    func withWriteLock<Result>(_ body: () -> Result) -> Result {
        pthread_rwlock_wrlock(&rwlock)
        defer { pthread_rwlock_unlock(&rwlock) }
        return body()
    }
}
