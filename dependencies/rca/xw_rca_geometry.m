function G = xw_rca_geometry(Trans, first_orientation)
    % G = xw_rca_geometry(Trans, first_orientation)
    %   Geometry of a row-column array (Trans.type = 4) for the xAM sequence.
    %   Elements 1:N/2 are the 'x elements' (positions along x, bars along y)
    %   and N/2+1:N the 'y elements' (positions along y), as in the Verasonics
    %   RC examples. The sequence has two orientations: all rays transmitted
    %   with the elements of one half, received with the other half, then the
    %   other way around. first_orientation (1 or 2) is the half that
    %   transmits first.
    %
    %   G.num_half   : elements per half
    %   G.tx_elements{o}, G.rx_elements{o} : element indices of orientation o
    %   G.tx_pos{o}, G.rx_pos{o}           : positions of these along their axis [mm]
    %   G.tx_view{o} : Trans-like struct of the transmit half as a linear array
    %                  (for xw_setup_build_transmit)
    %   G.rcv_cols{o}: columns of the receive buffer (hardware channels) of rx_elements{o}
    %   G.connector_source: where the element to channel mapping comes from: 'Connector'
    %                (Trans.Connector, present while VSX runs), else 'ConnectorES' (as
    %                defined by computeTrans, before VSX has run) or 'identity'
    if nargin < 2, first_orientation = 1; end
    assert(Trans.type == 4, 'xw_rca:type', 'Trans.type is %i: a row-column array has Trans.type = 4', Trans.type);
    assert(ismember(first_orientation, [1 2]), 'first orientation must be 1 or 2');
    nh = Trans.numelements / 2;
    assert(nh == round(nh), 'a row-column array has an even number of elements');
    if isfield(Trans, 'Connector') && ~isempty(Trans.Connector)
        connector = Trans.Connector; G.connector_source = 'Connector';
    elseif isfield(Trans, 'ConnectorES') && ~isempty(Trans.ConnectorES)
        connector = Trans.ConnectorES; G.connector_source = 'ConnectorES';
    else
        connector = (1:2 * nh)'; G.connector_source = 'identity';
    end
    half = {1:nh, nh + 1:2 * nh};
    half_pos = {Trans.ElementPos(1:nh, 1), Trans.ElementPos(nh + 1:2 * nh, 2)}; % [mm]
    order = [first_orientation, 3 - first_orientation];

    G.num_half = nh;
    G.first_half = first_orientation;
    for o = 1:2
        tx = order(o); rx = 3 - tx;
        G.tx_elements{o} = half{tx};
        G.rx_elements{o} = half{rx};
        G.tx_pos{o} = half_pos{tx};
        G.rx_pos{o} = half_pos{rx};
        v = struct('numelements', nh, 'spacingMm', Trans.spacingMm, 'units', 'mm');
        v.ElementPos = zeros(nh, 5);
        v.ElementPos(:, 1) = half_pos{tx};
        G.tx_view{o} = v;
        G.rcv_cols{o} = reshape(connector(half{rx}), 1, []);
    end
end
