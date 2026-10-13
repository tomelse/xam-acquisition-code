function xw_sequence_save_acquisition_parameters()

    % get stuff from workspace
    P = evalin('base', 'P');
    % VarsToSave = evalin('base', 'VarsToSave');
    VarsToSave = {
                  'P';
                  'Resource';
                  'Trans';
                  'TW';
                  'TX';
                  'Receive';
                  'RcvProfile';
                  'TPC';
                  'TGC';
                  'Media';
                  'UISTATES';
                  };

    % skip variables that are not defined (e.g. RcvProfile when left at default)
    VarsToSave = VarsToSave(cellfun(@(v) check_if_exist('base', v) > 0, VarsToSave));

    if ~isfolder(P.save_path); mkdir(P.save_path); end
    [~, base_name] = fileparts(P.matfile_file_name);
    save_path = fullfile(P.save_path, [base_name '_ACQ_PARAMETERS.mat']);

    % and save (and set saving display)
    varStr = char(join(compose('''%s'',', string(VarsToSave))));
    saveStr = ['save(''' save_path ''', ' varStr ' ''-v7'');']; % use v7, way faster
    disp(saveStr)
    evalin('base', saveStr);
    fprintf('Data Saved! %s\n', save_path)

end
