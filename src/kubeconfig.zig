const std = @import("std");

/// Kubeconfig parser for loading Kubernetes cluster configuration
///
/// Supports loading configuration from kubeconfig files, typically located at ~/.kube/config.
/// This implementation supports JSON format kubeconfig files, which can be generated from
/// YAML using: kubectl config view --flatten -o json
/// A Kubernetes cluster configuration
pub const Cluster = struct {
    name: []const u8,
    server: []const u8,
    certificate_authority_data: ?[]const u8 = null,
    insecure_skip_tls_verify: bool = false,

    pub fn deinit(self: *Cluster, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.server);
        if (self.certificate_authority_data) |ca| allocator.free(ca);
    }
};

/// User authentication information
pub const User = struct {
    name: []const u8,
    token: ?[]const u8 = null,
    client_certificate_data: ?[]const u8 = null,
    client_key_data: ?[]const u8 = null,
    username: ?[]const u8 = null,
    password: ?[]const u8 = null,

    pub fn deinit(self: *User, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.token) |t| allocator.free(t);
        if (self.client_certificate_data) |c| allocator.free(c);
        if (self.client_key_data) |k| allocator.free(k);
        if (self.username) |u| allocator.free(u);
        if (self.password) |p| allocator.free(p);
    }
};

/// Context links a cluster with a user and optional namespace
pub const Context = struct {
    name: []const u8,
    cluster: []const u8,
    user: []const u8,
    namespace: ?[]const u8 = null,

    pub fn deinit(self: *Context, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.cluster);
        allocator.free(self.user);
        if (self.namespace) |ns| allocator.free(ns);
    }
};

