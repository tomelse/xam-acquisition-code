function out = run_reconstruct_example(script, data_path) %#ok<INUSD> data_path is read by the script
    % Run examples/reconstruct_rf.m on data_path in this function's workspace
    % (not the base workspace, which VSX uses) and return its results.
    run(script);
    out = struct('images', eval('images'), 'images_dB', eval('images_dB'), 'fig', eval('fig'));
end
