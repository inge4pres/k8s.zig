# Type-Safe Resource Client

The `ResourceClient` provides a generic, type-safe interface for working with any Kubernetes resource type generated from protobuf definitions.

## Overview

Instead of using resource-specific methods like `listPods()` or `getDeployment()`, you can use a single generic client that works with any protobuf-generated Kubernetes type:

```zig
const v1 = k8s.proto.k8s.io.api.core.v1;

// Create a type-safe client for Pods
var pod_client = k8s.ResourceClient(v1.Pod).init(&client, "pods", "v1");

// All CRUD operations are now type-safe
var pod = try pod_client.get("default", "my-pod");
defer pod.deinit(allocator);
```

## Basic Usage

### Creating a ResourceClient

```zig
const ResourceClient = k8s.ResourceClient;

// For core resources (v1 API)
var pod_client = ResourceClient(v1.Pod).init(&client, "pods", "v1");
var service_client = ResourceClient(v1.Service).init(&client, "services", "v1");

// For API group resources
var deployment_client = ResourceClient(apps_v1.Deployment).init(&client, "deployments", "apps/v1");
var job_client = ResourceClient(batch_v1.Job).init(&client, "jobs", "batch/v1");
```

### CRUD Operations

All `ResourceClient` instances support the same operations:

#### Get a resource

```zig
var pod = try pod_client.get("default", "my-pod");
defer pod.deinit(allocator);

// Access fields
if (pod.metadata) |metadata| {
    if (metadata.name) |name| {
        std.debug.print("Pod name: {s}\n", .{name});
    }
}
```

#### List resources

```zig
var pod_list = try pod_client.list("default");
defer pod_list.deinit();

// pod_list is a PodList type with items array
```

#### Create a resource

```zig
var new_pod = v1.Pod{
    .metadata = meta_v1.ObjectMeta{
        .name = "nginx-pod",
        .namespace = "default",
    },
    .spec = v1.PodSpec{
        // ... configure pod spec
    },
};
defer new_pod.deinit(allocator);

var created_pod = try pod_client.create("default", new_pod);
defer created_pod.deinit(allocator);
```

#### Update a resource

```zig
// Modify the pod
pod.spec.?.activeDeadlineSeconds = 3600;

var updated_pod = try pod_client.update("default", "my-pod", pod);
defer updated_pod.deinit(allocator);
```

#### Delete a resource

```zig
try pod_client.delete("default", "my-pod");
```

## Working with Complex Types

### Challenge: Nested Structures

Kubernetes protobuf types can be very complex with deep nesting. Building them manually can be verbose:

```zig
var pod = v1.Pod{
    .metadata = meta_v1.ObjectMeta{
        .name = "my-pod",
        .namespace = "default",
        .labels = blk: {
            var labels: std.ArrayListUnmanaged(meta_v1.ObjectMeta.LabelsEntry) = .empty;
            try labels.append(allocator, .{ .key = "app", .value = "nginx" });
            break :blk labels;
        },
    },
    .spec = v1.PodSpec{
        .containers = blk: {
            var containers: std.ArrayListUnmanaged(v1.Container) = .empty;
            try containers.append(allocator, v1.Container{
                .name = "nginx",
                .image = "nginx:latest",
                .ports = blk2: {
                    var ports: std.ArrayListUnmanaged(v1.ContainerPort) = .empty;
                    try ports.append(allocator, v1.ContainerPort{
                        .containerPort = 80,
                    });
                    break :blk2 ports;
                },
            });
            break :blk containers;
        },
    },
};
```

### Solution 1: Builder Pattern

You can create helper functions to build complex structures:

```zig
fn createPod(allocator: std.mem.Allocator, name: []const u8, image: []const u8) !v1.Pod {
    var containers: std.ArrayListUnmanaged(v1.Container) = .empty;
    try containers.append(allocator, v1.Container{
        .name = "main",
        .image = image,
    });

    return v1.Pod{
        .metadata = meta_v1.ObjectMeta{
            .name = name,
            .namespace = "default",
        },
        .spec = v1.PodSpec{
            .containers = containers,
        },
    };
}

// Usage
var pod = try createPod(allocator, "nginx-pod", "nginx:latest");
defer pod.deinit(allocator);
```

