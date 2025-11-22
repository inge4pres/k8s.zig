# API Client

This document describes the k8s.zig Client API, including initialization, CRUD operations, resource management, and best practices.

## Overview

The Client is the main entry point for interacting with Kubernetes resources. It provides:

- High-level CRUD operations (Create, Read, Update, Patch, Delete)
- Convenience methods for common resources (Pods, Deployments, etc.)
- Authentication management
- API path construction
- Response handling

**File:** `src/client.zig`

## Client Structure

```zig
pub const Client = struct {
    allocator: std.mem.Allocator,
    base_url: []const u8,
    http_client: HttpClient,
    api_paths: ApiPaths,
    auth_token: ?[]const u8 = null,
};
```

## Initialization

### Basic Initialization

```zig
pub const InitOptions = struct {
    certificate_authority_data: ?[]const u8 = null,
    client_certificate_data: ?[]const u8 = null,
    client_key_data: ?[]const u8 = null,
    insecure_skip_tls_verify: bool = false,
};

pub fn init(allocator: std.mem.Allocator, base_url: []const u8, options: InitOptions) !Client
```

Example:
```zig
const std = @import("std");
const k8s = @import("k8s");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();
const allocator = gpa.allocator();

var client = try k8s.Client.init(allocator, "https://kubernetes.default.svc", .{});
defer client.deinit();
```

### Initialization with TLS Certificates

```zig
var client = try k8s.Client.init(allocator, "https://k8s.example.com:6443", .{
    .certificate_authority_data = ca_cert_base64,
    .client_certificate_data = client_cert_base64,
    .client_key_data = client_key_base64,
});
defer client.deinit();
```

### Initialization from Config

```zig
const clientFromConfig = @import("k8s").clientFromConfig;

var config = try k8s.Config.fromKubeconfigJSONFile(allocator, kubeconfig_path);
defer config.deinit();

var client = try clientFromConfig(&config);
defer client.deinit();
```

### In-Cluster Initialization

```zig
const clientFromInCluster = @import("k8s").clientFromInCluster;

var client = try clientFromInCluster(allocator);
defer client.deinit();
```

## Authentication

### Set Bearer Token

```zig
client.setAuthToken("your-bearer-token");
```

The token is automatically included in all subsequent requests as:
```
Authorization: Bearer <token>
```

## CRUD Operations

### Generic Operations

All generic operations return a `Response` struct that must be freed:

```zig
pub const Response = struct {
    status: std.http.Status,
    body: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Response) void {
        self.allocator.free(self.body);
    }
};
```

#### Get (Read)

```zig
pub fn get(
    self: *Client,
    path: []const u8,
    accept: HttpClient.ContentType,
) !HttpClient.Response
```

Example:
```zig
const path = try client.api_paths.pods("default", "my-pod");
defer allocator.free(path);

var response = try client.get(path, .json);
defer response.deinit();

std.debug.print("Status: {}\n", .{response.status});
std.debug.print("Body: {s}\n", .{response.body});
```

#### Create

```zig
pub fn create(
    self: *Client,
    path: []const u8,
    body: []const u8,
    content_type: HttpClient.ContentType,
) !HttpClient.Response
```

Example:
```zig
const pod_json =
    \\{
    \\  "apiVersion": "v1",
    \\  "kind": "Pod",
    \\  "metadata": {
    \\    "name": "my-pod",
    \\    "namespace": "default"
    \\  },
    \\  "spec": {
    \\    "containers": [{
    \\      "name": "nginx",
    \\      "image": "nginx:latest"
    \\    }]
    \\  }
    \\}
;

const path = try client.api_paths.pods("default", null);
defer allocator.free(path);

var response = try client.create(path, pod_json, .json);
defer response.deinit();

if (response.status == .created) {
    std.debug.print("Pod created successfully\n", .{});
}
```

#### Update (PUT)