/// Kubeconfig represents a complete Kubernetes configuration
pub const Kubeconfig = struct {
    allocator: std.mem.Allocator,
    clusters: []Cluster,
    users: []User,
    contexts: []Context,
    current_context: ?[]const u8,

    pub fn deinit(self: *Kubeconfig) void {
        for (self.clusters) |*cluster| {
            cluster.deinit(self.allocator);
        }
        self.allocator.free(self.clusters);

        for (self.users) |*user| {
            user.deinit(self.allocator);
        }
        self.allocator.free(self.users);

        for (self.contexts) |*context| {
            context.deinit(self.allocator);
        }
        self.allocator.free(self.contexts);

        if (self.current_context) |ctx| {
            self.allocator.free(ctx);
        }
    }

    /// Load kubeconfig from a JSON file
    ///
    /// Note: This expects JSON format. To convert YAML kubeconfig to JSON, use:
    /// kubectl config view --flatten -o json > ~/.kube/config.json
    pub fn fromJsonFile(allocator: std.mem.Allocator, path: []const u8) !Kubeconfig {
        const file = try std.fs.openFileAbsolute(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024); // 10MB max
        defer allocator.free(content);

        return try fromJson(allocator, content);
    }

    /// Parse kubeconfig from JSON content
    pub fn fromJson(allocator: std.mem.Allocator, json_content: []const u8) !Kubeconfig {
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            allocator,
            json_content,
            .{},
        );
        defer parsed.deinit();

        const root = parsed.value.object;

        // Parse clusters
        var clusters: std.ArrayList(Cluster) = .{};
        errdefer {
            for (clusters.items) |*c| c.deinit(allocator);
            clusters.deinit(allocator);
        }

        if (root.get("clusters")) |clusters_value| {
            for (clusters_value.array.items) |cluster_item| {
                const cluster_obj = cluster_item.object;
                const cluster_data = cluster_obj.get("cluster").?.object;

                try clusters.append(allocator, .{
                    .name = try allocator.dupe(u8, cluster_obj.get("name").?.string),
                    .server = try allocator.dupe(u8, cluster_data.get("server").?.string),
                    .certificate_authority_data = if (cluster_data.get("certificate-authority-data")) |ca|
                        try allocator.dupe(u8, ca.string)
                    else
                        null,
                    .insecure_skip_tls_verify = if (cluster_data.get("insecure-skip-tls-verify")) |skip|
                        skip.bool
                    else
                        false,
                });
            }
        }

        // Parse users
        var users: std.ArrayList(User) = .{};
        errdefer {
            for (users.items) |*u| u.deinit(allocator);
            users.deinit(allocator);
        }

        if (root.get("users")) |users_value| {
            for (users_value.array.items) |user_item| {
                const user_obj = user_item.object;
                const user_data = user_obj.get("user").?.object;

                try users.append(allocator, .{
                    .name = try allocator.dupe(u8, user_obj.get("name").?.string),
                    .token = if (user_data.get("token")) |t|
                        try allocator.dupe(u8, t.string)
                    else
                        null,
                    .client_certificate_data = if (user_data.get("client-certificate-data")) |c|
                        try allocator.dupe(u8, c.string)
                    else
                        null,
                    .client_key_data = if (user_data.get("client-key-data")) |k|
                        try allocator.dupe(u8, k.string)
                    else
                        null,
                    .username = if (user_data.get("username")) |u|
                        try allocator.dupe(u8, u.string)
                    else
                        null,
                    .password = if (user_data.get("password")) |p|
                        try allocator.dupe(u8, p.string)
                    else
                        null,
                });
            }
        }

        // Parse contexts
        var contexts: std.ArrayList(Context) = .{};
        errdefer {
            for (contexts.items) |*c| c.deinit(allocator);
            contexts.deinit(allocator);
        }

        if (root.get("contexts")) |contexts_value| {
            for (contexts_value.array.items) |context_item| {
                const context_obj = context_item.object;
                const context_data = context_obj.get("context").?.object;

                try contexts.append(allocator, .{
                    .name = try allocator.dupe(u8, context_obj.get("name").?.string),
                    .cluster = try allocator.dupe(u8, context_data.get("cluster").?.string),
                    .user = try allocator.dupe(u8, context_data.get("user").?.string),
                    .namespace = if (context_data.get("namespace")) |ns|
                        try allocator.dupe(u8, ns.string)
                    else
                        null,
                });
            }
        }

        // Get current context
        const current_context = if (root.get("current-context")) |ctx|
            try allocator.dupe(u8, ctx.string)
        else
            null;

        return Kubeconfig{
            .allocator = allocator,
            .clusters = try clusters.toOwnedSlice(allocator),
            .users = try users.toOwnedSlice(allocator),
            .contexts = try contexts.toOwnedSlice(allocator),
            .current_context = current_context,
        };
    }

    /// Get the current context
    pub fn getCurrentContext(self: *const Kubeconfig) ?*const Context {
        if (self.current_context) |name| {
            for (self.contexts) |*ctx| {
                if (std.mem.eql(u8, ctx.name, name)) {
                    return ctx;
                }
            }
        }
        return null;
    }

    /// Get a cluster by name
    pub fn getCluster(self: *const Kubeconfig, name: []const u8) ?*const Cluster {
        for (self.clusters) |*cluster| {
            if (std.mem.eql(u8, cluster.name, name)) {
                return cluster;
            }
        }
        return null;
    }

    /// Get a user by name
    pub fn getUser(self: *const Kubeconfig, name: []const u8) ?*const User {
        for (self.users) |*user| {
            if (std.mem.eql(u8, user.name, name)) {
                return user;
            }
        }
        return null;
    }

    /// Get a context by name
    pub fn getContext(self: *const Kubeconfig, name: []const u8) ?*const Context {
        for (self.contexts) |*ctx| {
            if (std.mem.eql(u8, ctx.name, name)) {
                return ctx;
            }
        }
        return null;
    }
};

test "kubeconfig structure" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var config = Kubeconfig{
        .allocator = allocator,
        .clusters = &[_]Cluster{},
        .users = &[_]User{},
        .contexts = &[_]Context{},
        .current_context = null,
    };
    defer config.deinit();

    try testing.expect(config.clusters.len == 0);
}
