function BFData = xw_rca_beamform_run(RFData, chunk)
    % External process function called by VSX in xAM_imaging_RCA.m: reconstructs
    % the volumes (xw_rca_reconstruct_setup / xw_rca_reconstruct_chunk, as
    % xw_beamform_run does for the linear array), records the frame and
    % advances a voltage sweep, applies persistence and puts BFData in the base
    % workspace for display.
    %
    % xw_rca_beamform_run(RFData) reconstructs a whole frame. The sequence
    % transfers the frame in groups of rays (chunks, see xw_rca_chunk_plan) and
    % calls xw_rca_beamform_run(RFData, k) once the rays of chunk k have
    % arrived. The volumes are assembled, and after the last chunk the frame is
    % finished as above. Returns [] for the other chunks.

    fprintfd('Starting beamforming\n')

    % volume grid, delay tables and beamformer, set up on the first frame
    persistent R part
    if isempty(R)
        R = xw_rca_reconstruct_setup(evalin('base', 'P'), evalin('base', 'Receive'), ...
            evalin('base', 'Trans'), evalin('base', 'TW'));
    end

    if nargin < 2
        BFData = xw_rca_reconstruct_frame(R, RFData);
    else
        if chunk == 1, part = cell(1, 2); end
        c = R.chunks(chunk);
        IQ = xw_rca_reconstruct_chunk(R, RFData, chunk);
        for mode = R.modes
            if isempty(part{c.orientation}) || ~isfield(part{c.orientation}, mode{1})
                part{c.orientation}.(mode{1}) = complex(zeros(R.BFC.Nz, numel(R.P.out_axis{c.orientation}), R.P.num_rays, 'single'));
            end
            part{c.orientation}.(mode{1})(:, :, c.rays) = IQ.(mode{1});
        end
        if chunk < numel(R.chunks)
            BFData = [];
            return
        end
        BFData = xw_rca_combine_orientations(R, part);
        BFData.TimeTag = xw_rca_time_tag(R, RFData);
    end

    % save frame to disk if recording, and advance a voltage sweep
    xw_record_frame(RFData, BFData);
    xw_sweep_frame(BFData);
    xw_burst_update_button();

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
    P.z_axis = R.P.z_axis;
    P.axis_first = R.P.axis_first;
    P.axis_second = R.P.axis_second;
    assignin('base', 'BFData', BFData);
    assignin('base', 'P', P);
    assignin('base', 'BFC', R.BFC);
end
