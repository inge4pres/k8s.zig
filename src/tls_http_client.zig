const std = @import("std");
const tls = @import("tls");

/// Custom HTTP client that uses tls.zig for TLS connections
/// This replaces std.http.Client to work around TLS handshake issues with minikube
pub const TlsHttpClient = struct {
    allocator: std.mem.Allocator,
    ca_bundle: std.crypto.Certificate.Bundle,
    has_custom_ca: bool,
    client_cert_pem: ?[]const u8,
    client_key_pem: ?[]const u8,

    pub fn init(
        allocator: std.mem.Allocator,
        ca_bundle: std.crypto.Certificate.Bundle,
        has_custom_ca: bool,
        client_cert_pem: ?[]const u8,
        client_key_pem: ?[]const u8,
    ) TlsHttpClient {
        return .{
            .allocator = allocator,
            .ca_bundle = ca_bundle,
            .has_custom_ca = has_custom_ca,
            .client_cert_pem = client_cert_pem,
            .client_key_pem = client_key_pem,
        };
    }

    pub fn deinit(self: *TlsHttpClient) void {
        // Always deinit the ca_bundle as it may contain system or custom certificates
        var bundle = self.ca_bundle;
        bundle.deinit(self.allocator);

        if (self.client_cert_pem) |cert| {
            self.allocator.free(cert);
        }
        if (self.client_key_pem) |key| {
            self.allocator.free(key);
        }
    }

    pub const Response = struct {
        status: std.http.Status,
        headers: std.StringHashMap([]const u8),
        body: []const u8,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *Response) void {
            self.headers.deinit();
            self.allocator.free(self.body);
        }
    };

    /// Make an HTTP/HTTPS request
    pub fn request(
        self: *TlsHttpClient,
        method: std.http.Method,
        url: []const u8,
        headers: []const std.http.Header,
        body: ?[]const u8,
    ) !Response {
        const uri = try std.Uri.parse(url);

        const host = (uri.host orelse return error.InvalidUri).percent_encoded;
        const is_https = std.mem.startsWith(u8, url, "https://");
        const port: u16 = uri.port orelse if (is_https) 443 else 80;

        // Connect to server
        const tcp_stream = try std.net.tcpConnectToHost(self.allocator, host, port);
        defer tcp_stream.close();

        if (is_https) {
            // Use tls.zig for HTTPS
            return try self.requestTls(tcp_stream, method, uri, host, headers, body);
        } else {
            // Plain HTTP (not needed for k8s but included for completeness)
            return try self.requestPlain(tcp_stream, method, uri, host, headers, body);
        }
    }

    fn requestTls(
        self: *TlsHttpClient,
        tcp_stream: std.net.Stream,
        method: std.http.Method,
        uri: std.Uri,
        host: []const u8,
        headers: []const std.http.Header,
        body: ?[]const u8,
    ) !Response {
        // Create client certificate pair if we have both cert and key
        var cert_key_pair_opt: ?tls.config.CertKeyPair = null;
        defer {
            if (cert_key_pair_opt) |*ckp| {
                ckp.deinit(self.allocator);
            }
        }

        if (self.client_cert_pem != null and self.client_key_pem != null) {
            cert_key_pair_opt = try self.createCertKeyPair();
        }

        // Upgrade to TLS using tls.zig
        var tls_conn = try tls.clientFromStream(tcp_stream, .{
            .host = host,
            .root_ca = self.ca_bundle,
            .auth = if (cert_key_pair_opt) |*ckp| ckp else null,
        });
        defer tls_conn.close() catch {};

        // Build HTTP request
        var request_buf: std.ArrayList(u8) = .{};
        defer request_buf.deinit(self.allocator);

        const writer = request_buf.writer(self.allocator);

        // Request line
        const path = uri.path.percent_encoded;
        const path_to_use = if (path.len > 0) path else "/";
        const query_string = if (uri.query) |q| try std.fmt.allocPrint(self.allocator, "?{s}", .{q.percent_encoded}) else try self.allocator.dupe(u8, "");
        defer self.allocator.free(query_string);

        try writer.print("{s} {s}{s} HTTP/1.1\r\n", .{ @tagName(method), path_to_use, query_string });

        // Host header
        try writer.print("Host: {s}\r\n", .{host});

        // Custom headers
        for (headers) |header| {
            try writer.print("{s}: {s}\r\n", .{ header.name, header.value });
        }

        // Content-Length if we have a body
        if (body) |b| {
            try writer.print("Content-Length: {d}\r\n", .{b.len});
        }

        // Connection: close for simplicity
        try writer.writeAll("Connection: close\r\n");

        // End of headers
        try writer.writeAll("\r\n");

        // Body
        if (body) |b| {
            try writer.writeAll(b);
        }

        // Send request
        _ = try tls_conn.write(request_buf.items);

        // Read response
        var response_buf: std.ArrayList(u8) = .{};
        defer response_buf.deinit(self.allocator);

        var read_buf: [4096]u8 = undefined;
        while (true) {
            const n = tls_conn.read(&read_buf) catch |err| {
                if (err == error.EndOfStream) break;
                return err;
            };
            if (n == 0) break;
            try response_buf.appendSlice(self.allocator, read_buf[0..n]);
        }

        return try self.parseResponse(response_buf.items);
    }

    fn requestPlain(
        self: *TlsHttpClient,
        stream: std.net.Stream,
        method: std.http.Method,
        uri: std.Uri,
        host: []const u8,
        headers: []const std.http.Header,
        body: ?[]const u8,
    ) !Response {
        _ = stream;
        _ = method;
        _ = uri;
        _ = host;
        _ = headers;
        _ = body;
        _ = self;
        return error.NotImplemented;
    }

    fn createCertKeyPair(self: *TlsHttpClient) !tls.config.CertKeyPair {
        const cert_pem = self.client_cert_pem.?;
        const key_pem = self.client_key_pem.?;

        // Parse client certificate into a bundle
        var cert_bundle: std.crypto.Certificate.Bundle = .{};
        errdefer cert_bundle.deinit(self.allocator);

        try self.parsePemCerts(&cert_bundle, cert_pem);

        // Convert RSA PRIVATE KEY (PKCS#1) to PRIVATE KEY (PKCS#8) if needed
        // tls.zig only supports PKCS#8 format
        const converted_key = try self.convertRsaKeyToPkcs8IfNeeded(key_pem);
        defer if (converted_key.ptr != key_pem.ptr) self.allocator.free(converted_key);

        // Parse private key from PEM
        const private_key = try tls.config.PrivateKey.parsePem(converted_key);

        return tls.config.CertKeyPair{
            .bundle = cert_bundle,
            .key = private_key,
        };
    }

    /// Convert RSA PRIVATE KEY (PKCS#1) to PRIVATE KEY (PKCS#8) format if needed
    /// Returns the original key if no conversion is needed, or a newly allocated converted key
    fn convertRsaKeyToPkcs8IfNeeded(self: *TlsHttpClient, key_pem: []const u8) ![]const u8 {
        // Check if this is an RSA PRIVATE KEY (PKCS#1 format)
        if (std.mem.indexOf(u8, key_pem, "-----BEGIN RSA PRIVATE KEY-----") == null) {
            // Not an RSA PRIVATE KEY, return as-is
            return key_pem;
        }

        // Use openssl to convert PKCS#1 to PKCS#8
        // This is a temporary solution - ideally we'd implement the conversion in Zig
        const temp_in = "/tmp/k8s_zig_temp_key_in.pem";
        const temp_out = "/tmp/k8s_zig_temp_key_out.pem";

        // Write input key
        {
            const file = try std.fs.createFileAbsolute(temp_in, .{});
            defer file.close();
            try file.writeAll(key_pem);
        }

        // Convert using openssl
        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                "openssl",
                "pkcs8",
                "-topk8",
                "-nocrypt",
                "-in",
                temp_in,
                "-out",
                temp_out,
            },
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.term != .Exited or result.term.Exited != 0) {
            return error.KeyConversionFailed;
        }

        // Read converted key
        const converted_file = try std.fs.openFileAbsolute(temp_out, .{});
        defer converted_file.close();
        const converted_key = try converted_file.readToEndAlloc(self.allocator, 4096);

        // Clean up temp files
        std.fs.deleteFileAbsolute(temp_in) catch {};
        std.fs.deleteFileAbsolute(temp_out) catch {};

        return converted_key;
    }

    /// Parse PEM-encoded certificates and add them to the bundle
    fn parsePemCerts(self: *TlsHttpClient, bundle: *std.crypto.Certificate.Bundle, pem_data: []const u8) !void {
        const begin_marker = "-----BEGIN CERTIFICATE-----";
        const end_marker = "-----END CERTIFICATE-----";
        const now_sec = std.time.timestamp();

        var start_index: usize = 0;
        while (std.mem.indexOfPos(u8, pem_data, start_index, begin_marker)) |begin_marker_start| {
            const cert_start = begin_marker_start + begin_marker.len;
            const cert_end = std.mem.indexOfPos(u8, pem_data, cert_start, end_marker) orelse
                return error.MissingEndCertificateMarker;
            start_index = cert_end + end_marker.len;

            // Extract the base64-encoded certificate and strip all whitespace
            const cert_with_ws = pem_data[cert_start..cert_end];
            const encoded_cert_buf = try self.allocator.alloc(u8, cert_with_ws.len);
            defer self.allocator.free(encoded_cert_buf);
            var encoded_len: usize = 0;
            for (cert_with_ws) |c| {
                if (c != ' ' and c != '\t' and c != '\n' and c != '\r') {
                    encoded_cert_buf[encoded_len] = c;
                    encoded_len += 1;
                }
            }
            const encoded_cert = encoded_cert_buf[0..encoded_len];

            // Decode the certificate
            const decoded_size = try std.base64.standard.Decoder.calcSizeForSlice(encoded_cert);
            try bundle.bytes.ensureUnusedCapacity(self.allocator, decoded_size);
            const decoded_start: u32 = @intCast(bundle.bytes.items.len);
            const dest_buf = bundle.bytes.allocatedSlice()[decoded_start..];
            try std.base64.standard.Decoder.decode(dest_buf, encoded_cert);
            bundle.bytes.items.len += decoded_size;

            // Parse and add the certificate
            try bundle.parseCert(self.allocator, decoded_start, now_sec);
        }
    }

    fn parseResponse(self: *TlsHttpClient, response_data: []const u8) !Response {
        // Find end of status line
        const status_line_end = std.mem.indexOf(u8, response_data, "\r\n") orelse return error.InvalidResponse;
        const status_line = response_data[0..status_line_end];

        // Parse status code
        // Format: "HTTP/1.1 200 OK"
        var status_parts = std.mem.tokenizeScalar(u8, status_line, ' ');
        _ = status_parts.next() orelse return error.InvalidResponse; // Skip HTTP version
        const status_code_str = status_parts.next() orelse return error.InvalidResponse;
        const status_code = try std.fmt.parseInt(u16, status_code_str, 10);

        // Find end of headers
        const headers_end = std.mem.indexOf(u8, response_data, "\r\n\r\n") orelse return error.InvalidResponse;
        const headers_section = response_data[status_line_end + 2 .. headers_end];

        // Parse headers
        var headers_map = std.StringHashMap([]const u8).init(self.allocator);
        errdefer headers_map.deinit();

        var headers_iter = std.mem.tokenizeSequence(u8, headers_section, "\r\n");
        while (headers_iter.next()) |header_line| {
            const colon_idx = std.mem.indexOf(u8, header_line, ":") orelse continue;
            const name = header_line[0..colon_idx];
            const value = std.mem.trim(u8, header_line[colon_idx + 1 ..], " ");
            try headers_map.put(name, value);
        }

        // Body starts after headers
        const body_start = headers_end + 4;
        const raw_body = response_data[body_start..];

        // Check if response is chunked
        const is_chunked = blk: {
            if (headers_map.get("Transfer-Encoding")) |te| {
                break :blk std.mem.eql(u8, te, "chunked");
            }
            break :blk false;
        };

        const body = if (is_chunked)
            try self.decodeChunkedBody(raw_body)
        else
            try self.allocator.dupe(u8, raw_body);

        return Response{
            .status = @enumFromInt(status_code),
            .headers = headers_map,
            .body = body,
            .allocator = self.allocator,
        };
    }

    /// Decode HTTP chunked transfer encoding
    fn decodeChunkedBody(self: *TlsHttpClient, chunked_data: []const u8) ![]const u8 {
        var result: std.ArrayList(u8) = .{};
        errdefer result.deinit(self.allocator);

        var pos: usize = 0;
        while (pos < chunked_data.len) {
            // Find end of chunk size line
            const size_line_end = std.mem.indexOfPos(u8, chunked_data, pos, "\r\n") orelse
                return error.InvalidChunkedEncoding;
            const size_line = chunked_data[pos..size_line_end];

            // Parse chunk size (hexadecimal)
            const chunk_size = std.fmt.parseInt(usize, size_line, 16) catch
                return error.InvalidChunkSize;

            // Move past size line
            pos = size_line_end + 2;

            // If chunk size is 0, we're done
            if (chunk_size == 0) break;

            // Read chunk data
            if (pos + chunk_size > chunked_data.len) return error.InvalidChunkedEncoding;
            try result.appendSlice(self.allocator, chunked_data[pos .. pos + chunk_size]);

            // Move past chunk data and trailing \r\n
            pos += chunk_size;
            if (pos + 2 > chunked_data.len) return error.InvalidChunkedEncoding;
            if (chunked_data[pos] != '\r' or chunked_data[pos + 1] != '\n')
                return error.InvalidChunkedEncoding;
            pos += 2;
        }

        return try result.toOwnedSlice(self.allocator);
    }
};
