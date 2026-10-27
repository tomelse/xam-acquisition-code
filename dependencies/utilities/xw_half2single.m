function X = xw_half2single(H, method)
    % X = xw_half2single(H)
    %   Convert RF data acquired with Receive.datatype = 'half' to single. The
    %   system returns half (16 bit floating point) data to MATLAB as the bit
    %   patterns in an int16 array, which is what is saved in RcvData and in RF
    %   recordings.
    %
    %   H : int16 array (any size; the mex function of the Vantage software needs 2 or 3 dimensions)
    %   X : single array of the same size. NaN and Inf as in the half data.
    %
    %   Uses convertHalfRcvData of the Vantage software if it is on the path
    %   (activate), else a MATLAB implementation, so that saved data can also be
    %   processed without the Vantage software. xw_half2single(H, 'matlab')
    %   always uses the MATLAB implementation.
    %
    %   The values are as stored: the system divides the 22 bit filter output by 256
    %   before storing it as half, so multiply by 256 for the scale of int16 data.
    %
    %   Note that the hardware time tags in the first two samples of every
    %   acquisition are not half data (see TimeTag2Sec); xw_reconstruct_rays sets
    %   these samples to 0 after converting.
    assert(isa(H, 'int16'), 'xw_half2single: input must be int16 (the half bit patterns)');
    if nargin < 2, method = 'auto'; end
    if ~strcmp(method, 'matlab') && exist('convertHalfRcvData', 'file') == 3 && ismember(ndims(H), [2 3])
        X = convertHalfRcvData(H, 'single');
        return
    end
    u = typecast(H(:), 'uint16');
    sgn = single(1 - 2 * double(bitshift(u, -15)));
    e = single(bitand(bitshift(u, -10), 31));
    f = single(bitand(u, 1023));
    x = (1024 + f) .* 2 .^ (e - 25); % normal numbers
    sub = e == 0;
    x(sub) = f(sub) * 2 ^ -24; % subnormal numbers and zero
    x(e == 31 & f == 0) = Inf;
    x(e == 31 & f ~= 0) = NaN;
    X = reshape(sgn .* x, size(H));
end
