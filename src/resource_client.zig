const std = @import("std");
const Client = @import("client.zig").Client;
const HttpClient = @import("http_client.zig").HttpClient;

/// Enum of known Kubernetes resource types
const ResourceType = enum {
    // Core API (v1) resources
    Pod,
    Service,
    ConfigMap,
    Secret,
    Namespace,
    Node,
    PersistentVolume,
    PersistentVolumeClaim,
    ServiceAccount,
    Endpoints,
    Event,
    LimitRange,
    ResourceQuota,
    // apps/v1 resources
    Deployment,
    StatefulSet,
    DaemonSet,
    ReplicaSet,
    // batch/v1 resources
    Job,
    CronJob,
    // networking.k8s.io/v1 resources
    Ingress,
    NetworkPolicy,
    // rbac.authorization.k8s.io/v1 resources
    Role,
    RoleBinding,
    ClusterRole,
    ClusterRoleBinding,
    // storage.k8s.io/v1 resources
    StorageClass,
    VolumeAttachment,
    // policy/v1 resources
    PodDisruptionBudget,
    // autoscaling/v2 resources
    HorizontalPodAutoscaler,

    /// Get metadata for this resource type
    pub fn getMetadata(self: ResourceType) ResourceMetadata {
        return switch (self) {
            // Core API (v1) resources
            .Pod => .{ .resource_name = "pods", .api_version = "v1" },
            .Service => .{ .resource_name = "services", .api_version = "v1" },
            .ConfigMap => .{ .resource_name = "configmaps", .api_version = "v1" },
            .Secret => .{ .resource_name = "secrets", .api_version = "v1" },
            .Namespace => .{ .resource_name = "namespaces", .api_version = "v1" },
            .Node => .{ .resource_name = "nodes", .api_version = "v1" },
            .PersistentVolume => .{ .resource_name = "persistentvolumes", .api_version = "v1" },
            .PersistentVolumeClaim => .{ .resource_name = "persistentvolumeclaims", .api_version = "v1" },
            .ServiceAccount => .{ .resource_name = "serviceaccounts", .api_version = "v1" },
            .Endpoints => .{ .resource_name = "endpoints", .api_version = "v1" },
            .Event => .{ .resource_name = "events", .api_version = "v1" },
            .LimitRange => .{ .resource_name = "limitranges", .api_version = "v1" },
            .ResourceQuota => .{ .resource_name = "resourcequotas", .api_version = "v1" },
            // apps/v1 resources
            .Deployment => .{ .resource_name = "deployments", .api_version = "apps/v1" },
            .StatefulSet => .{ .resource_name = "statefulsets", .api_version = "apps/v1" },
            .DaemonSet => .{ .resource_name = "daemonsets", .api_version = "apps/v1" },
            .ReplicaSet => .{ .resource_name = "replicasets", .api_version = "apps/v1" },
            // batch/v1 resources
            .Job => .{ .resource_name = "jobs", .api_version = "batch/v1" },
            .CronJob => .{ .resource_name = "cronjobs", .api_version = "batch/v1" },
            // networking.k8s.io/v1 resources
            .Ingress => .{ .resource_name = "ingresses", .api_version = "networking.k8s.io/v1" },
            .NetworkPolicy => .{ .resource_name = "networkpolicies", .api_version = "networking.k8s.io/v1" },
            // rbac.authorization.k8s.io/v1 resources
            .Role => .{ .resource_name = "roles", .api_version = "rbac.authorization.k8s.io/v1" },
            .RoleBinding => .{ .resource_name = "rolebindings", .api_version = "rbac.authorization.k8s.io/v1" },
            .ClusterRole => .{ .resource_name = "clusterroles", .api_version = "rbac.authorization.k8s.io/v1" },
            .ClusterRoleBinding => .{ .resource_name = "clusterrolebindings", .api_version = "rbac.authorization.k8s.io/v1" },
            // storage.k8s.io/v1 resources
            .StorageClass => .{ .resource_name = "storageclasses", .api_version = "storage.k8s.io/v1" },
            .VolumeAttachment => .{ .resource_name = "volumeattachments", .api_version = "storage.k8s.io/v1" },
            // policy/v1 resources
            .PodDisruptionBudget => .{ .resource_name = "poddisruptionbudgets", .api_version = "policy/v1" },
            // autoscaling/v2 resources
            .HorizontalPodAutoscaler => .{ .resource_name = "horizontalpodautoscalers", .api_version = "autoscaling/v2" },
        };
    }
};

