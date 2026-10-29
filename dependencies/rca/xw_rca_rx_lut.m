function LUT_R = xw_rca_rx_lut(z, x_out, x_el, f_number, c, toffset)
    % LUT_R = xw_rca_rx_lut(z, x_out, x_el, f_number, c, toffset)
    %   Receive delay table of the RCA beamformer: the time [s] from the output
    %   positions (depth z, position x_out along the receive axis) to the receive
    %   elements at x_el, plus toffset, and 0 for the elements outside the
    %   f-number. Lengths in m. LUT_R is [numel(z), numel(x_out), numel(x_el)].
    z = z(:);
    x_out = reshape(x_out, 1, []);
    x_el = reshape(x_el, 1, 1, []);
    d = abs(x_out - x_el); % [1, Nx, nEl]
    in_fnumber = d < z / f_number / 2; % [Nz, Nx, nEl]
    LUT_R = (sqrt(z .^ 2 + d .^ 2) / c + toffset) .* in_fnumber;
end
