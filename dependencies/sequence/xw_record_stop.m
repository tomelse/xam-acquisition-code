function xw_record_stop(XWRecord)
    % Stop a recording: no further frames are recorded from now on. Pending
    % background writes are left to finish; xw_record_finish then writes the
    % final recording_info.mat and reports, without blocking the acquisition.
    XWRecord.active = false;
    assignin('base', 'XWRecord', XWRecord);

    if isempty(XWRecord.pending)
        finish(XWRecord, XWRecord.pending);
    else
        afterAll(XWRecord.pending, @(F) finish(XWRecord, F), 0, 'PassFuture', true);
    end
end

function finish(XWRecord, futures)
    % errors in an afterAll callback are otherwise lost silently
    try
        xw_record_finish(XWRecord, futures);
    catch e
        fprintf(2, 'Recording: could not finish %s: %s\n', XWRecord.folder, e.message);
    end
end
