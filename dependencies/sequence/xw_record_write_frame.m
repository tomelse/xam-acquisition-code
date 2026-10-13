function xw_record_write_frame(fn, RF)
    % Write one raw RF frame to its own file. Runs on a backgroundPool thread,
    % started by xw_record_frame. Native byte order: an explicit 'ieee-le'
    % makes fwrite ~3.5x slower, even on little-endian machines.
    fid = fopen(fn, 'w');
    if fid < 0
        error('xw_record:open', 'Could not open %s for writing.', fn);
    end
    count = fwrite(fid, RF, class(RF));
    fclose(fid);
    if count ~= numel(RF)
        error('xw_record:write', 'Only %i of %i samples written to %s (disk full?).', count, numel(RF), fn);
    end
end
