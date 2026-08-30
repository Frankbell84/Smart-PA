import CryptoKit
import Foundation

// Vendored from MarlonJD/argon2id-swift-native 0.1.1 under the MIT License.
// KeyHollow patch: littleEndianUInt64(at:) is split into simple subexpressions
// to avoid an Xcode 16.4 type-checker timeout. No algorithmic operation changed.

/// Errors thrown by the Argon2id key-derivation implementation.
public enum Argon2idError: Error, Equatable {
    case invalidParameters
}

/// Pure Swift Argon2id v1.3 key derivation.
public enum Argon2id {
    public static let version: UInt32 = 0x13
    public static let defaultOutputByteCount = 32

    public static func deriveBytes(
        password: Data,
        salt: Data,
        memoryKiB: UInt32 = 65_536,
        iterations: UInt32 = 3,
        parallelism: UInt32 = 4,
        outputByteCount: Int = defaultOutputByteCount,
        secret: Data = Data(),
        associatedData: Data = Data()
    ) throws -> Data {
        try PureSwiftArgon2id.deriveBytes(
            password: password,
            salt: salt,
            memoryKiB: memoryKiB,
            iterations: iterations,
            parallelism: parallelism,
            outputByteCount: outputByteCount,
            secret: secret,
            associatedData: associatedData
        )
    }

    public static func deriveKey(
        password: Data,
        salt: Data,
        memoryKiB: UInt32 = 65_536,
        iterations: UInt32 = 3,
        parallelism: UInt32 = 4,
        outputByteCount: Int = defaultOutputByteCount,
        secret: Data = Data(),
        associatedData: Data = Data()
    ) throws -> SymmetricKey {
        SymmetricKey(data: try deriveBytes(
            password: password,
            salt: salt,
            memoryKiB: memoryKiB,
            iterations: iterations,
            parallelism: parallelism,
            outputByteCount: outputByteCount,
            secret: secret,
            associatedData: associatedData
        ))
    }
}

enum PureSwiftArgon2id {
    private static let syncPoints = 4
    private static let blockWords = 128
    private static let blockBytes = 1_024
    private static let addressesInBlock = 128
    private static let typeID: UInt32 = 2
    private static let maxParallelism: UInt32 = 0x00ff_ffff

    static func deriveBytes(
        password: Data,
        salt: Data,
        memoryKiB: UInt32,
        iterations: UInt32,
        parallelism: UInt32,
        outputByteCount: Int,
        secret: Data,
        associatedData: Data
    ) throws -> Data {
        guard outputByteCount >= 4,
              iterations > 0,
              parallelism > 0,
              parallelism <= maxParallelism,
              memoryKiB >= 8 * parallelism,
              outputByteCount <= Int(UInt32.max),
              password.count <= UInt32.max,
              salt.count <= UInt32.max,
              secret.count <= UInt32.max,
              associatedData.count <= UInt32.max else {
            throw Argon2idError.invalidParameters
        }

        let lanes = Int(parallelism)
        let memoryBlocks = Int(memoryKiB - (memoryKiB % (4 * parallelism)))
        let laneLength = memoryBlocks / lanes
        let segmentLength = laneLength / syncPoints

        var memory = [UInt64](repeating: 0, count: memoryBlocks * blockWords)
        let prehash = initialHash(
            password: password,
            salt: salt,
            memoryKiB: memoryKiB,
            iterations: iterations,
            parallelism: parallelism,
            outputByteCount: outputByteCount,
            secret: secret,
            associatedData: associatedData
        )

        for lane in 0..<lanes {
            storeInitialBlock(prehash: prehash, blockIndex: 0, lane: lane, laneLength: laneLength, into: &memory)
            storeInitialBlock(prehash: prehash, blockIndex: 1, lane: lane, laneLength: laneLength, into: &memory)
        }

        for pass in 0..<Int(iterations) {
            for slice in 0..<syncPoints {
                for lane in 0..<lanes {
                    fillSegment(
                        pass: pass,
                        slice: slice,
                        lane: lane,
                        iterations: Int(iterations),
                        lanes: lanes,
                        memoryBlocks: memoryBlocks,
                        laneLength: laneLength,
                        segmentLength: segmentLength,
                        memory: &memory
                    )
                }
            }
        }

        var finalBlock = [UInt64](repeating: 0, count: blockWords)
        let firstLastBlockOffset = (laneLength - 1) * blockWords
        for word in 0..<blockWords {
            finalBlock[word] = memory[firstLastBlockOffset + word]
        }
        for lane in 1..<lanes {
            let offset = (lane * laneLength + laneLength - 1) * blockWords
            for word in 0..<blockWords {
                finalBlock[word] ^= memory[offset + word]
            }
        }

        return variableLengthHash(wordsToBytes(finalBlock), outputByteCount: outputByteCount)
    }

