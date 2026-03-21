@testable
import Allocators
import Testing



@Suite("Arena: Allocation Alignment")
struct Arena_AllocationAlignment
{
    /// Allocating types with strictly increasing
    /// alignment should still satisfy each type's
    /// requirement, because the bump pointer must
    /// be rounded up before each allocation.
    @Test("ascending alignment")
    func ascendingAlignment()
    {
        scopedMemoryArena(withBlockSize: 256) { arena in
            let a = arena.allocate(initializedTo: 1 as Int8 )
            let b = arena.allocate(initializedTo: 2 as Int16)
            let c = arena.allocate(initializedTo: 3 as Int32)
            let d = arena.allocate(initializedTo: 4 as Int64)

            #expect(isAlignedCorrectly(a))
            #expect(isAlignedCorrectly(b))
            #expect(isAlignedCorrectly(c))
            #expect(isAlignedCorrectly(d))
        }
    }

    /// Allocating types with strictly
    /// decreasing alignment exercises
    /// the path where no padding is
    /// needed between objects.
    @Test("descending alignment")
    func descendingAlignment()
    {
        scopedMemoryArena(withBlockSize: 256) { arena in
            let a = arena.allocate(initializedTo: 1 as Int8 )
            let b = arena.allocate(initializedTo: 2 as Int16)
            let c = arena.allocate(initializedTo: 3 as Int32)
            let d = arena.allocate(initializedTo: 4 as Int64)

            #expect(isAlignedCorrectly(a))
            #expect(isAlignedCorrectly(b))
            #expect(isAlignedCorrectly(c))
            #expect(isAlignedCorrectly(d))
        }
    }

    @Test("correct alignment after unaligning offset")
    func correctAlignmentAfterUnalign()
    {
        scopedMemoryArena(withBlockSize: 256) { arena in
            // Misalign the pointer first
            let _ = arena.allocate(initializedTo: 0  as Int8 )
            let p = arena.allocate(initializedTo: 69 as Int64)
            
            #expect(isAlignedCorrectly(p))
        }
    }

    @Test("ascending alignment for raw allocations")
    func rawAlignments()
    {
        scopedMemoryArena(withBlockSize: 256) { arena in
            for powerOfTwo in [1, 2, 4, 8, 16, 32, 64] {
                let raw = arena.allocate(
                    byteCount: powerOfTwo,
                    alignment: powerOfTwo
                )
                
                #expect(isAlignedCorrectly(raw, alignment: powerOfTwo))
            }
        }
    }
    
    @Test("correct alignment of oversized allocations")
    func test_alignmentOversizedAllocation()
    {
        let blockSize = 16
        let allocSize = 32
        
        scopedMemoryArena(withBlockSize: blockSize) { arena in
            for alignment in [1, 2, 4, 8, 16, 32, 64]
            {
                let ptr = arena.allocate(
                    byteCount: allocSize,
                    alignment: alignment
                )
                
                #expect(isAlignedCorrectly(ptr, alignment: alignment))
            }
        }
    }
    
    @Test("correct alignment of structs")
    func structAlignment()
    {
        struct Pair: Equatable { var x: Bool; var y: Int32 }
        
        let pair = Pair(x: true, y: 1234)

        scopedMemoryArena(withBlockSize: 1024) { arena in
            // Misalign the pointer first
            let _ = arena.allocate(initializedTo: 0xAB as UInt8)
            let p = arena.allocate(initializedTo: pair)
            
            #expect(isAlignedCorrectly(p))
            #expect(p.pointee == pair)
        }
    }
}