### Solution 2: JSON Templates

For very complex resources, you can use JSON templates and parse them:

```zig
const pod_json =
    \\{
    \\  "apiVersion": "v1",
    \\  "kind": "Pod",
    \\  "metadata": {
    \\    "name": "nginx-pod",
    \\    "namespace": "default"
    \\  },
    \\  "spec": {
    \\    "containers": [{
    \\      "name": "nginx",
    \\      "image": "nginx:latest",
    \\      "ports": [{"containerPort": 80}]
    \\    }]
    \\  }
    \\}
;

// Parse JSON to typed Pod
const parsed = try v1.Pod.jsonDecode(pod_json, .{}, allocator);
defer parsed.deinit();

// Now create it
var created = try pod_client.create("default", parsed.value);
defer created.deinit(allocator);
```

### Solution 3: Hybrid Approach

Pass raw JSON directly to the base client for complex creates, but use typed client for reads:

```zig
// Create with raw JSON (easier for complex structures)
const pod_json = try std.fmt.allocPrint(allocator,
    \\{{"apiVersion":"v1","kind":"Pod","metadata":{{"name":"{s}"}},"spec":{{"containers":[{{"name":"nginx","image":"nginx:latest"}}]}}}}
, .{pod_name});
defer allocator.free(pod_json);

const path = try std.fmt.allocPrint(allocator, "{s}/api/v1/namespaces/default/pods", .{client.base_url});
defer allocator.free(path);

var response = try client.create(path, pod_json, .json);
defer response.deinit();

// Read with typed client (easier to work with fields)
var pod = try pod_client.get("default", pod_name);
defer pod.deinit(allocator);

// Now you can access fields type-safely
if (pod.status) |status| {
    if (status.phase) |phase| {
        std.debug.print("Pod phase: {s}\n", .{phase});
    }
}
```

## Benefits

1. **Type Safety**: Compile-time guarantees that you're using correct types
2. **Single Interface**: Same methods work for all resource types
3. **Flexibility**: Use typed structs for reading, JSON for writing if easier
4. **Extensibility**: Add new resource types without changing client code

## Complete Example

```zig
const std = @import("std");
const k8s = @import("k8s");
const v1 = k8s.proto.k8s.io.api.core.v1;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = try k8s.Client.fromKubeconfigJSONFile(allocator, "~/.kube/config.json");
    defer client.deinit();

    // Create type-safe pod client
    var pod_client = k8s.ResourceClient(v1.Pod).init(&client, "pods", "v1");

    // Get a pod
    var pod = try pod_client.get("default", "my-pod");
    defer pod.deinit(allocator);

    // Check status
    if (pod.status) |status| {
        if (status.phase) |phase| {
            std.debug.print("Pod is in phase: {s}\n", .{phase});
        }
    }

    // List all pods
    var pod_list = try pod_client.list("default");
    defer pod_list.deinit();
}
```

## API Reference

### ResourceClient(comptime T: type)

Generic client for Kubernetes resources.

#### Methods

- `init(client: *Client, resource_name: []const u8, api_version: []const u8) Self`
  - Creates a new ResourceClient
  - `resource_name`: Lowercase plural name (e.g., "pods", "deployments")
  - `api_version`: API version string (e.g., "v1", "apps/v1")

- `get(namespace: []const u8, name: []const u8) !T`
  - Retrieves a single resource by name

- `list(namespace: []const u8) !std.json.Parsed(T)`
  - Lists all resources in a namespace (returns a List type)

- `create(namespace: []const u8, resource: T) !T`
  - Creates a new resource, returns the created resource

- `update(namespace: []const u8, name: []const u8, resource: T) !T`
  - Updates an existing resource, returns the updated resource

- `delete(namespace: []const u8, name: []const u8) !void`
  - Deletes a resource

## Next Steps

- See `examples/typed_resources.zig` for a working demonstration
- Explore the protobuf types in `src/proto/k8s/io/api/`
- Check `src/resource_client.zig` for implementation details
