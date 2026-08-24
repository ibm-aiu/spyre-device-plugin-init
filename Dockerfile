 # +-------------------------------------------------------------------+
 # | (C) Copyright IBM Corp. 2025, 2026                                |
 # | SPDX-License-Identifier: Apache-2.0                               |
 # +-------------------------------------------------------------------+
ARG PYTHON_VERSION=3.12
ARG BASE_UBI_IMAGE_TAG=9.6
ARG TOOLBOX_BIN="/opt/ibm/spyre/bin"
ARG SENLIB_INSTALL_DIR="/opt/ibm/spyre/senlib"

FROM registry.access.redhat.com/ubi9/ubi-minimal:${BASE_UBI_IMAGE_TAG}

ARG PYTHON_VERSION
ARG VERSION
ARG TOOLBOX_BIN
ARG SENLIB_INSTALL_DIR

ENV LANG=C.UTF-8 \
	LC_ALL=C.UTF-8 \
	TOOLBOX_BIN=${TOOLBOX_BIN} \
	LD_LIBRARY_PATH="${SENLIB_INSTALL_DIR}/lib"

RUN microdnf install -y \
		pciutils jq \
		hwloc-libs \
		boost-atomic boost-chrono boost-container boost-filesystem \
		boost-json boost-locale boost-log boost-regex \
		boost-system boost-thread \
		libicu \
		python${PYTHON_VERSION} && \
	microdnf -y upgrade && \
	update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYTHON_VERSION} 0 && \
	update-alternatives --install /usr/bin/python python /usr/bin/python${PYTHON_VERSION} 0 && \
	update-alternatives --set python3 /usr/bin/python${PYTHON_VERSION} && \
	update-alternatives --set python /usr/bin/python${PYTHON_VERSION} && \
	microdnf clean all && \
	# Remove packages with known CVEs that are not required at runtime:
	# - curl-minimal-7.76.1-31.el9_6.1 (CVE-2024-8096, CVE-2024-9681)
	# - python3/python3-libs/python-unversioned-command-3.9.23-2.el9 (CVE-2025-8291)
	# - systemd-libs-252-55.el9_7.2 (CVE-2025-4598)
	rpm -e --nodeps curl-minimal libcurl-minimal 2>/dev/null || true && \
	rpm -e --nodeps python3 python3-libs python-unversioned-command 2>/dev/null || true && \
	rpm -e --nodeps systemd-libs 2>/dev/null || true

LABEL io.k8s.display-name="IBM Spyre Device Plugin Init Container"
LABEL name="IBM Spyre Device Plugin Init Container"
LABEL vendor="IBM"
LABEL version="${VERSION}"
LABEL release="N/A"
LABEL summary="Prepare information for device plugin."
LABEL description="See summary"

# Create directories with proper permissions for non-root user (UID 1001, GID 0)
# The output directory will be writable by group (GID 0)
RUN mkdir -p /usr/local/etc/device-plugins/metadata && \
    mkdir -p /etc/aiu && \
    mkdir -p /tmp && \
    chown -R 1001:0 /usr/local/etc/device-plugins && \
    chown -R 1001:0 /etc/aiu && \
    chown -R 1001:0 /tmp && \
    chmod -R ug+rwX /usr/local/etc/device-plugins && \
    chmod -R ug+rwX /etc/aiu && \
    chmod -R ug+rwX /tmp

COPY assets/ /
COPY ./LICENSE /licenses/LICENSE
# Ensure script is executable and all copied files are accessible by non-root user
RUN chmod +x /gen-topo.sh && \
    chown -R 1001:0 /gen-topo.sh /gen-topo-template.json /pseudo-topology.json && \
    chmod -R u+r /gen-topo-template.json /pseudo-topology.json

# Switch to non-root user (UID 1001) with root group (GID 0)
USER 1001:0

ENTRYPOINT [ "/gen-topo.sh" ]
HEALTHCHECK NONE
