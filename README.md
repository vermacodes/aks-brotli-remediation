# AKS Brotli Node Remediation

Temporary AKS host remediation for
[CVE-2026-111497](https://www.cve.org/CVERecord?id=CVE-2026-111497).
The Kubernetes DaemonSet updates `libbrotli1` on existing and newly added
Ubuntu nodes until an AKS node image containing the fix is available.

> [!WARNING]
> This project deploys a privileged init container that changes packages on
> AKS node hosts. Review the manifests before use. Remove the DaemonSet after
> all node pools run a fixed AKS node image.

This is an independent community utility. It is not an official Microsoft
product, advisory, or support statement.

## Remediation targets

| Node OS | Minimum package version |
| --- | --- |
| Ubuntu 22.04 | `libbrotli1 1.0.9-2ubuntu0.1` |
| Ubuntu 24.04 | `libbrotli1 1.1.0-2ubuntu0.1` |

Other Linux distributions and unsupported Ubuntu versions are detected and
skipped without modification.

## What it does

1. Schedules one pod on each Linux node.
2. Uses a privileged init container to enter the host filesystem with
   `chroot`.
3. Detects the host operating system and installed `libbrotli1` version.
4. Uses `dpkg --compare-versions` to avoid unnecessary package operations.
5. Runs the equivalent of:

   ```bash
   apt-get update
   apt-get install --only-upgrade --yes libbrotli1
   ```

6. Fails the init container if the resulting package is below the required
   version.
7. Leaves an unprivileged holder container running so Kubernetes can report
   the DaemonSet as ready.

While the DaemonSet remains installed, it also runs on nodes added or reimaged
later.

## Important limitations

- This updates a package on the current node. It does not create or replace an
  AKS node image.
- A node replacement or reimage can remove the package change. The DaemonSet
  reapplies it only while the DaemonSet remains installed.
- This does not update Brotli copies bundled inside application container
  images or language runtimes.
- This does not restart host processes or reboot nodes.
- Nodes need access to configured Ubuntu package repositories.
- The namespace is deliberately configured for the Kubernetes privileged Pod
  Security level.

## Prerequisites

- An AKS cluster containing Ubuntu 22.04 or Ubuntu 24.04 nodes.
- `kubectl` with permission to create namespaces, ConfigMaps, and DaemonSets.
- The intended AKS cluster selected as the current Kubernetes context.

Confirm the target before deployment:

```bash
kubectl config current-context
kubectl get nodes -o wide
```

## Deploy

Clone and validate the files locally:

```bash
git clone https://github.com/vermacodes/aks-brotli-remediation.git
cd aks-brotli-remediation
./test.sh
```

Deploy to the current Kubernetes context:

```bash
./deploy.sh
```

The script displays the current context and requires you to type its exact
name before it applies the privileged DaemonSet. For controlled automation
where the context has already been validated:

```bash
./deploy.sh --yes
```

## Validate every node

```bash
./validate.sh
```

Example result:

```text
NODE                                             RESULT
----                                             ------
aks-node-000000                                  RESULT node=aks-node-000000 status=UPDATED os=ubuntu-22.04 before=1.0.9-2build6 version=1.0.9-2ubuntu0.1 minimum=1.0.9-2ubuntu0.1
aks-node-000001                                  RESULT node=aks-node-000001 status=COMPLIANT os=ubuntu-24.04 version=1.1.0-2ubuntu0.1 minimum=1.1.0-2ubuntu0.1
```

The validator fails when:

- a selected node has no successful result;
- a package remains below its required version;
- no supported Ubuntu 22.04 or 24.04 nodes are found; or
- not all DaemonSet pods become ready.

Inspect the full remediation logs with:

```bash
kubectl logs \
  --namespace aks-brotli-remediation \
  --selector app.kubernetes.io/name=aks-brotli-remediation \
  --container remediate \
  --prefix
```

## Move to the fixed AKS node image

This DaemonSet is an interim measure. When a fixed image is available in the
cluster's region, upgrade each affected node pool:

```bash
az aks nodepool upgrade \
  --resource-group <resource-group> \
  --cluster-name <cluster-name> \
  --name <node-pool> \
  --node-image-only
```

Confirm the resulting image:

```bash
az aks nodepool show \
  --resource-group <resource-group> \
  --cluster-name <cluster-name> \
  --name <node-pool> \
  --query nodeImageVersion
```

Run `./validate.sh` again, then remove the temporary remediation:

```bash
./cleanup.sh
```

## Tested behavior

The following paths were exercised on a temporary AKS 1.36 cluster:

- Ubuntu 22.04 upgraded from `1.0.9-2build6` to `1.0.9-2ubuntu0.1`.
- Ubuntu 24.04 upgraded from `1.1.0-2build2` to `1.1.0-2ubuntu0.1`.
- Repeated runs reported `COMPLIANT` without reinstalling the package.
- A newly added Ubuntu 24.04 node was automatically updated.
- Cleanup removed the DaemonSet and its privileged namespace.

## Repository contents

| File | Purpose |
| --- | --- |
| `daemonset.yaml` | Privileged init container and unprivileged holder container |
| `namespace.yaml` | Dedicated namespace with required Pod Security labels |
| `remediate.sh` | Host OS detection, package update, and version validation |
| `validate.sh` | Cluster-wide result collection and compliance check |
| `deploy.sh` | Context confirmation, deployment, and validation |
| `cleanup.sh` | Removal of all Kubernetes remediation resources |
| `test.sh` | Local shell and Kustomize validation |
| `kustomization.yaml` | Kustomize assembly and script ConfigMap generation |

## References

- [Ubuntu USN-8956-1](https://ubuntu.com/security/notices/USN-8956-1)
- [AKS release tracker](https://releases.aks.azure.com/CVEStatus)
- [Upgrade AKS node images](https://learn.microsoft.com/azure/aks/upgrade-node-image)
