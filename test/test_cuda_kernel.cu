#include "catch.hpp"

#include <cuda_runtime.h>

#include <stk/cuda/cuda.h>
#include <stk/cuda/ptr.h>
#include <stk/image/gpu_volume.h>
#include <stk/image/volume.h>

#include "test_util.h"

using namespace stk;

namespace {
    const uint32_t W = 20;
    const uint32_t H = 30;
    const uint32_t D = 40;
}

__global__ void copy_kernel(cuda::VolumePtr<float> in, cuda::VolumePtr<float> out)
{
    int x = blockIdx.x*blockDim.x + threadIdx.x;
    int y = blockIdx.y*blockDim.y + threadIdx.y;
    int z = blockIdx.z*blockDim.z + threadIdx.z;

    if (x >= W || y >= H || z >= D) {
        return;
    }

    out(x,y,z) = in(x,y,z);
}

__global__ void copy_texture_kernel(cudaTextureObject_t in, cudaSurfaceObject_t out)
{
    int x = blockIdx.x*blockDim.x + threadIdx.x;
    int y = blockIdx.y*blockDim.y + threadIdx.y;
    int z = blockIdx.z*blockDim.z + threadIdx.z;

    if (x >= W || y >= H || z >= D) {
        return;
    }

    float v = tex3D<float>(in, x + 0.5f, y + 0.5f, z + 0.5f);
    surf3Dwrite(v, out, x*sizeof(float), y, z);
}

TEST_CASE("cuda_copy_kernel", "[cuda]")
{
    cuda::init();

    SECTION("float")
    {
        float test_data[W*H*D];
        TestDataGenerator<float>::run(test_data, W, H, D);
        
        VolumeFloat in({W,H,D}, test_data);
        
        GpuVolume gpu_in(in, gpu::Usage_PitchedPointer);
        GpuVolume gpu_out(gpu_in.size(), gpu_in.voxel_type(), gpu::Usage_PitchedPointer);

        dim3 block_size{8,8,1};
        dim3 grid_size
        {
            (W + block_size.x - 1) / block_size.x,
            (H + block_size.y - 1) / block_size.y,
            (D + block_size.z - 1) / block_size.z
        };
        
        copy_kernel<<<grid_size, block_size>>>(
            gpu_in.pitched_ptr(),
            gpu_out.pitched_ptr()
        );
        CUDA_CHECK_ERRORS(cudaDeviceSynchronize());

        Volume out = gpu_out.download();

        REQUIRE(compare_volumes<float>(in, out));
    }
}

TEST_CASE("cuda_copy_texture_kernel", "[cuda]")
{
    cuda::init();
    
    SECTION("float")
    {
        float test_data[W*H*D];
        TestDataGenerator<float>::run(test_data, W, H, D);
        
        VolumeFloat in({W,H,D}, test_data);
        
        GpuVolume gpu_in(in, gpu::Usage_Texture);
        GpuVolume gpu_out(gpu_in.size(), gpu_in.voxel_type(), gpu::Usage_Texture);

        cudaResourceDesc in_res_desc;
        memset(&in_res_desc, 0, sizeof(in_res_desc));
        
        in_res_desc.resType = cudaResourceTypeArray;
        in_res_desc.res.array.array = gpu_in.array_ptr();
        
        cudaTextureDesc tex_desc;
        memset(&tex_desc, 0, sizeof(tex_desc));
        
        tex_desc.addressMode[0] = cudaAddressModeClamp;
        tex_desc.addressMode[1] = cudaAddressModeClamp;
        tex_desc.addressMode[2] = cudaAddressModeClamp;
        tex_desc.filterMode = cudaFilterModeLinear;

        cudaTextureObject_t in_obj;
        memset(&in_obj, 0, sizeof(in_obj));

        CUDA_CHECK_ERRORS(cudaCreateTextureObject(&in_obj, &in_res_desc, &tex_desc, nullptr));

        cudaResourceDesc out_res_desc;
        memset(&out_res_desc, 0, sizeof(out_res_desc));
        out_res_desc.resType = cudaResourceTypeArray;
        out_res_desc.res.array.array = gpu_out.array_ptr();
    
        cudaSurfaceObject_t out_obj;
        memset(&out_obj, 0, sizeof(out_obj));
        
        CUDA_CHECK_ERRORS(cudaCreateSurfaceObject(&out_obj, &out_res_desc));

        dim3 block_size{8,8,1};
        dim3 grid_size
        {
            (W + block_size.x - 1) / block_size.x,
            (H + block_size.y - 1) / block_size.y,
            (D + block_size.z - 1) / block_size.z
        };
        
        copy_texture_kernel<<<grid_size, block_size>>>(
            in_obj,
            out_obj
        );
        CUDA_CHECK_ERRORS(cudaGetLastError());
        CUDA_CHECK_ERRORS(cudaDeviceSynchronize());

        CUDA_CHECK_ERRORS(cudaDestroyTextureObject(in_obj));
        CUDA_CHECK_ERRORS(cudaDestroySurfaceObject(out_obj));

        VolumeFloat out = gpu_out.download();
        REQUIRE(compare_volumes<float>(in, out));
    }
}
