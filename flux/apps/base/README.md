# Flux App Definitions

## Structure

```
flux/
├── clusters/k8-dev/          ← Flux sync config (auto-managed by flux bootstrap)
│   ├── flux-system/          ← Flux controllers
│   └── apps/                 ← Points to flux/apps/k8-dev
└── apps/
    ├── base/                 ← Reusable app manifests (Kustomize bases)
    └── k8-dev/               ← k8-dev cluster overlays
```

## Adding an Application

1. Create base manifests in `flux/apps/base/<app-name>/`
2. Create a cluster overlay in `flux/apps/k8-dev/<app-name>/`
3. Reference it from `flux/apps/k8-dev/kustomization.yaml`
4. Commit and push — Flux reconciles automatically

## Example: Deploy nginx

```yaml
# flux/apps/k8-dev/nginx/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base/nginx
```