```zig
pub fn update(
    self: *Client,
    path: []const u8,
    body: []const u8,
    content_type: HttpClient.ContentType,
) !HttpClient.Response
```

Example:
```zig
// Update requires the full resource definition
const updated_pod_json = "...";  // Full pod spec with modifications

const path = try client.api_paths.pods("default", "my-pod");
defer allocator.free(path);

var response = try client.update(path, updated_pod_json, .json);
defer response.deinit();
```

#### Patch

```zig
pub fn patch(
    self: *Client,
    path: []const u8,
    body: []const u8,
    content_type: HttpClient.ContentType,
) !HttpClient.Response
```

Example:
```zig
// JSON patch - only specify fields to change
const patch_json =
    \\{
    \\  "metadata": {
    \\    "labels": {
    \\      "env": "production"
    \\    }
    \\  }
    \\}
;

const path = try client.api_paths.pods("default", "my-pod");
defer allocator.free(path);

var response = try client.patch(path, patch_json, .json);
defer response.deinit();
```

#### Delete

```zig
pub fn delete(
    self: *Client,
    path: []const u8,
    accept: HttpClient.ContentType,
) !HttpClient.Response
```

Example:
```zig
const path = try client.api_paths.pods("default", "my-pod");
defer allocator.free(path);

var response = try client.delete(path, .json);
defer response.deinit();

if (response.status == .ok) {
    std.debug.print("Pod deleted successfully\n", .{});
}
```

## Convenience Methods

Convenience methods provide simpler interfaces for common operations on specific resources.

### Pods

#### List Pods

```zig
pub fn listPods(self: *Client, namespace: []const u8) !HttpClient.Response
```

Example:
```zig
var response = try client.listPods("default");
defer response.deinit();

std.debug.print("Pods in default namespace:\n{s}\n", .{response.body});
```

#### Get Pod

```zig
pub fn getPod(self: *Client, namespace: []const u8, name: []const u8) !HttpClient.Response
```

Example:
```zig
var response = try client.getPod("default", "my-pod");
defer response.deinit();

std.debug.print("Pod details:\n{s}\n", .{response.body});
```

### Deployments

#### List Deployments

```zig
pub fn listDeployments(self: *Client, namespace: []const u8) !HttpClient.Response
```

Example:
```zig
var response = try client.listDeployments("default");
defer response.deinit();
```

#### Get Deployment

```zig
pub fn getDeployment(self: *Client, namespace: []const u8, name: []const u8) !HttpClient.Response
```

Example:
```zig
var response = try client.getDeployment("default", "my-deployment");
defer response.deinit();
```

## API Paths

The `api_paths` field provides helpers for constructing Kubernetes API paths.

**File:** `src/api_paths.zig`

### Core Resources

Core resources use the `/api/v1` prefix:

```zig
const path = try client.api_paths.pods("default", "my-pod");
defer allocator.free(path);
// Result: https://k8s.example.com/api/v1/namespaces/default/pods/my-pod

const path = try client.api_paths.services("default", null);
defer allocator.free(path);
// Result: https://k8s.example.com/api/v1/namespaces/default/services

const path = try client.api_paths.configMaps("kube-system", "coredns");
defer allocator.free(path);
// Result: https://k8s.example.com/api/v1/namespaces/kube-system/configmaps/coredns

const path = try client.api_paths.secrets("default", "my-secret");
defer allocator.free(path);
```

### Grouped Resources

Grouped resources use the `/apis/{group}/{version}` prefix:

```zig
const path = try client.api_paths.deployments("default", "my-app");
defer allocator.free(path);
// Result: https://k8s.example.com/apis/apps/v1/namespaces/default/deployments/my-app

const path = try client.api_paths.statefulSets("default", "my-statefulset");
defer allocator.free(path);

const path = try client.api_paths.daemonSets("kube-system", "kube-proxy");
defer allocator.free(path);

const path = try client.api_paths.jobs("batch-ns", "my-job");
defer allocator.free(path);

const path = try client.api_paths.cronJobs("default", "backup");
defer allocator.free(path);
```

