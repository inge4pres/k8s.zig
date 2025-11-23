# k8s.zig Examples

This directory contains example programs demonstrating how to use the k8s.zig library.

## Examples

### list_pods.zig
Demonstrates how to list all pods in a namespace.

### get_deployment.zig
Demonstrates how to get a specific deployment by name.

## Building Examples

Examples can be built by adding them to `build.zig`. For now, they serve as reference implementations.

## Authentication

The examples show how to set a bearer token for authentication:

```zig
client.setAuthToken("your-bearer-token-here");
```

In a real application, you would:

1. **In-cluster**: Read the service account token from `/var/run/secrets/kubernetes.io/serviceaccount/token`
2. **Out-of-cluster**: Parse the kubeconfig file (typically at `~/.kube/config`) to get credentials

## API Usage Patterns

### Basic CRUD Operations

```zig
// Create a client
var client = try k8s.Client.init(allocator, "https://kubernetes.default.svc", .{});
defer client.deinit();

// Set authentication
client.setAuthToken(token);

// GET a resource
var response = try client.getPod("default", "my-pod");
defer response.deinit();

// CREATE a resource
const pod_json =
    \\{
    \\  "apiVersion": "v1",
    \\  "kind": "Pod",
    \\  "metadata": {"name": "my-pod"},
    \\  "spec": {"containers": [{"name": "nginx", "image": "nginx"}]}
    \\}
;
const path = try client.api_paths.pods("default", null);
defer allocator.free(path);
var create_response = try client.create(path, pod_json, .json);
defer create_response.deinit();

// UPDATE a resource (PUT)
const updated_json = "..."; // updated resource JSON
const update_path = try client.api_paths.pods("default", "my-pod");
defer allocator.free(update_path);
var update_response = try client.update(update_path, updated_json, .json);
defer update_response.deinit();

// DELETE a resource
const delete_path = try client.api_paths.pods("default", "my-pod");
defer allocator.free(delete_path);
var delete_response = try client.delete(delete_path, .json);
defer delete_response.deinit();
```

### Using Protobuf

For better performance, use protobuf serialization:

```zig
// Request protobuf response
var response = try client.get(path, .protobuf);
defer response.deinit();

// The response.body contains protobuf-encoded data
// You can decode it using the generated protobuf types in src/proto/
```

### Building API Paths

The `ApiPaths` helper provides methods for building Kubernetes API paths:

```zig
const paths = k8s.ApiPaths.init(allocator, "https://kubernetes.default.svc");

// Core resources (api/v1)
const pods_path = try paths.pods("default", null); // List
const pod_path = try paths.pods("default", "my-pod"); // Get

// Grouped resources (apis/{group}/{version})
const deployment_path = try paths.deployments("default", "my-deployment");
const job_path = try paths.jobs("batch-ns", "my-job");
```

## Next Steps

1. Implement kubeconfig parsing for easier authentication
2. Add watch functionality for real-time updates
3. Add support for more resource types
4. Implement strategic merge patch
5. Add label and field selectors for list operations
