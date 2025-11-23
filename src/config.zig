const std = @import("std");
const Kubeconfig = @import("kubeconfig.zig").Kubeconfig;

/// Kubernetes configuration
///
/// Represents connection and authentication configuration for a Kubernetes cluster.
/// Can be loaded from kubeconfig files or constructed programmatically.
pub const Config = struct {
    allocator: std.mem.Allocator,
    server: []const u8,
    namespace: []const u8,
    token: ?[]const u8 = null,
    certificate_authority_data: ?[]const u8 = null,
    client_certificate_data: ?[]const u8 = null,
    client_key_data: ?[]const u8 = null,
    insecure_skip_tls_verify: bool = false,

    pub fn init(allocator: std.mem.Allocator, server: []const u8, namespace: []const u8) !Config {
        return Config{
            .allocator = allocator,
            .server = try allocator.dupe(u8, server),
            .namespace = try allocator.dupe(u8, namespace),
        };
    }

    pub fn deinit(self: *Config) void {
        self.allocator.free(self.server);
        self.allocator.free(self.namespace);
        if (self.token) |t| {
            self.allocator.free(t);
        }
        if (self.certificate_authority_data) |ca| {
            self.allocator.free(ca);
        }
        if (self.client_certificate_data) |cert| {
            self.allocator.free(cert);
        }
        if (self.client_key_data) |key| {
            self.allocator.free(key);
        }
    }

    /// Load configuration from a kubeconfig YAML file and use the current context
    ///
    /// This is the preferred method for loading standard kubeconfig files.
    pub fn fromKubeconfigFile(allocator: std.mem.Allocator, path: []const u8) !Config {
        var kubeconfig = try Kubeconfig.fromYamlFile(allocator, path);
        defer kubeconfig.deinit();

        return try fromKubeconfig(allocator, &kubeconfig, null);
    }

    /// Load configuration from a kubeconfig YAML file with a specific context
    pub fn fromKubeconfigFileWithContext(
        allocator: std.mem.Allocator,
        path: []const u8,
        context_name: []const u8,
    ) !Config {
        var kubeconfig = try Kubeconfig.fromYamlFile(allocator, path);
        defer kubeconfig.deinit();

        return try fromKubeconfig(allocator, &kubeconfig, context_name);
    }

    /// Load configuration from a kubeconfig JSON file and use the current context
    ///
    /// Note: Expects JSON format. Convert YAML to JSON using:
    /// kubectl config view --flatten -o json > ~/.kube/config.json
    pub fn fromKubeconfigJSONFile(allocator: std.mem.Allocator, path: []const u8) !Config {
        var kubeconfig = try Kubeconfig.fromJsonFile(allocator, path);
        defer kubeconfig.deinit();

        return try fromKubeconfig(allocator, &kubeconfig, null);
    }

    /// Load configuration from a kubeconfig JSON file with a specific context
    pub fn fromKubeconfigJSONFileWithContext(
        allocator: std.mem.Allocator,
        path: []const u8,
        context_name: []const u8,
    ) !Config {
        var kubeconfig = try Kubeconfig.fromJsonFile(allocator, path);
        defer kubeconfig.deinit();

        return try fromKubeconfig(allocator, &kubeconfig, context_name);
    }

    /// Create Config from a Kubeconfig
    pub fn fromKubeconfig(
        allocator: std.mem.Allocator,
        kubeconfig: *const Kubeconfig,
        context_name: ?[]const u8,
    ) !Config {
        // Get the context
        const context = if (context_name) |name|
            kubeconfig.getContext(name) orelse return error.ContextNotFound
        else
            kubeconfig.getCurrentContext() orelse return error.NoCurrentContext;

        // Get cluster
        const cluster = kubeconfig.getCluster(context.cluster) orelse return error.ClusterNotFound;

        // Get user
        const user = kubeconfig.getUser(context.user) orelse return error.UserNotFound;

        // Determine namespace (use context namespace or default to "default")
        const namespace = context.namespace orelse "default";

        return Config{
            .allocator = allocator,
            .server = try allocator.dupe(u8, cluster.server),
            .namespace = try allocator.dupe(u8, namespace),
            .token = if (user.token) |t| try allocator.dupe(u8, t) else null,
            .certificate_authority_data = if (cluster.certificate_authority_data) |ca| try allocator.dupe(u8, ca) else null,
            .client_certificate_data = if (user.client_certificate_data) |cert| try allocator.dupe(u8, cert) else null,
            .client_key_data = if (user.client_key_data) |key| try allocator.dupe(u8, key) else null,
            .insecure_skip_tls_verify = cluster.insecure_skip_tls_verify,
        };
    }

    /// Load in-cluster configuration (for use inside a Kubernetes pod)
    pub fn inCluster(allocator: std.mem.Allocator) !Config {
        const token_path = "/var/run/secrets/kubernetes.io/serviceaccount/token";
        const namespace_path = "/var/run/secrets/kubernetes.io/serviceaccount/namespace";

        // Read token
        const token_file = try std.fs.openFileAbsolute(token_path, .{});
        defer token_file.close();
        const token = try token_file.readToEndAlloc(allocator, 4096);
        errdefer allocator.free(token);

        // Read namespace
        const namespace_file = try std.fs.openFileAbsolute(namespace_path, .{});
        defer namespace_file.close();
        const namespace = try namespace_file.readToEndAlloc(allocator, 256);
        errdefer allocator.free(namespace);

        // Kubernetes API server is always at this address in-cluster
        const server = try allocator.dupe(u8, "https://kubernetes.default.svc");

        return Config{
            .allocator = allocator,
            .server = server,
            .namespace = namespace,
            .token = token,
        };
    }
};

test "config initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var config = try Config.init(allocator, "https://kubernetes.default.svc", "default");
    defer config.deinit();

    try testing.expectEqualStrings("https://kubernetes.default.svc", config.server);
    try testing.expectEqualStrings("default", config.namespace);
}
