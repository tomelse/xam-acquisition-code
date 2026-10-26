function C = xw_chunk_timing(P, RFData)
    % C = xw_chunk_timing(P, RFData)
    %   Acquisition timing within frames from the hardware time tags, to check
    %   how the chunk transfers (sub-frame DMA, P.num_chunks) affect it.
    %   Hardware data only: in simulation all time tags are 0. Needs the
    %   'ray-major' layout. Run it on an RF snapshot or recording:
    %       S = load('snapshot_rf.mat', 'P', 'RcvData'); C = xw_chunk_timing(S.P, S.RcvData{1})
    %
    %   P      : sequence parameters (num_rays, num_angles, num_chunks, Nz_RF, ttna)
    %   RFData : RF data, [rows, channels, frames]
    %
    %   C has fields (times in seconds)
    %     increasing    : true if the time tags of the acquisitions increase in every frame
    %     ttna          : programmed time between acquisitions
    %     within_chunk  : median time between consecutive acquisitions of a chunk
    %     pause         : extra time (beyond ttna) before the first acquisition of
    %                     each next chunk, [chunks-1, frames]
    %     span          : mean time from the first to the last acquisition of a frame
    %     span_expected : (acquisitions - 1) * ttna
    %     num_chunks
    n_acq = 3 * P.num_angles * P.num_rays; % acquisitions per frame
    chunk_rays = xw_chunk_rays(P.num_rays, P.num_chunks);
    last_acq = cumsum(cellfun(@numel, chunk_rays)) * 3 * P.num_angles; % last acquisition of each chunk
    first_row = (0:n_acq - 1) * P.Nz_RF + 1; % time tag: first two samples of channel 1
    nF = size(RFData, 3);

    C.ttna = P.ttna * 1e-6;
    C.num_chunks = numel(chunk_rays);
    C.increasing = true;
    within = [];
    C.pause = zeros(C.num_chunks - 1, nF);
    span = zeros(1, nF);
    for f = 1:nF
        rf = RFData(:, 1, f);
        tags = TimeTag2Sec(rf([first_row; first_row + 1]));
        dt = diff(tags);
        C.increasing = C.increasing && all(dt > 0);
        is_boundary = ismember(1:numel(dt), last_acq(1:end - 1));
        within = [within, dt(~is_boundary)]; %#ok<AGROW>
        C.pause(:, f) = dt(is_boundary) - C.ttna;
        span(f) = tags(end) - tags(1);
    end
    C.within_chunk = median(within);
    C.span = mean(span);
    C.span_expected = (n_acq - 1) * C.ttna;
end
