const std = @import("std");
const TlsHttpClient = @import("tls_http_client.zig").TlsHttpClient;

/// HTTP client for making requests to the Kubernetes API server
pub const HttpClient = struct {
    allocator: std.mem.Allocator,
    tls_client: TlsHttpClient,

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

    pub fn init(allocator: std.mem.Allocator, options: InitOptions) !HttpClient {
        var ca_bundle: std.crypto.Certificate.Bundle = .{};
        var has_custom_ca = false;

        // Load CA bundle
        if (options.certificate_authority_data) |ca_data_b64| {
            has_custom_ca = true;
            // Use custom CA certificate from kubeconfig
            // Decode base64 CA data to get PEM content
            // Strip whitespace from base64 data as kubeconfig may contain newlines
            const stripped = try allocator.alloc(u8, ca_data_b64.len);
            defer allocator.free(stripped);
            var stripped_len: usize = 0;
            for (ca_data_b64) |c| {
                if (c != ' ' and c != '\t' and c != '\n' and c != '\r') {
                    stripped[stripped_len] = c;
                    stripped_len += 1;
                }
            }

            const decoded_size = try std.base64.standard.Decoder.calcSizeForSlice(stripped[0..stripped_len]);
            const ca_pem = try allocator.alloc(u8, decoded_size);
            defer allocator.free(ca_pem);

            try std.base64.standard.Decoder.decode(ca_pem, stripped[0..stripped_len]);

            // Initialize bundle and parse PEM certificates
            try parsePemCerts(&ca_bundle, allocator, ca_pem);
        } else if (!options.insecure_skip_tls_verify) {
            // Use system CA bundle
            try ca_bundle.rescan(allocator);
        }
        // Note: When insecure_skip_tls_verify is true and no CA cert is provided,
        // we leave the bundle empty. This won't fully disable TLS verification
        // (Zig doesn't support that), but it's the closest we can get.

        // Decode client certificate and key if provided
        const client_cert_pem = if (options.client_certificate_data) |cert_b64| blk: {
            // Strip whitespace from base64 data as kubeconfig may contain newlines
            const stripped = try allocator.alloc(u8, cert_b64.len);
            defer allocator.free(stripped);
            var stripped_len: usize = 0;
            for (cert_b64) |c| {
                if (c != ' ' and c != '\t' and c != '\n' and c != '\r') {
                    stripped[stripped_len] = c;
                    stripped_len += 1;
                }
            }

            const decoded_size = try std.base64.standard.Decoder.calcSizeForSlice(stripped[0..stripped_len]);
            const pem = try allocator.alloc(u8, decoded_size);
            try std.base64.standard.Decoder.decode(pem, stripped[0..stripped_len]);
            break :blk pem;
        } else null;

        const client_key_pem = if (options.client_key_data) |key_b64| blk: {
            // Strip whitespace from base64 data as kubeconfig may contain newlines
            const stripped = try allocator.alloc(u8, key_b64.len);
            defer allocator.free(stripped);
            var stripped_len: usize = 0;
            for (key_b64) |c| {
                if (c != ' ' and c != '\t' and c != '\n' and c != '\r') {
                    stripped[stripped_len] = c;
                    stripped_len += 1;
                }
            }

            const decoded_size = try std.base64.standard.Decoder.calcSizeForSlice(stripped[0..stripped_len]);
            const pem = try allocator.alloc(u8, decoded_size);
            try std.base64.standard.Decoder.decode(pem, stripped[0..stripped_len]);
            break :blk pem;
        } else null;

        const tls_client = TlsHttpClient.init(allocator, ca_bundle, has_custom_ca, client_cert_pem, client_key_pem);

        return .{
            .allocator = allocator,
            .tls_client = tls_client,
        };
    }

    /// Parse PEM-encoded certificates and add them to the CA bundle
    fn parsePemCerts(bundle: *std.crypto.Certificate.Bundle, gpa: std.mem.Allocator, pem_data: []const u8) !void {
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
            const encoded_cert_buf = try gpa.alloc(u8, cert_with_ws.len);
            defer gpa.free(encoded_cert_buf);
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
            try bundle.bytes.ensureUnusedCapacity(gpa, decoded_size);
            const decoded_start: u32 = @intCast(bundle.bytes.items.len);
            const dest_buf = bundle.bytes.allocatedSlice()[decoded_start..];
            try std.base64.standard.Decoder.decode(dest_buf, encoded_cert);
            bundle.bytes.items.len += decoded_size;

            // Parse and add the certificate
            try bundle.parseCert(gpa, decoded_start, now_sec);
        }
    }

    pub fn deinit(self: *HttpClient) void {
        self.tls_client.deinit();
    }

    /// HTTP request method
    pub const Method = enum {
        GET,
        POST,
        PUT,
        PATCH,
        DELETE,

        pub fn toStdMethod(self: Method) std.http.Method {
            return switch (self) {
                .GET => .GET,
                .POST => .POST,
                .PUT => .PUT,
                .PATCH => .PATCH,
                .DELETE => .DELETE,
            };
        }
    };

    /// Content type for Kubernetes API requests
    pub const ContentType = enum {
        json,
        protobuf,

        pub fn toString(self: ContentType) []const u8 {
            return switch (self) {
                .json => "application/json",
                .protobuf => "application/vnd.kubernetes.protobuf",
            };
        }
    };

    /// Options for making HTTP requests
    pub const RequestOptions = struct {
        method: Method,
        url: []const u8,
        body: ?[]const u8 = null,
        content_type: ContentType = .json,
        accept: ContentType = .json,
        authorization: ?[]const u8 = null,
        extra_headers: ?[]const std.http.Header = null,
    };

    /// HTTP response
    pub const Response = struct {
        status: std.http.Status,
        body: []const u8,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *Response) void {
            self.allocator.free(self.body);
        }
    };

    /// Make an HTTP request to the Kubernetes API
    pub fn request(self: *HttpClient, options: RequestOptions) !Response {
        // Prepare headers list
        var headers_list: std.ArrayList(std.http.Header) = .{};
        defer headers_list.deinit(self.allocator);

        // Add Accept header
        try headers_list.append(self.allocator, .{
            .name = "Accept",
            .value = options.accept.toString(),
        });

        // Add Content-Type if we have a body
        if (options.body != null) {
            try headers_list.append(self.allocator, .{
                .name = "Content-Type",
                .value = options.content_type.toString(),
            });
        }

        // Add Authorization header
        if (options.authorization) |auth| {
            try headers_list.append(self.allocator, .{
                .name = "Authorization",
                .value = auth,
            });
        }

        // Add extra headers
        if (options.extra_headers) |extra| {
            try headers_list.appendSlice(self.allocator, extra);
        }

        // Make request using TlsHttpClient
        var tls_response = try self.tls_client.request(
            options.method.toStdMethod(),
            options.url,
            headers_list.items,
            options.body,
        );
        defer tls_response.deinit();

        // Copy response body (tls_response will be deinitialized)
        const response_body = try self.allocator.dupe(u8, tls_response.body);

        return Response{
            .status = tls_response.status,
            .body = response_body,
            .allocator = self.allocator,
        };
    }

    /// Helper for GET requests
    pub fn get(self: *HttpClient, url: []const u8, auth: ?[]const u8, accept: ContentType) !Response {
        return self.request(.{
            .method = .GET,
            .url = url,
            .authorization = auth,
            .accept = accept,
        });
    }

    /// Helper for POST requests
    pub fn post(
        self: *HttpClient,
        url: []const u8,
        body: []const u8,
        auth: ?[]const u8,
        content_type: ContentType,
    ) !Response {
        return self.request(.{
            .method = .POST,
            .url = url,
            .body = body,
            .authorization = auth,
            .content_type = content_type,
            .accept = content_type,
        });
    }

    /// Helper for PUT requests
    pub fn put(
        self: *HttpClient,
        url: []const u8,
        body: []const u8,
        auth: ?[]const u8,
        content_type: ContentType,
    ) !Response {
        return self.request(.{
            .method = .PUT,
            .url = url,
            .body = body,
            .authorization = auth,
            .content_type = content_type,
            .accept = content_type,
        });
    }

    /// Helper for PATCH requests
    pub fn patch(
        self: *HttpClient,
        url: []const u8,
        body: []const u8,
        auth: ?[]const u8,
        content_type: ContentType,
    ) !Response {
        return self.request(.{
            .method = .PATCH,
            .url = url,
            .body = body,
            .authorization = auth,
            .content_type = content_type,
            .accept = content_type,
        });
    }

    /// Helper for DELETE requests
    pub fn delete(self: *HttpClient, url: []const u8, auth: ?[]const u8, accept: ContentType) !Response {
        return self.request(.{
            .method = .DELETE,
            .url = url,
            .authorization = auth,
            .accept = accept,
        });
    }
};

test "HttpClient initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var client = try HttpClient.init(allocator, .{});
    defer client.deinit();
}

test "ContentType toString" {
    const testing = std.testing;
    try testing.expectEqualStrings("application/json", HttpClient.ContentType.json.toString());
    try testing.expectEqualStrings("application/vnd.kubernetes.protobuf", HttpClient.ContentType.protobuf.toString());
}
