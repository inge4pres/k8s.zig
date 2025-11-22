const std = @import("std");

/// Kubernetes API path builder
pub const ApiPaths = struct {
    base_url: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, base_url: []const u8) ApiPaths {
        return .{
            .allocator = allocator,
            .base_url = base_url,
        };
    }

    /// Build a path for a core API resource
    /// Format: /api/v1/namespaces/{namespace}/{resource}/{name?}
    pub fn coreResource(
        self: ApiPaths,
        resource: []const u8,
        namespace: ?[]const u8,
        name: ?[]const u8,
    ) ![]const u8 {
        if (namespace) |ns| {
            if (name) |n| {
                return try std.fmt.allocPrint(
                    self.allocator,
                    "{s}/api/v1/namespaces/{s}/{s}/{s}",
                    .{ self.base_url, ns, resource, n },
                );
            } else {
                return try std.fmt.allocPrint(
                    self.allocator,
                    "{s}/api/v1/namespaces/{s}/{s}",
                    .{ self.base_url, ns, resource },
                );
            }
        } else {
            if (name) |n| {
                return try std.fmt.allocPrint(
                    self.allocator,
                    "{s}/api/v1/{s}/{s}",
                    .{ self.base_url, resource, n },
                );
            } else {
                return try std.fmt.allocPrint(
                    self.allocator,
                    "{s}/api/v1/{s}",
                    .{ self.base_url, resource },
                );
            }
        }
    }

    /// Build a path for a grouped API resource
    /// Format: /apis/{group}/{version}/namespaces/{namespace}/{resource}/{name?}
    pub fn groupedResource(
        self: ApiPaths,
        group: []const u8,
        version: []const u8,
        resource: []const u8,
        namespace: ?[]const u8,
        name: ?[]const u8,
    ) ![]const u8 {
        if (namespace) |ns| {
            if (name) |n| {
                return try std.fmt.allocPrint(
                    self.allocator,
                    "{s}/apis/{s}/{s}/namespaces/{s}/{s}/{s}",
                    .{ self.base_url, group, version, ns, resource, n },
                );
            } else {
                return try std.fmt.allocPrint(
                    self.allocator,
                    "{s}/apis/{s}/{s}/namespaces/{s}/{s}",
                    .{ self.base_url, group, version, ns, resource },
                );
            }
        } else {
            if (name) |n| {
                return try std.fmt.allocPrint(
                    self.allocator,
                    "{s}/apis/{s}/{s}/{s}/{s}",
                    .{ self.base_url, group, version, resource, n },
                );
            } else {
                return try std.fmt.allocPrint(
                    self.allocator,
                    "{s}/apis/{s}/{s}/{s}",
                    .{ self.base_url, group, version, resource },
                );
            }
        }
    }

    /// Build a path for pods (core/v1)
    pub fn pods(self: ApiPaths, namespace: []const u8, name: ?[]const u8) ![]const u8 {
        return self.coreResource("pods", namespace, name);
    }

    /// Build a path for services (core/v1)
    pub fn services(self: ApiPaths, namespace: []const u8, name: ?[]const u8) ![]const u8 {
        return self.coreResource("services", namespace, name);
    }

    /// Build a path for configmaps (core/v1)
    pub fn configMaps(self: ApiPaths, namespace: []const u8, name: ?[]const u8) ![]const u8 {
        return self.coreResource("configmaps", namespace, name);
    }

    /// Build a path for secrets (core/v1)
    pub fn secrets(self: ApiPaths, namespace: []const u8, name: ?[]const u8) ![]const u8 {
        return self.coreResource("secrets", namespace, name);
    }

    /// Build a path for namespaces (core/v1, cluster-scoped)
    pub fn namespaces(self: ApiPaths, name: ?[]const u8) ![]const u8 {
        return self.coreResource("namespaces", null, name);
    }

    /// Build a path for deployments (apps/v1)
    pub fn deployments(self: ApiPaths, namespace: []const u8, name: ?[]const u8) ![]const u8 {
        return self.groupedResource("apps", "v1", "deployments", namespace, name);
    }

    /// Build a path for statefulsets (apps/v1)
    pub fn statefulSets(self: ApiPaths, namespace: []const u8, name: ?[]const u8) ![]const u8 {
        return self.groupedResource("apps", "v1", "statefulsets", namespace, name);
    }

    /// Build a path for daemonsets (apps/v1)
    pub fn daemonSets(self: ApiPaths, namespace: []const u8, name: ?[]const u8) ![]const u8 {
        return self.groupedResource("apps", "v1", "daemonsets", namespace, name);
    }

    /// Build a path for jobs (batch/v1)
    pub fn jobs(self: ApiPaths, namespace: []const u8, name: ?[]const u8) ![]const u8 {
        return self.groupedResource("batch", "v1", "jobs", namespace, name);
    }

    /// Build a path for cronjobs (batch/v1)
    pub fn cronJobs(self: ApiPaths, namespace: []const u8, name: ?[]const u8) ![]const u8 {
        return self.groupedResource("batch", "v1", "cronjobs", namespace, name);
    }
};

test "ApiPaths - core resource paths" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const paths = ApiPaths.init(allocator, "https://kubernetes.default.svc");

    // Test namespaced resource with name
    const pod_path = try paths.pods("default", "my-pod");
    defer allocator.free(pod_path);
    try testing.expectEqualStrings("https://kubernetes.default.svc/api/v1/namespaces/default/pods/my-pod", pod_path);

    // Test namespaced resource without name (list)
    const pods_list_path = try paths.pods("default", null);
    defer allocator.free(pods_list_path);
    try testing.expectEqualStrings("https://kubernetes.default.svc/api/v1/namespaces/default/pods", pods_list_path);

    // Test cluster-scoped resource
    const namespace_path = try paths.namespaces("kube-system");
    defer allocator.free(namespace_path);
    try testing.expectEqualStrings("https://kubernetes.default.svc/api/v1/namespaces/kube-system", namespace_path);
}

test "ApiPaths - grouped resource paths" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const paths = ApiPaths.init(allocator, "https://kubernetes.default.svc");

    // Test deployment path
    const deployment_path = try paths.deployments("default", "my-deployment");
    defer allocator.free(deployment_path);
    try testing.expectEqualStrings(
        "https://kubernetes.default.svc/apis/apps/v1/namespaces/default/deployments/my-deployment",
        deployment_path,
    );

    // Test job path
    const job_path = try paths.jobs("batch-ns", null);
    defer allocator.free(job_path);
    try testing.expectEqualStrings(
        "https://kubernetes.default.svc/apis/batch/v1/namespaces/batch-ns/jobs",
        job_path,
    );
}
