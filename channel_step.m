function [channel, nodes, stats] = channel_step(channel, nodes, params, stats, t)
% channel_step.m
% Resolves transmissions, collisions, and updates channel state
% Extended version for realistic energy & current waste modeling.

N = length(nodes);

% ---------------- Detect active transmissions ----------------
activeTxNodes = [];
for i = 1:N
    if strcmp(nodes(i).state,'Transmit') && ~isempty(nodes(i).current_tx)
        activeTxNodes(end+1) = i; %#ok<AGROW>
    end
end

numActive = length(activeTxNodes);

% Initialize fields for collision energy/current if not already in stats
if ~isfield(stats, 'energy_wasted_tx')
    stats.energy_wasted_tx = 0;
    stats.energy_wasted_rx = 0;
    stats.current_wasted_tx = 0;
    stats.current_wasted_rx = 0;
end

% ---------------- Collision Handling ----------------
if numActive > 1
    % --- Collision detected ---
    stats.collisions = stats.collisions + 1;

    for idx = 1:numActive
        node_id = activeTxNodes(idx);
        pktType = nodes(node_id).current_tx.type;

        % --- Calculate energy & current wasted based on coil config ---
        [dur, eTotal] = coil_tx_params(pktType, params.config, params);

        % TX wasted energy (total per collided node)
        stats.energy_wasted_tx = stats.energy_wasted_tx + eTotal;

        % RX wasted energy (approx. receiver listening during collision)
        stats.energy_wasted_rx = stats.energy_wasted_rx + ...
            params.energy_per_step.receive * dur;

        % TX/RX wasted currents (in A·s)
        I_tx = params.currents.tx_single / 1000;
        I_rx = params.currents.receive / 1000;
        stats.current_wasted_tx = stats.current_wasted_tx + I_tx * (params.dt * dur);
        stats.current_wasted_rx = stats.current_wasted_rx + I_rx * (params.dt * dur);

        % --- Reset node state ---
        nodes(node_id).stats.collisions = nodes(node_id).stats.collisions + 1;
        nodes(node_id).current_tx = [];
        nodes(node_id).state = 'Backoff';
        nodes(node_id).timer = ceil(params.tau_wait_base * (0.5 + rand()));
    end

    channel.state = 'busy';
    channel.transmissions = [];

elseif numActive == 1
    % --- Successful transmission ---
    node_id = activeTxNodes(1);
    pktType = nodes(node_id).current_tx.type;

    if nodes(node_id).timer <= 0
        if strcmp(pktType,'Data')
            stats.successfulData = stats.successfulData + 1;
            stats.bytesTransmitted = stats.bytesTransmitted + nodes(node_id).current_tx.size;
        end
        nodes(node_id).current_tx = [];
        nodes(node_id).state = 'Idle';
    end

    channel.state = 'busy';
    channel.transmissions = node_id;

else
    % --- Idle channel ---
    channel.state = 'free';
    channel.transmissions = [];
end

% Carrier sense flag
channel.currentCarrier = numActive > 0;

end
