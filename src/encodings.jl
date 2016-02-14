# This file is a part of StringEncodings.jl. License is MIT: http://julialang.org/license

# Parametric singleton type representing a given string encoding via its symbol parameter

import Base: show, print, convert
export Encoding, @enc_str, codeunit, native_endian

immutable Encoding{enc} end

Encoding(s) = Encoding{symbol(s)}()
macro enc_str(s)
    :(Encoding{$(Expr(:quote, symbol(s)))}())
end

convert{T<:AbstractString, enc}(::Type{T}, ::Encoding{enc}) = string(enc)

show{enc}(io::IO, ::Encoding{enc}) = print(io, string(enc), " string encoding type")
print{enc}(io::IO, ::Encoding{enc}) = print(io, enc)


## Get the encoding used by a string type
encoding(::Type{ASCIIString}) = enc"ASCII"
encoding(::Type{UTF8String})  = enc"UTF-8"

if ENDIAN_BOM == 0x04030201
    encoding(::Type{UTF16String}) = enc"UTF-16LE"
    encoding(::Type{UTF32String}) = enc"UTF-32LE"
else
    encoding(::Type{UTF16String}) = enc"UTF-16BE"
    encoding(::Type{UTF32String}) = enc"UTF-32BE"
end


## Functions giving information about a particular encoding

# NO_ENDIAN: insensitive to endianness
# BIG_ENDIAN: default to big-endian
# LOW_ENDIAN: default to big-endian
# BIG_ENDIAN_AUTO: endianness detection using BOM on input, defaults to big-endian on output
# LOW_ENDIAN_AUTO: endianness detection using BOM on input, defaults to low-endian on output
# NATIVE_ENDIAN_AUTO: endianness detection using BOM on input, defaults to native-endian on output
@enum Endianness NO_ENDIAN BIG_ENDIAN LOW_ENDIAN BIG_ENDIAN_AUTO LOW_ENDIAN_AUTO NATIVE_ENDIAN_AUTO

immutable EncodingInfo
    name::ASCIIString
    codeunit::Int8 # Number of bytes per codeunit
    codepoint::Int8 # Number of bytes per codepoint; for MBCS, negative values give the maximum number of bytes
    lowendian::Endianness # Endianness, if applicable
    ascii::Bool # Is the encoding a superset of ASCII?
    unicode::Bool # Is the encoding Unicode-compatible?
end

"""
    native_endian(enc)

    Check whether string encoding `enc` follows the current machine endianness.
    `enc` can be specified either as a string or as an `Encoding` object.
"""
native_endian(::Encoding) = true

if ENDIAN_BOM == 0x04030201
    native_endian(::Encoding{symbol("UTF-16LE")}) = true
    native_endian(::Encoding{symbol("UTF-32LE")}) = true
    native_endian(::Encoding{symbol("UTF-16BE")}) = false
    native_endian(::Encoding{symbol("UTF-32BE")}) = false

    native_endian(::Encoding{symbol("UTF16LE")}) = true
    native_endian(::Encoding{symbol("UTF32LE")}) = true
    native_endian(::Encoding{symbol("UTF16BE")}) = false
    native_endian(::Encoding{symbol("UTF32BE")}) = false
else
    native_endian(::Encoding{symbol("UTF-16LE")}) = false
    native_endian(::Encoding{symbol("UTF-32LE")}) = false
    native_endian(::Encoding{symbol("UTF-16BE")}) = true
    native_endian(::Encoding{symbol("UTF-32BE")}) = true

    native_endian(::Encoding{symbol("UTF16LE")}) = false
    native_endian(::Encoding{symbol("UTF32LE")}) = false
    native_endian(::Encoding{symbol("UTF16BE")}) = true
    native_endian(::Encoding{symbol("UTF32BE")}) = true
end

native_endian(enc::AbstractString) = native_endian(Encoding(enc))


"""
    codeunit(enc)

    Get the type corresponding to a code unit in the encoding `enc`.
    `enc` can be specified either as a string or as an `Encoding` object.
"""
@generated function codeunit{enc_s}(enc::Encoding{enc_s})
    s = string(enc_s)
    if s in encodings32
       :UInt32
    elseif s in encodings16
       :UInt16
    elseif s in encodings8
       :UInt8
    else
       error("encoding with unknown codeunit size, define a codeunit method for it")
    end
end

codeunit(enc::AbstractString) = codeunit(Encoding(enc))

