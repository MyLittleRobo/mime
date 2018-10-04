/**
 * Functions for reading XML descriptions of MIME types.
 * Authors:
 *  $(LINK2 https://github.com/FreeSlave, Roman Chistokhodov)
 * License:
 *  $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Copyright:
 *  Roman Chistokhodov, 2018
 */

module mime.xml;

import mime.common;

public import mime.type;

private
{
    import dxml.parser;
    import dxml.util;
    import std.conv : to, ConvException;
    import std.exception : assumeUnique;
    import std.mmfile;
    import std.system : Endian, endian;
}

/**
 * Exception that's thrown on invalid XML definition of MIME type.
 */
final class XMLMimeException : Exception
{
    this(string msg, int lineNum, int col, string file = __FILE__, size_t line = __LINE__, Throwable next = null) pure nothrow @safe {
        super(msg, file, line, next);
        _line = lineNum;
        _col = col;
    }
    private this(string msg, TextPos pos, string file = __FILE__, size_t line = __LINE__, Throwable next = null) pure nothrow @safe {
        this(msg, pos.line, pos.col, file, line, next);
    }
    private this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null) pure nothrow @safe {
        this(msg, 0, 0, file, line, next);
    }

    /// Line number in XML file where error occured. Don't confuse with $(B line) property of $(B Throwable)
    @nogc @safe int lineNum() const nothrow {
        return _line;
    }
    /// Column number in XML file where error occured.
    @nogc @safe int column() const nothrow {
        return _col;
    }

private:
    int _line, _col;
}

private alias EntityRange!(simpleXML, const(char)[]) XmlRange;

private string readSingleAttribute(ref XmlRange.Entity entity, string attrName)
{
    foreach(attr; entity.attributes)
    {
        if (attr.name == attrName)
        {
            return attr.value.idup;
        }
    }
    return null;
}

private void checkXmlRange(ref XmlRange range)
{
    if (range.empty)
        throw new XMLMimeException("Unexpected end of file");
}

private XmlRange.Entity expectOpenTag(ref XmlRange range)
{
    checkXmlRange(range);
    auto elem = range.front;
    if (elem.type != EntityType.elementStart)
        throw new XMLMimeException("Expected an open tag", elem.pos);
    range.popFront();
    return elem;
}

private XmlRange.Entity expectOpenTag(ref XmlRange range, const(char)[] name)
{
    checkXmlRange(range);
    auto elem = range.front;
    if (elem.type != EntityType.elementStart || elem.name != name)
        throw new XMLMimeException(assumeUnique("Expected \"" ~ name ~ "\" open tag"), elem.pos);
    range.popFront();
    return elem;
}

private XmlRange.Entity expectClosingTag(ref XmlRange range, const(char)[] name)
{
    checkXmlRange(range);
    auto elem = range.front;
    if (elem.type != EntityType.elementEnd || elem.name != name)
        throw new XMLMimeException(assumeUnique("Expected \"" ~ name ~ "\" closing tag"), elem.pos);
    range.popFront();
    return elem;
}

private XmlRange.Entity expectTextTag(ref XmlRange range)
{
    checkXmlRange(range);
    auto elem = range.front;
    if (elem.type != EntityType.text)
        throw new XMLMimeException("Expected a text tag", elem.pos);
    range.popFront();
    return elem;
}

/**
 * Get symbolic constant of match type according to the string.
 * Returns: $(D mime.magic.MagicMatch.Type) for passed string, or $(D mime.magic.MagicMatch.Type.string_) if type name is unknown.
 */
@nogc @safe MagicMatch.Type matchTypeFromString(const(char)[] str) pure nothrow
{
    with(MagicMatch.Type) switch(str)
    {
        case "string":
            return string_;
        case "host16":
            return host16;
        case "host32":
            return host32;
        case "big16":
            return big16;
        case "big32":
            return big32;
        case "little16":
            return little16;
        case "little32":
            return little32;
        case "byte":
            return byte_;
        default:
            return string_;
    }
}