    static func blake2b(_ data: Data, outputByteCount: Int) -> Data {
        Blake2b.hash(data, outputByteCount: outputByteCount)
    }

    static func initialHash(
        password: Data,
        salt: Data,
        memoryKiB: UInt32,
        iterations: UInt32,
        parallelism: UInt32,
        outputByteCount: Int,
        secret: Data,
        associatedData: Data
    ) -> Data {
        var input = Data()
        input.reserveCapacity(4 * 10 + password.count + salt.count + secret.count + associatedData.count)
        input.appendLittleEndian(parallelism)
        input.appendLittleEndian(UInt32(outputByteCount))
        input.appendLittleEndian(memoryKiB)
        input.appendLittleEndian(iterations)
        input.appendLittleEndian(Argon2id.version)
        input.appendLittleEndian(typeID)
        input.appendLittleEndian(UInt32(password.count))
        input.append(password)
        input.appendLittleEndian(UInt32(salt.count))
        input.append(salt)
        input.appendLittleEndian(UInt32(secret.count))
        input.append(secret)
        input.appendLittleEndian(UInt32(associatedData.count))
        input.append(associatedData)
        return Blake2b.hash(input, outputByteCount: 64)
    }

    private static func storeInitialBlock(
        prehash: Data,
        blockIndex: UInt32,
        lane: Int,
        laneLength: Int,
        into memory: inout [UInt64]
    ) {
        var input = prehash
        input.appendLittleEndian(blockIndex)
        input.appendLittleEndian(UInt32(lane))
        let block = variableLengthHash(input, outputByteCount: blockBytes)
        let words = bytesToWords(block)
        let offset = (lane * laneLength + Int(blockIndex)) * blockWords
        for word in 0..<blockWords { memory[offset + word] = words[word] }
    }

    private static func fillSegment(
        pass: Int,
        slice: Int,
        lane: Int,
        iterations: Int,
        lanes: Int,
        memoryBlocks: Int,
        laneLength: Int,
        segmentLength: Int,
        memory: inout [UInt64]
    ) {
        let dataIndependentAddressing = pass == 0 && slice < syncPoints / 2
        let startingIndex = pass == 0 && slice == 0 ? 2 : 0
        var addressBlock = [UInt64](repeating: 0, count: blockWords)
        var inputBlock = [UInt64](repeating: 0, count: blockWords)
        let zeroBlock = [UInt64](repeating: 0, count: blockWords)

        if dataIndependentAddressing {
            inputBlock[0] = UInt64(pass)
            inputBlock[1] = UInt64(lane)
            inputBlock[2] = UInt64(slice)
            inputBlock[3] = UInt64(memoryBlocks)
            inputBlock[4] = UInt64(iterations)
            inputBlock[5] = UInt64(typeID)
            if pass == 0 && slice == 0 {
                nextAddresses(addressBlock: &addressBlock, inputBlock: &inputBlock, zeroBlock: zeroBlock)
            }
        }

        for index in startingIndex..<segmentLength {
            let currentIndex = slice * segmentLength + index
            let previousIndex = currentIndex == 0 ? laneLength - 1 : currentIndex - 1
            let previousOffset = (lane * laneLength + previousIndex) * blockWords
            let pseudoRandom: UInt64
            if dataIndependentAddressing {
                if index % addressesInBlock == 0 {
                    nextAddresses(addressBlock: &addressBlock, inputBlock: &inputBlock, zeroBlock: zeroBlock)
                }
                pseudoRandom = addressBlock[index % addressesInBlock]
            } else {
                pseudoRandom = memory[previousOffset]
            }

            var referenceLane = Int((pseudoRandom >> 32) % UInt64(lanes))
            if pass == 0 && slice == 0 { referenceLane = lane }

            let referenceIndex = indexAlpha(
                pass: pass,
                slice: slice,
                index: index,
                sameLane: referenceLane == lane,
                pseudoRandom: UInt32(truncatingIfNeeded: pseudoRandom),
                laneLength: laneLength,
                segmentLength: segmentLength
            )
            let referenceOffset = (referenceLane * laneLength + referenceIndex) * blockWords
            let currentOffset = (lane * laneLength + currentIndex) * blockWords
            fillBlock(
                previousOffset: previousOffset,
                referenceOffset: referenceOffset,
                currentOffset: currentOffset,
                xorWithCurrent: pass != 0,
                memory: &memory
            )
        }
    }

