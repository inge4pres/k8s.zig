# Kubernetes Protobuf Structure

## Overview

Kubernetes supports multiple wire encodings over HTTP (JSON, YAML, CBOR, and Protobuf). Protobuf is the most efficient binary representation for better performance at scale.

## Using Protobuf with Kubernetes API

### Client-side Usage

To use Protobuf serialization, set the appropriate HTTP headers:

**For GET requests:**
```
Accept: application/vnd.kubernetes.protobuf
```

**For PUT/POST requests:**
```
Content-Type: application/vnd.kubernetes.protobuf
Accept: application/vnd.kubernetes.protobuf
```

### Protobuf Envelope Format

Kubernetes uses an envelope wrapper for Protobuf responses that starts with a 4-byte magic number:
- Magic number: `0x6b, 0x38, 0x73, 0x00` (ASCII: "k8s\x00")
- This helps identify content as Kubernetes Protobuf

### Proto Files Location

Proto files are auto-generated in the kubernetes/api repository:

**Structure:**
```
kubernetes/api/
├── core/v1/generated.proto
├── apps/v1/generated.proto
├── batch/v1/generated.proto
├── networking/v1/generated.proto
└── ... (other API groups)
```

**Key API Groups:**
- **core/v1**: Pod, Service, ConfigMap, Secret, Namespace, Node, PersistentVolume, etc.
- **apps/v1**: Deployment, StatefulSet, DaemonSet, ReplicaSet
- **batch/v1**: Job, CronJob
- **networking/v1**: NetworkPolicy, Ingress
- **rbac/v1**: Role, RoleBinding, ClusterRole, ClusterRoleBinding
- **policy/v1**: PodDisruptionBudget
- **storage/v1**: StorageClass, VolumeAttachment
- **autoscaling/v1, v2**: HorizontalPodAutoscaler

## Implementation Strategy for k8s.zig

1. **Download proto files** from kubernetes/api repository
   - Focus on most commonly used API groups first (core/v1, apps/v1, batch/v1)
   - Download `generated.proto` files from each API group

2. **Handle dependencies**
   - Kubernetes proto files import common types
   - Need to handle proto imports correctly

3. **Generate Zig code** using zig-protobuf
   - Use `RunProtocStep` in build.zig
   - Generate type-safe Zig structs

4. **Implement envelope handling**
   - Wrap/unwrap protobuf messages with magic number
   - Handle envelope parsing in HTTP client

## Limitations

- Protobuf is NOT available for:
  - CustomResourceDefinitions (CRDs)
  - Resources served via aggregation layer
- For these, JSON serialization must be used

## Resources

- Proto files: https://github.com/kubernetes/api
- Design doc: https://github.com/kubernetes/design-proposals-archive/blob/main/api-machinery/protobuf.md
- API concepts: https://kubernetes.io/docs/reference/using-api/api-concepts/
