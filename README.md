# Wardrobe

A lightweight, simple [HTTP `multipart/form-data`](https://www.rfc-editor.org/rfc/rfc7578) library for Zig.

Supports both reading and writing form data payloads.

## Writing Usage

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

To access the generated boundary, use `boundary.slice()`.

#### Content-Type
For the HTTP Content-Type header value for a boundary, use `boundary.contentType()`. This returns a slice in the format
`multipart/form-data; boundary=<boundary>`

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
pub fn writer(self: *WriteStream) Writer;

pub fn beginTextEntry(self: *WriteStream, name: []const u8) !void;
pub fn beginFileEntry(self: *WriteStream, name: []const u8, content_type: []const u8, file_name: []const u8) !void;

pub fn endEntry(self: *WriteStream) !void;
pub fn endEntries(self: *WriteStream) !void;
```

There are runtime assertions to make sure you call functions in the right order. You can follow
this pseudocode to know which functions to call:

```
for each entry:
    write_stream.beginTextEntry() or write_stream.beginFileEntry()
    write entry data with write_stream.writer()
    write_stream.endEntry()

write_stream.endEntries();
```

## Reading Usage

### Boundary
Given a 'Content-Type' header, you can use `Boundary.parseContentType` to get a boundary object:
```zig
const boundary = try wardrobe.Boundary.parseContentType("multipart/form-data; boundary=------Boundary");
```

The function returns `error.Invalid` if the header is not valid for `multipart/form-data`, or if the boundary
is too long.

### Scanner
Given a reader, you can iterate through the form data entries of a body. Note that there's no guarantee that the reader
only reads what is necessary, it may overflow.

The Scanner API takes an allocator, but the allocations are only temporary.

```zig
var scanner = try scanner(allocator, boundary, reader);
defer scanner.deinit();

while (try scanner.nextEntry()) |entry| {
    const data = scanner.reader().readAllAlloc(allocator, std.math.maxInt(usize));
    defer std.testing.allocator.free(data);
}
``` 

`scanner.reader()` returns a reader that gives EOF upon the end of the current active entry's data.

The returned entry has the following signature:
```zig
pub const Scanner.Entry = struct {
    name: []const u8,
    file_name: ?[]const u8,
    content_type: ?[]const u8,
};
```

### Parser
Sometimes, it may be useful to parse an entire response body or slice at once. Wardrobe provides utility functions
in `wardrobe.parse`:
```zig
const entries = try wardrobe.parse.fromSlice(allocator, boundary, slice);
// or try wardrobe.parse.fromReader(allocator, boundary, reader);
// or try wardrobe.parse.fromScanner(allocator, boundary, scanner);
defer wardrobe.parse.deinitEntries(entries);
```

The entries returned is the same entry struct as in [Scanner.Entry](#scanner), but also has a `data: []const u8` field
for accessing the whole parsed data.

Since you own all of the data and entries returned, you can use `wardrobe.parse.deinitEntries`
(or `parse.Entry.deinit` for individual entries) to clean-up.

### License
All Wardrobe code is under the MIT license.