function rays = xw_chunk_rays(num_rays, num_chunks)
    % rays = xw_chunk_rays(num_rays, num_chunks)
    %   Split rays 1..num_rays into num_chunks groups of consecutive rays that
    %   differ in size by at most one. rays is a cell array, one vector per
    %   chunk. num_chunks is limited to num_rays.
    num_chunks = max(1, min(round(num_chunks), num_rays));
    edges = round(linspace(0, num_rays, num_chunks + 1));
    rays = arrayfun(@(k) edges(k) + 1:edges(k + 1), 1:num_chunks, 'UniformOutput', false);
end
