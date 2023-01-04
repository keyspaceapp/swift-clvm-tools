import Foundation
import BigInt
import CLVM

func iter_sexp_format(ir_sexp: SExp) throws -> IndexingIterator<[String]> {
    // Python implements this with yield.. we can do something similar with AsyncThrowingStream
    // but then everything becomes async. So doing this hack for now
    var chars: [String] = []
    
    chars.append("(")
    var is_first = true
    var ir_sexp = ir_sexp
    while !(try ir_nullp(ir_sexp: ir_sexp)) {
        if try !ir_listp(ir_sexp: ir_sexp) {
            chars.append(" . ")
            chars.append(contentsOf: try iter_ir_format(ir_sexp: ir_sexp))
            break
        }
        if !is_first {
            chars.append(" ")
        }
        for char in try iter_ir_format(ir_sexp: ir_first(ir_sexp: ir_sexp)) {
            chars.append(char)
        }
        ir_sexp = try ir_rest(ir_sexp: ir_sexp)
        is_first = false
    }
    chars.append(")")
    
    return chars.makeIterator() // hack
}

func iter_ir_format(ir_sexp: SExp) throws -> IndexingIterator<[String]> {
    // Python implements this with yield.. we can do something similar with AsyncThrowingStream
    // but then everything becomes async. So doing this hack for now
    var tokens: [String] = []
    
    if try ir_listp(ir_sexp: ir_sexp) {
        tokens.append(contentsOf: try iter_sexp_format(ir_sexp: ir_sexp))
        return tokens.makeIterator()
    }

    let type = try ir_type(ir_sexp: ir_sexp)

    if type == .CODE {
        let sexp_stream = try sexp_to_stream(sexp: ir_val(ir_sexp: ir_sexp)) // hack, python uses bytesio
        let code = sexp_stream.map { String(format: "%02hhx", $0) }.joined() // .hex()
        tokens.append("CODE[\(code)]")
        return tokens.makeIterator()
    }
    
    if type == .NULL {
        tokens.append("()")
        return tokens.makeIterator()
    }

    let atom = try ir_as_atom(ir_sexp: ir_sexp)

    if type == .INT {
        let int: BigInt = int_from_bytes(blob: atom)
        tokens.append("\(int)")
    } else if type == .NODE {
        let int: BigInt = int_from_bytes(blob: atom)
        tokens.append("NODE[\(int)]")
    } else if type == .HEX {
        tokens.append("0x\(atom.map { String(format: "%02hhx", $0) }.joined())") // hex()
    } else if type == .QUOTES {
        tokens.append("\"\(String(data: atom, encoding: .utf8)!)\"")
    } else if type == .DOUBLE_QUOTE {
        tokens.append("\"\(String(data: atom, encoding: .utf8)!)\"")
    } else if type == .SINGLE_QUOTE {
        tokens.append("'\(String(data: atom, encoding: .utf8)!)'")
    } else if [.SYMBOL, .OPERATOR].contains(type) {
        do {
            guard let string = String(data: atom, encoding: .utf8) else {
                throw UnicodeDecodeError()
            }
            tokens.append(string)
        }
        catch is UnicodeDecodeError {
            tokens.append("(indecipherable symbol: \(atom.map { String(format: "%02hhx", $0) }.joined())") // hex()
        }
    }
    else {
        throw SyntaxError.badIRFormat(ir_sexp)
    }
    
    return tokens.makeIterator()
}

private struct UnicodeDecodeError: Error { }

func write_ir_to_stream(ir_sexp: SExp, s: inout String) throws {
    for symbol in try iter_ir_format(ir_sexp: ir_sexp) {
        s += symbol
    }
}

func write_ir(ir_sexp: SExp) throws -> String {
    var s = ""
    try write_ir_to_stream(ir_sexp: ir_sexp, s: &s)
    return s
}