    private static func indexAlpha(
        pass: Int,
        slice: Int,
        index: Int,
        sameLane: Bool,
        pseudoRandom: UInt32,
        laneLength: Int,
        segmentLength: Int
    ) -> Int {
        let referenceAreaSize: Int
        if pass == 0 {
            if slice == 0 { referenceAreaSize = index - 1 }
            else if sameLane { referenceAreaSize = slice * segmentLength + index - 1 }
            else { referenceAreaSize = slice * segmentLength + (index == 0 ? -1 : 0) }
        } else if sameLane {
            referenceAreaSize = laneLength - segmentLength + index - 1
        } else {
            referenceAreaSize = laneLength - segmentLength + (index == 0 ? -1 : 0)
        }

        let squared = UInt64(pseudoRandom) &* UInt64(pseudoRandom)
        let relative = squared >> 32
        let scaled = (UInt64(referenceAreaSize) &* relative) >> 32
        let mapped = UInt64(referenceAreaSize - 1) &- scaled
        let startPosition = pass == 0 ? 0 : (slice == syncPoints - 1 ? 0 : (slice + 1) * segmentLength)
        return (startPosition + Int(mapped)) % laneLength
    }

    private static func nextAddresses(addressBlock: inout [UInt64], inputBlock: inout [UInt64], zeroBlock: [UInt64]) {
        inputBlock[6] &+= 1
        var temporary = [UInt64](repeating: 0, count: blockWords)
        fillBlock(x: zeroBlock, y: inputBlock, into: &temporary)
        fillBlock(x: zeroBlock, y: temporary, into: &addressBlock)
    }

    private static func fillBlock(
        previousOffset: Int,
        referenceOffset: Int,
        currentOffset: Int,
        xorWithCurrent: Bool,
        memory: inout [UInt64]
    ) {
        var block = [UInt64](repeating: 0, count: blockWords)
        var output = [UInt64](repeating: 0, count: blockWords)
        for word in 0..<blockWords {
            block[word] = memory[previousOffset + word] ^ memory[referenceOffset + word]
            output[word] = xorWithCurrent ? block[word] ^ memory[currentOffset + word] : block[word]
        }
        permuteBlock(&block)
        for word in 0..<blockWords { memory[currentOffset + word] = output[word] ^ block[word] }
    }

    private static func fillBlock(x: [UInt64], y: [UInt64], into output: inout [UInt64]) {
        var block = [UInt64](repeating: 0, count: blockWords)
        for word in 0..<blockWords {
            block[word] = x[word] ^ y[word]
            output[word] = block[word]
        }
        permuteBlock(&block)
        for word in 0..<blockWords { output[word] ^= block[word] }
    }

    private static func permuteBlock(_ block: inout [UInt64]) {
        for row in 0..<8 {
            let start = row * 16
            blamkaRound(
                &block,
                start, start + 1, start + 2, start + 3,
                start + 4, start + 5, start + 6, start + 7,
                start + 8, start + 9, start + 10, start + 11,
                start + 12, start + 13, start + 14, start + 15
            )
        }
        for column in 0..<8 {
            blamkaRound(
                &block,
                2 * column, 2 * column + 1,
                2 * column + 16, 2 * column + 17,
                2 * column + 32, 2 * column + 33,
                2 * column + 48, 2 * column + 49,
                2 * column + 64, 2 * column + 65,
                2 * column + 80, 2 * column + 81,
                2 * column + 96, 2 * column + 97,
                2 * column + 112, 2 * column + 113
            )
        }
    }

    private static func blamkaRound(
        _ v: inout [UInt64],
        _ v0: Int, _ v1: Int, _ v2: Int, _ v3: Int,
        _ v4: Int, _ v5: Int, _ v6: Int, _ v7: Int,
        _ v8: Int, _ v9: Int, _ v10: Int, _ v11: Int,
        _ v12: Int, _ v13: Int, _ v14: Int, _ v15: Int
    ) {
        blamka(&v, v0, v4, v8, v12)
        blamka(&v, v1, v5, v9, v13)
        blamka(&v, v2, v6, v10, v14)
        blamka(&v, v3, v7, v11, v15)
        blamka(&v, v0, v5, v10, v15)
        blamka(&v, v1, v6, v11, v12)
        blamka(&v, v2, v7, v8, v13)
        blamka(&v, v3, v4, v9, v14)
    }

