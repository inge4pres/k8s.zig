const std = @import("std");
const builtin = @import("builtin");

const k8s = @import("k8s");

const v1 = k8s.proto.k8s.io.api.core.v1;
const meta_v1 = k8s.proto.k8s.io.apimachinery.pkg.apis.meta.v1;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Load kubeconfig
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();
    const user_homedir: []const u8 = switch (builtin.os.tag) {
        .linux, .macos, .dragonfly, .netbsd, .freebsd, .openbsd => env_map.get("HOME") orelse unreachable,
        .windows => env_map.get("USERPROFILE") orelse unreachable,
        else => @compileError("Unsupported OS"),
    };

    const kubeconfig_path = try std.fmt.allocPrint(allocator, "{s}/.kube/config.json", .{user_homedir});
    defer allocator.free(kubeconfig_path);

    var client = try k8s.Client.fromKubeconfigJSONFile(allocator, kubeconfig_path);
    defer client.deinit();

    // Create a ResourceClient for Pods - resource name and API version are inferred automatically
    // You can choose .json or .protobuf encoding
    const pod_client = k8s.ResourceClient(v1.Pod).init(&client, .json);

    // Build the Pod object using protobuf types.
    // Nginx pod example in default namespace.
    var labels = std.ArrayListUnmanaged(meta_v1.ObjectMeta.LabelsEntry){};
    try labels.append(allocator, .{ .key = "app", .value = "nginx" });
    try labels.append(allocator, .{ .key = "example", .value = "typed-resources" });
    defer labels.deinit(allocator);

    var ports = std.ArrayListUnmanaged(v1.ContainerPort){};
    try ports.append(allocator, .{
        .containerPort = 80,
        .protocol = "TCP",
    });
    defer ports.deinit(allocator);

    var containers = std.ArrayListUnmanaged(v1.Container){};
    try containers.append(allocator, .{
        .name = "nginx",
        .image = "nginx:latest",
        .ports = ports,
    });
    defer containers.deinit(allocator);

    const pod = v1.Pod{
        .metadata = .{
            .name = "nginx-example",
            .namespace = "default",
            .labels = labels,
        },
        .spec = .{
            .containers = containers,
            .restartPolicy = "Never",
        },
    };

    // Create the pod using ResourceClient
    std.debug.print("Creating pod 'nginx-example'...\n", .{});
    const created_pod = pod_client.create("default", pod) catch |err| {
        std.debug.print("Failed to create pod (might already exist): {}\n", .{err});
        std.debug.print("Attempting to retrieve existing pod...\n", .{});
        const existing_pod = try pod_client.get("default", "nginx-example");
        std.debug.print("Found existing pod: {s}\n", .{existing_pod.metadata.?.name.?});

        // Clean up and exit
        std.debug.print("\nDeleting pod 'nginx-example'...\n", .{});
        try pod_client.delete("default", "nginx-example");
        std.debug.print("Pod deleted successfully\n", .{});
        return;
    };
    defer {
        var mut_pod = created_pod;
        mut_pod.deinit(allocator);
    }

    std.debug.print("Created pod: {s}\n", .{created_pod.metadata.?.name.?});

    // Get the pod back
    std.debug.print("\nRetrieving pod 'nginx-example'...\n", .{});
    const retrieved_pod = try pod_client.get("default", "nginx-example");
    defer {
        var mut_retrieved = retrieved_pod;
        mut_retrieved.deinit(allocator);
    }

    std.debug.print("Retrieved pod: {s}\n", .{retrieved_pod.metadata.?.name.?});
    if (retrieved_pod.status) |status| {
        if (status.phase) |phase| {
            std.debug.print("Pod status: {s}\n", .{phase});
        }
    }

    // Delete the pod
    std.debug.print("\nDeleting pod 'nginx-example'...\n", .{});
    try pod_client.delete("default", "nginx-example");
    std.debug.print("Pod deleted successfully\n", .{});
}