/// Metadata for a Kubernetes resource
const ResourceMetadata = struct {
    resource_name: []const u8, // e.g., "pods", "deployments"
    api_version: []const u8, // e.g., "v1", "apps/v1"
};

/// Extract the simple type name from a fully qualified type name
fn getSimpleTypeName(comptime type_name: []const u8) []const u8 {
    const last_dot = comptime std.mem.lastIndexOfScalar(u8, type_name, '.') orelse return type_name;
    return type_name[last_dot + 1 ..];
}

/// Compile-time mapping of Kubernetes types to their resource metadata
fn getResourceMetadata(comptime T: type) ?ResourceMetadata {
    const type_name = @typeName(T);
    const simple_name = comptime getSimpleTypeName(type_name);

    const resource_type = std.meta.stringToEnum(ResourceType, simple_name) orelse return null;
    return resource_type.getMetadata();
}

/// Base implementation for resource clients
/// This is the shared implementation used by both ResourceClient and CustomResourceClient
fn TypedResourceClient(comptime T: type) type {
    return struct {
        client: *Client,
        resource_name: []const u8,
        api_version: []const u8,
        encoding: HttpClient.ContentType,

        const Self = @This();

        /// Internal init - accepts resource_name, api_version, and encoding
        fn init(client: *Client, resource_name: []const u8, api_version: []const u8, encoding: HttpClient.ContentType) Self {
            return .{
                .client = client,
                .resource_name = resource_name,
                .api_version = api_version,
                .encoding = encoding,
            };
        }

        /// Create a resource in the specified namespace
        pub fn create(self: Self, namespace: []const u8, resource: T) !T {
            const allocator = self.client.allocator;

            // Encode the resource based on the configured encoding
            const body = switch (self.encoding) {
                .json => try resource.jsonEncode(.{}, allocator),
                .protobuf => {
                    // TODO: Protobuf encoding requires updates to zig-protobuf library
                    // for Zig 0.15+ std.Io.Writer changes
                    std.debug.print("Error: Protobuf encoding is not yet supported. Please use .json encoding.\n", .{});
                    return error.UnsupportedEncoding;
                },
            };
            defer allocator.free(body);

            // Build the API path
            const path = try self.buildPath(namespace, null);
            defer allocator.free(path);

            // Make the request
            var response = try self.client.create(path, body, self.encoding);
            defer response.deinit();

            // Check for errors
            if (@intFromEnum(response.status) >= 400) {
                std.debug.print("API Error: {s}\n", .{response.body});
                return error.ApiError;
            }

            // Parse the response based on the configured encoding
            // Increase eval branch quota for complex Kubernetes types
            // TODO: remove when the zig-protobuf library gets a new version.
            // fixed with https://github.com/Arwalk/zig-protobuf/pull/142
            @setEvalBranchQuota(1000000);
            return switch (self.encoding) {
                .json => blk: {
                    const parsed = try T.jsonDecode(response.body, .{ .ignore_unknown_fields = true }, allocator);
                    break :blk parsed.value;
                },
                .protobuf => {
                    // TODO: Protobuf decoding requires updates to zig-protobuf library
                    // for Zig 0.15+ std.Io.Reader changes
                    std.debug.print("Error: Protobuf decoding is not yet supported. Please use .json encoding.\n", .{});
                    return error.UnsupportedEncoding;
                },
            };
        }

        /// Get a resource by name
        pub fn get(self: Self, namespace: []const u8, name: []const u8) !T {
            const allocator = self.client.allocator;

            // Build the API path
            const path = try self.buildPath(namespace, name);
            defer allocator.free(path);

            // Make the request
            var response = try self.client.get(path, self.encoding);
            defer response.deinit();

            // Check for errors
            if (@intFromEnum(response.status) >= 400) {
                std.debug.print("API Error: {s}\n", .{response.body});
                return error.ApiError;
            }

            // Parse the response based on the configured encoding
            // Increase eval branch quota for complex Kubernetes types
            // TODO: remove when the zig-protobuf library gets a new version.
            // fixed with https://github.com/Arwalk/zig-protobuf/pull/142
            @setEvalBranchQuota(1000000);
            return switch (self.encoding) {
                .json => blk: {
                    const parsed = T.jsonDecode(response.body, .{
                        .ignore_unknown_fields = true,
                        .allocate = .alloc_if_needed,
                    }, allocator) catch |err| {
                        std.debug.print("\nNote: Failed to parse Kubernetes response into typed struct: {}\n", .{err});
                        std.debug.print("This is a known limitation with complex Kubernetes API responses.\n", .{});
                        std.debug.print("The Kubernetes API returns many runtime fields (managedFields, conditions with null values, etc.)\n", .{});
                        std.debug.print("that don't perfectly match the protobuf schema.\n\n", .{});
                        std.debug.print("Workaround: For complex queries, consider using the raw Client methods:\n", .{});
                        std.debug.print("  var response = try client.get(path, .json);\n", .{});
                        std.debug.print("  var parsed = try std.json.parseFromSlice(std.json.Value, allocator, response.body, .{{}});\n\n", .{});
                        return err;
                    };
                    break :blk parsed.value;
                },
                .protobuf => {
                    // TODO: Protobuf decoding requires updates to zig-protobuf library
                    // for Zig 0.15+ std.Io.Reader changes
                    std.debug.print("Error: Protobuf decoding is not yet supported. Please use .json encoding.\n", .{});
                    return error.UnsupportedEncoding;
                },
            };
        }

        /// List resources in a namespace
        /// Note: Returns std.json.Parsed(T) for JSON encoding, or T directly for protobuf
        pub fn list(self: Self, namespace: []const u8) !std.json.Parsed(T) {
            const allocator = self.client.allocator;

            // Build the API path
            const path = try self.buildPath(namespace, null);
            defer allocator.free(path);

            // Make the request
            var response = try self.client.get(path, self.encoding);
            defer response.deinit();

            // Check for errors
            if (@intFromEnum(response.status) >= 400) {
                std.debug.print("API Error: {s}\n", .{response.body});
                return error.ApiError;
            }

            // Parse the response (returns a List type)
            // Increase eval branch quota for complex Kubernetes types
            @setEvalBranchQuota(1000000);
            return switch (self.encoding) {
                .json => try T.jsonDecode(response.body, .{ .ignore_unknown_fields = true }, allocator),
                .protobuf => {
                    // TODO: Protobuf decoding requires updates to zig-protobuf library
                    // for Zig 0.15+ std.Io.Reader changes
                    std.debug.print("Error: Protobuf decoding is not yet supported. Please use .json encoding.\n", .{});
                    return error.UnsupportedEncoding;
                },
            };
        }

        /// Update a resource
        pub fn update(self: Self, namespace: []const u8, name: []const u8, resource: T) !T {
            const allocator = self.client.allocator;

            // Encode the resource based on the configured encoding
            const body = switch (self.encoding) {
                .json => try resource.jsonEncode(.{}, allocator),
                .protobuf => {
                    // TODO: Protobuf encoding requires updates to zig-protobuf library
                    // for Zig 0.15+ std.Io.Writer changes
                    std.debug.print("Error: Protobuf encoding is not yet supported. Please use .json encoding.\n", .{});
                    return error.UnsupportedEncoding;
                },
            };
            defer allocator.free(body);

            // Build the API path
            const path = try self.buildPath(namespace, name);
            defer allocator.free(path);

            // Make the request
            var response = try self.client.update(path, body, self.encoding);
            defer response.deinit();

            // Check for errors
            if (@intFromEnum(response.status) >= 400) {
                std.debug.print("API Error: {s}\n", .{response.body});
                return error.ApiError;
            }

            // Parse the response based on the configured encoding
            // Increase eval branch quota for complex Kubernetes types
            @setEvalBranchQuota(1000000);
            return switch (self.encoding) {
                .json => blk: {
                    const parsed = try T.jsonDecode(response.body, .{ .ignore_unknown_fields = true }, allocator);
                    break :blk parsed.value;
                },
                .protobuf => {
                    // TODO: Protobuf decoding requires updates to zig-protobuf library
                    // for Zig 0.15+ std.Io.Reader changes
                    std.debug.print("Error: Protobuf decoding is not yet supported. Please use .json encoding.\n", .{});
                    return error.UnsupportedEncoding;
                },
            };
        }

        /// Delete a resource by name
        pub fn delete(self: Self, namespace: []const u8, name: []const u8) !void {
            const allocator = self.client.allocator;

            // Build the API path
            const path = try self.buildPath(namespace, name);
            defer allocator.free(path);

            // Make the request
            var response = try self.client.delete(path, .json);
            defer response.deinit();

            // Check for errors
            if (@intFromEnum(response.status) >= 400) {
                std.debug.print("API Error: {s}\n", .{response.body});
                return error.ApiError;
            }
        }

        /// Build the API path for the resource
        fn buildPath(self: Self, namespace: []const u8, name: ?[]const u8) ![]const u8 {
            const allocator = self.client.allocator;

            // Determine if this is a core API (v1) or API group
            const api_prefix = if (std.mem.eql(u8, self.api_version, "v1"))
                "api"
            else
                "apis";

            if (name) |n| {
                // Specific resource: /api/v1/namespaces/{ns}/{resource}/{name}
                return try std.fmt.allocPrint(
                    allocator,
                    "{s}/{s}/{s}/namespaces/{s}/{s}/{s}",
                    .{ self.client.base_url, api_prefix, self.api_version, namespace, self.resource_name, n },
                );
            } else {
                // List resources: /api/v1/namespaces/{ns}/{resource}
                return try std.fmt.allocPrint(
                    allocator,
                    "{s}/{s}/{s}/namespaces/{s}/{s}",
                    .{ self.client.base_url, api_prefix, self.api_version, namespace, self.resource_name },
                );
            }
        }
    };
}

