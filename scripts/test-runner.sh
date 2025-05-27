#!/bin/bash

# Apptainer Kubernetes Test Runner
# This script builds the container and runs various Kubernetes tests

set -e

echo "=== Apptainer Kubernetes Test Suite ==="
echo "Testing Apptainer fakeroot functionality in different Kubernetes configurations"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to wait for pod completion and show logs
wait_and_show_logs() {
    local pod_name=$1
    local namespace=${2:-apptainer-test}
    local timeout=${3:-300}
    
    print_status $BLUE "Waiting for pod $pod_name to complete..."
    
    # Wait for pod to complete or fail
    kubectl wait --for=condition=Ready pod/$pod_name -n $namespace --timeout=${timeout}s 2>/dev/null || true
    sleep 5  # Give it a moment to run
    
    # Get pod status
    local status=$(kubectl get pod $pod_name -n $namespace -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    
    echo "Pod Status: $status"
    echo ""
    echo "=== Pod Logs ==="
    kubectl logs $pod_name -n $namespace 2>/dev/null || echo "Could not retrieve logs"
    echo ""
    echo "=== Pod Events ==="
    kubectl describe pod $pod_name -n $namespace | grep -A 10 "Events:" || echo "No events found"
    echo ""
}

# Function to check Kubernetes connectivity
check_k8s_connection() {
    if ! kubectl cluster-info &>/dev/null; then
        print_status $RED "Cannot connect to Kubernetes cluster."
        print_status $YELLOW "Make sure your kubectl is configured properly:"
        print_status $YELLOW "  kubectl config current-context"
        print_status $YELLOW "  kubectl config get-contexts"
        print_status $YELLOW ""
        print_status $YELLOW "For local setups, try:"
        print_status $YELLOW "  export KUBECONFIG=~/.kube/config"
        print_status $YELLOW "  sudo -E kubectl ..."
        return 1
    fi
    return 0
}

# Function to cleanup previous test runs
cleanup_tests() {
    print_status $YELLOW "Cleaning up previous test runs..."
    if check_k8s_connection; then
        kubectl delete namespace apptainer-test --ignore-not-found=true
        sleep 5
    else
        print_status $YELLOW "Skipping cleanup due to Kubernetes connection issues"
    fi
}

# Function to build Docker image
build_image() {
    print_status $BLUE "Building Docker image..."
    if docker build -t rocky-apptainer-test:9.4 .; then
        print_status $GREEN "✓ Docker image built successfully"
    else
        print_status $RED "✗ Docker image build failed"
        exit 1
    fi
    echo ""
}

# Function to test local Docker functionality
test_local_docker() {
    print_status $BLUE "Testing local Docker functionality..."
    
    echo "--- Test 1: Basic Docker run ---"
    if docker run --rm rocky-apptainer-test:9.4; then
        print_status $GREEN "✓ Basic Docker test passed"
    else
        print_status $RED "✗ Basic Docker test failed"
    fi
    echo ""
    
    echo "--- Test 2: Privileged Docker run ---"
    if docker run --rm --privileged rocky-apptainer-test:9.4; then
        print_status $GREEN "✓ Privileged Docker test passed"
    else
        print_status $RED "✗ Privileged Docker test failed"
    fi
    echo ""
}

# Function to run Kubernetes tests
run_k8s_tests() {
    if ! check_k8s_connection; then
        print_status $RED "Skipping Kubernetes tests due to connection issues"
        return 1
    fi
    
    print_status $BLUE "Setting up Kubernetes test environment..."
    
    # Create the namespace first
    kubectl create namespace apptainer-test --dry-run=client -o yaml | kubectl apply -f -
    
    # Apply the test manifests (you'll need to create this file from the YAML artifact)
    if [ -f "../k8s-manifests/apptainer-k8s-tests.yaml" ]; then
        kubectl apply -f ../k8s-manifests/apptainer-k8s-tests.yaml
    else
        print_status $RED "../k8s-manifests/apptainer-k8s-tests.yaml not found!"
        print_status $YELLOW "Please save the Kubernetes manifests from the second artifact to this file"
        return 1
    fi
    
    echo ""
    print_status $BLUE "Running Kubernetes tests..."
    
    # Test each pod configuration
    local tests=("basic" "sysadmin" "fakeroot" "privileged" "hostusers")
    
    for test in "${tests[@]}"; do
        local pod_name="apptainer-${test}-test"
        print_status $YELLOW "=== Running Test: $test ==="
        
        # Wait for pod to be created
        kubectl wait --for=condition=PodScheduled pod/$pod_name -n apptainer-test --timeout=60s || {
            print_status $RED "Pod $pod_name failed to schedule"
            kubectl describe pod $pod_name -n apptainer-test
            continue
        }
        
        wait_and_show_logs $pod_name
        print_status $YELLOW "=== End of Test: $test ==="
        echo ""
    done
}

# Function to provide interactive session
interactive_session() {
    if ! check_k8s_connection; then
        print_status $RED "Cannot start interactive session due to Kubernetes connection issues"
        return 1
    fi
    
    print_status $BLUE "Starting interactive session..."
    print_status $YELLOW "You can now exec into the interactive pod:"
    print_status $YELLOW "kubectl exec -it apptainer-interactive -n apptainer-test -- /bin/bash"
    print_status $YELLOW ""
    print_status $YELLOW "Inside the pod, try these commands:"
    print_status $YELLOW "  su - testuser"
    print_status $YELLOW "  /opt/test/test-apptainer.sh"
    print_status $YELLOW "  apptainer exec --fakeroot docker://alpine:latest whoami"
    print_status $YELLOW ""
    print_status $YELLOW "Press Ctrl+C to cleanup and exit"
    
    # Wait for user interrupt
    trap cleanup_tests INT
    kubectl wait --for=condition=Ready pod/apptainer-interactive -n apptainer-test --timeout=300s
    
    while true; do
        sleep 10
        if ! kubectl get pod apptainer-interactive -n apptainer-test &>/dev/null; then
            break
        fi
    done
}

# Function to show cluster info
show_cluster_info() {
    if ! check_k8s_connection; then
        print_status $RED "Cannot show cluster info due to Kubernetes connection issues"
        return 1
    fi
    
    print_status $BLUE "=== Cluster Information ==="
    echo "Kubernetes version:"
    kubectl version --short 2>/dev/null || kubectl version --client
    echo ""
    echo "Node information:"
    kubectl get nodes -o wide
    echo ""
    echo "Available storage classes:"
    kubectl get storageclass
    echo ""
    echo "PSP/PSS status:"
    kubectl get psp 2>/dev/null || echo "Pod Security Policies not found (may be using Pod Security Standards)"
    echo ""
}

# Main execution
main() {
    local action=${1:-all}
    
    case $action in
        "build")
            build_image
            ;;
        "local")
            build_image
            test_local_docker
            ;;
        "k8s")
            run_k8s_tests
            ;;
        "interactive")
            interactive_session
            ;;
        "info")
            show_cluster_info
            ;;
        "cleanup")
            cleanup_tests
            ;;
        "all"|"")
            show_cluster_info
            cleanup_tests
            build_image
            test_local_docker
            run_k8s_tests
            interactive_session
            ;;
        *)
            echo "Usage: $0 [build|local|k8s|interactive|info|cleanup|all]"
            echo ""
            echo "Commands:"
            echo "  build       - Build Docker image only"
            echo "  local       - Build and test with local Docker"
            echo "  k8s         - Run Kubernetes tests only"
            echo "  interactive - Start interactive pod for manual testing"
            echo "  info        - Show cluster information"
            echo "  cleanup     - Cleanup test resources"
            echo "  all         - Run complete test suite (default)"
            exit 1
            ;;
    esac
}

# Only set cleanup trap for operations that use Kubernetes
case "${1:-all}" in
    "k8s"|"interactive"|"all"|"cleanup")
        trap cleanup_tests EXIT
        ;;
esac

# Run main function
main "$@"
