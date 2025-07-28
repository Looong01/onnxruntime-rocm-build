#!/bin/bash
set -euo pipefail

# Configuration
conda_path="/root/miniconda3/"
# conda_path="/mnt/4T/miniconda3/loong"
version="1.22.1"
glibc_version="2.35"
dir_os="Linux"
py_versions=("py310" "py311" "py312" "py313")

output_base="./"
start_dir="$(pwd)"
glibc_file_version="${glibc_version//./_}"
dir_os_name="${dir_os,,}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
base_dir="${script_dir}/onnxruntime-${version}"
backend="glibc_${glibc_version}"

# 记录起始目录
echo "Starting directory: ${start_dir}"

# Build function for C/C++/CSharp
build_c_cpp_csharp() {
    echo "=============================================="
    echo "Building combined (rocm+migraphx) C/C++/CSharp..."
    echo "=============================================="
    
    # 进入构建目录
    cd "${base_dir}" || exit 1
    echo "Working directory: $(pwd)"
    
    # 确保构建目录存在
    local build_dir="build/${dir_os}"
    mkdir -p "${build_dir}"
    
    # 构建共享库（同时启用rocm和migraphx）
    "${conda_path}/py312/bin/python" \
        "tools/ci_build/build.py" \
        --build_dir "${build_dir}" \
        --config Release \
        --skip_tests \
        --build_shared_lib \
        --build_nuget \
        --parallel \
        --use_rocm \
        --rocm_home /opt/rocm \
        --use_migraphx \
        --migraphx_home /opt/rocm \
        --allow_running_as_root
    
    # 返回到起始目录进行移动操作
    cd "${start_dir}" || exit 1
    echo "Returned to starting directory: $(pwd)"
    
    # 创建目标目录并移动构建结果
    local dest_dir="${output_base}${backend}-build"
    mkdir -p "${dest_dir}"
    
    # 创建目标目录结构
    local target_dir="${dest_dir}/onnxruntime-${dir_os_name}-x64-rocm-${version}"
    
    # 创建必要的目录结构
    mkdir -p "${target_dir}/include/core"
    mkdir -p "${target_dir}/lib/cmake/onnxruntime"
    mkdir -p "${target_dir}/lib/pkgconfig"
    
    # 第一部分：处理构建目录中的文件
    local release_dir="${base_dir}/${build_dir}/Release"
    
    # 查找并复制cmake配置文件
    find "${release_dir}" -type f \( -name "onnxruntimeConfig.cmake" -o -name "onnxruntimeConfigVersion.cmake" -o -name "onnxruntimeTargets.cmake" -o -name "onnxruntimeTargets-release.cmake" \) -exec cp {} "${target_dir}/lib/cmake/onnxruntime/" \;
    
    # 复制pkgconfig文件
    find "${release_dir}" -type f -name "libonnxruntime.pc" -exec cp {} "${target_dir}/lib/pkgconfig/" \;
    
    # 复制主共享库文件
    find "${release_dir}" -type f -name "libonnxruntime.so*" -exec cp {} "${target_dir}/lib/" \;
    
    # 复制providers共享库文件
    find "${release_dir}" -type f -name "libonnxruntime_providers_*.so" -exec cp {} "${target_dir}/lib/" \;
    
    # 第二部分：处理源码目录中的头文件
    # 复制指定头文件
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
    
    # 复制providers文件夹并删除不需要的子目录
    cp -r "${base_dir}/include/onnxruntime/core/providers" "${target_dir}/include/core/"
    local unwanted_providers=("acl" "armnn" "cann" "coreml" "dml" "dnnl" "nnapi" "openvino" "rknpu" "tvm" "vsinpu" "webgpu" "winml")
    for provider in "${unwanted_providers[@]}"; do
        rm -rf "${target_dir}/include/core/providers/${provider}"
    done

    # 在目标库目录中创建符号链接
    cd "${target_dir}/lib" || exit 1
    
    # 查找主共享库文件（格式为libonnxruntime.so.x.y.z）
    local so_file=$(ls libonnxruntime.so.*.*.* 2>/dev/null | head -1)
    
    if [[ -z "$so_file" ]]; then
        echo "Error: Could not find libonnxruntime.so.x.y.z file"
        exit 1
    fi
    
    # 提取主版本号（x部分）
    local major_version=$(echo "$so_file" | awk -F'.' '{print $(NF-2)}')
    
    # 创建第一级符号链接：libonnxruntime.so.x -> libonnxruntime.so.x.y.z
    local so_major="libonnxruntime.so.${major_version}"
    ln -sf "$so_file" "$so_major"
    
    # 创建第二级符号链接：libonnxruntime.so -> libonnxruntime.so.x
    ln -sf "$so_major" "libonnxruntime.so"
    
    echo "Created symlinks:"
    echo "  $so_major -> $so_file"
    echo "  libonnxruntime.so -> $so_major"
    
    # 返回到起始目录
    cd "${start_dir}" || exit 1

    # 移动Nuget包到目标目录
    # 复制并重命名 NuGet 包到目标目录
    find "$release_dir" -type f -name "Microsoft.ML.OnnxRuntime.*.nupkg" | while read -r pkg; do
        filename=$(basename "$pkg")
        
        # 去掉 .nupkg 后缀，删除 -dev-* 及其后缀
        base=${filename%.nupkg}
        base=${base%%-dev*}
        
        # 拼出新文件名
        newname="${base}.nupkg"
        
        # 复制到目标目录
        cp "$pkg" "${dest_dir}/${newname}"
        echo "Copied and renamed: $filename → $newname"
    done
    echo "Moved Nuget packages to ${dest_dir}/"
    
    # 清理构建目录（在原始位置）
    # rm -rf "${base_dir}/${build_dir}"
    rm -f  "${base_dir}/${build_dir}/Release/CMakeCache.txt"
    rm -rf "${base_dir}/${build_dir}/Release/CMakeFiles"
    rm -f  "${base_dir}/${build_dir}/Release/Makefile" "${base_dir}/${build_dir}/Release/cmake_install.cmake"
    find "${base_dir}/${build_dir}" -type f \( -name "*.cmake" -o -name "CMakeCache.txt" -o -name "Makefile" \) -exec rm -f {} +
    find "${base_dir}/${build_dir}" -type d -name "CMakeFiles" -exec rm -rf {} +
    
    echo "=============================================="
    echo "Combined C/C++/CSharp built and organized in ${target_dir}"
    echo "=============================================="
}

