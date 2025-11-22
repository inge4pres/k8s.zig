const std = @import("std");

const ApiPaths = @import("api_paths.zig").ApiPaths;
const Config = @import("config.zig").Config;
const HttpClient = @import("http_client.zig").HttpClient;

pub const Client = @This();
/// Kubernetes API Client
///
/// Provides methods to interact with Kubernetes resources through the API server.
allocator: std.mem.Allocator,
base_url: []const u8,
http_client: HttpClient,
api_paths: ApiPaths,
auth_token: ?[]const u8 = null,
// Track whether we own the base_url and auth_token memory
owns_base_url: bool,
owns_auth_token: bool,

pub const TLSOptions = struct {
    /// Base64-encoded PEM certificate data for the CA
    certificate_authority_data: ?[]const u8 = null,
    /// Base64-encoded PEM certificate data for client authentication
    client_certificate_data: ?[]const u8 = null,
    /// Base64-encoded PEM private key data for client authentication
    client_key_data: ?[]const u8 = null,
    /// Skip TLS certificate verification (insecure)
    insecure_skip_tls_verify: bool = false,
};

pub fn init(allocator: std.mem.Allocator, base_url: []const u8, options: TLSOptions) !Client {
    return Client{
        .allocator = allocator,
        .base_url = base_url,
        .http_client = try HttpClient.init(allocator, .{
            .certificate_authority_data = options.certificate_authority_data,
            .client_certificate_data = options.client_certificate_data,
            .client_key_data = options.client_key_data,
            .insecure_skip_tls_verify = options.insecure_skip_tls_verify,
        }),
        .api_paths = ApiPaths.init(allocator, base_url),
        .owns_base_url = false,
        .owns_auth_token = false,
    };
}

pub fn deinit(self: *Client) void {
    self.http_client.deinit();
    if (self.owns_base_url) {
        self.allocator.free(self.base_url);
    }
    if (self.owns_auth_token) {
        if (self.auth_token) |token| {
            self.allocator.free(token);
        }
    }
}

/// Set the bearer token for authentication
pub fn setAuthToken(self: *Client, token: []const u8) void {
    self.auth_token = token;
}

/// Build authorization header value
fn getAuthHeader(self: *Client) !?[]const u8 {
    if (self.auth_token) |token| {
        return try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{token});
    }
    return null;
}

/// Get a resource by name
pub fn get(
    self: *Client,
    path: []const u8,
    accept: HttpClient.ContentType,
) !HttpClient.Response {
    const auth = try self.getAuthHeader();
    defer if (auth) |a| self.allocator.free(a);

    return self.http_client.get(path, auth, accept);
}

/// Create a resource
pub fn create(
    self: *Client,
    path: []const u8,
    body: []const u8,
    content_type: HttpClient.ContentType,
) !HttpClient.Response {
    const auth = try self.getAuthHeader();
    defer if (auth) |a| self.allocator.free(a);

    return self.http_client.post(path, body, auth, content_type);
}

/// Update a resource (PUT)
pub fn update(
    self: *Client,
    path: []const u8,
    body: []const u8,
    content_type: HttpClient.ContentType,
) !HttpClient.Response {
    const auth = try self.getAuthHeader();
    defer if (auth) |a| self.allocator.free(a);

    return self.http_client.put(path, body, auth, content_type);
}

/// Patch a resource
pub fn patch(
    self: *Client,
    path: []const u8,
    body: []const u8,
    content_type: HttpClient.ContentType,
) !HttpClient.Response {
    const auth = try self.getAuthHeader();
    defer if (auth) |a| self.allocator.free(a);

    return self.http_client.patch(path, body, auth, content_type);
}

/// Delete a resource
pub fn delete(
    self: *Client,
    path: []const u8,
    accept: HttpClient.ContentType,
) !HttpClient.Response {
    const auth = try self.getAuthHeader();
    defer if (auth) |a| self.allocator.free(a);

    return self.http_client.delete(path, auth, accept);
}

// Convenience methods for common resources

/// List pods in a namespace
pub fn listPods(self: *Client, namespace: []const u8) !HttpClient.Response {
    const path = try self.api_paths.pods(namespace, null);
    defer self.allocator.free(path);
    return self.get(path, .json);
}