const encodings_list2 = EncodingInfo[
    EncodingInfo("ASCII", 1, 1, NO_ENDIAN, true, true),

    # Unicode encodings
    EncodingInfo("UTF-8", 1, -4, NO_ENDIAN, true, true),
    EncodingInfo("UTF-16", 2, -2, BIG_ENDIAN_AUTO, false, true), # FIXME: iconv implementations vary regarding endianness
    EncodingInfo("UTF-16LE", 2, -2, LOW_ENDIAN, false, true),
    EncodingInfo("UTF-16BE", 2, -2, BIG_ENDIAN, false, true),
    EncodingInfo("UTF-32",  4, 1, BIG_ENDIAN_AUTO, false, true), # FIXME: iconv implementations vary regarding endianness
    EncodingInfo("UTF-32LE", 4, 1, LOW_ENDIAN, false, true),
    EncodingInfo("UTF-32BE", 4, 1, BIG_ENDIAN, false, true),

    EncodingInfo("UCS-2", 2, 1, BIG_ENDIAN_AUTO, false, true), # FIXME: iconv implementations vary regarding endianness
    EncodingInfo("UCS-2LE", 2, 1, LOW_ENDIAN, false, true),
    EncodingInfo("UCS-2BE", 2, 1, BIG_ENDIAN, false, true),

    # ISO-8859
    EncodingInfo("ISO-8869-1",  1, 1, NO_ENDIAN, true, true),
    EncodingInfo("ISO-8869-2",  1, 1, NO_ENDIAN, true, true),
    EncodingInfo("ISO-8869-3",  1, 1, NO_ENDIAN, true, true),
    EncodingInfo("ISO-8869-4",  1, 1, NO_ENDIAN, true, true),
    EncodingInfo("ISO-8869-5",  1, 1, NO_ENDIAN, true, true),
    EncodingInfo("ISO-8869-6",  1, 1, NO_ENDIAN, true, true),
    EncodingInfo("ISO-8869-7",  1, 1, NO_ENDIAN, true, true),
    EncodingInfo("ISO-8869-8",  1, 1, NO_ENDIAN, true, true),
    EncodingInfo("ISO-8869-9",  1, 1, NO_ENDIAN, true, true),
    EncodingInfo("ISO-8869-10", 1, 1, NO_ENDIAN, true, true),
    EncodingInfo("ISO-8869-11", 1, 1, NO_ENDIAN, true, true),
    EncodingInfo("ISO-8869-12", 1, 1, NO_ENDIAN, true, true),
    EncodingInfo("ISO-8869-13", 1, 1, NO_ENDIAN, true, true),
    EncodingInfo("ISO-8869-14", 1, 1, NO_ENDIAN, true, true),
    EncodingInfo("ISO-8869-15", 1, 1, NO_ENDIAN, true, true),
    EncodingInfo("ISO-8869-16", 1, 1, NO_ENDIAN, true, true),

    # KOI8 codepages
    EncodingInfo("KOI8-R", 1, 1, NO_ENDIAN, true, true),
    EncodingInfo("KOI8-U", 1, 1, NO_ENDIAN, true, true),
    EncodingInfo("KOI8-RU", 1, 1, NO_ENDIAN, true, true),

    # 8-bit Windows codepages
    EncodingInfo("CP1250",  1, 1, NO_ENDIAN, true, true),
    EncodingInfo("CP1251",  1, 1, NO_ENDIAN, true, true),
    EncodingInfo("CP1252",  1, 1, NO_ENDIAN, true, true),
    EncodingInfo("CP1253",  1, 1, NO_ENDIAN, true, true),
    EncodingInfo("CP1254",  1, 1, NO_ENDIAN, true, true),
    EncodingInfo("CP1255",  1, 1, NO_ENDIAN, true, true),
    EncodingInfo("CP1256",  1, 1, NO_ENDIAN, true, true),
    EncodingInfo("CP1257",  1, 1, NO_ENDIAN, true, true),
    EncodingInfo("CP1258",  1, 1, NO_ENDIAN, true, true),

    # DOS 8-bit codepages
    EncodingInfo("CP850",  1, 1, NO_ENDIAN, true, true),
    EncodingInfo("CP866",  1, 1, NO_ENDIAN, true, true),

    # Mac 8-bit codepages
    EncodingInfo("MacRoman",  1, 1, NO_ENDIAN, true, true),
    EncodingInfo("MacCentralEurope",  1, 1, NO_ENDIAN, true, true),
    EncodingInfo("MacIceland",  1, 1, NO_ENDIAN, true, true),
    EncodingInfo("MacCroatian",  1, 1, NO_ENDIAN, true, true),
    EncodingInfo("MacRomania",  1, 1, NO_ENDIAN, true, true),
    EncodingInfo("MacCyrillic",  1, 1, NO_ENDIAN, true, true),
    EncodingInfo("MacUkraine",  1, 1, NO_ENDIAN, true, true),
    EncodingInfo("MacGreek",  1, 1, NO_ENDIAN, true, true),
    EncodingInfo("MacTurkish",  1, 1, NO_ENDIAN, true, true),
    EncodingInfo("MacHebrew",  1, 1, NO_ENDIAN, true, true),
    EncodingInfo("MacArabic",  1, 1, NO_ENDIAN, true, true),
    EncodingInfo("MacThai",  1, 1, NO_ENDIAN, true, true),

    # Other 8-bit codepages
    EncodingInfo("HP-ROMAN8",  1, 1, NO_ENDIAN, true, true),
    EncodingInfo("NEXTSTEP",  1, 1, NO_ENDIAN, true, true)

    # TODO: other encodings (8-bit and others)
    ]


## Lists of all known encodings taken from various iconv implementations,
## including different aliases for the same encoding


