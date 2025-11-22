# HTTP Layer

This document describes the HTTP/HTTPS communication layer in k8s.zig, including TLS handling, certificate management, and the custom TLS implementation.

## Overview

The HTTP layer consists of two main components:

1. **HttpClient** (`src/http_client.zig`) - High-level HTTP client wrapper
2. **TlsHttpClient** (`src/tls_http_client.zig`) - Low-level TLS connection handler

## Architecture

```
┌──────────────────────────────────────────────┐
│          HttpClient                          │
│  - Request preparation                       │
│  - Header management                         │
│  - Content type handling                     │
│  - Response wrapping                         │
└───────────────┬──────────────────────────────┘
                │
                ▼
┌──────────────────────────────────────────────┐
│        TlsHttpClient                         │
│  - TCP connection                            │
│  - TLS handshake (via tls.zig)              │
│  - Certificate validation                    │
│  - HTTP request/response                     │
└───────────────┬──────────────────────────────┘
                │
                ▼
          ┌─────────┐
          │ tls.zig │
          └─────────┘
```

## HttpClient

**File:** `src/http_client.zig:src/http_client.zig`

### Initialization

```zig
pub const InitOptions = struct {
    /// Base64-encoded PEM certificate data for the CA
    certificate_authority_data: ?[]const u8 = null,
    /// Base64-encoded PEM certificate data for client authentication
    client_certificate_data: ?[]const u8 = null,
    /// Base64-encoded PEM private key data for client authentication
    client_key_data: ?[]const u8 = null,
    /// Skip TLS certificate verification (insecure)
    insecure_skip_tls_verify: bool = false,
};

var client = try HttpClient.init(allocator, .{
    .certificate_authority_data = ca_cert_base64,
    .client_certificate_data = client_cert_base64,
    .client_key_data = client_key_base64,
});
defer client.deinit();
```

### Certificate Handling

The `init()` function handles three types of certificates:

1. **CA Certificate** - For server verification
   - Loaded from `certificate_authority_data` if provided
   - Falls back to system CA bundle if not provided
   - Decoded from base64 to PEM format
   - Parsed and added to certificate bundle

2. **Client Certificate** - For client authentication
   - Loaded from `client_certificate_data` if provided
   - Decoded from base64 to PEM format
   - Passed to TlsHttpClient for client auth

3. **Client Key** - For client authentication
   - Loaded from `client_key_data` if provided
   - Decoded from base64 to PEM format
   - Converted from PKCS#1 to PKCS#8 if needed
   - Passed to TlsHttpClient for client auth

### PEM Certificate Parsing

```zig
fn parsePemCerts(bundle: *std.crypto.Certificate.Bundle, gpa: std.mem.Allocator, pem_data: []const u8) !void {
    const begin_marker = "-----BEGIN CERTIFICATE-----";
    const end_marker = "-----END CERTIFICATE-----";

    // Find each certificate in the PEM data
    var start_index: usize = 0;
    while (std.mem.indexOfPos(u8, pem_data, start_index, begin_marker)) |begin_marker_start| {
        // Extract base64-encoded certificate
        // Strip whitespace
        // Decode base64
        // Parse certificate
        // Add to bundle
    }
}
```

### Request Methods

```zig
pub const Method = enum {
    GET,
    POST,
    PUT,
    PATCH,
    DELETE,
};

pub const ContentType = enum {
    json,         // application/json
    protobuf,     // application/vnd.kubernetes.protobuf
};

pub const RequestOptions = struct {
    method: Method,
    url: []const u8,
    body: ?[]const u8 = null,
    content_type: ContentType = .json,
    accept: ContentType = .json,
    authorization: ?[]const u8 = null,
    extra_headers: ?[]const std.http.Header = null,
};
```

### Making Requests

