# Kubernetes Protobuf Definitions

This directory contains protobuf definitions from the Kubernetes project.

## Structure

```
proto/
├── core_v1_generated.proto         # Core API v1 (Pod, Service, ConfigMap, etc.)
├── apps_v1_generated.proto         # Apps API v1 (Deployment, StatefulSet, etc.)
├── batch_v1_generated.proto        # Batch API v1 (Job, CronJob)
└── apimachinery/                   # Common types and metadata
    ├── api/resource/               # Resource quantities (CPU, memory)
    ├── apis/meta/v1/               # Object metadata (ObjectMeta, TypeMeta)
    ├── runtime/                    # Runtime types
    ├── runtime/schema/             # Schema definitions
    └── util/intstr/                # Integer or string types
```

## Sources

Proto files are downloaded from:
- **API definitions**: https://github.com/kubernetes/api
- **Common types**: https://github.com/kubernetes/apimachinery

## Import Path Mapping

The proto files use Go-style import paths that need to be mapped to local file paths. This is handled via symbolic links in the `k8s.io/` directory:

| Proto Import Path | Local Path |
|-------------------|------------|
| `k8s.io/api/core/v1` | `proto/core_v1_generated.proto` |
| `k8s.io/api/apps/v1` | `proto/apps_v1_generated.proto` |
| `k8s.io/api/batch/v1` | `proto/batch_v1_generated.proto` |
| `k8s.io/apimachinery/pkg/apis/meta/v1` | `proto/apimachinery/apis/meta/v1/generated.proto` |
| `k8s.io/apimachinery/pkg/api/resource` | `proto/apimachinery/api/resource/generated.proto` |
| `k8s.io/apimachinery/pkg/runtime` | `proto/apimachinery/runtime/generated.proto` |
| `k8s.io/apimachinery/pkg/runtime/schema` | `proto/apimachinery/runtime/schema/generated.proto` |
| `k8s.io/apimachinery/pkg/util/intstr` | `proto/apimachinery/util/intstr/generated.proto` |

The `k8s.io/` directory contains symbolic links that resolve these import paths. For example:
- `proto/k8s.io/api/core/v1/generated.proto` -> `../../../../core_v1_generated.proto`
- `proto/k8s.io/apimachinery/pkg/runtime` -> `../../../apimachinery/runtime`

These symlinks are already set up and should be committed to the repository.

## Adding More API Groups

To add support for more Kubernetes API groups, download the corresponding `generated.proto` file:

```bash
# Example: Add networking/v1
curl -sL https://raw.githubusercontent.com/kubernetes/api/master/networking/v1/generated.proto \
  -o proto/networking_v1_generated.proto
```

Common API groups to consider:
- `networking/v1` - NetworkPolicy, Ingress
- `rbac/v1` - Role, RoleBinding, ClusterRole, ClusterRoleBinding
- `policy/v1` - PodDisruptionBudget
- `storage/v1` - StorageClass, VolumeAttachment
- `autoscaling/v1`, `autoscaling/v2` - HorizontalPodAutoscaler

## Code Generation

To generate Zig code from these proto files:

```bash
zig build gen-proto
```

This will create Zig type definitions in `src/proto/`.