# 8-bit codeunit encodings
const encodings8 = [
    "ASCII", "US-ASCII", "us-ascii", "CSASCII",
     "UTF7", "UTF8", "UTF-7", "UTF-8",
    "CP037", "CP038", "CP10007", "CP1004", "CP1008",
    "cp1025", "CP1025", "CP1026", "CP1046", "CP1047", "CP1070", "CP1079",
    "CP1081", "CP1084", "CP1089", "CP1097", "CP1112", "CP1122", "CP1123",
    "CP1124", "CP1125", "CP1129", "CP1130", "CP1131", "CP1132", "CP1133",
    "CP1137", "CP1140", "CP1141", "CP1142", "CP1143", "CP1144", "CP1145",
    "CP1146", "CP1147", "CP1148", "CP1149", "CP1153", "CP1154", "CP1155",
    "CP1156", "CP1157", "CP1158", "CP1160", "CP1161", "CP1162", "CP1163",
    "CP1164", "CP1166", "CP1167", "CP1200", "CP12000", "CP12001",
    "CP1201", "CP1250", "CP1251", "CP1252", "CP1253", "CP1254", "CP1255",
    "CP1256", "CP1257", "CP1258", "CP12712", "CP1282", "CP1361",
    "CP1364", "CP1371", "CP1388", "CP1390", "CP1399", "CP154", "CP16804",
    "CP273", "CP274", "CP275", "CP278", "CP280", "CP281", "CP282",
    "CP284", "CP285", "CP290", "CP297", "CP367", "CP420", "CP423",
    "CP424", "CP437", "CP4517", "CP4899", "CP4909", "CP4971", "CP500",
    "CP50221", "CP51932", "CP5347", "CP65001", "CP737", "CP770",
    "CP771", "CP772", "CP773", "CP774", "CP775", "CP803", "CP813",
    "CP819", "CP850", "CP851", "CP852", "CP853", "CP855", "CP856",
    "CP857", "CP858", "CP860", "CP861", "CP862", "CP863", "CP864",
    "CP865", "cp866", "CP866", "CP866NAV", "CP868", "CP869", "CP870",
    "CP871", "CP874", "cp875", "CP875", "CP880", "CP891", "CP901",
    "CP902", "CP903", "CP9030", "CP904", "CP905", "CP9066", "CP912",
    "CP915", "CP916", "CP918", "CP920", "CP921", "CP922", "CP930",
    "CP932", "CP933", "CP935", "CP936", "CP937", "CP939", "CP9448",
    "CP949", "CP950",
    "CSEBCDICATDE", "CSEBCDICATDEA", "CSEBCDICCAFR", "CSEBCDICDKNO",
    "CSEBCDICDKNOA", "CSEBCDICES", "CSEBCDICESA", "CSEBCDICESS",
    "CSEBCDICFISE", "CSEBCDICFISEA", "CSEBCDICFR", "CSEBCDICIT",
    "CSEBCDICPT", "CSEBCDICUK", "CSEBCDICUS",
    "CSIBM037", "CSIBM038", "CSIBM1008", "CSIBM1025",
    "CSIBM1026", "CSIBM1097", "CSIBM1112", "CSIBM1122", "CSIBM1123",
    "CSIBM1124", "CSIBM1129", "CSIBM1130", "CSIBM1132", "CSIBM1133",
    "CSIBM1137", "CSIBM1140", "CSIBM1141", "CSIBM1142", "CSIBM1143",
    "CSIBM1144", "CSIBM1145", "CSIBM1146", "CSIBM1147", "CSIBM1148",
    "CSIBM1149", "CSIBM1153", "CSIBM1154", "CSIBM1155", "CSIBM1156",
    "CSIBM1157", "CSIBM1158", "CSIBM1160", "CSIBM1161", "CSIBM11621162",
    "CSIBM1163", "CSIBM1164", "CSIBM1166", "CSIBM1167", "CSIBM12712",
    "CSIBM1364", "CSIBM1371", "CSIBM1388", "CSIBM1390", "CSIBM1399",
    "CSIBM16804", "CSIBM273", "CSIBM274", "CSIBM275", "CSIBM277",
    "CSIBM278", "CSIBM280", "CSIBM281", "CSIBM284", "CSIBM285", "CSIBM290",
    "CSIBM297", "CSIBM420", "CSIBM423", "CSIBM424", "CSIBM4517",
    "CSIBM4899", "CSIBM4909", "CSIBM4971", "CSIBM500", "CSIBM5347",
    "CSIBM803", "CSIBM851", "CSIBM855", "CSIBM856", "CSIBM857", "CSIBM860",
    "CSIBM861", "CSIBM863", "CSIBM864", "CSIBM865", "CSIBM866", "CSIBM868",
    "CSIBM869", "CSIBM870", "CSIBM871", "CSIBM880", "CSIBM891", "CSIBM901",
    "CSIBM902", "CSIBM903", "CSIBM9030", "CSIBM904", "CSIBM905",
    "CSIBM9066", "CSIBM918", "CSIBM921", "CSIBM922", "CSIBM930",
    "CSIBM932", "CSIBM933", "CSIBM935", "CSIBM937", "CSIBM939", "CSIBM943", "CSIBM9448",
    "EBCDIC-AT-DE", "EBCDIC-AT-DE-A",
    "EBCDIC-BE", "EBCDIC-BR", "EBCDIC-CA-FR", "EBCDIC-CP-AR1", "EBCDIC-CP-AR2",
    "EBCDIC-CP-BE", "EBCDIC-CP-CA", "EBCDIC-CP-CH", "EBCDIC-CP-DK",
    "EBCDIC-CP-ES", "EBCDIC-CP-FI", "EBCDIC-CP-FR", "EBCDIC-CP-GB",
    "EBCDIC-CP-GR", "EBCDIC-CP-HE", "EBCDIC-CP-IS", "EBCDIC-CP-IT",
    "EBCDIC-CP-NL", "EBCDIC-CP-NO", "EBCDIC-CP-ROECE", "EBCDIC-CP-SE",
    "EBCDIC-CP-TR", "EBCDIC-CP-US", "EBCDIC-CP-WT", "EBCDIC-CP-YU",
    "EBCDIC-CYRILLIC", "EBCDIC-DK-NO", "EBCDIC-DK-NO-A", "EBCDIC-ES",
    "EBCDIC-ES-A", "EBCDIC-ES-S", "EBCDIC-FI-SE", "EBCDIC-FI-SE-A",
    "EBCDIC-FR", "EBCDIC-GREEK", "EBCDIC-INT", "EBCDIC-INT1", "EBCDIC-IS-FRISS",
    "EBCDIC-IT", "EBCDIC-JP-E", "EBCDIC-JP-KANA", "EBCDIC-PT", "EBCDIC-UK",
    "EBCDIC-US", "EBCDICATDE", "EBCDICATDEA", "EBCDICCAFR", "EBCDICDKNO",
    "EBCDICDKNOA", "EBCDICES", "EBCDICESA", "EBCDICESS", "EBCDICFISE",
    "EBCDICFISEA", "EBCDICFR", "EBCDICISFRISS", "EBCDICIT", "EBCDICPT",
    "EBCDICUK", "EBCDICUS",
    "IBM-1008", "IBM-1025", "IBM-1046", "IBM-1047", "IBM-1097", "IBM-1112", "IBM-1122",
    "IBM-1123", "IBM-1124", "IBM-1129", "IBM-1130", "IBM-1132", "IBM-1133",
    "IBM-1137", "IBM-1140", "IBM-1141", "IBM-1142", "IBM-1143", "IBM-1144",
    "IBM-1145", "IBM-1146", "IBM-1147", "IBM-1148", "IBM-1149", "IBM-1153",
    "IBM-1154", "IBM-1155", "IBM-1156", "IBM-1157", "IBM-1158", "IBM-1160",
    "IBM-1161", "IBM-1162", "IBM-1163", "IBM-1164", "IBM-1166", "IBM-1167",
    "IBM-12712", "IBM-1364", "IBM-1371", "IBM-1388", "IBM-1390",
    "IBM-1399", "IBM-16804", "IBM-4517", "IBM-4899", "IBM-4909",
    "IBM-4971", "IBM-5347", "IBM-803", "IBM-856", "IBM-901", "IBM-902",
    "IBM-9030", "IBM-9066", "IBM-921", "IBM-922", "IBM-930", "IBM-932",
    "IBM-933", "IBM-935", "IBM-937", "IBM-939", "IBM-943", "IBM-9448",
    "IBM-CP1133", "IBM-Thai", "IBM00858", "IBM00924", "IBM01047",
    "IBM01140", "IBM01141", "IBM01142", "IBM01143", "IBM01144", "IBM01145",
    "IBM01146", "IBM01147", "IBM01148", "IBM01149", "IBM037", "IBM038",
    "IBM1004", "IBM1008", "IBM1025", "IBM1026", "IBM1046", "IBM1047",
    "IBM1089", "IBM1097", "IBM1112", "IBM1122", "IBM1123", "IBM1124",
    "IBM1129", "IBM1130", "IBM1132", "IBM1133", "IBM1137", "IBM1140",
    "IBM1141", "IBM1142", "IBM1143", "IBM1144", "IBM1145", "IBM1146",
    "IBM1147", "IBM1148", "IBM1149", "IBM1153", "IBM1154", "IBM1155",
    "IBM1156", "IBM1157", "IBM1158", "IBM1160", "IBM1161", "IBM1162",
    "IBM1163", "IBM1164", "IBM1166", "IBM1167", "IBM12712", "IBM1364",
    "IBM1371", "IBM1388", "IBM1390", "IBM1399", "IBM16804", "IBM256",
    "IBM273", "IBM274", "IBM275", "IBM277", "IBM278", "IBM280", "IBM281",
    "IBM284", "IBM285", "IBM290", "IBM297", "IBM367", "IBM420", "IBM423",
    "IBM424", "IBM437", "IBM4517", "IBM4899", "IBM4909", "IBM4971",
    "IBM500", "IBM5347", "ibm737", "ibm775", "IBM775", "IBM803",
    "IBM813", "IBM819", "IBM848", "ibm850", "IBM850", "IBM851", "ibm852",
    "IBM852", "IBM855", "IBM856", "ibm857", "IBM857", "IBM860", "ibm861",
    "IBM861", "IBM862", "IBM863", "IBM864", "IBM865", "IBM866", "IBM866NAV",
    "IBM868", "ibm869", "IBM869", "IBM870", "IBM871", "IBM874", "IBM875",
    "IBM880", "IBM891", "IBM901", "IBM902", "IBM903", "IBM9030",
    "IBM904", "IBM905", "IBM9066", "IBM912", "IBM915", "IBM916",
    "IBM918", "IBM920", "IBM921", "IBM922", "IBM930", "IBM932", "IBM933",
    "IBM935", "IBM937", "IBM939", "IBM943", "IBM9448",
    "iso_8859_1", "iso_8859_13", "iso_8859_15", "iso_8859_2",
    "iso_8859_3", "iso_8859_4", "iso_8859_5", "iso_8859_6", "iso_8859_7",
    "iso_8859_8", "iso_8859_8-i", "iso_8859_9", "iso_8859-1", "ISO_8859-1",
    "ISO_8859-1:1987", "ISO_8859-10", "ISO_8859-10:1992", "ISO_8859-11",
    "iso_8859-13", "ISO_8859-13", "ISO_8859-14", "ISO_8859-14:1998",
    "iso_8859-15", "ISO_8859-15", "ISO_8859-15:1998", "ISO_8859-16",
    "ISO_8859-16:2001", "iso_8859-2", "ISO_8859-2", "ISO_8859-2:1987",
    "iso_8859-3", "ISO_8859-3", "ISO_8859-3:1988", "iso_8859-4",
    "ISO_8859-4", "ISO_8859-4:1988", "iso_8859-5", "ISO_8859-5",
    "ISO_8859-5:1988", "iso_8859-6", "ISO_8859-6", "ISO_8859-6:1987",
    "iso_8859-7", "ISO_8859-7", "ISO_8859-7:1987", "ISO_8859-7:2003",
    "iso_8859-8", "ISO_8859-8", "iso_8859-8-i", "ISO_8859-8:1988",
    "iso_8859-9", "ISO_8859-9", "ISO_8859-9:1989", "ISO_8859-9E",
    "iso-8859-1", "ISO-8859-1", "ISO-8859-10",
    "ISO-8859-11", "iso-8859-13", "ISO-8859-13", "ISO-8859-14", "iso-8859-15",
    "ISO-8859-15", "ISO-8859-16", "iso-8859-2", "ISO-8859-2", "iso-8859-3",
    "ISO-8859-3", "iso-8859-4", "ISO-8859-4", "iso-8859-5", "ISO-8859-5",
    "iso-8859-6", "ISO-8859-6", "iso-8859-7", "ISO-8859-7", "iso-8859-8",
    "ISO-8859-8", "iso-8859-8-i", "iso-8859-9", "ISO-8859-9", "ISO-8859-9E",
    "iso8859-1", "ISO8859-1", "ISO8859-10",
    "ISO8859-11", "iso8859-13", "ISO8859-13", "ISO8859-14", "iso8859-15",
    "ISO8859-15", "ISO8859-16", "iso8859-2", "ISO8859-2", "iso8859-3",
    "ISO8859-3", "iso8859-4", "ISO8859-4", "iso8859-5", "ISO8859-5",
    "iso8859-6", "ISO8859-6", "iso8859-7", "ISO8859-7", "iso8859-8",
    "ISO8859-8", "iso8859-8-i", "iso8859-9", "ISO8859-9", "ISO8859-9E",
    "ISO88591", "ISO885910", "ISO885911", "ISO885913", "ISO885914",
    "ISO885915", "ISO885916", "ISO88592", "ISO88593", "ISO88594",
    "ISO88595", "ISO88596", "ISO88597", "ISO88598", "ISO88599", "ISO88599E",
    "windows-1250", "WINDOWS-1250", "windows-1251", "WINDOWS-1251", "windows-1252",
    "WINDOWS-1252", "windows-1253", "WINDOWS-1253", "windows-1254", "WINDOWS-1254",
    "windows-1255", "WINDOWS-1255", "windows-1256", "WINDOWS-1256",
    "windows-1257", "WINDOWS-1257", "windows-1258", "WINDOWS-1258",
    "WINDOWS-31J", "WINDOWS-50221", "WINDOWS-51932", "windows-874",
    "WINDOWS-874", "WINDOWS-932", "WINDOWS-936"]