/// Generic client for Kubernetes resources with automatic type inference
/// Usage:
///   var pod_client = ResourceClient(v1.Pod).init(client, .json);
///   var pod = try pod_client.create("default", my_pod);
///
/// Encoding options:
///   - .json: JSON encoding (recommended, fully supported)
///   - .protobuf: Protobuf encoding (TODO: requires zig-protobuf library updates for Zig 0.15+)
pub fn ResourceClient(comptime T: type) type {
    // Increase eval branch quota for complex Kubernetes types
    @setEvalBranchQuota(10000);

    const metadata = getResourceMetadata(T) orelse @compileError(
        "Type " ++ @typeName(T) ++ " is not a known Kubernetes resource. " ++
            "For custom resources (CRDs), use CustomResourceClient instead.",
    );

    const Typed = TypedResourceClient(T);

    return struct {
        client: Typed,

        const Self = @This();

        pub fn init(client: *Client, encoding: HttpClient.ContentType) Self {
            return .{
                .client = Typed.init(client, metadata.resource_name, metadata.api_version, encoding),
            };
        }

        // Delegate all methods to the base implementation
        pub fn create(self: Self, namespace: []const u8, resource: T) !T {
            return self.client.create(namespace, resource);
        }

        pub fn get(self: Self, namespace: []const u8, name: []const u8) !T {
            return self.client.get(namespace, name);
        }

        pub fn list(self: Self, namespace: []const u8) !std.json.Parsed(T) {
            return self.client.list(namespace);
        }

        pub fn update(self: Self, namespace: []const u8, name: []const u8, resource: T) !T {
            return self.client.update(namespace, name, resource);
        }

        pub fn delete(self: Self, namespace: []const u8, name: []const u8) !void {
            return self.client.delete(namespace, name);
        }
    };
}

