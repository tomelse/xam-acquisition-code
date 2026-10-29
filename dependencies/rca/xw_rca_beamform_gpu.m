function BFIQ = xw_rca_beamform_gpu(BFC, RF, LUT_T, LUT_R)
    % BFIQ = xw_rca_beamform_gpu(BFC, RF, LUT_T, LUT_R)
    %   GPU version of xw_rca_beamform_cpu: the same code, run on gpuArrays.
    %   Inputs and output as xw_rca_beamform_cpu; the output is gathered.
    %   The delay tables are uploaded here if they are not on the GPU yet
    %   (xw_rca_reconstruct_setup keeps them there).
    if ~isa(LUT_T, 'gpuArray'), LUT_T = gpuArray(LUT_T); end
    if ~isa(LUT_R, 'gpuArray'), LUT_R = gpuArray(LUT_R); end
    BFIQ = gather(xw_rca_beamform_cpu(BFC, RF, LUT_T, LUT_R));
end
