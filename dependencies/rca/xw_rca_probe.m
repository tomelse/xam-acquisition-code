function D = xw_rca_probe(name)
    % D = xw_rca_probe(name)
    %   Starting values of the settings that depend on the row-column array
    %   (RCA) probe, for xAM_imaging_RCA.m. The probes are the Vermon RC15gV
    %   (80 + 80 elements, 13.6 MHz, 0.11 mm pitch) and RC6gV (128 + 128
    %   elements, 6 MHz, 0.2 mm pitch). Their geometry, frequency and voltage
    %   limit come from computeTrans; these are the imaging choices on top.
    %   They are starting values, to be tuned on the hardware.
    switch name
        case 'RC15gV'
            D.image_start_depth_mm = 0;
            D.image_end_depth_mm = 10;
            D.aperture_size_min = 32; % elements in the transmit aperture (per orientation)
            D.aperture_size_max = 64;
            D.burst_voltage = 25; % [V] (limit 30 V)
            D.burst_start_depth_mm = 2;
            D.burst_end_depth_mm = 14;
            D.burst_num_tx = 32;
            D.burst_focus_mm = 6;
        case 'RC6gV'
            D.image_start_depth_mm = 0;
            D.image_end_depth_mm = 30;
            D.aperture_size_min = 48;
            D.aperture_size_max = 96;
            D.burst_voltage = 25; % [V] (limit 40 V)
            D.burst_start_depth_mm = 5;
            D.burst_end_depth_mm = 35;
            D.burst_num_tx = 48;
            D.burst_focus_mm = 15;
        otherwise
            error('xw_rca:probe', 'Unknown RCA probe ''%s'': use ''RC15gV'' or ''RC6gV''', name);
    end
end
