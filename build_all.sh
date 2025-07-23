#!/bin/bash
set -euo pipefail

# Configuration
conda_path="/mnt/4T/miniconda3/loong"
version="1.22.1"
dir_os="Linux"
py_versions=("py310" "py311" "py312")
# py_versions=("py39" "py310" "py311" "py312" "py313")
backends=("rocm" "migraphx")
# backends=("migraphx")
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
base_dir="${script_dir}/onnxruntime-${version}"
# base_dir="${script_dir}/onnxruntime-${version}"
output_base="../"

# 记录起始目录
start_dir="$(pwd)"
echo "Starting directory: ${start_dir}"

# Build function for shared library
build_shared_lib() {
    local backend=$1
    local backend_flags
    
    case $backend in
        rocm) backend_flags="--use_rocm --rocm_home /opt/rocm" ;;
        migraphx) backend_flags="--use_migraphx --migraphx_home /opt/rocm" ;;
    esac

    echo "=============================================="
    echo "Building ${backend} shared library..."
    echo "=============================================="
    
    # 进入构建目录
    cd "${base_dir}" || exit 1
    echo "Working directory: $(pwd)"
    
    # 确保构建目录存在
    local build_dir="build/${dir_os}"
    mkdir -p "${build_dir}"
    
    # 构建共享库
    "${conda_path}/py312/bin/python" \
        "tools/ci_build/build.py" \
        --build_dir "${build_dir}" \
        --config Release \
        --skip_tests \
        --build_shared_lib \
        --parallel \
        ${backend_flags}
    
    # 返回到起始目录进行移动操作
    cd "${start_dir}" || exit 1
    echo "Returned to starting directory: $(pwd)"
    
    # 创建目标目录并移动构建结果
    local dest_dir="${output_base}${backend}-build"
    mkdir -p "${dest_dir}"
    
    # 重命名并移动共享库构建目录
    mv "${base_dir}/${build_dir}" "${dest_dir}/onnxruntime-${version}-${backend}"
    
    echo "=============================================="
    echo "${backend} shared library built and moved to ${dest_dir}/onnxruntime-${version}-${backend}"
    echo "=============================================="
}

# Build function for Python wheel (single version)
build_wheel() {
    local backend=$1
    local py=$2
    local backend_flags
    
    case $backend in
        rocm) backend_flags="--use_rocm --rocm_home /opt/rocm" ;;
        migraphx) backend_flags="--use_migraphx --migraphx_home /opt/rocm" ;;
    esac

    echo "=============================================="
    echo "Building ${backend} wheel for ${py}..."
    echo "=============================================="
    
    # 进入构建目录
    cd "${base_dir}" || exit 1
    echo "Working directory: $(pwd)"
    
    # 重新创建构建目录
    local build_dir="build/${dir_os}"
    mkdir -p "${build_dir}"
    
    # 构建 wheel
    "${conda_path}/${py}/bin/python" \
        "tools/ci_build/build.py" \
        --build_dir "${build_dir}" \
        --config Release \
        --skip_tests \
        --build_wheel \
        --parallel \
        ${backend_flags}
    
    # 返回到起始目录进行移动操作
    cd "${start_dir}" || exit 1
    echo "Returned to starting directory: $(pwd)"
    
    # 移动生成的 wheel 到目标目录
    local dest_dir="${output_base}${backend}-build"
    mkdir -p "${dest_dir}"
    mv "${base_dir}/${build_dir}/Release/dist"/*.whl "${dest_dir}/"
    
    # 清理构建目录（在原始位置）
    rm -rf "${base_dir}/${build_dir}"
    
    echo "=============================================="
    echo "${backend} wheel for ${py} built and moved to ${dest_dir}"
    echo "=============================================="
}

# Main build process
for backend in "${backends[@]}"; do
    echo "################################################################"
    echo "Starting ${backend} backend builds"
    echo "################################################################"
    
    # 1. 首先构建共享库
    build_shared_lib "${backend}"
    
    # 2. 按顺序构建所有 Python 版本的 wheel
    for py in "${py_versions[@]}"; do
        build_wheel "${backend}" "${py}"
    done
    
    echo "################################################################"
    echo "Completed all builds for ${backend} backend"
    echo "################################################################"
done

echo "=============================================="
echo "All builds completed successfully!"
echo "Output directories:"
for backend in "${backends[@]}"; do
    echo "  ${output_base}${backend}-build"
    echo "    - onnxruntime-${version}-${backend} (shared library)"
    echo "    - onnxruntime-${version}-cp39-*.whl (Python 3.9 wheel)"
    echo "    - ... (other Python wheels)"
    echo "    - onnxruntime-${version}-cp313-*.whl (Python 3.13 wheel)"
done