```zig
// Generic request
var response = try client.request(.{
    .method = .GET,
    .url = "https://k8s.example.com/api/v1/pods",
    .authorization = "Bearer token123",
    .accept = .json,
});
defer response.deinit();

// Helper methods
var response = try client.get(url, auth, .json);
var response = try client.post(url, body, auth, .json);
var response = try client.put(url, body, auth, .json);
var response = try client.patch(url, body, auth, .json);
var response = try client.delete(url, auth, .json);
```

### Response Structure

```zig
pub const Response = struct {
    status: std.http.Status,
    body: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Response) void {
        self.allocator.free(self.body);
    }
};
```

## TlsHttpClient

**File:** `src/tls_http_client.zig:src/tls_http_client.zig`

### Why Custom TLS Client?

The standard library's `std.http.Client` has issues with TLS handshake on certain Kubernetes setups:

- Minikube with self-signed certificates
- Kind clusters
- K3s clusters
- Any setup with non-standard TLS configuration

See `TLS_ISSUE_REPORT.md` for detailed information.

### Solution: tls.zig

We use [tls.zig](https://github.com/ianic/tls.zig) for TLS connections, which provides:

- Better compatibility with self-signed certificates
- Support for client certificate authentication
- More flexible TLS handshake handling
- Better error reporting

### Initialization

```zig
pub const TlsHttpClient = struct {
    allocator: std.mem.Allocator,
    ca_bundle: std.crypto.Certificate.Bundle,
    has_custom_ca: bool,
    client_cert_pem: ?[]const u8,
    client_key_pem: ?[]const u8,
};

const tls_client = TlsHttpClient.init(
    allocator,
    ca_bundle,
    has_custom_ca,
    client_cert_pem,
    client_key_pem,
);
```

### Request Flow

```zig
pub fn request(
    self: *TlsHttpClient,
    method: std.http.Method,
    url: []const u8,
    headers: []const std.http.Header,
    body: ?[]const u8,
) !Response {
    // 1. Parse URL
    const uri = try std.Uri.parse(url);
    const host = (uri.host orelse return error.InvalidUri).percent_encoded;
    const is_https = std.mem.startsWith(u8, url, "https://");
    const port: u16 = uri.port orelse if (is_https) 443 else 80;

    // 2. Connect TCP
    const tcp_stream = try std.net.tcpConnectToHost(self.allocator, host, port);
    defer tcp_stream.close();

    // 3. Upgrade to TLS or use plain HTTP
    if (is_https) {
        return try self.requestTls(tcp_stream, method, uri, host, headers, body);
    } else {
        return try self.requestPlain(tcp_stream, method, uri, host, headers, body);
    }
}
```

### TLS Handshake

```zig
fn requestTls(
    self: *TlsHttpClient,
    tcp_stream: std.net.Stream,
    method: std.http.Method,
    uri: std.Uri,
    host: []const u8,
    headers: []const std.http.Header,
    body: ?[]const u8,
) !Response {
    // 1. Create client certificate pair if needed
    var cert_key_pair_opt: ?tls.config.CertKeyPair = null;
    defer {
        if (cert_key_pair_opt) |*ckp| {
            ckp.deinit(self.allocator);
        }
    }

    if (self.client_cert_pem != null and self.client_key_pem != null) {
        cert_key_pair_opt = try self.createCertKeyPair();
    }

    // 2. Perform TLS handshake
    var tls_conn = try tls.clientFromStream(tcp_stream, .{
        .host = host,
        .root_ca = self.ca_bundle,
        .auth = if (cert_key_pair_opt) |*ckp| ckp else null,
    });
    defer tls_conn.close() catch {};

    // 3. Build HTTP request
    // 4. Send request
    // 5. Read response
    // 6. Parse response
}
```

### Client Certificate Authentication

```zig
fn createCertKeyPair(self: *TlsHttpClient) !tls.config.CertKeyPair {
    const cert_pem = self.client_cert_pem.?;
    const key_pem = self.client_key_pem.?;

    // 1. Parse client certificate into a bundle
    var cert_bundle: std.crypto.Certificate.Bundle = .{};
    errdefer cert_bundle.deinit(self.allocator);
    try self.parsePemCerts(&cert_bundle, cert_pem);

    // 2. Convert RSA PRIVATE KEY (PKCS#1) to PRIVATE KEY (PKCS#8) if needed
    const converted_key = try self.convertRsaKeyToPkcs8IfNeeded(key_pem);
    defer if (converted_key.ptr != key_pem.ptr) self.allocator.free(converted_key);

    // 3. Parse private key from PEM
    const private_key = try tls.config.PrivateKey.parsePem(converted_key);

    return tls.config.CertKeyPair{
        .bundle = cert_bundle,
        .key = private_key,
    };
}
```

### PKCS#1 to PKCS#8 Conversion

Client certificate private keys are often in PKCS#1 format (RSA PRIVATE KEY), but tls.zig requires PKCS#8 format (PRIVATE KEY).

```zig
fn convertRsaKeyToPkcs8IfNeeded(self: *TlsHttpClient, key_pem: []const u8) ![]const u8 {
    // Check if this is an RSA PRIVATE KEY (PKCS#1 format)
    if (std.mem.indexOf(u8, key_pem, "-----BEGIN RSA PRIVATE KEY-----") == null) {
        // Not an RSA PRIVATE KEY, return as-is
        return key_pem;
    }

    // Use openssl to convert PKCS#1 to PKCS#8
    // This is a temporary solution - ideally we'd implement the conversion in Zig
    const result = try std.process.Child.run(.{
        .allocator = self.allocator,
        .argv = &[_][]const u8{
            "openssl",
            "pkcs8",
            "-topk8",
            "-nocrypt",
            "-in", temp_in,
            "-out", temp_out,
        },
    });

    // Read converted key and return
}
```

**Note:** This currently uses an external `openssl` command. A pure Zig implementation is planned for the future.

### HTTP Request Building

```zig
// Build HTTP request manually
var request_buf: std.ArrayList(u8) = .{};
defer request_buf.deinit(self.allocator);

const writer = request_buf.writer(self.allocator);

// Request line
try writer.print("{s} {s}{s} HTTP/1.1\r\n", .{ @tagName(method), path, query_string });

// Headers
try writer.print("Host: {s}\r\n", .{host});
for (headers) |header| {
    try writer.print("{s}: {s}\r\n", .{ header.name, header.value });
}
if (body) |b| {
    try writer.print("Content-Length: {d}\r\n", .{b.len});
}
try writer.writeAll("Connection: close\r\n");
try writer.writeAll("\r\n");

// Body
if (body) |b| {
    try writer.writeAll(b);
}

// Send
_ = try tls_conn.write(request_buf.items);
```

### HTTP Response Parsing

```zig
fn parseResponse(self: *TlsHttpClient, response_data: []const u8) !Response {
    // 1. Parse status line
    const status_line_end = std.mem.indexOf(u8, response_data, "\r\n") orelse return error.InvalidResponse;
    const status_line = response_data[0..status_line_end];

    // Parse status code from "HTTP/1.1 200 OK"
    var status_parts = std.mem.tokenizeScalar(u8, status_line, ' ');
    _ = status_parts.next(); // Skip HTTP version
    const status_code_str = status_parts.next() orelse return error.InvalidResponse;
    const status_code = try std.fmt.parseInt(u16, status_code_str, 10);

    // 2. Parse headers
    const headers_end = std.mem.indexOf(u8, response_data, "\r\n\r\n") orelse return error.InvalidResponse;
    const headers_section = response_data[status_line_end + 2 .. headers_end];

    var headers_map = std.StringHashMap([]const u8).init(self.allocator);
    // ... parse headers

    // 3. Extract body
    const body_start = headers_end + 4;
    const body = try self.allocator.dupe(u8, response_data[body_start..]);

    return Response{
        .status = @enumFromInt(status_code),
        .headers = headers_map,
        .body = body,
        .allocator = self.allocator,
    };
}
```

## Content Type Handling

k8s.zig supports two content types for Kubernetes API communication:

### JSON (default)
- Content-Type: `application/json`
- Accept: `application/json`
- Human-readable
- Widely supported
- Slightly less efficient

### Protobuf
- Content-Type: `application/vnd.kubernetes.protobuf`
- Accept: `application/vnd.kubernetes.protobuf`
- Binary format
- More efficient
- Requires generated types

```zig
// Use JSON
var response = try client.get(url, auth, .json);

// Use Protobuf
var response = try client.get(url, auth, .protobuf);
```

## Error Handling

### TLS Errors

```zig
error.TlsInitializationFailed  // TLS handshake failed
error.InvalidCertificate        // Certificate parsing failed
error.MissingEndCertificateMarker  // PEM parsing failed
error.KeyConversionFailed       // PKCS#1 to PKCS#8 conversion failed
```

### HTTP Errors

```zig
error.InvalidUri               // URL parsing failed
error.ConnectionRefused        // Cannot connect to server
error.InvalidResponse          // Response parsing failed
```

### Network Errors

```zig
error.NetworkUnreachable
error.ConnectionResetByPeer
error.BrokenPipe
```

## Performance Considerations

### Connection Management
Currently, each request creates a new TCP/TLS connection. Future improvements:
- Connection pooling
- Keep-alive connections
- Connection reuse

### Memory Allocation
- Certificate data is allocated during init and freed during deinit
- Request buffers are stack-allocated where possible
- Response bodies are heap-allocated (caller must free)

### Buffer Sizes
```zig
var read_buf: [4096]u8 = undefined;  // 4KB read buffer
const max_kubeconfig_size = 10 * 1024 * 1024;  // 10MB max kubeconfig
```

## Testing

### Unit Tests
```zig
test "HttpClient initialization" {
    const allocator = testing.allocator;
    var client = try HttpClient.init(allocator, .{});
    defer client.deinit();
}

test "ContentType toString" {
    try testing.expectEqualStrings("application/json", ContentType.json.toString());
    try testing.expectEqualStrings("application/vnd.kubernetes.protobuf", ContentType.protobuf.toString());
}
```

### Integration Tests
Testing with a real Kubernetes cluster is recommended:
```bash
# Start minikube
minikube start

# Run integration tests
zig build test
```

## Best Practices

### 1. Always defer deinit
```zig
var client = try HttpClient.init(allocator, .{});
defer client.deinit();

var response = try client.get(url, auth, .json);
defer response.deinit();
```

### 2. Use TLS certificate verification
```zig
// Good: Verify server certificate
var client = try HttpClient.init(allocator, .{
    .certificate_authority_data = ca_cert,
});

// Bad: Skip verification (insecure)
var client = try HttpClient.init(allocator, .{
    .insecure_skip_tls_verify = true,
});
```

### 3. Handle errors appropriately
```zig
const response = client.get(url, auth, .json) catch |err| {
    switch (err) {
        error.TlsInitializationFailed => {
            std.debug.print("TLS handshake failed - check certificates\n", .{});
            return err;
        },
        error.ConnectionRefused => {
            std.debug.print("Cannot connect to {s}\n", .{url});
            return err;
        },
        else => return err,
    }
};
```

### 4. Prefer JSON for debugging
Use JSON content type during development for easier debugging. Switch to protobuf for production if performance is critical.

## Future Improvements

1. **Connection Pooling** - Reuse TCP/TLS connections
2. **Async I/O** - Non-blocking operations
3. **HTTP/2 Support** - For better multiplexing
4. **Pure Zig PKCS#1 to PKCS#8 Conversion** - Remove openssl dependency
5. **Chunked Transfer Encoding** - For large responses
6. **Compression** - gzip/deflate support
7. **Request Timeout** - Configurable timeout for requests
8. **Retry Logic** - Automatic retries with backoff
