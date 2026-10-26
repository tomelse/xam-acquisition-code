function BFData = xw_beamform_run(RFData, chunk)
    % External process function called by VSX: reconstructs the images
    % (xw_reconstruct_setup / xw_reconstruct_frame, shared with offline
    % reconstruction in examples/reconstruct_rf.m), records the frame and
    % advances a voltage sweep, applies persistence and puts BFData in the base
    % workspace for display.
    %
    % xw_beamform_run(RFData) reconstructs a whole frame. With P.num_chunks > 1
    % the sequence transfers the frame in groups of rays, and calls
    % xw_beamform_run(RFData, k) once the rays of chunk k have arrived (see
    % xw_reconstruct_chunk). The images are assembled, and after the last chunk
    % the frame is finished as above. Returns [] for the other chunks.

    fprintfd('Starting beamforming\n')

    % image grid, delay tables and beamformer, set up on the first frame
    persistent R part
    if isempty(R)
        R = xw_reconstruct_setup(evalin('base', 'P'), evalin('base', 'Receive'), ...
            evalin('base', 'Trans'), evalin('base', 'TW'));
    end

    if nargin < 2
        BFData = xw_reconstruct_frame(R, RFData);
    else
        if chunk == 1, part = []; end
        IQ = xw_reconstruct_chunk(R, RFData, chunk);
        for mode = R.modes
            if chunk == 1
                part.(mode{1}) = complex(zeros(R.BFC.Nz, R.P.num_rays, 'single'));
            end
            part.(mode{1})(:, R.chunks(chunk).rays) = IQ.(mode{1});
        end
        if chunk < numel(R.chunks)
            BFData = [];
            return
        end
        BFData = part;
        BFData.TimeTag = TimeTag2Sec(RFData(1:2, 1, 1));
    end

    % save frame to disk if recording, and advance a voltage sweep
    xw_record_frame(RFData, BFData);
    xw_sweep_frame(BFData);

    % apply persistence if set
    assignin('base', 'BFData_raw', BFData); % raw BFData without persistence
    persistence = evalin('base', 'UISTATES.persistence');
    if persistence < 1
        BFData_prev = evalin('base', 'BFData');
        for mode = R.modes
            BFData.(mode{1}) = persistence * BFData.(mode{1}) + (1 - persistence) * BFData_prev.(mode{1});
        end
    end

    % assign to base workspace
    P = evalin('base', 'P');
    P.x_axis = R.P.x_axis;
    P.z_axis = R.P.z_axis;
    assignin('base', 'BFData', BFData);
    assignin('base', 'LUTStruct', R.LUT);
    assignin('base', 'P', P);
    assignin('base', 'BFC', R.BFC);
end
