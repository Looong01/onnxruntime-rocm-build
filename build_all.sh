#!/bin/bash
set -euo pipefail

# export CXXFLAGS="-Wno-error"

conda_path="/root/miniconda3/"
version="1.23.2"
glibc_version="2.34"
dir_os="Linux"
py_versions=("py310" "py311" "py312" "py313" "py314")

output_base="./"
start_dir="$(pwd)"
glibc_file_version="${glibc_version//./_}"
dir_os_name="${dir_os,,}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
base_dir="${script_dir}/onnxruntime-${version}"
build_dir="build/${dir_os}"
backend="glibc_${glibc_version}"

echo "Starting directory: ${start_dir}"

build_c_cpp_csharp() {
    echo "=============================================="
    echo "Building combined (rocm+migraphx) C/C++/C#..."
    echo "=============================================="
    
    cd "${base_dir}" || exit 1
    echo "Working directory: $(pwd)"
    
    mkdir -p "${build_dir}"
    
    "${conda_path}/py312/bin/python" \
        "tools/ci_build/build.py" \
        --build_dir "${build_dir}" \
        --config Release \
        --skip_tests \
        --build_shared_lib \
        --build_nuget \
        --parallel \
        --use_migraphx \
        --migraphx_home /opt/rocm \
        --allow_running_as_root
    
    cd "${start_dir}" || exit 1
    echo "Returned to starting directory: $(pwd)"
    
    local dest_dir="${output_base}${backend}-build"
    mkdir -p "${dest_dir}"
    
    local target_dir="${dest_dir}/onnxruntime-${dir_os_name}-x64-rocm-${version}"
    
    mkdir -p "${target_dir}/include/core"
    mkdir -p "${target_dir}/lib/cmake/onnxruntime"
    mkdir -p "${target_dir}/lib/pkgconfig"
    
    local release_dir="${base_dir}/${build_dir}/Release"
    
    find "${release_dir}" -type f \( -name "onnxruntimeConfig.cmake" -o -name "onnxruntimeConfigVersion.cmake" -o -name "onnxruntimeTargets.cmake" -o -name "onnxruntimeTargets-release.cmake" \) -exec cp {} "${target_dir}/lib/cmake/onnxruntime/" \;
    find "${release_dir}" -type f -name "libonnxruntime.pc" -exec cp {} "${target_dir}/lib/pkgconfig/" \;
    find "${release_dir}" -type f -name "libonnxruntime.so*" -exec cp {} "${target_dir}/lib/" \;
    find "${release_dir}" -type f -name "libonnxruntime_providers_*.so" -exec cp {} "${target_dir}/lib/" \;

    local headers=(
        "cpu_provider_factory.h"
        "onnxruntime_c_api.h"
        "onnxruntime_cxx_api.h"
        "onnxruntime_cxx_inline.h"
        "onnxruntime_float16.h"
        "onnxruntime_lite_custom_op.h"
        "onnxruntime_run_options_config_keys.h"
        "onnxruntime_session_options_config_keys.h"
        "provider_options.h"
    )
    
    for header in "${headers[@]}"; do
        find "${base_dir}" -type f -name "${header}" -exec cp {} "${target_dir}/include/" \;
    done
    
    cp -r "${base_dir}/include/onnxruntime/core/providers" "${target_dir}/include/core/"
    local unwanted_providers=("acl" "armnn" "cann" "coreml" "dml" "dnnl" "nnapi" "openvino" "rknpu" "tvm" "vsinpu" "webgpu" "winml")
    for provider in "${unwanted_providers[@]}"; do
        rm -rf "${target_dir}/include/core/providers/${provider}"
    done

    cd "${target_dir}/lib" || exit 1
    
    local so_file=$(ls libonnxruntime.so.*.*.* 2>/dev/null | head -1)
    
    if [[ -z "$so_file" ]]; then
        echo "Error: Could not find libonnxruntime.so.x.y.z file"
        exit 1
    fi
    
    local major_version=$(echo "$so_file" | awk -F'.' '{print $(NF-2)}')
    
    local so_major="libonnxruntime.so.${major_version}"
    ln -sf "$so_file" "$so_major"
    
    ln -sf "$so_major" "libonnxruntime.so"
    
    echo "Created symlinks:"
    echo "  $so_major -> $so_file"
    echo "  libonnxruntime.so -> $so_major"
    
    cd "${start_dir}" || exit 1

    find "$release_dir" -type f -name "Microsoft.ML.OnnxRuntime.*.nupkg" | while read -r pkg; do
        filename=$(basename "$pkg")
        
        base=${filename%.nupkg}
        base=${base%%-dev*}
        
        newname="${base}.nupkg"
        
        cp "$pkg" "${dest_dir}/${newname}"
        echo "Copied and renamed: $filename → $newname"
    done
    echo "Moved Nuget packages to ${dest_dir}/"
    
    rm -f  "${base_dir}/${build_dir}/Release/CMakeCache.txt"
    rm -rf "${base_dir}/${build_dir}/Release/CMakeFiles"
    rm -f  "${base_dir}/${build_dir}/Release/Makefile" "${base_dir}/${build_dir}/Release/cmake_install.cmake"
    find "${base_dir}/${build_dir}" -type f \( -name "*.cmake" -o -name "*.nupkg" -o -name "CMakeCache.txt" -o -name "Makefile" \) -exec rm -f {} +
    find "${base_dir}/${build_dir}" -type d -name "CMakeFiles" -exec rm -rf {} +
    
    echo "=============================================="
    echo "Combined C/C++/CSharp built and organized in ${target_dir}"
    echo "=============================================="
}

