// Copyright (c) 2016-2017 Intel Corporation
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.


#if FP16_SUPPORTED
    #pragma OPENCL EXTENSION cl_khr_fp16 : enable

    #if RELU
        #define ACTIVATION(output, input) output = isinf(convert_half(NEGATIVE_SLOPE)) ? ((input >= 0.0h) ? \
        input : -convert_half(NEGATIVE_SLOPE)) : (max(input, 0.0h) + convert_half(NEGATIVE_SLOPE) * min(input, 0.0h));
    #else
        #define ACTIVATION(output, input) output = input;
    #endif

KERNEL(convolution_gpu_yxfb_yxio_fp16)(
    const __global half* input,
    __global half* output,
    const __global half* filter,
#if BIAS_TERM
    const __global half* bias,
#endif
    uint split_idx)
{
    const int batch_num = INPUT_BATCH_NUM;

    const uint linear_id = get_global_id(0) + get_global_size(0) * (get_global_id(1) + get_global_size(1) * get_global_id(2));
    const int bifn_num = batch_num * FILTER_OUTPUT_FEATURE_NUM;
    int global_id = linear_id % bifn_num + (linear_id / bifn_num) * bifn_num * FILTER_ARRAY_NUM + split_idx * bifn_num;

    const int ofm_offset = (global_id / batch_num) % FILTER_OUTPUT_FEATURE_NUM;

    half result = 0.0h;

    bool finish = false;
    const int out_x = (uint)get_global_id(1) - OUTPUT_PADDING_LOWER_SIZE_X;
    const int out_y = (uint)get_global_id(2) - OUTPUT_PADDING_LOWER_SIZE_Y;

    finish = out_x >= OUTPUT_SIZE_X || out_x < 0;
    finish = (out_y >= OUTPUT_SIZE_Y || out_y < 0) ? true : finish;

    if(!finish)
    {
        const int batch_offset = global_id % batch_num;

        const int x = out_x * STRIDE_SIZE_X + INPUT_OFFSET_SIZE_X;
        const int y = out_y * STRIDE_SIZE_Y + INPUT_OFFSET_SIZE_Y;

        for (uint i = 0; i < FILTER_SIZE_Y; i++)
        {
            int input_offset_y = y + i * DILATION_SIZE_Y;
            bool zero_y = input_offset_y >= INPUT_SIZE_Y || input_offset_y < 0;

            if(!zero_y)
            {
                for (uint j = 0; j < FILTER_SIZE_X; j++)
                {
                    int input_offset_x = x + j * DILATION_SIZE_X;

                    bool zero = input_offset_x >= INPUT_SIZE_X || input_offset_x < 0;

                    if(!zero)
                    {
                        int input_idx = (input_offset_x + (input_offset_y * INPUT_SIZE_X)) * INPUT_FEATURE_NUM * batch_num;
                        input_idx += split_idx * FILTER_INPUT_FEATURE_NUM * batch_num;
                        input_idx += batch_offset;

                        uint filter_idx = ofm_offset + FILTER_INPUT_FEATURE_NUM * FILTER_OUTPUT_FEATURE_NUM * (i * FILTER_SIZE_X + j);

                        for (uint h = 0; h < FILTER_INPUT_FEATURE_NUM; h++)
                        {
                            result = fma(input[input_idx], filter[filter_idx], result);
                            filter_idx += FILTER_OUTPUT_FEATURE_NUM;
                            input_idx += batch_num;
                        }
                    }
                }
            }
        }
    }
#if BIAS_TERM
    result += bias[ofm_offset];
#endif
    ACTIVATION(output[global_id], result);
}

    #undef ACTIVATION
#endif // FP16_SUPPORTED