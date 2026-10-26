function IQ = xw_reconstruct_chunk(R, RFData, k)
    % IQ = xw_reconstruct_chunk(R, RFData, k)
    %   Reconstruct only the rays of chunk k (R.chunks(k).rays) of a frame, which
    %   can be done as soon as these rays have been transferred from the
    %   hardware, while the other rays are still being acquired. Needs the
    %   'ray-major' layout; see xw_reconstruct_frame.
    %
    %   RFData : one frame of RF data, [rows, channels]; only the rows of the
    %            rays of this chunk are read
    %   IQ     : struct with the complex IQ images ([depth, rays in chunk]) of
    %            the modes in R.modes. Columns R.chunks(k).rays of the image of
    %            xw_reconstruct_frame; the result is identical.
    assert(strcmp(R.layout, 'ray-major'), 'xw_reconstruct_chunk needs the ray-major receive buffer layout (P.rf_layout)');
    c = R.chunks(k);
    IQ = xw_reconstruct_rays(R, RFData, c.BFC, c.LUT, c.rays);
end
