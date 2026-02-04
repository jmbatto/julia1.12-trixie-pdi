# julia1.12-trixie-pdi
A robust Debian Trixie environment featuring source-compiled Julia 1.12, PDI 1.10, and headless GTK4 support.

# Julia 1.12 & PDI Development Environment (Debian Trixie)

A robust, source-compiled development environment designed for high-performance coupling between Julia and C using PDI. This image is built on **Debian Trixie (Testing)** and includes critical patches for stability with modern toolchains (GCC 13+).

## 🚀 Key Features

* **Julia 1.12.4 (Source Compiled):** Built from source to ensure compatibility with Debian Trixie's system libraries.
    * *Stability Fixes:* Compiled with `-gdwarf-4` and `noexecstack` to resolve critical `libunwind` segfaults caused by GCC 13 defaults.
    * *System Integration:* Configured to use internal unwinding while avoiding conflicts with system LLVM.
* **PDI 1.10.0:** Installed with full Python support.
    * *Compatibility:* Patched to support Python 3.12+ (which removed `distutils`), ensuring the `pycall` plugin compiles correctly.
* **Headless GTK4 Support:** Pre-configured with `Xvfb`, `dbus-x11`, and `libgl1` to support graphical plotting libraries (ProfileView, Gtk4.jl) in a headless container environment.
* **Clean Environment:** `LD_LIBRARY_PATH` is strictly optimized to prevent "DLL Hell" between Julia Artifacts and system libraries (GLib/GObject).

## 📦 Installed Components

* **OS:** Debian Trixie (Testing)
* **Julia:** v1.12.4
* **PDI:** v1.10.0 (with HDF5, Python, and PyCall plugins)
* **Python:** 3.12+ (with `numpy` and `setuptools`)
* **Dev Tools:** `build-essential`, `cmake`, `git`, `gdb`, `valgrind`, `vim`, `neowofetch`.
* **Julia Packages:** `HDF5`, `DataFrames`, `Gtk4`, `ProfileView`, `PProf`.

## 🛠 Usage

### Basic Interactive Shell
```bash
docker run -it jmbatto/juliabench