///
unittest
{
    assert(matchTypeFromString("string") == MagicMatch.Type.string_);
    assert(matchTypeFromString("little32") == MagicMatch.Type.little32);
    assert(matchTypeFromString("byte") == MagicMatch.Type.byte_);
    assert(matchTypeFromString("") == MagicMatch.Type.string_);
}

private T toNumberValue(T)(const(char)[] valueStr)
{
    if (valueStr.length > 2 && valueStr[0..2] == "0x")
    {
        return valueStr[2..$].to!T(16);
    }
    if (valueStr.length > 1 && valueStr[0] == '0')
    {
        return valueStr[1..$].to!T(8);
    }
    return valueStr.to!T;
}

unittest
{
    assert(toNumberValue!uint("0xFF") == 255);
    assert(toNumberValue!uint("017") == 15);
    assert(toNumberValue!uint("42") == 42);
}

private immutable(ubyte)[] unescapeValue(string value)
{
    import std.array : appender;
    import std.string : representation;
    size_t i = 0;
    for (; i < value.length; i++) {
        if (value[i] == '\\') {
            break;
        }
    }
    if (i == value.length) {
        return value.representation;
    }
    auto toReturn = appender!(immutable(ubyte)[])();
    toReturn.reserve(value.length);
    toReturn.put(value[0..i].representation);
    for (; i < value.length; i++) {
        if (value[i] == '\\' && i+1 < value.length) {
            const char c = value[i+1];
            switch(c)
            {
                case '\\':
                    toReturn.put('\\');
                    ++i;
                    continue;
                case 'n':
                    toReturn.put('\n');
                    ++i;
                    continue;
                case 'r':
                    toReturn.put('\r');
                    ++i;
                    continue;
                case 't':
                    toReturn.put('\t');
                    ++i;
                    continue;
                case 'x':
                {
                    if (i+3 < value.length)
                    {
                        auto hexStr = value[i+2..i+4];
                        toReturn.put(hexStr.to!ubyte(16));
                        i+=3;
                        continue;
                    }
                }
                break;
                default:
                {
                    import std.algorithm.searching : countUntil;
                    import std.ascii : isOctalDigit;
                    auto octalCount = value[i+1..$].countUntil!(a => !isOctalDigit(a));
                    if (octalCount < 0)
                    {
                        octalCount = value.length - (i+1);
                    }
                    if (octalCount == 3)
                    {
                        auto octalStr = value[i+1..i+1+octalCount];
                        toReturn.put(octalStr.to!ubyte(8));
                        i+=octalCount;
                        continue;
                    }
                    else if (octalCount == 1 && value[i+1] == '0')
                    {
                        toReturn.put('\0');
                        ++i;
                        continue;
                    }
                }
                break;
            }
        }
        toReturn.put(value[i]);
    }
    return toReturn.data;
}

unittest
{
    import std.conv : octal;
    assert(unescapeValue(`\\\n\t\r`) == "\\\n\t\r");
    assert(unescapeValue(`\\xFF`) == "\\xFF");
    assert(unescapeValue(`\x7F`) == [127]);
    assert(unescapeValue(`\177`) == [127]);
    assert(unescapeValue(`\003`) == [3]);
    assert(unescapeValue(`\003vbn`) == [3, 'v', 'b', 'n']);
    assert(unescapeValue(`\0`) == ['\0']);
}

private T swapEndianIfNeeded(T)(T val, Endian expectedEndian)
{
    import std.bitmanip : swapEndian;
    if (endian != expectedEndian)
        return swapEndian(val);
    return val;
}

unittest
{
    assert(swapEndianIfNeeded(42, endian) == 42);
    static if (endian != Endian.bigEndian)
        assert(swapEndianIfNeeded!ushort(10, Endian.bigEndian) == 2560);
}