# 16-bit codeunit encodings
const encodings16 = [
    "UTF-16", "UTF-16BE", "UTF-16LE"
    ]

# 32-bit codeunit encodings
const encodings32 = [
    "UTF-32", "UTF-32BE", "UTF-32LE", "UTF32", "UTF32BE", "UTF32LE"
    ]

const encodings_other = [
    "1026", "1046", "1047", "10646-1:1993", "10646-1:1993/UCS4",
    "437", "500", "500V1", "850", "851", "852", "855", "856", "857",
    "860", "861", "862", "863", "864", "865", "866", "866NAV", "869",
    "874", "8859_1", "8859_2", "8859_3", "8859_4", "8859_5", "8859_6",
    "8859_7", "8859_8", "8859_9", "904", "ANSI_X3.110", "ANSI_X3.110-1983",
    "ANSI_X3.4", "ANSI_X3.4-1968", "ANSI_X3.4-1986", "ARABIC", "ARABIC7",
    "ARMSCII-8", "ASCII", "ASMO_449", "ASMO-708", "BALTIC", "BIG-5",
    "BIG-FIVE", "big5", "BIG5", "big5-hkscs", "BIG5-HKSCS", "BIG5-HKSCS:1999",
    "BIG5-HKSCS:2001", "BIG5-HKSCS:2004", "BIG5-HKSCS:2008", "big5hkscs",
    "BIG5HKSCS", "BIGFIVE", "BRF", "BS_4730", "C99", "CA", "CHINESE",
    "CN", "CN-BIG5", "CN-GB", "CN-GB-ISOIR165", "CP-AR", "CP-GR",
    "CP-HU", "CP-IS", "CPIBM861", "CSA_T500", "CSA_T500-1983", "CSA_Z243.4-1985-1",
    "CSA_Z243.4-1985-2", "CSA_Z243.419851", "CSA_Z243.419852", "CSA7-1",
    "CSA7-2", "CSBIG5", "CSDECMCS",
    "CSEUCKR", "CSEUCPKDFMTJAPANESE", "CSEUCTW", "CSGB2312", "CSHALFWIDTHKATAKANA",
    "CSHPROMAN8", "CSISO10367BOX", "CSISO103T618BIT", "CSISO10SWEDISH",
    "CSISO111ECMACYRILLIC", "CSISO11SWEDISHFORNAMES", "CSISO121CANADIAN1",
    "CSISO122CANADIAN2", "CSISO139CSN369103", "CSISO141JUSIB1002",
    "CSISO143IECP271", "CSISO14JISC6220RO", "CSISO150", "CSISO150GREEKCCITT",
    "CSISO151CUBA", "CSISO153GOST1976874", "CSISO159JISX02121990",
    "CSISO15ITALIAN", "CSISO16PORTUGESE", "CSISO17SPANISH", "CSISO18GREEK7OLD",
    "CSISO19LATINGREEK", "CSISO2022CN", "csISO2022JP", "CSISO2022JP",
    "CSISO2022JP2", "CSISO2022KR", "CSISO2033", "CSISO21GERMAN",
    "CSISO25FRENCH", "CSISO27LATINGREEK1", "CSISO49INIS", "CSISO4UNITEDKINGDOM",
    "CSISO50INIS8", "CSISO51INISCYRILLIC", "CSISO5427CYRILLIC", "CSISO5427CYRILLIC1981",
    "CSISO5428GREEK", "CSISO57GB1988", "CSISO58GB1988", "CSISO58GB231280",
    "CSISO60DANISHNORWEGIAN", "CSISO60NORWEGIAN1", "CSISO61NORWEGIAN2",
    "CSISO646DANISH", "CSISO69FRENCH", "CSISO84PORTUGUESE2", "CSISO85SPANISH2",
    "CSISO86HUNGARIAN", "CSISO87JISX0208", "CSISO88GREEK7", "CSISO89ASMO449",
    "CSISO90", "CSISO92JISC62991984B", "CSISO99NAPLPS", "CSISOLATIN1",
    "CSISOLATIN2", "CSISOLATIN3", "CSISOLATIN4", "CSISOLATIN5", "CSISOLATIN6",
    "CSISOLATINARABIC", "CSISOLATINCYRILLIC", "CSISOLATINGREEK",
    "CSISOLATINHEBREW", "CSKOI8R", "CSKSC56011987", "CSKSC5636",
    "CSKZ1048", "CSMACINTOSH", "CSN_369103", "CSNATSDANO", "CSNATSSEFI",
    "CSPC775BALTIC", "CSPC850MULTILINGUAL", "CSPC862LATINHEBREW",
    "CSPC8CODEPAGE437", "CSPCP852", "CSPTCP154", "CSSHIFTJIS", "CSUCS4",
    "CSUNICODE", "CSUNICODE11", "CSUNICODE11UTF7", "CSVISCII", "CSWINDOWS31J",
    "CUBA", "CWI", "CWI-2", "CYRILLIC", "CYRILLIC-ASIAN", "DE", "DEC",
    "DEC-MCS", "DECMCS", "DIN_66003", "DK", "DOS-720", "DOS-862",
    "DS_2089", "DS2089", "E13B", "ECMA-114", "ECMA-118", "ECMA-128", "ECMA-CYRILLIC",
    "ECMACYRILLIC", "ELOT_928", "ES", "ES2", "EUC-CN", "EUC-JISX0213",
    "euc-jp", "EUC-JP", "EUC-JP-MS", "euc-kr", "EUC-KR", "EUC-TW",
    "EUCCN", "EUCJP", "EUCJP-MS", "EUCJP-OPEN", "EUCJP-WIN", "EUCKR",
    "EUCTW", "EXTENDED_UNIX_CODE_PACKED_FORMAT_FOR_JAPANESE", "FI",
    "FR", "GB", "GB_1988-80", "GB_198880", "GB_2312-80", "GB13000",
    "GB18030", "gb2312", "GB2312", "GBK", "GEORGIAN-ACADEMY", "GEORGIAN-PS",
    "GOST_19768", "GOST_19768-74", "GOST_1976874", "GREEK", "GREEK-CCITT",
    "GREEK7", "GREEK7-OLD", "GREEK7OLD", "GREEK8", "GREEKCCITT",
    "HEBREW", "HP-GREEK8", "HP-ROMAN8", "HP-ROMAN9", "HP-THAI8",
    "HP-TURKISH8", "HPGREEK8", "HPROMAN8", "HPROMAN9", "HPTHAI8",
    "HPTURKISH8", "HU", "HZ", "hz-gb-2312", "HZ-GB-2312", "IEC_P27-1",
    "IEC_P271", "INIS", "INIS-8", "INIS-CYRILLIC", "INIS8", "INISCYRILLIC",
    "ISIRI-3342", "ISIRI3342", "ISO_10367-BOX", "ISO_10367BOX", "ISO_11548-1",
    "ISO_2033", "ISO_2033-1983", "ISO_5427", "ISO_5427-EXT", "ISO_5427:1981",
    "ISO_5427EXT", "ISO_5428", "ISO_5428:1980", "ISO_646.IRV:1991",
    "ISO_6937", "ISO_6937-2", "ISO_6937-2:1983", "ISO_6937:1992",
    "ISO_69372", "ISO_9036", "ISO-10646", "ISO-10646-UCS-2", "ISO-10646-UCS-4",
    "ISO-10646/UCS2", "ISO-10646/UCS4", "ISO-10646/UTF-8", "ISO-10646/UTF8",
    "ISO-2022-CN", "ISO-2022-CN-EXT", "iso-2022-jp", "ISO-2022-JP",
    "ISO-2022-JP-1", "ISO-2022-JP-2", "ISO-2022-JP-3", "ISO-2022-JP-MS",
    "iso-2022-kr", "ISO-2022-KR",
    "ISO-CELTIC", "ISO-IR-10", "ISO-IR-100", "ISO-IR-101", "ISO-IR-103",
    "ISO-IR-109", "ISO-IR-11", "ISO-IR-110", "ISO-IR-111", "ISO-IR-121",
    "ISO-IR-122", "ISO-IR-126", "ISO-IR-127", "ISO-IR-138", "ISO-IR-139",
    "ISO-IR-14", "ISO-IR-141", "ISO-IR-143", "ISO-IR-144", "ISO-IR-148",
    "ISO-IR-149", "ISO-IR-15", "ISO-IR-150", "ISO-IR-151", "ISO-IR-153",
    "ISO-IR-155", "ISO-IR-156", "ISO-IR-157", "ISO-IR-159", "ISO-IR-16",
    "ISO-IR-165", "ISO-IR-166", "ISO-IR-17", "ISO-IR-179", "ISO-IR-18",
    "ISO-IR-19", "ISO-IR-193", "ISO-IR-197", "ISO-IR-199", "ISO-IR-203",
    "ISO-IR-209", "ISO-IR-21", "ISO-IR-226", "ISO-IR-25", "ISO-IR-27",
    "ISO-IR-37", "ISO-IR-4", "ISO-IR-49", "ISO-IR-50", "ISO-IR-51",
    "ISO-IR-54", "ISO-IR-55", "ISO-IR-57", "ISO-IR-58", "ISO-IR-6",
    "ISO-IR-60", "ISO-IR-61", "ISO-IR-69", "ISO-IR-8-1", "ISO-IR-84",
    "ISO-IR-85", "ISO-IR-86", "ISO-IR-87", "ISO-IR-88", "ISO-IR-89",
    "ISO-IR-9-1", "ISO-IR-90", "ISO-IR-92", "ISO-IR-98", "ISO-IR-99",
    "ISO/TR_11548-1", "ISO11548-1", "ISO2022-JP", "ISO2022-JP-MS",
    "iso2022-kr", "ISO2022CN", "ISO2022CNEXT", "ISO2022JP", "ISO2022JP2",
    "ISO2022KR", "ISO646-CA", "ISO646-CA2", "ISO646-CN", "ISO646-CU",
    "ISO646-DE", "ISO646-DK", "ISO646-ES", "ISO646-ES2", "ISO646-FI",
    "ISO646-FR", "ISO646-FR1", "ISO646-GB", "ISO646-HU", "ISO646-IT",
    "ISO646-JP", "ISO646-JP-OCR-B", "ISO646-KR", "ISO646-NO", "ISO646-NO2",
    "ISO646-PT", "ISO646-PT2", "ISO646-SE", "ISO646-SE2", "ISO646-US",
    "ISO646-YU", "ISO6937",
    "IT", "JAVA", "JIS_C6220-1969-RO", "JIS_C62201969RO", "JIS_C6226-1983",
    "JIS_C6229-1984-B", "JIS_C62291984B", "JIS_X0201", "JIS_X0208",
    "JIS_X0208-1983", "JIS_X0208-1990", "JIS_X0212", "JIS_X0212-1990",
    "JIS_X0212.1990-0", "JIS0208", "JISX0201-1976", "Johab", "JOHAB",
    "JP", "JP-OCR-B", "JS", "JUS_I.B1.002", "KOI-7", "KOI-8", "KOI8",
    "koi8-r", "KOI8-R", "KOI8-RU", "KOI8-T", "koi8-u", "KOI8-U",
    "KOI8R", "KOI8U", "KOREAN", "ks_c_5601-1987", "KS_C_5601-1987",
    "KS_C_5601-1989", "KSC_5601", "KSC5636", "KZ-1048", "L1", "L10",
    "L2", "L3", "L4", "L5", "L6", "L7", "L8", "LATIN-9", "LATIN-GREEK",
    "LATIN-GREEK-1", "LATIN1", "LATIN10", "LATIN2", "LATIN3", "LATIN4",
    "LATIN5", "LATIN6", "LATIN7", "LATIN8", "LATIN9", "LATINGREEK",
    "LATINGREEK1", "MAC", "MAC-CENTRALEUROPE", "MAC-CYRILLIC", "MAC-IS",
    "MAC-SAMI", "MAC-UK", "MACARABIC", "MACCENTRALEUROPE", "MACCROATIAN",
    "MACCYRILLIC", "MACGREEK", "MACHEBREW", "MACICELAND", "macintosh",
    "MACINTOSH", "MACIS", "MACROMAN", "MACROMANIA", "MACTHAI", "MACTURKISH",
    "MACUK", "MACUKRAINE", "MACUKRAINIAN", "MIK", "MS_KANJI", "MS-ANSI",
    "MS-ARAB", "MS-CYRL", "MS-EE", "MS-GREEK", "MS-HEBR", "MS-MAC-CYRILLIC",
    "MS-TURK", "MS50221", "MS51932", "MS932", "MS936", "MSCP1361",
    "MSCP949", "MSMACCYRILLIC", "MSZ_7795.3", "MULELAO-1", "NAPLPS",
    "NATS-DANO", "NATS-SEFI", "NATSDANO", "NATSSEFI", "NC_NC00-10",
    "NC_NC00-10:81", "NC_NC0010", "NEXTSTEP", "NF_Z_62-010", "NF_Z_62-010_(1973)",
    "NF_Z_62-010_1973", "NF_Z_62010", "NF_Z_62010_1973", "NO", "NO2",
    "NS_4551-1", "NS_4551-2", "NS_45511", "NS_45512", "OS2LATIN1",
    "OSF00010001", "OSF00010002", "OSF00010003", "OSF00010004", "OSF00010005",
    "OSF00010006", "OSF00010007", "OSF00010008", "OSF00010009", "OSF0001000A",
    "OSF00010020", "OSF00010100", "OSF00010101", "OSF00010102", "OSF00010104",
    "OSF00010105", "OSF00010106", "OSF00030010", "OSF0004000A", "OSF0005000A",
    "OSF05010001", "OSF10010001", "OSF10010004", "OSF10010006", "OSF10020025",
    "OSF10020111", "OSF10020115", "OSF10020116", "OSF10020118", "OSF1002011C",
    "OSF1002011D", "OSF10020122", "OSF10020129", "OSF100201A4", "OSF100201A8",
    "OSF100201B5", "OSF100201F4", "OSF10020352", "OSF10020354", "OSF10020357",
    "OSF10020359", "OSF1002035D", "OSF1002035E", "OSF1002035F", "OSF10020360",
    "OSF10020364", "OSF10020365", "OSF10020366", "OSF10020367", "OSF1002036B",
    "OSF10020370", "OSF1002037B", "OSF10020387", "OSF10020388", "OSF10020396",
    "OSF100203B5", "OSF10020402", "OSF10020417", "PT", "PT154", "PT2",
    "PTCP154", "R8", "R9", "RK1048", "ROMAN8", "ROMAN9", "RUSCII",
    "SE", "SE2", "SEN_850200_B", "SEN_850200_C", "SHIFFT_JIS", "SHIFFT_JIS-MS",
    "shift_jis", "SHIFT_JIS", "SHIFT_JISX0213", "shift-jis", "SHIFT-JIS",
    "SJIS", "SJIS-MS", "SJIS-OPEN", "SJIS-WIN", "SS636127", "ST_SEV_358-88",
    "STRK1048-2002", "T.61", "T.61-8BIT", "T.618BIT", "TCVN", "TCVN-5712",
    "TCVN5712-1", "TCVN5712-1:1993", "THAI8", "TIS-620", "TIS620",
    "TIS620-0", "TIS620.2529-1", "TIS620.2533-0", "TIS620.2533-1",
    "TS-5881", "TSCII", "TURKISH8", "UCS-2", "UCS-2-INTERNAL", "UCS-2-SWAPPED",
    "UCS-2BE", "UCS-2LE", "UCS-4", "UCS-4-INTERNAL", "UCS-4-SWAPPED",
    "UCS-4BE", "UCS-4LE", "UCS2", "UCS2BE", "UCS2LE", "UCS4", "UCS4BE",
    "UCS4LE", "UHC", "UJIS", "UK", "UNICODE", "UNICODE-1-1", "UNICODE-1-1-UTF-7",
    "UNICODEBIG", "unicodeFFFE", "UNICODELITTLE", "US", "VISCII", "VISCII1.1-1",
    "WCHAR_T", "WIN-SAMI-2", "WINBALTRIM", "WINSAMI2", "WS2",
    "x_Chinese-Eten", "x-Chinese_CNS", "x-cp20001", "x-cp20003",
    "x-cp20004", "x-cp20005", "x-cp20261", "x-cp20269", "x-cp20936",
    "x-cp20949", "x-cp50227", "x-EBCDIC-KoreanExtended", "x-Europa",
    "x-IA5", "x-IA5-German", "x-IA5-Norwegian", "x-IA5-Swedish",
    "x-iscii-as", "x-iscii-be", "x-iscii-de", "x-iscii-gu", "x-iscii-ka",
    "x-iscii-ma", "x-iscii-or", "x-iscii-pa", "x-iscii-ta", "x-iscii-te",
    "x-mac-arabic", "x-mac-ce", "x-mac-chinesesimp", "x-mac-chinesetrad",
    "x-mac-croatian", "x-mac-cyrillic", "x-mac-greek", "x-mac-hebrew",
    "x-mac-icelandic", "x-mac-japanese", "x-mac-korean", "x-mac-romanian",
    "x-mac-thai", "x-mac-turkish", "x-mac-ukrainian", "X0201", "X0208",
    "X0212", "YU"
    ]

const encodings_list = [encodings8; encodings16; encodings32; encodings_other]
