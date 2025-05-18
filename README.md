# Wardrobe

A lightweight, simple [HTTP `multipart/form-data`](https://www.rfc-editor.org/rfc/rfc7578) library for Zig.

Supports writing form data payloads. Parsing not currently supported.

## Usage

### Boundary
To start writing form data, you need to create a boundary string for your application. The spec requires
a certain number of bytes of entropy, so Wardrobe helps by giving you a helper struct for creating
boundaries:
```zig
const boundary: wardrobe.Boundary = .entropy("MyApplicationBoundary", random);
```

`random` is an interface instance of `std.Random`, for example:
```zig
var prng = std.Random.DefaultPrng.init(@intCast(std.time.microTimestamp()));

const boundary: wardrobe.Boundary = .entropy("MyApplicationBoundary", prng.random());
```

If you want to pass in a boundary, you can also use `wardrobe.Boundary.buffer`:

```zig
const boundary: wardrobe.Boundary = .buffer("----MyApplicationBoundaryRANDOMBYTES");
```

### Write Stream
Creating a write stream just needs an underlying writer to write to:
```zig
const write_stream = wardrobe.writeStream(boundary, http_request.writer());
```

Using decl literals, you can write this in one line:
```zig
const write_stream = wardrobe.writeStream(.entropy("MyApplicationBoundary", prng.random()), http_request.writer());
```

Given a write stream, you have the following functions to write form data sections:
```zig
pub fn writer(self: WriteStream) Writer;

pub fn beginTextEntry(self: WriteStream) !void;
pub fn beginFileEntry(self: WriteStream) !void;

pub fn endEntry(self: WriteStream) !void;
pub fn endEntries(self: WriteStream) !void;
```

There are runtime checks to make sure you call functions in the right order. You can follow
this pseudocode to know which functions to call:

```
for each entry:
    write_stream.beginTextEntry() or write_stream.beginFileEntry()
    write entry data with write_stream.writer()
    write_stream.endEntry()

write_stream.endEntries();
```

### License
All Wardrobe code is under the MIT license.