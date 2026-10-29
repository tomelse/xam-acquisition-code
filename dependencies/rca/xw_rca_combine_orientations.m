function BFData = xw_rca_combine_orientations(R, part)
    % BFData = xw_rca_combine_orientations(R, part)
    %   Combine the volumes of the two orientations (transmit with one half of
    %   the elements and receive with the other, and the other way around) into
    %   one volume per mode. part{o}.(mode) is [depth, positions along the
    %   receive axis, rays, frames] of orientation o. In orientation 1 the
    %   receive axis is the second axis and the rays are along the first, in
    %   orientation 2 the other way around, so orientation 2 is permuted to
    %   [depth, second axis, first axis, frames]. The two are combined
    %   incoherently (root mean square of the envelopes).
    BFData = struct();
    for mode = R.modes
        v1 = abs(part{1}.(mode{1}));
        v2 = permute(abs(part{2}.(mode{1})), [1 3 2 4]);
        BFData.(mode{1}) = sqrt((v1 .^ 2 + v2 .^ 2) / 2);
    end
end
