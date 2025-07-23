# Update
1. Upgrade ONNXRuntime libraries to the newest versions.
2. ~~Remove Python 3.9 support, because ONNXRuntime 1.20.0 does not support it.~~ Old update
3. Add Python 3.11 and 3.12 support.
4. Support ROCm 6.4.* & 6.3.*.
  
# How to use
1. Be sure that you have installed ROCm 6.3.* or newer versions. You can use ```amd-smi``` to check it.
2. Go to Releases module, choose the versions of ONNXRuntime-ROCm you want and the right version of your Python environment.
3. Download the wheel file.
4. ```pip install``` it.
  
# Build environment
```
Ubuntu 24.04
Python 3.10~3.12
ROCm 6.4.1
```
  
# Current version
```
onnxruntime-1.22.1
```