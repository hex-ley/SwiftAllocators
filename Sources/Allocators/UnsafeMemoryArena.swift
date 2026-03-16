/// A fast, bump-pointer allocator backed by a chain of fixed-size memory blocks.
///
/// `UnsafeMemoryArena` provides O(1) allocation by advancing a pointer into a
/// pre-allocated backing block. When the current block is exhausted, a new one
/// is obtained from the system allocator and appended to an internal linked list.
/// All memory is reclaimed in a single pass when the arena is destroyed.
///
/// This design is well-suited for phase-based workloads: allocate freely during
/// a computation, then destroy the arena in one call when the phase is complete.
///
/// - Warning: Using this type requires strict lifetime discipline.
///   All pointers vended by the arena become dangling as soon as ``destroy()``
///   is called. The arena itself must be destroyed manually; it has no
///   automatic deallocation.
///
/// ## Scoped usage
///
/// Prefer ``scopedMemoryArena(withBlockSize:_:)`` to manage the lifetime
/// automatically via a trailing closure:
///
/// ```swift
/// scopedArena(withBlockSize: 1024) { arena in
///     let p: UnsafeMutablePointer<Int> = arena.allocate(initializedTo: 42)
///     // use p here
/// } // arena is destroyed on exit
/// ```
///
/// ## Manual usage
///
/// When a scoped closure is not practical, destroy the arena explicitly:
///
/// ```swift
/// var arena = UnsafeMemoryArena(blockSize: 4096)
/// let p: UnsafeMutablePointer<Int> = arena.allocate(initializedTo: 42)
/// // ...
/// arena.destroy() // all pointers obtained above are now invalid
/// ```
///
/// ## Allocation strategy
///
/// - **Normal allocations** (≤ block size) are served from the current backing
///   block. When the block has insufficient space, a new block of `blockSize`
///   bytes is allocated and becomes the active block. Prior blocks are retained
///   until the arena is destroyed.
/// - **Oversized allocations** (> block size) receive a dedicated block sized
///   exactly to the request. The active block is left intact, avoiding
///   fragmentation of the common fast path.
///
/// Backing blocks are chained into a singly linked list. ``destroy()`` traverses
/// the list and returns every block to the system allocator in one pass, without
/// tracking individual allocations.
public struct UnsafeMemoryArena: ~Copyable
{
    internal typealias RawPointer = UnsafeMutableRawPointer
    internal typealias Pointer    = UnsafeMutablePointer
    
    private struct MemoryBlockHeader {
        internal var previousBlock: RawPointer?
        
        internal init(_ previousBlock: RawPointer?) {
            self.previousBlock = previousBlock
        }
    }
    
    
    
    
    
    // MARK: variables
    
    /// The length of an arena's
    /// backing memory block in bytes.
    internal let blockLength: Int
    
    /// The offset from the current block's base pointer
    /// to the first byte of unallocated memory.
    internal var currentOffset: Int
    
    /// The base pointer to the current
    /// backing memory block.
    internal var backingMemory: RawPointer!
    
    
    
    
    
    // MARK: (de)init
    
    private init(_ size: Int)
    {
        self.blockLength   = size
        self.currentOffset = 0
        self.backingMemory = nil
    }
    
    /// Creates an arena with the specified backing block size.
    ///
    /// The first backing block is not allocated until the first allocation is made.
    ///
    /// - Parameter blockSize:
    ///   The size, in bytes, of each backing memory block.
    ///   Must be greater than zero. Allocations larger than `blockSize` receive a
    ///   dedicated block and do not affect this value.
    public init(blockSize: Int)
    {
        // TODO: round up to next page size?
        assert(blockSize > MemoryLayout<MemoryBlockHeader>.size)

        self.init(blockSize)
        self.initializeNewBlock(first: true)
    }
    
    /// Destroys the arena and releases all allocated memory.
    ///
    /// Traverses the internal block list and returns every backing block to the
    /// system allocator. After this call, all pointers previously obtained from
    /// the arena are dangling and must not be accessed.
    ///
    /// - Note: This method must be called explicitly when not using
    ///   ``scopedMemoryArena(withBlockSize:_:)``.
    public consuming func destroy()
    {
        var next: RawPointer? = backingMemory

        while let block = next {
            next = block
                .assumingMemoryBound(to: MemoryBlockHeader.self)
                .pointee
                .previousBlock

            block.deallocate()
        }
    }


    
    
    
    // MARK: slow paths

