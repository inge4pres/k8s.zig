const std = @import("std");
const k8s = @import("k8s");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a Kubernetes client
    var client = try k8s.Client.init(allocator, "https://kubernetes.default.svc", .{});
    defer client.deinit();

    // Set authentication token (in real usage, load from kubeconfig or service account)
    // client.setAuthToken("your-bearer-token-here");

    // Get a specific deployment
    const namespace = "default";
    const deployment_name = "nginx-deployment";

    std.debug.print("Getting deployment '{s}' in '{s}' namespace...\n", .{ deployment_name, namespace });

    var response = try client.getDeployment(namespace, deployment_name);
    defer response.deinit();

    std.debug.print("Status: {}\n", .{response.status});
    std.debug.print("Response body:\n{s}\n", .{response.body});
}