/// Get a pod by name
pub fn getPod(self: *Client, namespace: []const u8, name: []const u8) !HttpClient.Response {
    const path = try self.api_paths.pods(namespace, name);
    defer self.allocator.free(path);
    return self.get(path, .json);
}

/// List deployments in a namespace
pub fn listDeployments(self: *Client, namespace: []const u8) !HttpClient.Response {
    const path = try self.api_paths.deployments(namespace, null);
    defer self.allocator.free(path);
    return self.get(path, .json);
}

/// Get a deployment by name
pub fn getDeployment(self: *Client, namespace: []const u8, name: []const u8) !HttpClient.Response {
    const path = try self.api_paths.deployments(namespace, name);
    defer self.allocator.free(path);
    return self.get(path, .json);
}

test "client initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var client = try Client.init(allocator, "https://kubernetes.default.svc", .{});
    defer client.deinit();

    try testing.expectEqualStrings("https://kubernetes.default.svc", client.base_url);
}

test "client with system TLS - no memory leak" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Using system CA bundle (no custom certs)
    // This tests the common case where the system CA bundle is loaded
    var client = try Client.init(allocator, "https://kubernetes.default.svc", .{
        .insecure_skip_tls_verify = false,
    });
    defer client.deinit();

    try testing.expectEqualStrings("https://kubernetes.default.svc", client.base_url);
}

test "client from config - no memory leak" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create a Config with allocated strings (using system CA bundle)
    // This tests that fromConfig() properly duplicates strings and allows Config to be freed
    var config = Config{
        .allocator = allocator,
        .server = try allocator.dupe(u8, "https://test-cluster.example.com"),
        .namespace = try allocator.dupe(u8, "default"),
        .token = try allocator.dupe(u8, "test-token-12345"),
    };
    defer config.deinit();

    var client = try fromConfig(&config);
    defer client.deinit();

    try testing.expectEqualStrings("https://test-cluster.example.com", client.base_url);
    try testing.expect(client.owns_base_url);
    try testing.expect(client.owns_auth_token);
}

test "client from config without token - no memory leak" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test with no auth token to verify proper ownership tracking
    var config = Config{
        .allocator = allocator,
        .server = try allocator.dupe(u8, "https://test-cluster.example.com"),
        .namespace = try allocator.dupe(u8, "default"),
    };
    defer config.deinit();

    var client = try fromConfig(&config);
    defer client.deinit();

    try testing.expectEqualStrings("https://test-cluster.example.com", client.base_url);
    try testing.expect(client.owns_base_url);
    try testing.expect(!client.owns_auth_token);
    try testing.expect(client.auth_token == null);
}

// Create a Kubernetes client from a Config
fn fromConfig(config: *const Config) !Client {
    // Duplicate the base_url so we own it and can free the config
    const owned_base_url = try config.allocator.dupe(u8, config.server);
    errdefer config.allocator.free(owned_base_url);

    var client = try Client.init(config.allocator, owned_base_url, .{
        .certificate_authority_data = config.certificate_authority_data,
        .client_certificate_data = config.client_certificate_data,
        .client_key_data = config.client_key_data,
        .insecure_skip_tls_verify = config.insecure_skip_tls_verify,
    });
    client.owns_base_url = true;

    // Duplicate and set authentication token if available
    if (config.token) |token| {
        const owned_token = try config.allocator.dupe(u8, token);
        client.auth_token = owned_token;
        client.owns_auth_token = true;
    }

    return client;
}

/// Create a Kubernetes client from a kubeconfig file using the current context
pub fn fromKubeconfigJSONFile(allocator: std.mem.Allocator, path: []const u8) !Client {
    var config = try Config.fromKubeconfigJSONFile(allocator, path);
    defer config.deinit();

    // fromConfig will duplicate the strings it needs, so we can safely free the config
    return fromConfig(&config);
}

/// Create a Kubernetes client from in-cluster configuration
pub fn inCluster(allocator: std.mem.Allocator) !Client {
    var config = try Config.inCluster(allocator);
    defer config.deinit();

    // fromConfig will duplicate the strings it needs, so we can safely free the config
    return fromConfig(&config);
}
