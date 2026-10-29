function roi = xw_rca_crossing_roi(P)
    % roi = xw_rca_crossing_roi(P)
    %   Logical mask [depth, second axis, first axis] of the voxels where the
    %   two plane waves of each ray still cross, within the image depth, for
    %   the rays of both orientations. Used to measure the mean xAM signal in
    %   a voltage sweep (the counterpart of xw_crossing_roi).
    max_depth = min(P.ray_max_image_depth, [], 1); % [1, rays], m
    per_ray = P.z_axis(:) <= max_depth;            % [depth, rays]
    nz = numel(P.z_axis); nr = P.num_rays;
    roi = reshape(per_ray, nz, 1, nr) & reshape(per_ray, nz, nr, 1);
end
