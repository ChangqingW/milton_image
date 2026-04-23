FROM rockylinux:9

RUN dnf install -y \
        libgomp \
        readline \
        libicu \
        libtirpc \
        brotli \
        libpsl \
        libunistring \
        libidn2 \
        libgfortran \
        libquadmath \
        openssl-libs \
        ca-certificates \
        glibc-langpack-en && \
    dnf clean all && \
    rm -rf /var/cache/dnf

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8
