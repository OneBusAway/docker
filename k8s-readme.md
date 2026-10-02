### Running in Kubernetes

#### Creating the docker images

1. Build the bundler image:

```bash
docker build ./bundler -t oba/bundler:test
```

2. Build the app image:

```bash
docker build ./oba -t oba/app:test
```

#### Creating the Kubernetes resources:

Apply the Kubernetes resources in oba.yaml

```bash
kubectl apply -f oba.yaml
```

> **Security note:** `oba.yaml` ships a `Secret` containing well-known placeholder passwords so the example works out of the box on a local cluster. Do not use it as-is anywhere reachable by others — remove that `Secret` from the manifest and create `oba-secrets` yourself with generated values (see the comment above the `Secret` in `oba.yaml`).

The YAML file deploys the OneBusAway application and a MySQL database within a dedicated oba namespace in Kubernetes. It also sets up a secret for sensitive data and a ConfigMap for GTFS data URL, while exposing the database as a service for other pods to access.

You can portforward the oba app to your localhost using:

```bash
kubectl port-forward deploy/oba-app-deployment -n oba 8080:8080
```

#### Inspecting the database

You can portforward the service to your localhost using:

```bash
kubectl port-forward service/oba-database -n oba 3306:3306
```

Then you can connect to it programmatically using `mysql`:

```bash
mysql -u oba_user -p -h localhost:3306
```