    private static func blamka(_ v: inout [UInt64], _ a: Int, _ b: Int, _ c: Int, _ d: Int) {
        v[a] = blamkaAdd(v[a], v[b])
        v[d] = (v[d] ^ v[a]).rotatedRight(by: 32)
        v[c] = blamkaAdd(v[c], v[d])
        v[b] = (v[b] ^ v[c]).rotatedRight(by: 24)
        v[a] = blamkaAdd(v[a], v[b])
        v[d] = (v[d] ^ v[a]).rotatedRight(by: 16)
        v[c] = blamkaAdd(v[c], v[d])
        v[b] = (v[b] ^ v[c]).rotatedRight(by: 63)
    }

    private static func blamkaAdd(_ x: UInt64, _ y: UInt64) -> UInt64 {
        x &+ y &+ (2 &* (x & 0xffff_ffff) &* (y & 0xffff_ffff))
    }

    private static func variableLengthHash(_ data: Data, outputByteCount: Int) -> Data {
        var input = Data()
        input.reserveCapacity(data.count + 4)
        input.appendLittleEndian(UInt32(outputByteCount))
        input.append(data)
        if outputByteCount <= 64 { return Blake2b.hash(input, outputByteCount: outputByteCount) }

        let blockCount = (outputByteCount + 31) / 32 - 2
        var output = Data()
        output.reserveCapacity(outputByteCount)
        var current = Blake2b.hash(input, outputByteCount: 64)
        output.append(current.prefix(32))
        if blockCount > 1 {
            for _ in 2...blockCount {
                current = Blake2b.hash(current, outputByteCount: 64)
                output.append(current.prefix(32))
            }
        }
        let finalByteCount = outputByteCount - 32 * blockCount
        output.append(Blake2b.hash(current, outputByteCount: finalByteCount))
        return output
    }

    private static func bytesToWords(_ data: Data) -> [UInt64] {
        var words = [UInt64](repeating: 0, count: data.count / 8)
        for wordIndex in 0..<words.count { words[wordIndex] = data.littleEndianUInt64(at: wordIndex * 8) }
        return words
    }

    private static func wordsToBytes(_ words: [UInt64]) -> Data {
        var data = Data()
        data.reserveCapacity(words.count * 8)
        for word in words { data.appendLittleEndian(word) }
        return data
    }
}

private enum Blake2b {
    private static let blockByteCount = 128
    private static let iv: [UInt64] = [
        0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
        0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179
    ]
    private static let sigma: [[Int]] = [
        [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15],
        [14,10,4,8,9,15,13,6,1,12,0,2,11,7,5,3],
        [11,8,12,0,5,2,15,13,10,14,3,6,7,1,9,4],
        [7,9,3,1,13,12,11,14,2,6,5,10,4,0,15,8],
        [9,0,5,7,2,4,10,15,14,1,11,12,6,8,3,13],
        [2,12,6,10,0,11,8,3,4,13,7,5,15,14,1,9],
        [12,5,1,15,14,13,4,10,0,7,6,3,9,2,8,11],
        [13,11,7,14,12,1,3,9,5,0,15,4,8,6,2,10],
        [6,15,14,9,11,3,0,8,12,2,13,7,1,4,10,5],
        [10,2,8,4,7,6,1,5,15,11,9,14,3,12,13,0],
        [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15],
        [14,10,4,8,9,15,13,6,1,12,0,2,11,7,5,3]
    ]

    static func hash(_ data: Data, outputByteCount: Int) -> Data {
        precondition((1...64).contains(outputByteCount))
        var h = iv
        h[0] ^= 0x0101_0000 ^ UInt64(outputByteCount)
        var offset = 0
        var counterLow: UInt64 = 0
        var counterHigh: UInt64 = 0
        while offset + blockByteCount < data.count {
            let block = paddedBlock(data, offset: offset, byteCount: blockByteCount)
            addToCounter(UInt64(blockByteCount), low: &counterLow, high: &counterHigh)
            compress(block: block, h: &h, counterLow: counterLow, counterHigh: counterHigh, isFinal: false)
            offset += blockByteCount
        }
        let remainingByteCount = data.count - offset
        let block = paddedBlock(data, offset: offset, byteCount: remainingByteCount)
        addToCounter(UInt64(remainingByteCount), low: &counterLow, high: &counterHigh)
        compress(block: block, h: &h, counterLow: counterLow, counterHigh: counterHigh, isFinal: true)
        var output = Data()
        output.reserveCapacity(64)
        for word in h { output.appendLittleEndian(word) }
        return Data(output.prefix(outputByteCount))
    }

