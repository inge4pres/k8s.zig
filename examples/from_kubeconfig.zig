const std = @import("std");
const builtin = @import("builtin");

const k8s = @import("k8s");

const ExecError = error{
    UnsupportedOS,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Load configuration from kubeconfig YAML file
    // This example reads the standard kubeconfig file in YAML format (typically ~/.kube/config)
    // No conversion to JSON is required - YAML is now natively supported!

    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const user_homedir: []const u8 = switch (builtin.os.tag) {
        .linux, .macos, .dragonfly, .netbsd, .freebsd, .openbsd => env_map.get("HOME") orelse unreachable,
        .windows => env_map.get("USERPROFILE") orelse unreachable,
        else => return ExecError.UnsupportedOS,
    };

    const kubeconfig_path = try std.fmt.allocPrint(allocator, "{s}/.kube/config", .{user_homedir});
    defer allocator.free(kubeconfig_path);

    std.debug.print("Loading kubeconfig from: {s}\n", .{kubeconfig_path});

    // Create client from YAML kubeconfig file
    // Uses the current context from the kubeconfig file
    var client = k8s.Client.fromKubeconfigFile(allocator, kubeconfig_path) catch |err| {
        std.debug.print("Error loading kubeconfig: {}\n", .{err});
        std.debug.print("\nMake sure your kubeconfig file exists at {s}\n", .{kubeconfig_path});
        return err;
    };
    defer client.deinit();

    var args = std.process.args();
    _ = args.skip(); // skip program name
    const namespace = args.next() orelse "default";
    std.debug.print("Using namespace {s}\n", .{namespace});

    // List pods in the configured namespace
    std.debug.print("\nListing pods in '{s}' namespace...\n", .{namespace});

    var response = client.listPods(namespace) catch |err| {
        std.debug.print("Error listing pods: {}\n", .{err});
        std.debug.print("Make sure your kubeconfig has valid credentials.\n", .{});
        return err;
    };
    defer response.deinit();

    std.debug.print("Status: {}\n", .{response.status});
    std.debug.print("Response:\n{s}\n", .{response.body});
}
