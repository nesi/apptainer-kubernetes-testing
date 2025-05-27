FROM rockylinux/rockylinux:9.4

# Install EPEL and update system
RUN dnf install -y epel-release && dnf update -y

# Install required packages including debugging tools
RUN dnf install -y --allowerasing \
    wget \
    curl \
    git \
    fakeroot \
    squashfs-tools \
    cryptsetup \
    fuse-overlayfs \
    sudo \
    which \
    procps-ng \
    util-linux \
    shadow-utils \
    strace \
    lsof

# Add Apptainer repository and install
RUN curl -fsSL https://github.com/apptainer/apptainer/releases/download/v1.4.0/apptainer-1.4.0-1.x86_64.rpm -o apptainer.rpm && \
#    curl -fsSL https://github.com/apptainer/apptainer/releases/download/v1.3.4/apptainer-suid-1.3.4-1.el9.x86_64.rpm -o apptainer-suid.rpm && \
     dnf install -y ./apptainer.rpm  
#    dnf install -y ./apptainer.rpm ./apptainer-suid.rpm && \
#@     rm -rf apptainer.rpm
#    rm -f apptainer.rpm apptainer-suid.rpm

# Create apptainer config directory and basic configuration
RUN mkdir -p /etc/apptainer && \
    echo "allow setuid = yes" > /etc/apptainer/apptainer.conf && \
    echo "max loop devices = 256" >> /etc/apptainer/apptainer.conf && \
    echo "allow pid ns = yes" >> /etc/apptainer/apptainer.conf && \
    echo "config passwd = yes" >> /etc/apptainer/apptainer.conf && \
    echo "config group = yes" >> /etc/apptainer/apptainer.conf && \
    echo "config resolv_conf = yes" >> /etc/apptainer/apptainer.conf && \
    echo "mount proc = yes" >> /etc/apptainer/apptainer.conf && \
    echo "mount sys = yes" >> /etc/apptainer/apptainer.conf && \
    echo "mount dev = yes" >> /etc/apptainer/apptainer.conf && \
    echo "mount devpts = yes" >> /etc/apptainer/apptainer.conf && \
    echo "mount home = yes" >> /etc/apptainer/apptainer.conf && \
    echo "mount tmp = yes" >> /etc/apptainer/apptainer.conf && \
    echo "bind path = /etc/localtime" >> /etc/apptainer/apptainer.conf && \
    echo "bind path = /etc/hosts" >> /etc/apptainer/apptainer.conf

# Create fakeroot configuration file
RUN touch /etc/apptainer/fakeroot && \
    echo "# Fakeroot user mappings - Format: username:subuid_start:subuid_count" > /etc/apptainer/fakeroot

# Set up user namespace limits
RUN echo "user.max_user_namespaces=15000" >> /etc/sysctl.conf && \
    echo "user.max_pid_namespaces=15000" >> /etc/sysctl.conf

# Create test users with different privilege levels
RUN useradd -m -s /bin/bash testuser && \
    useradd -m -s /bin/bash rootuser && \
    usermod -aG wheel rootuser && \
    echo "rootuser ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Set up subuid and subgid for fakeroot testing
RUN echo "testuser:100000:65536" >> /etc/subuid && \
    echo "testuser:100000:65536" >> /etc/subgid && \
    echo "testuser:100000:65536" >> /etc/apptainer/fakeroot && \
    echo "rootuser:200000:65536" >> /etc/subuid && \
    echo "rootuser:200000:65536" >> /etc/subgid && \
    echo "rootuser:200000:65536" >> /etc/apptainer/fakeroot

# Create cache and working directories
RUN mkdir -p /opt/apptainer/cache /opt/apptainer/tmp /opt/test && \
    chmod 755 /opt/apptainer/cache /opt/apptainer/tmp /opt/test && \
    chown testuser:testuser /opt/test

# Set environment variables
ENV APPTAINER_CACHEDIR="/opt/apptainer/cache"
ENV APPTAINER_TMPDIR="/opt/apptainer/tmp"

