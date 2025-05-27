# apptainer-kubernetes-testing
Test framework for Apptainer + Kubernetes integration 



```bash

./scripts/test-runner.sh --help
=== Apptainer Kubernetes Test Suite ===
Testing Apptainer fakeroot functionality in different Kubernetes configurations

Usage: ./test-runner.sh [build|local|k8s|interactive|info|cleanup|all]

Commands:
  build       - Build Docker image only
  local       - Build and test with local Docker
  k8s         - Run Kubernetes tests only
  interactive - Start interactive pod for manual testing
  info        - Show cluster information
  cleanup     - Cleanup test resources
  all         - Run complete test suite (default)
```