    private static func paddedBlock(_ data: Data, offset: Int, byteCount: Int) -> Data {
        var block = Data(repeating: 0, count: blockByteCount)
        guard byteCount > 0 else { return block }
        block.replaceSubrange(0..<byteCount, with: data[offset..<(offset + byteCount)])
        return block
    }

    private static func addToCounter(_ value: UInt64, low: inout UInt64, high: inout UInt64) {
        let previous = low
        low &+= value
        if low < previous { high &+= 1 }
    }

    private static func compress(block: Data, h: inout [UInt64], counterLow: UInt64, counterHigh: UInt64, isFinal: Bool) {
        var message = [UInt64](repeating: 0, count: 16)
        for index in 0..<16 { message[index] = block.littleEndianUInt64(at: index * 8) }
        var v = [UInt64](repeating: 0, count: 16)
        for index in 0..<8 {
            v[index] = h[index]
            v[index + 8] = iv[index]
        }
        v[12] ^= counterLow
        v[13] ^= counterHigh
        if isFinal { v[14] = ~v[14] }
        for round in 0..<12 {
            let s = sigma[round]
            g(&v,0,4,8,12,message[s[0]],message[s[1]])
            g(&v,1,5,9,13,message[s[2]],message[s[3]])
            g(&v,2,6,10,14,message[s[4]],message[s[5]])
            g(&v,3,7,11,15,message[s[6]],message[s[7]])
            g(&v,0,5,10,15,message[s[8]],message[s[9]])
            g(&v,1,6,11,12,message[s[10]],message[s[11]])
            g(&v,2,7,8,13,message[s[12]],message[s[13]])
            g(&v,3,4,9,14,message[s[14]],message[s[15]])
        }
        for index in 0..<8 { h[index] ^= v[index] ^ v[index + 8] }
    }

    private static func g(_ v: inout [UInt64], _ a: Int, _ b: Int, _ c: Int, _ d: Int, _ x: UInt64, _ y: UInt64) {
        v[a] = v[a] &+ v[b] &+ x
        v[d] = (v[d] ^ v[a]).rotatedRight(by: 32)
        v[c] = v[c] &+ v[d]
        v[b] = (v[b] ^ v[c]).rotatedRight(by: 24)
        v[a] = v[a] &+ v[b] &+ y
        v[d] = (v[d] ^ v[a]).rotatedRight(by: 16)
        v[c] = v[c] &+ v[d]
        v[b] = (v[b] ^ v[c]).rotatedRight(by: 63)
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 24))
    }

    mutating func appendLittleEndian(_ value: UInt64) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 24))
        append(UInt8(truncatingIfNeeded: value >> 32))
        append(UInt8(truncatingIfNeeded: value >> 40))
        append(UInt8(truncatingIfNeeded: value >> 48))
        append(UInt8(truncatingIfNeeded: value >> 56))
    }

    func littleEndianUInt64(at offset: Int) -> UInt64 {
        let b0 = UInt64(self[index(startIndex, offsetBy: offset)])
        let b1 = UInt64(self[index(startIndex, offsetBy: offset + 1)]) << 8
        let b2 = UInt64(self[index(startIndex, offsetBy: offset + 2)]) << 16
        let b3 = UInt64(self[index(startIndex, offsetBy: offset + 3)]) << 24
        let b4 = UInt64(self[index(startIndex, offsetBy: offset + 4)]) << 32
        let b5 = UInt64(self[index(startIndex, offsetBy: offset + 5)]) << 40
        let b6 = UInt64(self[index(startIndex, offsetBy: offset + 6)]) << 48
        let b7 = UInt64(self[index(startIndex, offsetBy: offset + 7)]) << 56
        return b0 | b1 | b2 | b3 | b4 | b5 | b6 | b7
    }
}

private extension UInt64 {
    func rotatedRight(by amount: UInt64) -> UInt64 {
        (self >> amount) | (self << (64 - amount))
    }
}
