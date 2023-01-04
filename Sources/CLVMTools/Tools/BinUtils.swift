import Foundation
import BigInt
import CLVM

public func type_for_atom(atom: Data) -> IRType {
    if atom.count > 2 {
        let v = String(data: atom, encoding: .utf8)
        if v != nil && v!.allSatisfy({ c in
            // hack to match python string.printable
            c.isPunctuation || c.isNumber || c.isASCII || c.isWhitespace
        }) {
            return .QUOTES
        }
        return .HEX
    }
    if int_to_bytes(v: int_from_bytes(blob: atom) as BigInt) == atom {
        return .INT
    }
    return .HEX
}

func assemble_from_ir(ir_sexp: SExp) throws -> SExp {
    if var keyword = try ir_as_symbol(ir_sexp: ir_sexp) {
        if keyword.first == "#" {
            keyword = String(keyword[keyword.index(keyword.startIndex, offsetBy: 1)...])
        }
        if let atom = KEYWORD_TO_ATOM[keyword] {
            return try SExp.to(v: .bytes(atom))
        }
        return try ir_val(ir_sexp: ir_sexp)
    }
    
    if try !ir_listp(ir_sexp: ir_sexp) {
        return try ir_val(ir_sexp: ir_sexp)
    }
    
    if try ir_nullp(ir_sexp: ir_sexp) {
        return try SExp.to(v: .list([]))
    }
    
    // handle "q"
    let first = try ir_first(ir_sexp: ir_sexp)
    let keyword = try ir_as_symbol(ir_sexp: first)
    if keyword == "q" {
        // pass
        // TODO: note that any symbol is legal after this point
    }

    let sexp_1 = try assemble_from_ir(ir_sexp: first)
    let sexp_2 = try assemble_from_ir(ir_sexp: try ir_rest(ir_sexp: ir_sexp))
    return try sexp_1.cons(right: .sexp(sexp_2))
}

func disassemble_to_ir(sexp: SExp, keyword_from_atom: [Data: String], allow_keyword: Bool = false) throws -> SExp {
    if is_ir(sexp: sexp) && allow_keyword != false {
        let symbol = ir_symbol(symbol: "ir")
        let symbol_sexp = try SExp.to(v: .tuple((.int(BigInt(symbol.0.rawValue)), .bytes(symbol.1))))
        return try ir_cons(first: symbol_sexp, rest: sexp)
    }
    
    if sexp.listp() {
        var allow_keyword = allow_keyword
        if try sexp.first().listp() || allow_keyword == false {
            allow_keyword = true
        }
        let v0 = try disassemble_to_ir(sexp: try sexp.first(), keyword_from_atom: keyword_from_atom, allow_keyword: allow_keyword)
        let v1 = try disassemble_to_ir(sexp: sexp.rest(), keyword_from_atom: keyword_from_atom, allow_keyword: false)
        return try ir_cons(first: v0, rest: v1)
    }
    
    let as_atom = sexp.atom!
    if allow_keyword {
        let v = keyword_from_atom[as_atom]
        if v != nil && v != "." {
            let symbol = ir_symbol(symbol: v!)
            return try SExp.to(v: .tuple((.int(BigInt(symbol.0.rawValue)), .bytes(symbol.1))))
        }
    }
    
    if sexp.nullp() {
        return try ir_null()
    }
    
    return try SExp.to(v: .tuple((.int(BigInt(type_for_atom(atom: as_atom).rawValue)), .bytes(as_atom))))
}

public func disassemble(sexp: SExp, keyword_from_atom: [Data: String] = KEYWORD_FROM_ATOM) throws -> String {
    let symbols = try disassemble_to_ir(sexp: sexp, keyword_from_atom: keyword_from_atom)
    return try write_ir(ir_sexp: symbols)
}

public func assemble(s: String) throws -> SExp {
    let symbols = try read_ir(s: s)
    return try assemble_from_ir(ir_sexp: symbols)
}
