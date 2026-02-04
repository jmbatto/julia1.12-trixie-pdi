FROM debian:trixie-slim

# Metadata
LABEL maintainer="jmbatto"
LABEL description="Julia 1.12 (Source Build) on Debian Trixie with PDI/GTK - Optimized for stability"

# Build Arguments
ARG USER_ID=1001
ARG GROUP_ID=1001
ARG USER_NAME=coder
ARG JULIA_VERSION=v1.12.4
ARG PDI_VERSION=1.10.0

# -----------------------------------------------------------------------------
# 1. System Dependencies Installation
# -----------------------------------------------------------------------------
# Rationale:
# - 'neowofetch': Replaces 'neofetch' which has been removed from Debian Trixie repos.
# - 'python3-setuptools': REQUIRED for PDI compilation. Python 3.12+ (shipped with Trixie)
#   removed 'distutils', causing CMake/PDI detection scripts to fail without setuptools.
# - 'dbus-x11' & 'xvfb': Essential for running GTK applications in a headless Docker environment.
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build tools and base utilities
    build-essential cmake git pkg-config \
    gfortran which perl gawk m4 vim libatomic1 \
    nano sudo lsof jq neowofetch curl wget \
    gdb valgrind clang-format \
    ca-certificates iputils-ping colordiff \
    # Python Environment (with setuptools fix for Py3.12)
    python3 python3-dev python3-numpy python3-setuptools \
    # Scientific Libraries (MPI/PDI/HDF5)
    mpi-default-dev libhdf5-dev libz-dev \
    # Graphics Stack (X11, GTK4, OpenGL, DBus)
    libx11-6 libxext6 libxrender1 libxtst6 xauth xvfb dbus-x11 \
    libgl1-mesa-dri libgl1 \
    libgtk-4-1 libgtk-3-0 libglib2.0-0 libcairo2 \
    libpango-1.0-0 libharfbuzz0b \
    libgdk-pixbuf-2.0-0 libgdk-pixbuf2.0-bin \
    libgraphene-1.0-0 librsvg2-common \
    shared-mime-info \
    adwaita-icon-theme-full hicolor-icon-theme fonts-liberation \
    graphviz \
    && rm -rf /var/lib/apt/lists/*

# Fix: Generate machine-id to prevent GLib/GTK runtime errors regarding missing D-Bus UUID.
RUN dbus-uuidgen > /etc/machine-id

# Fix: Update GDK pixbuf loaders cache.
# Prevents runtime warnings/errors about missing image format loaders.
RUN LOADER_PATH=$(find /usr/lib -name gdk-pixbuf-query-loaders | head -n 1) && \
    ln -s $LOADER_PATH /usr/bin/gdk-pixbuf-query-loaders && \
    gdk-pixbuf-query-loaders --update-cache

# -----------------------------------------------------------------------------
# 2. JULIA COMPILATION
# -----------------------------------------------------------------------------
WORKDIR /tmp/julia-build
RUN git clone --depth 1 --branch ${JULIA_VERSION} https://github.com/JuliaLang/julia.git .

# Build Configuration (Make.user) - CRITICAL FIXES FOR DEBIAN TRIXIE
# 1. USE_SYSTEM_LIBUNWIND=0: Forces internal libunwind. System libunwind on Trixie causes Segfaults.
# 2. noexecstack: Security flag required by modern Linux kernels.
# 3. -gdwarf-4: CRITICAL FIX. GCC 13+ defaults to DWARF-5 debug format, which is incompatible
#    with Julia's current unwinder, leading to immediate Segfaults on startup.
RUN echo "prefix=/usr/local/julia" > Make.user && \
    echo "MARCH=x86-64" >> Make.user && \
    echo "USE_SYSTEM_LIBUNWIND=0" >> Make.user && \
    echo "LDFLAGS=-Wl,-z,noexecstack" >> Make.user && \
    echo "CFLAGS=-Wa,--noexecstack -gdwarf-4" >> Make.user && \
    echo "CXXFLAGS=-Wa,--noexecstack -gdwarf-4" >> Make.user

# Compile, Install, and Cleanup
# Cleanup is performed immediately to reduce final image size (~1GB saved).
ENV JULIA_PATH=/usr/local/julia
ENV PATH=$JULIA_PATH/bin:$PATH
RUN make -j$(nproc) && \
    make install && \
    rm -rf /tmp/julia-build

# -----------------------------------------------------------------------------
# 3. PDI INSTALLATION
# -----------------------------------------------------------------------------
ENV PDI_DIR=/usr/local
ENV LD_LIBRARY_PATH=/usr/local/lib:/usr/lib/x86_64-linux-gnu
ENV CPATH=/usr/local/include
ENV PREFIX=/usr/local

WORKDIR /tmp/pdi-build
# Build Configuration:
# - BUILD_PYTHON=ON & BUILD_PYCALL_PLUGIN=ON: Explicitly enabled to generate
#   'libpdi_pycall_plugin.so'. Required to prevent 'plugin not found' errors
#   when interacting with Python from Julia/PDI.
RUN git clone --depth 1 --branch ${PDI_VERSION} https://github.com/pdidev/pdi.git . && \
    mkdir build && cd build && \
    cmake \
        -DBUILD_MPI=OFF \
        -DBUILD_DECL_HDF5_PLUGIN=ON \
        -DBUILD_SHARED_LIBS=ON \
        -DBUILD_FORTRAN=OFF \
        -DBUILD_HDF5_PARALLEL=OFF \
        -DBUILD_PYTHON=ON \
        -DBUILD_PYCALL_PLUGIN=ON \
        -DBUILD_NETCDF_PARALLEL=OFF \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        .. && \
    make -j$(nproc) && \
    make install && \
    ldconfig && \
    cd / && rm -rf /tmp/pdi-build

# -----------------------------------------------------------------------------
# 4. USER CONFIGURATION & RUNTIME ENVIRONMENT
# -----------------------------------------------------------------------------
RUN groupadd -g ${GROUP_ID} ${USER_NAME} && \
    useradd -m -u ${USER_ID} -g ${USER_NAME} -s /bin/bash ${USER_NAME} && \
    echo "${USER_NAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# RUNTIME ENVIRONMENT VARIABLES - CRITICAL SETTINGS
# 1. LD_LIBRARY_PATH: STRICTLY excludes '/usr/lib/x86_64-linux-gnu'.
#    Reason: Preventing "DLL Hell". Including system paths forces Julia to load system
#    libraries (e.g., system libglib) instead of its own Artifacts, causing undefined
#    symbol errors (e.g., 'g_string_copy'). We prioritize Julia and PDI libs.
ENV LD_LIBRARY_PATH=/usr/local/julia/lib:/usr/local/julia/lib/julia:/usr/local/lib

# 2. GTK_A11Y=none: Disables GTK Accessibility Bus to suppress "org.a11y.Bus" warnings in logs.
ENV GTK_A11Y=none

# 3. Graphics & Julia settings
ENV GKSwstype=100
ENV JULIA_PKG_PRECOMPILE_AUTO=0
ENV JULIA_PKG_USE_CLI_GIT=true
ENV DISPLAY=host.docker.internal:0.0

# Switch to non-root user for Package Installation
# Ensures ~/.julia permissions are correctly set for the user 'coder'.
USER ${USER_NAME}
WORKDIR /home/${USER_NAME}/project

# -----------------------------------------------------------------------------
# 5. JULIA PACKAGES INSTALLATION
# -----------------------------------------------------------------------------
# Optimization:
# - Operations are consolidated into a single RUN instruction to reduce Docker layer count.
# - xvfb-run: Executes in a virtual framebuffer. Essential for 'Pkg.precompile()'
#   of Gtk4 and ProfileView, which require a display server even during installation.




ENV LD_LIBRARY_PATH=/usr/local/julia/lib:/usr/local/julia/lib/julia:/usr/local/lib

RUN julia -e 'import Pkg; \
    Pkg.add([ \
        "HDF5"])'
RUN xvfb-run --auto-servernum --server-args="-screen 0 1920x1080x24 -nolisten tcp" \
	julia -e 'import Pkg; \
       Pkg.add([ \		
        "DataFrames", \
        "Gtk4", \
        "Gtk", \
        "ProfileView", \
        "PProf", \
        "Reexport" \
    ])'


ENV LD_LIBRARY_PATH=""
# hack to install julia package
RUN xvfb-run --auto-servernum --server-args="-screen 0 1920x1080x24 -nolisten tcp" \
    julia -e 'import Pkg; Pkg.precompile()'
ENV LD_LIBRARY_PATH=/usr/local/julia/lib:/usr/local/julia/lib/julia:/usr/local/lib



CMD ["/bin/bash"]