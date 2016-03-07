# Mime

[Shared MIME-info database](http://standards.freedesktop.org/shared-mime-info-spec/shared-mime-info-spec-latest.html) specification implementation in D programming language. Shared MIME-info database helps to determine media type of file by its name or contents.

[![Build Status](https://travis-ci.org/MyLittleRobo/mime.svg?branch=master)](https://travis-ci.org/MyLittleRobo/mime)

## Generating documentation

Ddoc:

    dub build --build=docs
    
Ddox:

    dub build --build=ddox

## Examples
    
### [MimeDatabase](examples/mimedatabase/source/app.d)

Run to detect mime types of files.

    dub run mime:mimedatabase -- detect README.md source .gitignore lib/libmime.a examples/mimedatabase/bin/mimedatabase /var/run/acpid.socket dub.json
    
Automated mime path detection works only on Freedesktop platforms. On other systmes or for testing purposes it's possible to use mimepath option to set alternate path to mime/ subfolder. E.g. on Windows with KDE installed it would be:

    dub run mime:mimedatabase -- --mimepath=C:\ProgramData\KDE\share\mime detect README.md source .gitignore lib/mime.lib examples/mimedatabase/bin/mimedatabase.exe dub.json
    
Run to print info about MIME types:

    dub run mime:mimedatabase -- info application/pdf application/x-executable image/png text/plain text/html text/xml

Run to resolve aliases:

    dub run mime:mimedatabase -- resolve application/wwf application/x-pdf application/pgp text/rtf text/xml
    
## Features

### Implemented features

* Reading mime.cache files.
* Using mime.cache files to match file names against glob patterns, match file contents against magic rules (not fully implemented yet, but works in most cases), resolve aliases and find mime type parents.
* Reading various files in mime/ subfolder, e.g. globs2, magic and others.

### Missing features

* Reading MIME types from mime/packages sources (requires xml library).
* Determining MIME type by XMLnamespace if document is xml (requires streaming xml library).
* treemagic support.
