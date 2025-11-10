function [duration, energyTotal] = coil_tx_params(pktType, config, params)
% Returns transmit duration (steps) and total energy (J) for packet type & config

% base durations (in steps)
switch pktType
    case 'W'
        baseDur = params.tau_txW;
    case 'ACK'
        baseDur = params.tau_txAck;
    case 'Data'
        baseDur = params.tau_txData;
    otherwise
        error('Unknown pktType');
end

% Duration depends on sequential time multiplier (sequential sends same packet 3 times)
if strcmpi(config,'sequential')
    duration = baseDur * params.coil.timeMultiplier; % usually 3x time
else
    duration = baseDur * 1; % simultaneous/hybrid send in one slot
end

% Determine effective transmit current (A) for this pkt and config
I_single_A = params.currents.tx_single/1000; % convert mA -> A
switch lower(config)
    case 'sequential'
        % sequential: send same packet 3 times on single coil each -> energy accounted via duration multiplier
        I_effective = I_single_A;
    case 'simultaneous'
        % all 3 coils excited together: ~3x current.
        I_effective = I_single_A * 3;
    case 'hybrid'
        % hybrid: WakeUp uses all coils (3x current); ACK/Data use single coil
        if strcmp(pktType,'W')
            I_effective = I_single_A * 3;
        else
            I_effective = I_single_A;
        end
    otherwise
        error('Unknown config');
end

% energy per step (J per step) : V * I * dt
energy_per_step = params.V * I_effective * params.dt;

% total energy for full packet transmission (J)
energyTotal = energy_per_step * duration;

end
