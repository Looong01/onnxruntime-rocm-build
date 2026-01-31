# Update
1. Upgrade ONNXRuntime libraries to the newest versions.
2. ~~Remove Python 3.9 support, because ONNXRuntime 1.20.0 does not support it.~~ Old update
3. Add Python 3.14 support.
4. Support ROCm 7.1.1.
5. Remove ROCm EP because of 1.23.0 update.
  
# Prerequisites
Be sure that you have installed ROCm 6.3.* or newer versions. You can use ```amd-smi``` to check it.

# How to use

## 1. C/C++ packages
Go to Releases page, choose the versions of ONNXRuntime-ROCm you want, and ```tar zxvf ``` it.

## 2. Python wheels
### Option 1: From Pypi.org
   ```bash
   pip install onnxruntime-rocm onnxruntime-migraphx
   ```

### Option 2: From Github Release page
1. Go to Releases page, choose the versions of ONNXRuntime-ROCm you want and the right version of your Python environment.
2. Download the wheel file.
3. ```pip install``` it.

## 3. C# packages
1. Go to Releases page, choose the versions of ONNXRuntime-ROCm you want and copy it to a ```local_nuget_dir```.
2. Add the following configuration to your ```Nuget.Config```.
```
   <configuration>
      <packageSources>
         <add key="LocalSource" value="/path/to/local_nuget_dir" />
      </packageSources>
   </configuration>
```
3. ```dotnet add package Microsoft.ML.OnnxRuntime.Managed --version <the version of nupkg>``` and ```dotnet add package Microsoft.ML.OnnxRuntime.ROCm --version <the version of nupkg>```

  
# Build environment
```
Ubuntu 22.04
Python 3.10~3.14
ROCm 7.1.1
GLIBC 2.34
GNU-11
Clang-20
```
  
# Current version
```
onnxruntime-1.23.2
```
