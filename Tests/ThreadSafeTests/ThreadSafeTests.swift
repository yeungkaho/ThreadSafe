import Testing
import Foundation
import ThreadSafe

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

struct StringConvertibleTest {
    @Test func testStringInterpolation() {
        struct TestStruct {
            @ThreadSafe var text: String = "Hello"
        }
        
        let testStruct = TestStruct()
        
        #expect("\(testStruct)" == #"TestStruct(_text: "Hello")"#)
        // without the extension "\(wrapped)" will show the type instead of the value
        #expect("\(testStruct)" != "TestStruct(_text: Swift.String)")
    }
    
    @Test func testStringConvertible() {
        struct TestStruct: CustomStringConvertible, CustomDebugStringConvertible {
            @ThreadSafe var text: String = "Hello"
            var description: String { _text.description }
            var debugDescription: String { _text.debugDescription }
        }
        let testStruct = TestStruct()
        #expect(testStruct.debugDescription == testStruct.text.debugDescription)
        #expect(testStruct.description == testStruct.text.description)
    }
}

struct TestEquatable {
    // without the extension this code will simply fail to compile
    struct TestStruct<Value: Equatable>: Equatable {
        @ThreadSafe var value: Value
    }
    
    @Test func testIntEquatable() {
        
        let int1 = TestStruct(value: 1)
        let int2 = TestStruct(value: 1)
        let int3 = TestStruct(value: 2)
        
        #expect(int1 == int2)
        #expect(int1 != int3)
        
        let string1 = TestStruct(value: "foo")
        let string2 = TestStruct(value: "foo")
        let string3 = TestStruct(value: "bar")
        
        #expect(string1 == string2)
        #expect(string1 != string3)
    }
}

struct TestCustomReflectable {
    struct Custom: CustomReflectable, Equatable {
        var a = 1
        var b = 2
        var customMirror: Mirror {
            Mirror(self, children: ["A": a, "B": b])
        }
    }
    
    struct WrappedCustom {
        @ThreadSafe var value = Custom()
    }
    
    @Test func testCustomReflectablePreserved() throws {
        
        let mirror = Mirror(reflecting: WrappedCustom())
        
        try #require(mirror.children.count == 1)
        guard let child = mirror.children.first else {
            fatalError()
        }
        
        // label of wrapped value will have an underscore prefix
        #expect(child.label == "_value")
        
        let childMirror = Mirror(reflecting: child.value)
        let labels = childMirror.children.compactMap { $0.label }
        
        #expect(labels == ["A", "B"])
    }
    
}

struct TestSendable {
    
    // normally we don't have to do anything if all the members already conform to Sendable.
    struct SendableStruct: Sendable {
        var a: Int = 0
    }
    
    // when the property wrapper is used without the extension this code won't compile.
    struct SendableStructWrapped: Sendable {
        @ThreadSafe var a: Int = 0
    }
    
    // @unchecked Sendable puts the responsibility on the dev to ensure thread safety
    // without @ThreadSafe this class will compile but may cause issues
    class SenableObj: @unchecked Sendable {
        @ThreadSafe var a: Int = 0
    }
    
    @Test func testSendable() async {
        let sendable = SendableStruct()
        await doThingWithSendable(sendable)
        let sendableWrapped = SendableStructWrapped()
        await doThingWithSendable(sendableWrapped)
    }
    
    func doThingWithSendable(_ senable: Sendable) async {
        _ = await Task {
            senable
        }.value
    }
}

struct TestCodable {
    struct TestStruct: Codable, Equatable {
        struct SubStruct : Codable, Equatable {
            @ThreadSafe var text: String
        }
        @ThreadSafe var text: String
        @ThreadSafe var number: Int
        @ThreadSafe var bool: Bool
        @ThreadSafe var numberArray: [Int]
        @ThreadSafe var optionalText: String?
        @ThreadSafe var optionalText2: String?
        @ThreadSafe var optionalText3: String?
        @ThreadSafe var sub: SubStruct?
    }
    
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    
    @Test func testDecodeAndEncode() throws {
        let testJson = """
            {
                "text": "Hello",
                "number": 42,
                "bool": false,
                "numberArray": [0, 1, 2],
                "optionalText": "not null",
                "optionalText2": null,
                "sub": {
                    "text": "World"
                }
            }
            """
        let decoded = try decoder.decode(TestStruct.self, from: Data(testJson.utf8))
        
        #expect(decoded.text == "Hello")
        #expect(decoded.number == 42)
        #expect(!decoded.bool)
        #expect(decoded.numberArray == [0, 1, 2])
        #expect(decoded.optionalText == "not null")
        #expect(decoded.optionalText2 == nil)
        #expect(decoded.optionalText3 == nil)
        #expect(decoded.sub?.text == "World")
        
        let encoded = try encoder.encode(decoded)
        let encodedString = String(data: encoded, encoding: .utf8)!
        
        // nil values won't be encoded into the data
        #expect(!encodedString.contains("optionalText2"))
        #expect(!encodedString.contains("optionalText3"))
    }
    
    @Test func testEncodeThenDecodeAgain() throws {
        let aStruct = TestStruct(
            text: "Hello",
            number: 42,
            bool: false,
            numberArray: [0, 1, 2],
            optionalText: "not null",
            optionalText2: nil,
            optionalText3: "optionalText4",
            sub: TestStruct.SubStruct(text: "World")
        )
        
        let data = try JSONEncoder().encode(aStruct)
        let decoded = try JSONDecoder().decode(TestStruct.self, from: data)
        
        #expect(decoded == aStruct)
    }
}
