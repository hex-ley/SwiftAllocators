/// Runs a closure with a temporary memory arena and destroys it on return.
///
/// Use this function to confine the lifetime of an ``UnsafeMemoryArena`` to a
/// lexical scope. The arena is destroyed automatically when `body` returns.
///
/// ```swift
/// let result = try scopedMemoryArena(withBlockSize: 4096) { arena in
///     let p = arena.allocate(initializedTo: 42)
///     return computeSomething(using: p)
/// } // arena destroyed here; p is now invalid
/// ```
///
/// All pointers obtained from `arena` inside `body` become dangling once the
/// closure returns. Do not store them in any variable that outlives the call.
///
/// - Parameters:
///   - size: The size, in bytes, of each backing memory block in the arena.
///     Must be greater than zero.
///   - body: A closure that receives an `inout` reference to a newly created
///     arena. The closure may allocate freely.
/// - Returns: The value returned by `body`.
@inline(__always)
@inlinable
public func scopedMemoryArena<T>(
    withBlockSize size: Int = 16_384,
    _ body: (_ arena: inout UnsafeMemoryArena) -> T
) -> T {
    var arena = UnsafeMemoryArena(blockSize: size)
    let result = body(&arena)
    arena.destroy()
    return result
}
