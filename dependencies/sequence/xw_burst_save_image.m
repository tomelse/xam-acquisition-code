function xw_burst_save_image(imData)
    % External process at the end of a burst, called for every frame in turn after
    % its reconstruction: keeps the image (reconstructed intensity [depth, rays x 2]) in
    % XWBurst.images. xw_burst_finish saves them.
    if ~evalin('base', 'exist(''XWBurst'', ''var'') && XWBurst.active')
        return
    end
    B = evalin('base', 'XWBurst');
    k = B.image_count + 1;
    if k == 1
        B.images = zeros([size(imData, [1 2]), B.num_frames], 'single');
    end
    if k <= B.num_frames
        B.images(:, :, k) = imData(:, :, 1);
        B.image_count = k;
    end
    assignin('base', 'XWBurst', B);
end
