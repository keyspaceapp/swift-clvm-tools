import Foundation
import BigInt
import CLVM

typealias Token = (String, Int)
typealias Stream = IndexingIterator<[Token]>

enum SyntaxError: Error {
    case unexpectedEndOfStream
    case missingClosingParenthesis
    case unterminatedString(Int, String)
    case illegalDotExpression(Int)
    case invalidHex(Int, String)
    case badIRFormat(SExp)
}

/// This also deals with comments.
func consume_whitespace(s: String, offset: Int) -> Int {
    var offset = offset
    while true {
        while offset < s.count && s[s.index(s.startIndex, offsetBy: offset)].isWhitespace {
            offset += 1
        }
        if offset >= s.count || s[s.index(s.startIndex, offsetBy: offset)] != ";" {
            break
        }
        while offset < s.count && !Set(["\n", "\r"]).contains(s[s.index(s.startIndex, offsetBy: offset)]) {
            offset += 1
        }
    }
    return offset
}

func consume_until_whitespace(s: String, offset: Int) -> Token {
    let start = offset
    var offset = offset
    while offset < s.count && !s[s.index(s.startIndex, offsetBy: offset)].isWhitespace && s[s.index(s.startIndex, offsetBy: offset)] != ")" {
        offset += 1
    }
    return (String(s[s.index(s.startIndex, offsetBy: start)..<s.index(s.startIndex, offsetBy: offset)]), offset)
}

func next_cons_token(stream: inout Stream) throws -> Token {
    if let token = stream.next() {
        return token
    }
    throw SyntaxError.missingClosingParenthesis
}

func tokenize_cons(token: String, offset: Int, stream: inout Stream) throws -> CLVMObject {
    if token == ")" {
        return CLVMObject(v: .sexp(try ir_new(type: .NULL, val: .int(0), offset: offset)))
    }
    
    let initial_offset = offset
    
    let first_sexp = try tokenize_sexp(token: token, offset: offset, stream: &stream)
    
    var (token, offset) = try next_cons_token(stream: &stream)
    let rest_sexp: CLVMObject
    if token == "." {
        let dot_offset = offset
        // grab the last item
        (token, offset) = try next_cons_token(stream: &stream)
        rest_sexp = try tokenize_sexp(token: token, offset: offset, stream: &stream)
        (token, offset) = try next_cons_token(stream: &stream)
        if token != ")" {
            throw SyntaxError.illegalDotExpression(dot_offset)
        }
    }
    else {
        rest_sexp = try tokenize_cons(token: token, offset: offset, stream: &stream)
    }
    return CLVMObject(v: .sexp(
        try ir_cons(
            first: SExp(obj: first_sexp),
            rest: SExp(obj: rest_sexp),
            offset: initial_offset
        )
    ))
}

func tokenize_int(token: String, offset: Int) throws -> CLVMObject? {
    do {
        // hack to avoid assert in bigint
        if token == "-" {
            return nil
        }
        guard let int = BigInt(token) else {
            throw ValueError("Invalid Int")
        }
        return CLVMObject(v: .sexp(try ir_new(type: .INT, val: .int(int), offset: offset)))
    }
    catch is ValueError {
        //pass
    }
    return nil
}

func tokenize_hex(token: String, offset: Int) throws -> CLVMObject? {
    if token.prefix(2).uppercased() == "0X" {
        do {
            var token = String(token.suffix(token.count - 2))
            if token.count % 2 == 1 {
                token = "0" + token
            }
            return CLVMObject(v: .sexp(try ir_new(type: .HEX, val: .bytes(Data(hex: token)), offset: offset)))
        }
        catch {
            throw SyntaxError.invalidHex(offset, token)
        }
    }
    return nil
}

func tokenize_quotes(token: String, offset: Int) throws -> CLVMObject? {
    if token.count < 2 {
        return nil
    }
    let c = token.first
    if !Set(["\'", "\\", "\""]).contains(c) {
        return nil
    }
    
    if token.last != c {
        throw SyntaxError.unterminatedString(offset, token)
    }
    
    let q_type: IRType =  c == "'" ? .SINGLE_QUOTE : .DOUBLE_QUOTE
    
    return CLVMObject(v: .tuple((.tuple((.int(BigInt(q_type.rawValue)), .int(BigInt(offset)))), .bytes(token.suffix(token.count-1).data(using: .utf8)!))))
}

