function chunks = xw_rca_chunk_plan(num_rays, num_chunks)
    % chunks = xw_rca_chunk_plan(num_rays, num_chunks)
    %   Groups of rays that are transferred and reconstructed together in the
    %   RCA sequence. The rays of the two orientations are numbered one after
    %   the other (global rays 1..2*num_rays, orientation 1 first), and a
    %   chunk never contains rays of both orientations, as they are received
    %   with different elements. So there are at least 2 chunks; num_chunks is
    %   the total (rounded up to an even number).
    %
    %   chunks : struct array with fields
    %     orientation : 1 or 2
    %     rays        : rays of this orientation, 1..num_rays
    %     global_rays : the same rays in the numbering of the whole frame
    per_orientation = max(1, ceil(num_chunks / 2));
    groups = xw_chunk_rays(num_rays, per_orientation);
    chunks = struct('orientation', {}, 'rays', {}, 'global_rays', {});
    for o = 1:2
        for k = 1:numel(groups)
            chunks(end + 1) = struct('orientation', o, 'rays', groups{k}, ...
                'global_rays', groups{k} + (o - 1) * num_rays); %#ok<AGROW>
        end
    end
end
