import Testing
import Foundation
@testable import ThreadSafe

class ThreadSafetyTest: @unchecked Sendable {
    
    class Obj {
        let id = UUID().uuidString
    }
    
    // If @ThreadSafe is removed, the test would crash instantly
    @ThreadSafe var obj = Obj()
    
    @Test func testThreadSafe() async throws {
        let coreCount = ProcessInfo.processInfo.activeProcessorCount
        
        for _ in 0 ..< coreCount / 2 {
            Thread { // write thread
                while true {
                    self.obj = .init()
                }
            }.start()
        }
        
        for _ in 0 ..< coreCount / 2{
            Thread { // read thread
                while self.obj.id.count != 0 {}
            }.start()
        }
        
        // If it doesn't crash after 10s, consider it passed.
        // I think it's good enough as the possibility for a false positive is microscopic.
        // Can't think of a way to definitively prove it's thread safe
        try? await Task.sleep(for: .seconds(10))
    }
}

@Test func TestCopyBehaviour() async throws {
    struct Example {
        // valueTypeCopyOnWrite enabled by default
        @ThreadSafe var string: String = "Hello"
        // valueTypeCopyOnWrite disabled
        @ThreadSafe(valueTypeCopyOnWrite: false) var anotherString: String = "Hello"
        // won't do anything as NSMutableString is a class
        @ThreadSafe(valueTypeCopyOnWrite: true) var nsString: NSMutableString = "Hello"
        // same as above
        @ThreadSafe(valueTypeCopyOnWrite: false) var anotherNSString: NSMutableString = "Hello"
    }

    let original = Example()
    var copy = original
    
    copy.string.append(", World!")
    #expect(original.string == "Hello") // copy on write triggered, original not affected
    #expect(copy.string == "Hello, World!")
    
    copy.anotherString.append(", World!")
    #expect(original.anotherString == "Hello, World!") // valueTypeCopyOnWrite == false, underlying box not copied
    #expect(copy.anotherString == "Hello, World!")
    
    copy.nsString.append(", World!")
    #expect(original.nsString == "Hello, World!")
    #expect(copy.nsString == "Hello, World!")
    
    copy.anotherNSString.append(", World!")
    #expect(original.anotherNSString == "Hello, World!")
    #expect(copy.anotherNSString == "Hello, World!")
}