### Cluster-Scoped Resources

```zig
const path = try client.api_paths.namespaces("kube-system");
defer allocator.free(path);
// Result: https://k8s.example.com/api/v1/namespaces/kube-system

const path = try client.api_paths.namespaces(null);
defer allocator.free(path);
// Result: https://k8s.example.com/api/v1/namespaces (list all)
```

### Custom Paths

For resources not covered by convenience methods:

```zig
// Core resource
const path = try client.api_paths.coreResource(
    "persistentvolumeclaims",
    "default",
    "my-pvc",
);
defer allocator.free(path);

// Grouped resource
const path = try client.api_paths.groupedResource(
    "networking.k8s.io",  // group
    "v1",                  // version
    "ingresses",           // resource
    "default",             // namespace
    "my-ingress",         // name
);
defer allocator.free(path);
```

## Response Handling

### Status Codes

```zig
const response = try client.getPod("default", "my-pod");
defer response.deinit();

switch (response.status) {
    .ok => std.debug.print("Success: {s}\n", .{response.body}),
    .not_found => std.debug.print("Pod not found\n", .{}),
    .unauthorized => std.debug.print("Authentication failed\n", .{}),
    .forbidden => std.debug.print("Insufficient permissions\n", .{}),
    else => std.debug.print("Unexpected status: {}\n", .{response.status}),
}
```

Common HTTP status codes:
- `200 OK` - Successful GET, PUT, PATCH, DELETE
- `201 Created` - Successful POST (create)
- `404 Not Found` - Resource doesn't exist
- `401 Unauthorized` - Invalid or missing authentication
- `403 Forbidden` - Insufficient permissions
- `409 Conflict` - Resource version mismatch
- `422 Unprocessable Entity` - Invalid resource definition

### JSON Parsing

```zig
const std = @import("std");

var response = try client.listPods("default");
defer response.deinit();

// Parse JSON response
const parsed = try std.json.parseFromSlice(
    std.json.Value,
    allocator,
    response.body,
    .{},
);
defer parsed.deinit();

const root = parsed.value.object;
const items = root.get("items").?.array;

std.debug.print("Found {} pods\n", .{items.items.len});

for (items.items) |item| {
    const metadata = item.object.get("metadata").?.object;
    const name = metadata.get("name").?.string;
    std.debug.print("  - {s}\n", .{name});
}
```

### Error Handling

```zig
const response = client.getPod("default", "my-pod") catch |err| {
    switch (err) {
        error.ConnectionRefused => {
            std.debug.print("Cannot connect to API server\n", .{});
            return err;
        },
        error.TlsInitializationFailed => {
            std.debug.print("TLS handshake failed - check certificates\n", .{});
            return err;
        },
        error.OutOfMemory => {
            std.debug.print("Out of memory\n", .{});
            return err;
        },
        else => {
            std.debug.print("Unexpected error: {}\n", .{err});
            return err;
        },
    }
};
defer response.deinit();

// Also check HTTP status
if (response.status != .ok) {
    std.debug.print("Request failed with status: {}\n", .{response.status});
    return error.RequestFailed;
}
```

## Content Types

k8s.zig supports both JSON and Protobuf content types:

### JSON (Default)

```zig
var response = try client.get(path, .json);
defer response.deinit();
```

Advantages:
- Human-readable
- Easy to debug
- Widely supported
- No type generation needed

Disadvantages:
- Larger payload size
- Slower parsing

### Protobuf

```zig
var response = try client.get(path, .protobuf);
defer response.deinit();
```

Advantages:
- Smaller payload size
- Faster serialization/deserialization
- Type-safe with generated types

Disadvantages:
- Binary format (not human-readable)
- Requires generated types
- More complex to debug

## Complete Examples

### Example 1: List and Filter Pods

