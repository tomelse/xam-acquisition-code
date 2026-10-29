function xw_setup_timetag()
    % Enable Verasonics Time Tags to check sequence timing.
    % Resource.VDAS.acqTimeTagEnable = 1 (set in the scripts) enables the acquisition
    % time tags in all versions of the software. This also enables them explicitly
    % and resets the counter, with Java methods that older software (e.g. Vantage
    % NXT 2.1.0) does not have: then they are skipped.
    import com.verasonics.hal.hardware.*
    VDAS = evalin('base', 'VDAS');
    if VDAS
        try
            % enable time tag
            rc = Hardware.enableAcquisitionTimeTagging(true);
            if ~rc
                error('Error from enableAcqTimeTagging')
            end
            % and reset counter
            rc = Hardware.setTimeTaggingAttributes(false, true);
            if ~rc
                error('Error from setTimeTaggingAttributes')
            end
        catch e
            if ~contains(e.message, 'no Constant property or Static method')
                rethrow(e)
            end
            fprintf(['Time tags: this software version has no Hardware.enableAcquisitionTimeTagging / ' ...
                'setTimeTaggingAttributes; using Resource.VDAS.acqTimeTagEnable only (the time tag counter is not reset).\n']);
        end
    end
end