func tokenize_symbol(token: String, offset: Int) -> CLVMObject? {
    return CLVMObject(v: .tuple((
        .tuple((
            .int(BigInt(IRType.SYMBOL.rawValue)),
            .int(BigInt(offset))
        )),
        .bytes(token.data(using: .utf8)!)
    )))
}

func tokenize_sexp(token: String, offset: Int, stream: inout Stream) throws -> CLVMObject {
    if token == "(" {
        let (token, offset) = try next_cons_token(stream: &stream)
        return try tokenize_cons(token: token, offset: offset, stream: &stream)
    }

    for f in [
        tokenize_int,
        tokenize_hex,
        tokenize_quotes,
        tokenize_symbol,
    ] {
        if let r = try f(token, offset) {
            return r
        }
    }
    
    throw ValueError("Invalid sexp")
}

func token_stream(s: String) throws -> Stream {
    // Python implements this with yield.. we can do something similar with AsyncThrowingStream
    // but then everything becomes async.
    var tokens: [Token] = []
    var offset = 0
    while offset < s.count {
        offset = consume_whitespace(s: s, offset: offset)
        if offset >= s.count {
            break
        }
        let c = s[s.index(s.startIndex, offsetBy: offset)]
        if ["(", ".", ")"].contains(c) {
            tokens.append((String(c), offset))
            offset += 1
            continue
        }
        if ["\\", "\"", "'"].contains(c) {
            let start = offset
            let initial_c = s[s.index(s.startIndex, offsetBy: start)]
            offset += 1
            while offset < s.count && s[s.index(s.startIndex, offsetBy: offset)] != initial_c {
                offset += 1
            }
            if offset < s.count {
                tokens.append((String(s[s.index(s.startIndex, offsetBy: start)..<s.index(s.startIndex, offsetBy: offset + 1)]), start))
                offset += 1
                continue
            }
            else {
                throw SyntaxError.unterminatedString(start, String(s.suffix(s.count - start)))
            }
        }
        let (token, end_offset) = consume_until_whitespace(s: s, offset: offset)
        tokens.append((token, offset))
        offset = end_offset
    }
    return tokens.makeIterator()
}

func read_ir(
    s: String,
    to_sexp: @escaping (CastableType) throws -> SExp = SExp.to
) throws -> SExp {
    var stream = try token_stream(s: s)
    guard let (token, offset) = stream.next() else {
        throw SyntaxError.unexpectedEndOfStream
    }
    return try to_sexp(.object(try tokenize_sexp(
        token: token,
        offset: offset,
        stream: &stream
    )))
}


#warning("hack")

extension Data {
    public init(hex: String) {
        self.init(Array<UInt8>(hex: hex))
    }
}

// Data(hex:)
// From https://github.com/krzyzanowskim/CryptoSwift/ (MIT)
extension Array where Element == UInt8 {
    public init(hex: String) {
        self.init()
        reserveCapacity(hex.unicodeScalars.lazy.underestimatedCount)
        var buffer: UInt8?
        var skip = hex.hasPrefix("0x") ? 2 : 0
        for char in hex.unicodeScalars.lazy {
            guard skip == 0 else {
                skip -= 1
                continue
            }
            guard char.value >= 48 && char.value <= 102 else {
                removeAll()
                return
            }
            let v: UInt8
            let c: UInt8 = UInt8(char.value)
            switch c {
            case let c where c <= 57:
                v = c - 48
            case let c where c >= 65 && c <= 70:
                v = c - 55
            case let c where c >= 97:
                v = c - 87
            default:
                removeAll()
                return
            }
            if let b = buffer {
                append(b << 4 | v)
                buffer = nil
            } else {
                buffer = v
            }
        }
        if let b = buffer {
            append(b)
        }
    }
}
