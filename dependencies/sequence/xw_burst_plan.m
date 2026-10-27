function plan = xw_burst_plan(num_pre, num_collapse, num_post)
    % plan = xw_burst_plan(num_pre, num_collapse, num_post)
    %   Frames of a burst: num_pre frames at the imaging voltage (TPC profile
    %   1), num_collapse frames at the burst voltage (profile 2), then num_post
    %   frames at the imaging voltage again. Used to build the burst events in
    %   xAM_imaging.m and to label the frames while they are processed.
    %
    %   plan.num_frames    : total number of frames
    %   plan.profile       : [1, num_frames] TPC profile used for each frame
    %   plan.switch_before : [1, num_frames] TPC profile to switch to before the
    %                        frame is acquired, 0 = keep the profile. Frame 1
    %                        always sets its profile, so a burst starts from a
    %                        known voltage.
    assert(all([num_pre, num_collapse, num_post] >= 0 & [num_pre, num_collapse, num_post] == round([num_pre, num_collapse, num_post])), ...
        'Burst frame counts must be non-negative integers')
    assert(num_collapse >= 1, 'A burst needs at least one frame at the burst voltage')
    plan.profile = [ones(1, num_pre), 2 * ones(1, num_collapse), ones(1, num_post)];
    plan.num_frames = numel(plan.profile);
    plan.switch_before = [plan.profile(1), plan.profile(2:end) .* (diff(plan.profile) ~= 0)];
end
