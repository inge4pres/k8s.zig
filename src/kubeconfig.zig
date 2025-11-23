const std = @import("std");
const yaml = @import("yaml");

/// Kubeconfig parser for loading Kubernetes cluster configuration
///
/// Supports loading configuration from kubeconfig files, typically located at ~/.kube/config.
/// This implementation supports both YAML and JSON format kubeconfig files.
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

                // Try certificate-authority-data first (inline base64), then certificate-authority (file path)
                const ca_data = if (cluster_data.get("certificate-authority-data")) |ca|
                    try allocator.dupe(u8, ca.string)
                else if (cluster_data.get("certificate-authority")) |ca_file|
                    try readAndEncodeCertFile(allocator, ca_file.string)
                else
                    null;

                try clusters.append(allocator, .{
                    .name = try allocator.dupe(u8, cluster_obj.get("name").?.string),
                    .server = try allocator.dupe(u8, cluster_data.get("server").?.string),
                    .certificate_authority_data = ca_data,
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

                // Try client-certificate-data first (inline base64), then client-certificate (file path)
                const cert_data = if (user_data.get("client-certificate-data")) |c|
                    try allocator.dupe(u8, c.string)
                else if (user_data.get("client-certificate")) |cert_file|
                    try readAndEncodeCertFile(allocator, cert_file.string)
                else
                    null;

                // Try client-key-data first (inline base64), then client-key (file path)
                const key_data = if (user_data.get("client-key-data")) |k|
                    try allocator.dupe(u8, k.string)
                else if (user_data.get("client-key")) |key_file|
                    try readAndEncodeCertFile(allocator, key_file.string)
                else
                    null;

                try users.append(allocator, .{
                    .name = try allocator.dupe(u8, user_obj.get("name").?.string),
                    .token = if (user_data.get("token")) |t|
                        try allocator.dupe(u8, t.string)
                    else
                        null,
                    .client_certificate_data = cert_data,
                    .client_key_data = key_data,
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

    /// Load kubeconfig from a YAML file
    ///
    /// This is the preferred method for loading standard kubeconfig files.
    pub fn fromYamlFile(allocator: std.mem.Allocator, path: []const u8) !Kubeconfig {
        var parsed = try yaml.parseFromFile(allocator, path);
        defer parsed.deinit();

        return try fromYaml(allocator, &parsed.value);
    }

    /// Helper function to read a certificate file and encode it as base64
    fn readAndEncodeCertFile(allocator: std.mem.Allocator, file_path: []const u8) ![]const u8 {
        const file = try std.fs.openFileAbsolute(file_path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024); // 10MB max
        defer allocator.free(content);

        // Encode to base64
        const encoder = std.base64.standard.Encoder;
        const encoded_len = encoder.calcSize(content.len);
        const encoded = try allocator.alloc(u8, encoded_len);
        _ = encoder.encode(encoded, content);

        return encoded;
    }

    /// Parse kubeconfig from YAML content
    pub fn fromYaml(allocator: std.mem.Allocator, yaml_value: *yaml.Value) !Kubeconfig {
        var root = yaml_value.asMapping() orelse return error.InvalidFormat;

        // Parse clusters
        var clusters: std.ArrayList(Cluster) = .{};
        errdefer {
            for (clusters.items) |*c| c.deinit(allocator);
            clusters.deinit(allocator);
        }

        if (root.get("clusters")) |clusters_value_const| {
            var clusters_value_mut = clusters_value_const;
            const clusters_seq = clusters_value_mut.asSequence() orelse return error.InvalidFormat;

            for (clusters_seq.items) |*cluster_item| {
                var cluster_obj = cluster_item.asMapping() orelse continue;

                const name = if (cluster_obj.get("name")) |n|
                    n.asString() orelse continue
                else
                    continue;

                if (cluster_obj.get("cluster")) |cluster_data_const| {
                    var cluster_data_mut = cluster_data_const;
                    var cluster_map = cluster_data_mut.asMapping() orelse continue;

                    const server = if (cluster_map.get("server")) |s|
                        s.asString() orelse continue
                    else
                        continue;

                    // Try certificate-authority-data first (inline base64), then certificate-authority (file path)
                    const ca_data = if (cluster_map.get("certificate-authority-data")) |ca|
                        if (ca.asString()) |s| try allocator.dupe(u8, s) else null
                    else if (cluster_map.get("certificate-authority")) |ca_file|
                        if (ca_file.asString()) |path| try readAndEncodeCertFile(allocator, path) else null
                    else
                        null;

                    const insecure = if (cluster_map.get("insecure-skip-tls-verify")) |skip|
                        skip.asBool() orelse false
                    else
                        false;

                    try clusters.append(allocator, .{
                        .name = try allocator.dupe(u8, name),
                        .server = try allocator.dupe(u8, server),
                        .certificate_authority_data = ca_data,
                        .insecure_skip_tls_verify = insecure,
                    });
                }
            }
        }

        // Parse users
        var users: std.ArrayList(User) = .{};
        errdefer {
            for (users.items) |*u| u.deinit(allocator);
            users.deinit(allocator);
        }

        if (root.get("users")) |users_value_const| {
            var users_value_mut = users_value_const;
            const users_seq = users_value_mut.asSequence() orelse return error.InvalidFormat;

            for (users_seq.items) |*user_item| {
                var user_obj = user_item.asMapping() orelse continue;

                const name = if (user_obj.get("name")) |n|
                    n.asString() orelse continue
                else
                    continue;

                if (user_obj.get("user")) |user_data_const| {
                    var user_data_mut = user_data_const;
                    var user_map = user_data_mut.asMapping() orelse continue;

                    const token = if (user_map.get("token")) |t| t.asString() else null;

                    // Try client-certificate-data first (inline base64), then client-certificate (file path)
                    const cert_data = if (user_map.get("client-certificate-data")) |c|
                        if (c.asString()) |s| try allocator.dupe(u8, s) else null
                    else if (user_map.get("client-certificate")) |cert_file|
                        if (cert_file.asString()) |path| try readAndEncodeCertFile(allocator, path) else null
                    else
                        null;

                    // Try client-key-data first (inline base64), then client-key (file path)
                    const key_data = if (user_map.get("client-key-data")) |k|
                        if (k.asString()) |s| try allocator.dupe(u8, s) else null
                    else if (user_map.get("client-key")) |key_file|
                        if (key_file.asString()) |path| try readAndEncodeCertFile(allocator, path) else null
                    else
                        null;

                    const username = if (user_map.get("username")) |u| u.asString() else null;
                    const password = if (user_map.get("password")) |p| p.asString() else null;

                    try users.append(allocator, .{
                        .name = try allocator.dupe(u8, name),
                        .token = if (token) |t| try allocator.dupe(u8, t) else null,
                        .client_certificate_data = cert_data,
                        .client_key_data = key_data,
                        .username = if (username) |u| try allocator.dupe(u8, u) else null,
                        .password = if (password) |p| try allocator.dupe(u8, p) else null,
                    });
                }
            }
        }

        // Parse contexts
        var contexts: std.ArrayList(Context) = .{};
        errdefer {
            for (contexts.items) |*c| c.deinit(allocator);
            contexts.deinit(allocator);
        }

        if (root.get("contexts")) |contexts_value_const| {
            var contexts_value_mut = contexts_value_const;
            const contexts_seq = contexts_value_mut.asSequence() orelse return error.InvalidFormat;

            for (contexts_seq.items) |*context_item| {
                var context_obj = context_item.asMapping() orelse continue;

                const name = if (context_obj.get("name")) |n|
                    n.asString() orelse continue
                else
                    continue;

                if (context_obj.get("context")) |context_data_const| {
                    var context_data_mut = context_data_const;
                    var context_map = context_data_mut.asMapping() orelse continue;

                    const cluster = if (context_map.get("cluster")) |c|
                        c.asString() orelse continue
                    else
                        continue;

                    const user = if (context_map.get("user")) |u|
                        u.asString() orelse continue
                    else
                        continue;

                    const namespace = if (context_map.get("namespace")) |ns| ns.asString() else null;

                    try contexts.append(allocator, .{
                        .name = try allocator.dupe(u8, name),
                        .cluster = try allocator.dupe(u8, cluster),
                        .user = try allocator.dupe(u8, user),
                        .namespace = if (namespace) |ns| try allocator.dupe(u8, ns) else null,
                    });
                }
            }
        }

        // Get current context
        const current_context = if (root.get("current-context")) |ctx|
            if (ctx.asString()) |s| try allocator.dupe(u8, s) else null
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
