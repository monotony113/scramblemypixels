//
//  SHA2.swift
//  pixelscrambling
//
//  Created by Tony Wu on 1/7/19.
//  Copyright © 2019 Tony Wu. All rights reserved.
//

import Foundation
import CommonCrypto

/// This program manipulate bitmap data through the following methods:
///
/// - substitution: each pixel is substituted by bitwise-XORing its color values (RGB, alpha is untouched for now because of alpha premultiplication) with bytes generated with the specified password. Doing this again restores the pixel. For obvious reasons this will not work with 16- and 32-bit floating-point images.
/// - permutation: each pixel is translated from its original location to a new location according to a vector value specified on a lookup table, which is generated using the specified password
/// - unpermutation: each pixel is translated from its location to a new location like it is in permutation, however unpermutation instructs the program to use a lookup table that is complementary to the lookup table used in permutation
enum CipherMode: Float {
    case substitution = 0.0
    case permutation = 0.5
    case unpermutation = 1.0
}

extension Data {
    
    /// (stolen from StackOverflow)
    ///
    /// - Returns: the 64-byte SHA-512 digest
    func sha512Digest() -> Data {
        var digestData = Data(count: Int(CC_SHA512_DIGEST_LENGTH))
        _ = digestData.withUnsafeMutableBytes {digestBytes in
            self.withUnsafeBytes {messageBytes in
                CC_SHA512(messageBytes, CC_LONG(self.count), digestBytes)
            }
        }
        return digestData
    }
}

struct CipherSecret: Hashable {
    let substitutionSequence: [UInt16]
    let permutationSequence: [UInt16]
    let sequenceLength: Int
    
    /// Generates a numerical array with no duplicate items, which will be sorted, and the way elements are displaced when they are sorted will serve as the basis of how pixels are reordered.
    ///
    /// The S-Sequence comes directly from the SHA-512 digest, which will be made into S-Boxes.
    ///
    /// The P-Sequence is generated by first tagging each byte in the digest with its index in the digest, then sorting the zipped array by the digest bytes, and then keeping the shuffled indices. This produces two arrays in which elements have different positions between arrays but are 1-to-1 mapped (a bijection?). Thus this program uses the relation information contained in a hash digest to shuffle bitmaps.
    ///
    /// - Parameters:
    ///   - data: data from which to produce the SHA digest
    ///   - length: tells the function to generate a *length*-byte long array. Currently will not go above 256 due to restrictions in `LookupTableTile`.
    init(from data: Data, _ length: Int) {
        var digestArray8bit = [UInt8]()
        sequenceLength = Int(ceil((Float(length) * Float(length) / 64)) * 64)
        let step = sequenceLength / 64 - 1
        digestArray8bit.append(contentsOf: Array(data.sha512Digest()))
        if step <= 1023 {
            for _ in 1...step {
                digestArray8bit.append(contentsOf: Array(Data(digestArray8bit).sha512Digest()))
            }
        } else {
            for _ in 1...1023 {
                digestArray8bit.append(contentsOf: Array(Data(digestArray8bit).sha512Digest()))
            }
            for _ in 1024...step {
                digestArray8bit.append(contentsOf: digestArray8bit[0...255])
            }
        }
        let digestArray = digestArray8bit.map() { b in UInt16(b) }
        self.substitutionSequence = digestArray
        self.permutationSequence = Array(zip([UInt16](0...65535), digestArray)).sorted() { e1, e2 in
            return pseudoStableSort2DAscending(e1.1, e1.0, e2.1, e2.0)
            }.map() { b in b.0 }
    }
}

extension CipherSecret {
    init(fromString: String, length: Int) {
        let data = fromString.data(using: String.Encoding.utf8)!
        self.init(from: data, length)
    }
    init?(fromFilePath: String, length: Int) {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: fromFilePath), options: Data.ReadingOptions.uncached)
            self.init(from: data, length)
        } catch {
            return nil
        }
    }
}