/// Client for Custom Resource Definitions (CRDs)
/// Use this for non-standard Kubernetes resources where you need to specify
/// the resource name and API version manually.
/// Usage:
///   var my_crd_client = CustomResourceClient(MyCRD).init(client, "mycrds", "mygroup.io/v1", .json);
///   var resource = try my_crd_client.create("default", my_resource);
///
/// Encoding options:
///   - .json: JSON encoding (recommended, fully supported)
///   - .protobuf: Protobuf encoding (TODO: requires zig-protobuf library updates for Zig 0.15+)
pub fn CustomResourceClient(comptime T: type) type {
    // Increase eval branch quota for complex Kubernetes types
    @setEvalBranchQuota(10000);

    const Typed = TypedResourceClient(T);

    return struct {
        client: Typed,

        const Self = @This();

        pub fn init(client: *Client, resource_name: []const u8, api_version: []const u8, encoding: HttpClient.ContentType) Self {
            return .{
                .client = Typed.init(client, resource_name, api_version, encoding),
            };
        }

        // Delegate all methods to the base implementation
        pub fn create(self: Self, namespace: []const u8, resource: T) !T {
            return self.client.create(namespace, resource);
        }

        pub fn get(self: Self, namespace: []const u8, name: []const u8) !T {
            return self.client.get(namespace, name);
        }

        pub fn list(self: Self, namespace: []const u8) !std.json.Parsed(T) {
            return self.client.list(namespace);
        }

        pub fn update(self: Self, namespace: []const u8, name: []const u8, resource: T) !T {
            return self.client.update(namespace, name, resource);
        }

        pub fn delete(self: Self, namespace: []const u8, name: []const u8) !void {
            return self.client.delete(namespace, name);
        }
    };
}
