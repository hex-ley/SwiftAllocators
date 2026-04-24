/// Include the following forward declaration in your C code:
/// ```c
/// void* arena_allocate(void* allocator, intptr_t bytecount, intptr_t alignment);
/// ```
#if swift(>=6.3)
@c func arena_allocate(
    _ allocator: OpaquePointer,
    _ bytecount: Int,
    _ alignment: Int,
) -> UnsafeMutableRawPointer
{
    return UnsafeMutablePointer<UnsafeMemoryArena>
        .init(allocator)
        .pointee
        .allocate(byteCount: bytecount, alignment: alignment)
}

@c func arena_destroy(_ allocator: OpaquePointer)
{
    UnsafeMutablePointer<UnsafeMemoryArena>
        .init(allocator)
        .move()
        .destroy()
}
#endif
