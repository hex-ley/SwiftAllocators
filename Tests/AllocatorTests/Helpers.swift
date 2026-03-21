@testable
import Allocators
import Testing



typealias Arena   = UnsafeMemoryArena
typealias Pointer = UnsafeMutablePointer
typealias RawPointer = UnsafeMutableRawPointer



func isAlignedCorrectly<T>(_ ptr: Pointer<T>) -> Bool
{
    let address   = Int(bitPattern: ptr)
    let alignment = MemoryLayout<T>.alignment
    return (address % alignment) == 0
}

func isAlignedCorrectly(_ ptr: RawPointer, alignment: Int) -> Bool
{
    let address = Int(bitPattern: ptr)
    return (address % alignment) == 0
}

func noOverlap(between startA: RawPointer, ofSize sizeA: Int,
               and     startB: RawPointer, ofSize sizeB: Int) -> Bool
{
    precondition(sizeA >= 0, "sizeA must not be negative")
    precondition(sizeB >= 0, "sizeB must not be negative")
    
    let endA = startA + sizeA
    let endB = startB + sizeB
    
    return !(startA < endB && startB < endA)
}
