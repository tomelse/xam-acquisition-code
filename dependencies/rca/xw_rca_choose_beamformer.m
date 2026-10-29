function [beamform, beamformer] = xw_rca_choose_beamformer(P, beamformer)
    % [beamform, beamformer] = xw_rca_choose_beamformer(P, beamformer)
    %   The RCA beamformer function: 'cpu' (xw_rca_beamform_cpu), 'gpu'
    %   (xw_rca_beamform_gpu, checks that the GPU can be used) or 'auto' (cpu if
    %   P.use_cpu_beamformer, else gpu). Returns the function handle and the name.
    if nargin < 2 || isempty(beamformer), beamformer = 'auto'; end
    if strcmp(beamformer, 'auto')
        if isfield(P, 'use_cpu_beamformer') && P.use_cpu_beamformer
            beamformer = 'cpu';
        else
            beamformer = 'gpu';
        end
    end
    switch beamformer
        case 'cpu'
            beamform = @xw_rca_beamform_cpu;
            fprintf('Using the CPU beamformer (xw_rca_beamform_cpu)\n');
        case 'gpu'
            fprintf('Starting the GPU (the first time on a new GPU, MATLAB compiles its GPU libraries, which can take minutes)\n');
            [gpu_ok, gpu_msg] = xw_beamform_gpu_available();
            if ~gpu_ok
                error('xw_beamform:nogpu', ['The GPU beamformer cannot run: %s.\n' ...
                    'To use the slow CPU beamformer instead, set P.use_cpu_beamformer = true or run with --cpu-beamformer.'], gpu_msg);
            end
            beamform = @xw_rca_beamform_gpu;
            fprintf('Using the GPU beamformer (xw_rca_beamform_gpu) on %s\n', gpu_msg);
        otherwise
            error('xw_rca:beamformer', 'Unknown beamformer ''%s'': use ''auto'', ''gpu'' or ''cpu''', beamformer);
    end
end