private Endian endianFromMatchType(MagicMatch.Type type)
{
    with(MagicMatch.Type) switch(type)
    {
        case big16:
        case big32:
            return Endian.bigEndian;
        case little16:
        case little32:
            return Endian.littleEndian;
        default:
            return endian;
    }
}

private immutable(ubyte)[] readMatchValue(const(char)[] valueStr, MagicMatch.Type type, TextPos pos, bool isMask = false)
{
    immutable(ubyte)[] value;
    ubyte val8;
    ushort val16;
    uint val32;
    with(MagicMatch.Type) final switch(type)
    {
        case string_:
            if (isMask)
            {
                import std.array : array;
                import std.algorithm.iteration : map;
                import std.range : chunks;
                import std.utf : byCodeUnit;
                if (valueStr.length > 2 && valueStr[0..2] == "0x")
                {
                    valueStr = valueStr[2..$];
                    if (valueStr.length % 2 == 0)
                    {
                        value = valueStr.byCodeUnit.chunks(2).map!(pair => pair.to!ubyte(16)).array;
                    }
                    else
                    {
                        throw new XMLMimeException("Mask of type string has uneven length", pos);
                    }
                }
                else
                {
                    throw new XMLMimeException("Mask of type string must be in base16 form starting with 0x prefix", pos);
                }
            }
            else
            {
                value = valueStr.idup.decodeXML.unescapeValue;
            }
            break;
        case host16:
        case little16:
        case big16:
            val16 = swapEndianIfNeeded(valueStr.toNumberValue!ushort, endianFromMatchType(type));
            value = (cast(ubyte*)&val16)[0..2].idup;
            break;
        case host32:
        case little32:
        case big32:
            val32 = swapEndianIfNeeded(valueStr.toNumberValue!uint, endianFromMatchType(type));
            value = (cast(ubyte*)&val32)[0..4].idup;
            break;
        case byte_:
            val8 = valueStr.toNumberValue!ubyte;
            value = (&val8)[0..1].idup;
            break;
    }
    return value;
}

private MagicMatch readMagicMatch(ref XmlRange range, string mimeTypeName, uint level = 0)
{
    import std.algorithm.searching : findSplit;
    auto elem = expectOpenTag(range, "match");
    try
    {
        const(char)[] typeStr, valueStr, offset, maskStr;
        getAttrs(elem.attributes, "type", &typeStr, "value", &valueStr, "offset", &offset, "mask", &maskStr);

        auto splitted = offset.findSplit(":");
        uint startOffset = splitted[0].to!uint;
        uint rangeLength = 1;
        if (splitted[2].length)
            rangeLength = splitted[2].to!uint;
        immutable(ubyte)[] value, mask;
        auto type = matchTypeFromString(typeStr);
        value = readMatchValue(valueStr, type, elem.pos);
        if (maskStr.length)
            mask = readMatchValue(maskStr, type, elem.pos, true);
        auto magicMatch = MagicMatch(type, value, mask, startOffset, rangeLength);
        while(!range.empty)
        {
            elem = range.front;
            if (elem.type == EntityType.elementEnd && elem.name == "match")
            {
                range.popFront();
                break;
            }
            magicMatch.addSubmatch(readMagicMatch(range, mimeTypeName, level+1));
        }
        return magicMatch;
    }
    catch (ConvException e)
    {
        throw new XMLMimeException(e.msg, elem.pos);
    }
}