```zig
const std = @import("std");
const k8s = @import("k8s");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = try k8s.Client.init(allocator, "https://kubernetes.default.svc", .{});
    defer client.deinit();

    client.setAuthToken("your-token");

    var response = try client.listPods("default");
    defer response.deinit();

    // Parse and filter pods
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response.body, .{});
    defer parsed.deinit();

    const items = parsed.value.object.get("items").?.array;

    std.debug.print("Running pods:\n", .{});
    for (items.items) |item| {
        const metadata = item.object.get("metadata").?.object;
        const status = item.object.get("status").?.object;
        const phase = status.get("phase").?.string;

        if (std.mem.eql(u8, phase, "Running")) {
            const name = metadata.get("name").?.string;
            std.debug.print("  - {s}\n", .{name});
        }
    }
}
```

### Example 2: Create and Monitor Pod

```zig
const std = @import("std");
const k8s = @import("k8s");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = try k8s.Client.init(allocator, "https://kubernetes.default.svc", .{});
    defer client.deinit();

    client.setAuthToken("your-token");

    // Create pod
    const pod_json =
        \\{
        \\  "apiVersion": "v1",
        \\  "kind": "Pod",
        \\  "metadata": {"name": "test-pod", "namespace": "default"},
        \\  "spec": {
        \\    "containers": [{"name": "test", "image": "busybox:latest", "command": ["sleep", "3600"]}]
        \\  }
        \\}
    ;

    const create_path = try client.api_paths.pods("default", null);
    defer allocator.free(create_path);

    var create_response = try client.create(create_path, pod_json, .json);
    defer create_response.deinit();

    if (create_response.status == .created) {
        std.debug.print("Pod created successfully\n", .{});
    } else {
        std.debug.print("Failed to create pod: {}\n", .{create_response.status});
        return error.PodCreationFailed;
    }

    // Wait for pod to be running
    std.debug.print("Waiting for pod to start...\n", .{});
    var attempts: usize = 0;
    while (attempts < 30) : (attempts += 1) {
        std.time.sleep(1 * std.time.ns_per_s);

        var get_response = try client.getPod("default", "test-pod");
        defer get_response.deinit();

        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, get_response.body, .{});
        defer parsed.deinit();

        const status = parsed.value.object.get("status").?.object;
        const phase = status.get("phase").?.string;

        std.debug.print("Pod phase: {s}\n", .{phase});

        if (std.mem.eql(u8, phase, "Running")) {
            std.debug.print("Pod is running!\n", .{});
            break;
        }
    }
}
```

## Best Practices

### 1. Always Use defer for Cleanup

```zig
var client = try Client.init(allocator, url, .{});
defer client.deinit();

var response = try client.get(path, .json);
defer response.deinit();
```

### 2. Check Status Codes

```zig
if (response.status != .ok) {
    std.debug.print("Request failed: {}\n", .{response.status});
    return error.RequestFailed;
}
```

### 3. Handle Errors Appropriately

```zig
const response = client.get(path, .json) catch |err| {
    // Log error, cleanup, return
    std.debug.print("Error: {}\n", .{err});
    return err;
};
```

### 4. Free Allocated Paths

```zig
const path = try client.api_paths.pods("default", "my-pod");
defer allocator.free(path);  // Important!
```

### 5. Use Appropriate Content Type

- Use JSON for debugging and development
- Use Protobuf for production if performance is critical

### 6. Reuse Client Instances

Create one client and reuse it for multiple requests instead of creating a new client for each operation.

## Future Enhancements

1. **Watch API** - Streaming updates for resources
2. **Pagination** - Handle large result sets with continue tokens
3. **Field Selectors** - Filter resources by field values
4. **Label Selectors** - Filter resources by labels
5. **Resource Versions** - Optimistic concurrency control
6. **Subresources** - status, scale, logs, exec, etc.
7. **Batch Operations** - Multiple operations in one request
8. **Connection Pooling** - Reuse connections for better performance