build_wheel() {
    local py=$1

    echo "=============================================="
    echo "Building combined wheel for ${py}..."
    echo "=============================================="
    
    cd "${base_dir}" || exit 1
    echo "Working directory: $(pwd)"
    
    mkdir -p "${build_dir}"
    
    "${conda_path}/${py}/bin/python" \
        "tools/ci_build/build.py" \
        --build_dir "${build_dir}" \
        --config Release \
        --skip_tests \
        --build_wheel \
        --parallel \
        --use_migraphx \
        --migraphx_home /opt/rocm \
        --allow_running_as_root
    
    cd "${start_dir}" || exit 1
    echo "Returned to starting directory: $(pwd)"
    
    local dest_dir="${output_base}${backend}-build"
    mkdir -p "${dest_dir}"
    
    local dist_dir="${base_dir}/${build_dir}/Release/dist"
    local dist_wheel
    dist_wheel=$(ls "${dist_dir}"/*.whl 2>/dev/null | head -1)
    
    if [[ -z "$dist_wheel" ]]; then
        echo "Error: No wheel file generated for ${py}"
        exit 1
    fi
    
    local wheel_base
    wheel_base=$(basename "$dist_wheel")
    local wheel_new="${wheel_base/-linux_/-manylinux_${glibc_file_version}_}"
    
    mv "$dist_wheel" "${dest_dir}/${wheel_new}"
    echo "Moved & renamed: ${wheel_base}  -->  ${wheel_new}"

    rm -f  "${base_dir}/${build_dir}/Release/CMakeCache.txt"
    rm -rf "${base_dir}/${build_dir}/Release/CMakeFiles"
    rm -f  "${base_dir}/${build_dir}/Release/Makefile" "${base_dir}/${build_dir}/Release/cmake_install.cmake"
    find "${base_dir}/${build_dir}" -type f \( -name "*.cmake" -o -name "*.whl" -o -name "CMakeCache.txt" -o -name "Makefile" \) -exec rm -f {} +
    find "${base_dir}/${build_dir}" -type d -name "CMakeFiles" -exec rm -rf {} +


    echo "=============================================="
    echo "Combined wheel for ${py} built and moved to ${dest_dir}"
    echo "=============================================="
}

compress_results() {
    local dest_dir="${output_base}${backend}-build"
    local target_dir="${dest_dir}/onnxruntime-${dir_os_name}-x64-rocm-${version}"
    
    echo "=============================================="
    echo "Compressing build results..."
    echo "=============================================="
    
    local sevenz_archive="${start_dir}/onnxruntime-${version}-glibc_${glibc_version}-build.7z"
    if command -v 7z &> /dev/null; then
        echo "Compressing entire build directory to ${sevenz_archive}..."
        7z a -t7z -m0=lzma2 -mx=9 -mfb=64 -md=32m -ms=on "${sevenz_archive}" "${dest_dir}"/*
        echo "7z compression completed"
    else
        echo "Warning: 7z command not found. Skipping 7z compression."
    fi
    
    local tgz_archive="${dest_dir}/onnxruntime-${dir_os_name}-x64-rocm-${version}.tgz"
    echo "Compressing shared library directory to ${tgz_archive}..."
    tar -czf "${tgz_archive}" -C "${dest_dir}" "onnxruntime-${dir_os_name}-x64-rocm-${version}"
    echo "tgz compression completed"
    
    echo "=============================================="
    echo "Compression completed:"
    echo " - Full build directory: ${sevenz_archive}"
    echo " - Shared library only: ${tgz_archive}"
    echo "=============================================="
}

echo "################################################################"
echo "Starting combined backend builds (rocm+migraphx)"
echo "################################################################"

build_c_cpp_csharp

for py in "${py_versions[@]}"; do
    build_wheel "${py}"
done

compress_results

rm -rf "${base_dir}/${build_dir}"

echo "################################################################"
echo "Completed all builds for combined backend"
echo "################################################################"

echo "=============================================="
echo "All builds completed successfully!"
echo "Output directory: ${output_base}${backend}-build"
echo "  - onnxruntime-${version}-${backend} (shared library)"
echo "  - onnxruntime_rocm-${version}-cp*-cp*-manylinux_${glibc_file_version}_x86_64.whl (Python wheels)"
echo "=============================================="