    /// Allocates a new backing memory block if the current backing
    /// memory block is exhausted. Resets the `currentOffset`,
    /// and creates a link to the previous backing memory block.
    @inline(__always)
    private mutating func initializeNewBlock(first isFirstBlock: Bool = false)
    {
        let previousBlock = isFirstBlock ? nil : backingMemory
        
        let newBlock = RawPointer.allocate(
            byteCount: blockLength,
            alignment: MemoryLayout<MemoryBlockHeader>.alignment
        )
        
        newBlock
            .bindMemory(to: MemoryBlockHeader.self, capacity: 1)
            .initialize(to: MemoryBlockHeader(previousBlock))
        
        backingMemory = newBlock
        currentOffset = MemoryLayout<MemoryBlockHeader>.size
    }
    
    /// Allocates a dedicated backing memory block for memory
    /// allocations too large to fit within a standard block.
    @inline(__always)
    private mutating func allocateDedicatedBlock(_ byteCount: Int, _ alignment: Int) -> RawPointer
    {
        let blockHeaderSize = MemoryLayout<MemoryBlockHeader>.size
        let offsetAlignment = (blockHeaderSize + alignment - 1) & ~(alignment - 1)
        
        let byteCountNewBlock = offsetAlignment + byteCount
        let alignmentNewBlock = max(MemoryLayout<MemoryBlockHeader>.alignment, alignment)
        
        let curBlock = backingMemory!
        let oldBlock = backingMemory
            .assumingMemoryBound(to: MemoryBlockHeader.self)
            .pointee
            .previousBlock
        
        let newBlock = RawPointer.allocate(
            byteCount: byteCountNewBlock,
            alignment: alignmentNewBlock
        )
        
        let headerCurBlock = curBlock.assumingMemoryBound(to: MemoryBlockHeader.self)
        let headerNewBlock = newBlock.bindMemory(to: MemoryBlockHeader.self, capacity: 1)

        headerNewBlock.initialize(to: MemoryBlockHeader(oldBlock))
        headerCurBlock.pointee = MemoryBlockHeader(newBlock)
        
        return newBlock + offsetAlignment
    }
    
    
    

    
    // MARK: allocate
    
    /// Allocates uninitialized memory with the given size and alignment.
    ///
    /// Serviced from the current backing block when space permits; otherwise a new
    /// block is obtained from the system allocator. Oversized requests (larger than
    /// the arena's block size) receive a dedicated block.
    ///
    /// The returned memory is not bound to any type. Bind and initialize it before
    /// performing typed operations.
    ///
    /// Do not call `deallocate()` on pointers returned by this method. Memory is
    /// reclaimed only when the arena is destroyed via ``destroy()``.
    ///
    /// - Parameters:
    ///   - byteCount: Number of bytes to allocate. Must be greater than zero.
    ///   - alignment: Required alignment in bytes. Must be a power of two.
    ///
    /// - Returns: A pointer to uninitialized, unbound allocated memory.
    public mutating func allocate(byteCount: Int, alignment: Int) -> UnsafeMutableRawPointer
    {
        let sizeHeader = MemoryLayout<MemoryBlockHeader>.size
        
        if _slowPath(byteCount > blockLength - sizeHeader) {
            return allocateDedicatedBlock(byteCount, alignment)
        }
        
        var allocation: RawPointer
        var newOffset: Int
        
        allocation = backingMemory
            .advanced(by: currentOffset)
            .alignedUp(toMultipleOf: alignment)
        newOffset = allocation - backingMemory
        
        if _slowPath(newOffset >= blockLength) {
            initializeNewBlock()
            allocation = backingMemory
                .advanced(by: currentOffset)
                .alignedUp(toMultipleOf: alignment)
            newOffset = allocation - backingMemory
        }
        
        currentOffset = newOffset + byteCount
        
        return allocation
    }
    
    /// Allocates memory for a value of type `T` and initializes it.
    ///
    /// Equivalent to calling ``allocate(byteCount:alignment:)`` with the size and
    /// alignment of `T`, then initializing the result with `value`.
    ///
    /// - Parameters:
    ///     - value: The value to store in the newly allocated memory.
    ///
    /// - Returns: A typed pointer to the initialized allocation.
    @inlinable
    public mutating func allocate<T>(initializedTo value: consuming T) -> UnsafeMutablePointer<T>
    {
        let rawAllocation = allocate(
            byteCount: MemoryLayout<T>.size,
            alignment: MemoryLayout<T>.alignment
        )
        
        let allocation = rawAllocation.bindMemory(
            to: T.self,
            capacity: 1
        )
        
        allocation.initialize(to: value)
        return allocation
    }
}
