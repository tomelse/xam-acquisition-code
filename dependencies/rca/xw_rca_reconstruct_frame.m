function BFData = xw_rca_reconstruct_frame(R, RFData)
    % BFData = xw_rca_reconstruct_frame(R, RFData)
    %   Reconstruct the volumes of one frame of RF data of the RCA sequence, as
    %   in the live view. R comes from xw_rca_reconstruct_setup.
    %
    %   RFData : [rows, channels] (one frame of RcvData{1}), or
    %            [rows, channels, frames] to reconstruct several at once
    %   BFData : struct with the volumes [depth, second axis, first axis, frames]
    %            of the modes in R.modes ('PW', 'xBmode', 'xAM'), real (envelope),
    %            and TimeTag [s] of the first frame. See xw_rca_combine_orientations.
    nF = size(RFData, 3);
    part = cell(1, 2);
    for k = 1:numel(R.chunks)
        c = R.chunks(k);
        IQ = xw_rca_reconstruct_chunk(R, RFData, k);
        for mode = R.modes
            if isempty(part{c.orientation}) || ~isfield(part{c.orientation}, mode{1})
                part{c.orientation}.(mode{1}) = complex(zeros(R.BFC.Nz, numel(R.P.out_axis{c.orientation}), R.P.num_rays, nF, 'single'));
            end
            part{c.orientation}.(mode{1})(:, :, c.rays, :) = IQ.(mode{1});
        end
    end
    BFData = xw_rca_combine_orientations(R, part);
    BFData.TimeTag = xw_rca_time_tag(R, RFData);
end
