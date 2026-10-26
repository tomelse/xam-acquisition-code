function BFData = xw_beamform_run(RFData)
    % External process function called by VSX for every frame: reconstructs
    % the images (xw_reconstruct_setup / xw_reconstruct_frame, shared with
    % offline reconstruction in examples/reconstruct_rf.m), records the frame
    % and advances a voltage sweep, applies persistence and puts BFData in
    % the base workspace for display.

    fprintfd('Starting beamforming\n')

    % image grid, delay tables and beamformer, set up on the first frame
    persistent R
    if isempty(R)
        R = xw_reconstruct_setup(evalin('base', 'P'), evalin('base', 'Receive'), ...
            evalin('base', 'Trans'), evalin('base', 'TW'));
    end

    BFData = xw_reconstruct_frame(R, RFData);

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
