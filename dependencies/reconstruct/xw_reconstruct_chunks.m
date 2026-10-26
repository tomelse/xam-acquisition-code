function R = xw_reconstruct_chunks(R, num_chunks)
    % R = xw_reconstruct_chunks(R, num_chunks)
    %   Add R.chunks to the reconstruction set up by xw_reconstruct_setup: the
    %   groups of rays (xw_chunk_rays) that xw_reconstruct_chunk reconstructs
    %   separately, each with its own beamformer configuration and delay tables.
    %   The tables are kept on the GPU for the GPU beamformer, so they are not
    %   uploaded again for every call. Empty unless R.layout is 'ray-major'.
    R.chunks = struct('rays', {}, 'BFC', {}, 'LUT', {});
    if ~strcmp(R.layout, 'ray-major'), return, end
    rays = xw_chunk_rays(R.P.num_rays, num_chunks);
    for k = 1:numel(rays)
        c.rays = rays{k};
        c.BFC = R.BFC;
        c.BFC.NRays = numel(c.rays);
        c.LUT.TX = R.LUT.TX(:, c.rays, :);
        c.LUT.RX = R.LUT.RX(:, c.rays, :);
        if strcmp(R.beamformer, 'gpu')
            c.LUT = structfun(@gpuArray, c.LUT, 'UniformOutput', false);
        end
        R.chunks(k) = c;
    end
end
