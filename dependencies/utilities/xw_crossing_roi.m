function roi = xw_crossing_roi(P)
    % roi = xw_crossing_roi(P)
    %   Logical mask [depth, rays] of the pixels where the two plane waves of
    %   each ray still cross (above the dashed line in the display), within
    %   the image depth. Used to measure the mean xAM signal.
    max_depth = min(P.ray_max_image_depth, [], 1); % [1, rays], m
    roi = P.z_axis(:) <= max_depth;                % [depth, rays]
end
