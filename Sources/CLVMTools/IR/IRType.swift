import Foundation

/// Associated values are `Int.from_bytes(b, .big)` where b is the utf8 encoding of the type's symbol.
public enum IRType: Int {
    case CONS = 1129270867
    case NULL = 1314212940
    case INT = 4804180
    case HEX = 4736344
    case QUOTES = 20820
    case DOUBLE_QUOTE = 4477268
    case SINGLE_QUOTE = 5460308
    case SYMBOL = 5462349
    case OPERATOR = 20304
    case CODE = 1129268293
    case NODE = 1313817669
}

let CONS_TYPES: Set<IRType> = Set([.CONS])
