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
        glibc-langpack-en \
        environment-modules \
        diffutils \
        which && \
    dnf clean all && \
    rm -rf /var/cache/dnf && \
    # Source module init for any interactive bash or zsh session
    echo '. /etc/profile.d/modules.sh' >> /etc/bash.bashrc && \
    echo '. /etc/profile.d/modules.sh' >> /etc/zshrc

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8