private MimeType readMimeType(ref XmlRange range)
{
    typeof(range).Entity elem = expectOpenTag(range, "mime-type");
    string name = readSingleAttribute(elem, "type");
    if (!isValidMimeTypeName(name))
    {
        throw new XMLMimeException("Missing or invalid mime type name", elem.pos);
    }
    auto mimeType = new MimeType(name);
    while(!range.empty)
    {
        if (range.front.type == EntityType.elementEnd && range.front.name == "mime-type")
        {
            range.popFront();
            break;
        }
        elem = expectOpenTag(range);
        const tagName = elem.name;
        switch(elem.name)
        {
            case "glob":
            {
                MimeGlob glob;
                string pattern;
                uint weight = defaultGlobWeight;
                const(char)[] caseSensitive;
                getAttrs(elem.attributes, "pattern", &pattern, "weight", &weight, "case-sensitive", &caseSensitive);
                if (pattern.length == 0)
                {
                    throw new XMLMimeException("Missing pattern in glob declaration", elem.pos);
                }
                else
                {
                    glob.pattern = pattern;
                    glob.weight = weight;
                    glob.caseSensitive = caseSensitive == "true";
                }
                mimeType.addGlob(glob);
                expectClosingTag(range, tagName);
            }
            break;
            case "glob-deleteall":
            {
                expectClosingTag(range, tagName);
            }
            break;
            case "magic-deleteall":
            {
                expectClosingTag(range, tagName);
            }
            break;
            case "alias":
            {
                string aliasName = readSingleAttribute(elem, "type");
                if (!isValidMimeTypeName(aliasName))
                {
                    throw new XMLMimeException("Missing or invalid alias name", elem.pos);
                }
                mimeType.addAlias(aliasName);
                expectClosingTag(range, tagName);
            }
            break;
            case "sub-class-of":
            {
                string parentName = readSingleAttribute(elem, "type");
                if (!isValidMimeTypeName(parentName))
                {
                    throw new XMLMimeException("Missing or invalid parent name", elem.pos);
                }
                mimeType.addParent(parentName);
                expectClosingTag(range, tagName);
            }
            break;
            case "comment":
            {
                bool localized = false;
                foreach(attr; elem.attributes)
                {
                    if (attr.name == "xml:lang")
                    {
                        localized = true;
                        break;
                    }
                }
                elem = expectTextTag(range);
                if (!localized)
                {
                    mimeType.displayName = elem.text.idup.decodeXML;
                }
                expectClosingTag(range, tagName);
            }
            break;
            case "icon":
            {
                string icon = readSingleAttribute(elem, "name");
                mimeType.icon = icon;
                expectClosingTag(range, tagName);
            }
            break;
            case "generic-icon":
            {
                string genericIcon = readSingleAttribute(elem, "name");
                mimeType.genericIcon = genericIcon;
                expectClosingTag(range, tagName);
            }
            break;
            case "root-XML":
            {
                string namespaceURI, localName;
                getAttrs(elem.attributes, "namespaceURI", &namespaceURI, "localName", &localName);
                mimeType.addXMLnamespace(namespaceURI, localName);
                expectClosingTag(range, tagName);
            }
            break;
            case "magic":
            {
                uint priority = defaultMatchWeight;
                getAttrs(elem.attributes, "priority", &priority);
                auto magic = MimeMagic(priority);
                while (!range.empty)
                {
                    elem = range.front;
                    if (elem.type == EntityType.elementEnd && elem.name == "magic")
                    {
                        mimeType.addMagic(magic);
                        range.popFront();
                        break;
                    }
                    magic.addMatch(readMagicMatch(range, name));
                }
            }
            break;
            default:
            {
                while(!range.empty)
                {
                    elem = range.front;
                    range.popFront();
                    if (elem.type == EntityType.elementEnd && elem.name == tagName)
                    {
                        break;
                    }
                }
            }
            break;
        }
    }
    return mimeType;
}

/**
 * Read MIME type from MEDIA/SUBTYPE.xml file (e.g. image/png.xml).
 * Returns: $(D mime.type.MimeType) parsed from xml definition.
 * Throws: $(D XMLMimeException) on format error or $(B std.file.FileException) on file reading error.
 * See_Also: $(D mime.xml.readMediaSubtypeXML)
 * Note: According to the spec MEDIA/SUBTYPE.xml files have glob fields removed.
 *  In reality they stay untouched, but this may change in future and this behavior should not be relied on.
 */