# Create test script to check Apptainer functionality
RUN echo '#!/bin/bash' > /opt/test/test-apptainer.sh && \
    echo 'echo "=== Apptainer Test Script ==="' >> /opt/test/test-apptainer.sh && \
    echo 'echo "Running as user: $(whoami)"' >> /opt/test/test-apptainer.sh && \
    echo 'echo "UID: $(id -u), GID: $(id -g)"' >> /opt/test/test-apptainer.sh && \
    echo 'echo "Current directory: $(pwd)"' >> /opt/test/test-apptainer.sh && \
    echo 'echo ""' >> /opt/test/test-apptainer.sh && \
    echo '' >> /opt/test/test-apptainer.sh && \
    echo 'echo "=== System Information ==="' >> /opt/test/test-apptainer.sh && \
    echo 'echo "Kernel version: $(uname -r)"' >> /opt/test/test-apptainer.sh && \
    echo 'echo "User namespaces available: $(cat /proc/sys/user/max_user_namespaces 2>/dev/null || echo N/A)"' >> /opt/test/test-apptainer.sh && \
    echo 'echo "PID namespaces available: $(cat /proc/sys/user/max_pid_namespaces 2>/dev/null || echo N/A)"' >> /opt/test/test-apptainer.sh && \
    echo 'echo ""' >> /opt/test/test-apptainer.sh && \
    echo '' >> /opt/test/test-apptainer.sh && \
    echo 'echo "=== Apptainer Version ==="' >> /opt/test/test-apptainer.sh && \
    echo 'apptainer --version' >> /opt/test/test-apptainer.sh && \
    echo 'echo ""' >> /opt/test/test-apptainer.sh && \
    echo '' >> /opt/test/test-apptainer.sh && \
    echo 'echo "=== User Namespace Mappings ==="' >> /opt/test/test-apptainer.sh && \
    echo 'echo "Current user subuid:"' >> /opt/test/test-apptainer.sh && \
    echo 'grep "$(whoami)" /etc/subuid 2>/dev/null || echo "No subuid mapping found"' >> /opt/test/test-apptainer.sh && \
    echo 'echo "Current user subgid:"' >> /opt/test/test-apptainer.sh && \
    echo 'grep "$(whoami)" /etc/subgid 2>/dev/null || echo "No subgid mapping found"' >> /opt/test/test-apptainer.sh && \
    echo 'echo "Fakeroot mapping:"' >> /opt/test/test-apptainer.sh && \
    echo 'grep "$(whoami)" /etc/apptainer/fakeroot 2>/dev/null || echo "No fakeroot mapping found"' >> /opt/test/test-apptainer.sh && \
    echo 'echo ""' >> /opt/test/test-apptainer.sh && \
    echo '' >> /opt/test/test-apptainer.sh && \
    echo 'echo "=== Testing Basic Apptainer Functionality ==="' >> /opt/test/test-apptainer.sh && \
    echo 'echo "1. Testing apptainer pull..."' >> /opt/test/test-apptainer.sh && \
    echo 'if apptainer pull --force /tmp/alpine.sif docker://alpine:latest; then' >> /opt/test/test-apptainer.sh && \
    echo '    echo "✓ Pull successful"' >> /opt/test/test-apptainer.sh && \
    echo 'else' >> /opt/test/test-apptainer.sh && \
    echo '    echo "✗ Pull failed"' >> /opt/test/test-apptainer.sh && \
    echo 'fi' >> /opt/test/test-apptainer.sh && \
    echo 'echo ""' >> /opt/test/test-apptainer.sh && \
    echo '' >> /opt/test/test-apptainer.sh && \
    echo 'echo "2. Testing basic container execution..."' >> /opt/test/test-apptainer.sh && \
    echo 'if apptainer exec /tmp/alpine.sif whoami; then' >> /opt/test/test-apptainer.sh && \
    echo '    echo "✓ Basic exec successful"' >> /opt/test/test-apptainer.sh && \
    echo 'else' >> /opt/test/test-apptainer.sh && \
    echo '    echo "✗ Basic exec failed"' >> /opt/test/test-apptainer.sh && \
    echo 'fi' >> /opt/test/test-apptainer.sh && \
    echo 'echo ""' >> /opt/test/test-apptainer.sh && \
    echo '' >> /opt/test/test-apptainer.sh && \
    echo 'echo "3. Testing fakeroot functionality..."' >> /opt/test/test-apptainer.sh && \
    echo 'echo "3a. Checking if fakeroot option is available..."' >> /opt/test/test-apptainer.sh && \
    echo 'if apptainer exec --help | grep -q fakeroot; then' >> /opt/test/test-apptainer.sh && \
    echo '    echo "✓ Fakeroot option available"' >> /opt/test/test-apptainer.sh && \
    echo '    echo "3b. Testing fakeroot execution..."' >> /opt/test/test-apptainer.sh && \
    echo '    if apptainer exec --fakeroot /tmp/alpine.sif whoami; then' >> /opt/test/test-apptainer.sh && \
    echo '        echo "✓ Fakeroot exec successful"' >> /opt/test/test-apptainer.sh && \
    echo '        echo "User inside fakeroot container:"' >> /opt/test/test-apptainer.sh && \
    echo '        apptainer exec --fakeroot /tmp/alpine.sif id' >> /opt/test/test-apptainer.sh && \
    echo '    else' >> /opt/test/test-apptainer.sh && \
    echo '        echo "✗ Fakeroot exec failed"' >> /opt/test/test-apptainer.sh && \
    echo '        echo "Error details:"' >> /opt/test/test-apptainer.sh && \
    echo '        apptainer exec --fakeroot /tmp/alpine.sif whoami 2>&1 || true' >> /opt/test/test-apptainer.sh && \
    echo '    fi' >> /opt/test/test-apptainer.sh && \
    echo 'else' >> /opt/test/test-apptainer.sh && \
    echo '    echo "✗ Fakeroot option not available"' >> /opt/test/test-apptainer.sh && \
    echo 'fi' >> /opt/test/test-apptainer.sh && \
    echo 'echo ""' >> /opt/test/test-apptainer.sh && \
    echo '' >> /opt/test/test-apptainer.sh && \
    echo 'echo "=== Testing User Namespace Creation ==="' >> /opt/test/test-apptainer.sh && \
    echo 'echo "Current UID map:"' >> /opt/test/test-apptainer.sh && \
    echo 'cat /proc/self/uid_map 2>/dev/null || echo "Cannot read uid_map"' >> /opt/test/test-apptainer.sh && \
    echo 'echo "Current GID map:"' >> /opt/test/test-apptainer.sh && \
    echo 'cat /proc/self/gid_map 2>/dev/null || echo "Cannot read gid_map"' >> /opt/test/test-apptainer.sh && \
    echo 'echo ""' >> /opt/test/test-apptainer.sh && \
    echo '' >> /opt/test/test-apptainer.sh && \
    echo 'echo "=== Detailed Error Analysis ==="' >> /opt/test/test-apptainer.sh && \
    echo 'echo "Running fakeroot with verbose output..."' >> /opt/test/test-apptainer.sh && \
    echo 'apptainer --verbose exec --fakeroot /tmp/alpine.sif id 2>&1 || true' >> /opt/test/test-apptainer.sh && \
    echo 'echo ""' >> /opt/test/test-apptainer.sh && \
    echo '' >> /opt/test/test-apptainer.sh && \
    echo 'echo "=== Test Complete ==="' >> /opt/test/test-apptainer.sh

# Make test script executable
RUN chmod +x /opt/test/test-apptainer.sh

# Clean up
RUN dnf clean all && rm -rf /var/cache/dnf

# Set working directory
WORKDIR /opt/test

# Default command runs the test script as testuser
CMD ["su", "-", "testuser", "-c", "/opt/test/test-apptainer.sh"]

# Build instructions and notes:
# docker build -t rocky-apptainer-test:9.4 .
# 
# Test locally with different privilege levels:
# docker run --rm rocky-apptainer-test:9.4
# docker run --rm --privileged rocky-apptainer-test:9.4
# docker run --rm --privileged --cap-add SYS_ADMIN rocky-apptainer-test:9.4
