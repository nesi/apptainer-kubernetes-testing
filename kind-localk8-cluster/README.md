* Make sure to add your user account to docker group with `sudo usermod -aG docker $USER` ( and then run `newgrp docker` ) 
```bash
# Install Kind
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.29.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# Create cluster with custom config for privileged containers
cat << EOF | kind create cluster --name apptainer-test --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraMounts:
  - hostPath: /dev/fuse
    containerPath: /dev/fuse
  kubeadmConfigPatches:
  - |
    kind: ClusterConfiguration
    apiServer:
      extraArgs:
        allow-privileged: "true"
EOF

# Set kubectl context
kubectl cluster-info --context kind-apptainer-test

# Load your image
kind load docker-image rocky-apptainer-test:9.4 --name apptainer-test
```
