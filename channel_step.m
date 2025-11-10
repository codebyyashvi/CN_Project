function [channel, nodes, stats] = channel_step(channel, nodes, params, stats, t)
% channel_step.m
% Resolves transmissions, collisions, and updates channel state
% Now extended to measure energy and current wasted due to collisions.

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
    for idx = 1:numActive
        node_id = activeTxNodes(idx);
        nodes(node_id).stats.collisions = nodes(node_id).stats.collisions + 1;
        nodes(node_id).current_tx = [];
        nodes(node_id).state = 'Backoff';
        nodes(node_id).timer = ceil(params.tau_wait_base * (0.5 + rand())); % random backoff
    end

    % Update collision stats
    stats.collisions = stats.collisions + 1;

    % --- Energy and current wasted calculations ---
    V = params.V;                  % voltage (V)
    I_tx = params.currents.tx_single / 1000; % convert mA to A
    I_rx = params.currents.receive / 1000;   % convert mA to A
    t_tx = params.dt * params.tau_txData;    % transmission duration (s)
    t_rx = params.dt * params.tau_txData;    % receive duration (s)

    % Energy wasted per node in this collision
    E_tx = V * I_tx * t_tx;
    E_rx = V * I_rx * t_rx;

    % Add to totals (Tx and Rx)
    stats.energy_wasted_tx = stats.energy_wasted_tx + numActive * E_tx;
    stats.energy_wasted_rx = stats.energy_wasted_rx + numActive * E_rx;

    % Equivalent wasted current (I = E / (V * t))
    stats.current_wasted_tx = stats.energy_wasted_tx / (V * t_tx);
    stats.current_wasted_rx = stats.energy_wasted_rx / (V * t_rx);

    % Channel state update
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
    % --- No transmission (idle channel) ---
    channel.state = 'free';
    channel.transmissions = [];
end

% Carrier sense flag
channel.currentCarrier = numActive > 0;

end
