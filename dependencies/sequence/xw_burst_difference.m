function D = xw_burst_difference(images, num_pre, num_collapse)
    % D = xw_burst_difference(images, num_pre, num_collapse)
    %   Burst analysis: the first frame at the burst voltage (frame num_pre + 1,
    %   gas vesicles still intact) minus the mean of the subsequent frames at
    %   the same voltage (the gas vesicles collapse during these), as intensity.
    %
    %   images       : [depth, lateral, frames] reconstructed intensity
    %   num_pre      : number of frames before the burst voltage
    %   num_collapse : number of frames at the burst voltage
    %
    %   D.frame       : index of the frame that is analysed
    %   D.reference   : indices of the frames that are averaged
    %   D.image       : the frame, D.reference_image: the mean of the reference frames
    %   D.difference  : image minus reference_image (negative values are kept)
    n = size(images, 3);
    D = struct('frame', num_pre + 1, 'reference', [], 'image', [], 'reference_image', [], 'difference', []);
    D.reference = num_pre + 1 + (1:num_collapse - 1);
    D.reference = D.reference(D.reference <= n);
    if D.frame > n || isempty(D.reference)
        return % not enough frames, e.g. an aborted burst
    end
    D.image = images(:, :, D.frame);
    D.reference_image = mean(images(:, :, D.reference), 3);
    D.difference = D.image - D.reference_image;
end
