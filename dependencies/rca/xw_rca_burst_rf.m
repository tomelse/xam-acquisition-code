function out = xw_rca_burst_rf(cmd, varargin)
    % out = xw_rca_burst_rf(cmd, ...)
    %   Host memory for the raw RF of the frames of a burst of the RCA, which are
    %   reconstructed after the burst (xw_rca_burst_save_image).
    %     xw_rca_burst_rf('reset', rows, cols, num_frames)  allocate, int16 [rows, cols, frames]
    %     xw_rca_burst_rf('set', k, RF)                      store frame k
    %     RF = xw_rca_burst_rf('get', k)                     frame k
    %     xw_rca_burst_rf('clear')                           free the memory
    persistent store
    out = [];
    switch cmd
        case 'reset'
            store = zeros(varargin{1}, varargin{2}, varargin{3}, 'int16');
        case 'set'
            store(:, :, varargin{1}) = varargin{2};
        case 'get'
            out = store(:, :, varargin{1});
        case 'clear'
            store = [];
        otherwise
            error('xw_rca:burstrf', 'Unknown command ''%s''', cmd);
    end
end
