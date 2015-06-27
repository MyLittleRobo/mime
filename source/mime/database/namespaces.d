module mime.database.namespaces;

private {
    import std.algorithm;
    import std.range;
    import std.string;
    import std.traits;
    import std.typecons;
}

alias Tuple!(string, "namespaceUri", string, "localName", string, "mimeType") NamespaceLine;

@trusted auto namespacesFileReader(Range)(Range byLine) if(is(ElementType!Range : string)) {
    return byLine.filter!(s => !s.empty).map!(function(string line) {
        auto splitted = line.splitter;
        if (!splitted.empty) {
            auto namespaceUri = splitted.front;
            splitted.popFront();
            if (!splitted.empty) {
                auto localName = splitted.front;
                splitted.popFront();
                if (!splitted.empty) {
                    auto mimeType = splitted.front;
                    return NamespaceLine(namespaceUri, localName, mimeType);
                }
            }
        }
        throw new Exception("Malformed namespaces file: must be 3 words per line");
    });
}