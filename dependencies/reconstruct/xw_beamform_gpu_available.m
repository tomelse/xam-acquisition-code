function [ok, msg] = xw_beamform_gpu_available()
    % [ok, msg] = xw_beamform_gpu_available()
    %   True if xw_beamform_gpu can run: the Parallel Computing Toolbox is
    %   installed and licensed, and a CUDA GPU is usable. msg says why not.
    %
    %   Enables CUDA forward compatibility first, so GPUs newer than the MATLAB
    %   release (e.g. an RTX 50-series GPU with R2024a) work too. MATLAB then
    %   compiles its GPU libraries for that GPU the first time it is used
    %   (from ~30 s to several minutes, once; kept in the CUDA cache, see
    %   CUDA_CACHE_MAXSIZE in run_xam.sh).
    ok = false;
    if isempty(ver('parallel'))
        msg = 'the Parallel Computing Toolbox is not installed';
        return
    end
    if ~license('test', 'Distrib_Computing_Toolbox')
        msg = 'no licence for the Parallel Computing Toolbox';
        return
    end
    try
        parallel.gpu.enableCUDAForwardCompatibility(true);
        g = gpuDevice;
        ok = g.DeviceSupported;
        msg = sprintf('%s (compute capability %s)', g.Name, g.ComputeCapability);
        if ~ok, msg = [msg ' is not supported by this MATLAB release']; end
    catch e
        msg = ['no usable CUDA GPU: ' e.message];
    end
end
