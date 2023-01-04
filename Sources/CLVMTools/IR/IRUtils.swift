import Foundation
import BigInt
import CLVM

func ir_new(type: IRType, val: CastableType, offset: Int? = nil) throws -> SExp {
    let sexpType: SExp
    if offset != nil {
        sexpType = try SExp.to(v: .tuple((.int(BigInt(type.rawValue)), .int(BigInt(offset!)))))
    } else {
        sexpType = SExp(obj: CLVMObject(v: .int(BigInt(type.rawValue))))
    }
    return try SExp.to(v: .tuple((.sexp(sexpType), val)))
}

func ir_new(type: CastableType, val: CastableType) throws -> SExp {
    return try SExp.to(v: .tuple((type, val)))
}

func ir_cons(first: SExp, rest: SExp, offset: Int? = nil) throws -> SExp {
    return try ir_new(
        type: .CONS,
        val: .sexp(
            ir_new(
                type: .sexp(first),
                val: .sexp(rest)
            )
        ),
        offset: offset
    )
}

func ir_null() throws -> SExp {
    return try ir_new(type: .int(BigInt(IRType.NULL.rawValue)), val: .int(0))
}

func ir_type(ir_sexp: SExp) throws -> IRType {
    var the_type = try ir_sexp.first()
    if the_type.listp() {
        the_type = try the_type.first()
    }
    
    return IRType(rawValue: int_from_bytes(blob: the_type.atom!))!
}

func ir_val(ir_sexp: SExp) throws -> SExp {
    try ir_sexp.rest()
}

func ir_nullp(ir_sexp: SExp) throws -> Bool {
    try ir_type(ir_sexp: ir_sexp) == .NULL
}

func ir_listp(ir_sexp: SExp) throws -> Bool {
    try CONS_TYPES.contains(ir_type(ir_sexp: ir_sexp))
}

func ir_as_sexp(ir_sexp: SExp) throws -> SExp {
    if try ir_nullp(ir_sexp: ir_sexp) {
        return SExp(obj: CLVMObject(v: .list([])))
    }
    if try ir_type(ir_sexp: ir_sexp) == .CONS {
        return try ir_as_sexp(ir_sexp: ir_first(ir_sexp: ir_sexp))
            .cons(right: .sexp(ir_as_sexp(ir_sexp: ir_rest(ir_sexp: ir_sexp))))
    }
    return try ir_sexp.rest()
}

func ir_as_atom(ir_sexp: SExp) throws -> Data {
    return try ir_sexp.rest().atom!
}

func ir_first(ir_sexp: SExp) throws -> SExp {
    try ir_sexp.rest().first()
}

func ir_rest(ir_sexp: SExp) throws -> SExp {
    try ir_sexp.rest().rest()
}

func ir_symbol(symbol: String) -> (IRType, Data) {
    return (.SYMBOL, symbol.data(using: .utf8)!)
}

func ir_as_symbol(ir_sexp: SExp) throws -> String? {
    if try ir_sexp.listp() && ir_type(ir_sexp: ir_sexp) == .SYMBOL {
        return String(data: try ir_as_sexp(ir_sexp: ir_sexp).atom!, encoding: .utf8)
    }
    return nil
}

func is_ir(sexp: SExp) -> Bool {
    if sexp.atom != nil {
        return false
    }
    
    let (type_sexp, val_sexp) = sexp.pair!
    let f = type_sexp?.atom
    if f == nil || f!.count > 1 {
        return false
    }
    
    let the_type: Int = int_from_bytes(blob: f!)
    guard let t = IRType(rawValue: the_type) else {
        return false
    }
    
    if t == .CONS {
        if val_sexp!.atom == Data() {
            return true
        }
        if val_sexp!.pair != nil {
            return is_ir(sexp: SExp(obj: val_sexp?.pair?.0)) && is_ir(sexp: SExp(obj: val_sexp?.pair?.1))
        }
        return false
    }
    
    return val_sexp!.atom != nil
}
