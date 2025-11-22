const std = @import("std");

/// k8s.zig - A Kubernetes client library for Zig
///
/// This library provides a type-safe interface to interact with Kubernetes clusters
/// using protobuf serialization for efficient communication.
pub const Client = @import("client.zig").Client;
pub const Config = @import("config.zig").Config;
pub const HttpClient = @import("http_client.zig").HttpClient;
pub const ApiPaths = @import("api_paths.zig").ApiPaths;
pub const Kubeconfig = @import("kubeconfig.zig").Kubeconfig;

/// Generic resource client for type-safe Kubernetes API operations
pub const ResourceClient = @import("resource_client.zig").ResourceClient;
pub const inferResourceClient = @import("resource_client.zig").inferResourceClient;

/// Protobuf-generated Kubernetes API types
pub const proto = struct {
    pub const k8s = struct {
        pub const io = struct {
            pub const api = struct {
                pub const core = struct {
                    pub const v1 = @import("proto/k8s/io/api/core/v1.pb.zig");
                };
                pub const apps = struct {
                    pub const v1 = @import("proto/k8s/io/api/apps/v1.pb.zig");
                };
            };
            pub const apimachinery = struct {
                pub const pkg = struct {
                    pub const apis = struct {
                        pub const meta = struct {
                            pub const v1 = @import("proto/k8s/io/apimachinery/pkg/apis/meta/v1.pb.zig");
                        };
                    };
                };
            };
        };
    };
};

test {
    @import("std").testing.refAllDecls(@This());

    _ = @import("api_paths.zig");
    _ = @import("client.zig");
    _ = @import("config.zig");
    _ = @import("http_client.zig");
    _ = @import("kubeconfig.zig");
}