# Build function for Python wheel (single version)
build_wheel() {
    local py=$1

    echo "=============================================="
    echo "Building combined wheel for ${py}..."
    echo "=============================================="
    
    # 进入构建目录
    cd "${base_dir}" || exit 1
    echo "Working directory: $(pwd)"
    
    # 重新创建构建目录
    local build_dir="build/${dir_os}"
    mkdir -p "${build_dir}"
    
    # 构建 wheel（同时启用rocm和migraphx）
    "${conda_path}/${py}/bin/python" \
        "tools/ci_build/build.py" \
        --build_dir "${build_dir}" \
        --config Release \
        --skip_tests \
        --build_wheel \
        --parallel \
        --use_rocm \
        --rocm_home /opt/rocm \
        --use_migraphx \
        --migraphx_home /opt/rocm \
        --allow_running_as_root
    
    # 返回到起始目录进行移动操作
    cd "${start_dir}" || exit 1
    echo "Returned to starting directory: $(pwd)"
    
    # 移动生成的 wheel 到目标目录
    local dest_dir="${output_base}${backend}-build"
    mkdir -p "${dest_dir}"
    
    # 获取生成的wheel文件（应该只有一个）
    local dist_dir="${base_dir}/${build_dir}/Release/dist"
    local dist_wheel
    dist_wheel=$(ls "${dist_dir}"/*.whl 2>/dev/null | head -1)
    
    if [[ -z "$dist_wheel" ]]; then
        echo "Error: No wheel file generated for ${py}"
        exit 1
    fi
    
    # 只替换第一次出现的 "-linux_" 部分
    local wheel_base
    wheel_base=$(basename "$dist_wheel")
    local wheel_new="${wheel_base/-linux_/-manylinux_${glibc_file_version}_}"
    
    # 移动并重命名
    mv "$dist_wheel" "${dest_dir}/${wheel_new}"
    echo "Moved & renamed: ${wheel_base}  -->  ${wheel_new}"

    # 清理构建目录（在原始位置）
    # rm -rf "${base_dir}/${build_dir}"
    rm -f  "${base_dir}/${build_dir}/Release/CMakeCache.txt"
    rm -rf "${base_dir}/${build_dir}/Release/CMakeFiles"
    rm -f  "${base_dir}/${build_dir}/Release/Makefile" "${base_dir}/${build_dir}/Release/cmake_install.cmake"
    find "${base_dir}/${build_dir}" -type f \( -name "*.cmake" -o -name "*.whl" -o -name "CMakeCache.txt" -o -name "Makefile" \) -exec rm -f {} +
    find "${base_dir}/${build_dir}" -type d -name "CMakeFiles" -exec rm -rf {} +


    echo "=============================================="
    echo "Combined wheel for ${py} built and moved to ${dest_dir}"
    echo "=============================================="
}

# 压缩函数
compress_results() {
    local dest_dir="${output_base}${backend}-build"
    local target_dir="${dest_dir}/onnxruntime-${dir_os_name}-x64-rocm-${version}"
    
    echo "=============================================="
    echo "Compressing build results..."
    echo "=============================================="
    
    # 1. 将整个构建目录压缩为7z格式
    local sevenz_archive="${start_dir}/onnxruntime-${version}-glibc_${glibc_version}-build.7z"
    if command -v 7z &> /dev/null; then
        echo "Compressing entire build directory to ${sevenz_archive}..."
        7z a -t7z -m0=lzma2 -mx=9 -mfb=64 -md=32m -ms=on "${sevenz_archive}" "${dest_dir}"/*
        echo "7z compression completed"
    else
        echo "Warning: 7z command not found. Skipping 7z compression."
    fi
    
    # 2. 将共享库目录单独压缩为tgz格式
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

# Main build process
echo "################################################################"
echo "Starting combined backend builds (rocm+migraphx)"
echo "################################################################"

# 1. 首先构建共享库
build_shared_lib

# 2. 按顺序构建所有 Python 版本的 wheel
for py in "${py_versions[@]}"; do
    build_wheel "${py}"
done

# 3. 压缩构建结果
compress_results

# 清理构建目录（在原始位置）
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