@trusted MimeType readMediaSubtypeFile(string filePath)
{
    auto mmFile = new MmFile(filePath);
    scope(exit) destroy(mmFile);
    auto data = cast(const(char)[])mmFile[];
    return readMediaSubtypeXML(data);
}

/**
 * Read MIME type from xml formatted data with mime-type root element as defined by spec.
 * Returns: $(D mime.type.MimeType) parsed from xml definition.
 * Throws: $(D XMLMimeException) on format error.
 */
@trusted MimeType readMediaSubtypeXML(const(char)[] xmlData)
{
    try
    {
        auto range = parseXML!simpleXML(xmlData);
        if (range.empty)
            throw new XMLMimeException("No elements in subtype xml");
        return readMimeType(range);
    }
    catch(XMLParsingException e)
    {
        throw new XMLMimeException(e.msg, e.pos);
    }
}

///
unittest
{
    auto xmlData = `<?xml version="1.0" encoding="utf-8"?>
<mime-type xmlns="http://www.freedesktop.org/standards/shared-mime-info" type="text/markdown">
  <!--Created automatically by update-mime-database. DO NOT EDIT!-->
  <comment>Markdown document</comment>
  <comment xml:lang="ru">документ Markdown</comment>
  <sub-class-of type="text/plain"/>
  <glob pattern="*.md"/>
  <glob pattern="*.mkd" weight="40"/>
  <glob pattern="*.markdown" case-sensitive="true"/>
  <alias type="text/x-markdown"/>
</mime-type>`;
    auto mimeType = readMediaSubtypeXML(xmlData);
    assert(mimeType.name == "text/markdown");
    assert(mimeType.displayName == "Markdown document");
    assert(mimeType.aliases == ["text/x-markdown"]);
    assert(mimeType.parents == ["text/plain"]);
    assert(mimeType.globs == [MimeGlob("*.md"), MimeGlob("*.mkd", 40), MimeGlob("*.markdown", defaultGlobWeight, true)]);

    import std.exception : assertThrown, assertNotThrown;
    auto notXml = "not xml";
    assertThrown!XMLMimeException(readMediaSubtypeXML(notXml));
    auto invalidEmpty = `<?xml version="1.0" encoding="utf-8"?>`;
    assertThrown!XMLMimeException(readMediaSubtypeXML(invalidEmpty));

    auto notNumber = `<mime-type type="text/markdown">
  <glob pattern="*.mkd" weight="not_a_number"/>
</mime-type>`;
    assertThrown!XMLMimeException(readMediaSubtypeXML(notNumber));

    auto validEmpty = `<mime-type type="text/markdown"></mime-type>`;
    assertNotThrown(readMediaSubtypeXML(validEmpty));

    auto missingName = `<mime-type></mime-type>`;
    assertThrown(readMediaSubtypeXML(missingName));
}

struct XmlPackageRange
{
    private this(XmlRange range, MmFile mmFile)
    {
        this.range = range;
        this.mmFile = mmFile;
    }
    MimeType front()
    {
        if (mimeType)
            return mimeType;
        mimeType = readMimeType(range);
        return mimeType;
    }
    void popFront()
    {
        mimeType = null;
    }
    bool empty()
    {
        if (range.empty)
            return true;
        auto elem = range.front;
        if (elem.type == EntityType.elementEnd && elem.name == "mime-info")
        {
            range.popFront();
            return true;
        }
        return false;
    }
    auto save()
    {
        return this;
    }
private:
    MmFile mmFile;
    XmlRange range;
    MimeType mimeType;
}

auto readMimePackageFile(string filePath)
{
    auto mmFile = new MmFile(filePath);
    auto data = cast(const(char)[])mmFile[];
    auto range = parseXML!simpleXML(data);
    if (range.empty)
    {
        throw new XMLMimeException("No elements in package xml");
    }
    expectOpenTag(range, "mime-info");
    return XmlPackageRange(range, mmFile);
}
