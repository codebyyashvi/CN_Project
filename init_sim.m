function params = init_sim(N, T, config)
% init_sim.m
% Initialize simulation parameters, node array and channel structure.
% Inputs:
%   N      - number of nodes
%   T      - total time steps (not strictly used here, but passed for completeness)
%   config - 'sequential', 'simultaneous', or 'hybrid'
%
% Output:
%   params - struct containing:
%     .N, .T, .config
%     .nodes (1xN struct array initialized)
%     .channel (struct)
%     .packetSizes, timing params, energy params, traffic_lambda, etc.
%
% NOTE: This function is called by mi_mac_sim.m. Do not rename.

%% Basic meta
params.N = N;
params.T = T;
params.config = config;

%% Packet sizes (bytes) from paper
params.packetSizes.W   = 13;   % WakeUp
params.packetSizes.ACK = 9;    % Acknowledgement
params.packetSizes.Data= 24;   % Data (maximum)

%% Timing parameters (time-steps are arbitrary units)
% These are representative values you can tune.
params.tau_txW    = 5;   % duration to transmit WakeUp packet (in steps)
params.tau_txAck  = 3;   % duration to transmit ACK packet
params.tau_txData = 10;  % duration to transmit Data packet
params.tau_sense  = 2;   % carrier sense time
params.tau_safe   = 1;   % safety time (randomized fraction used later)

% Derived timers
params.tau_noAck = params.tau_txW + params.tau_txAck + params.tau_safe;
params.tau_wait_base = params.tau_txW + params.tau_sense + params.tau_txAck + params.tau_txData + params.tau_safe;

%% Energy / current parameters (based on values in the paper - units mA)
% These are approximate per-state currents measured in the paper (Table IV)
% Idle: 60 uA -> 0.06 mA, Receive: 0.49 mA, Sense: 0.74 mA
params.currents.idle    = 0.06;   % mA
params.currents.receive = 0.49;   % mA
params.currents.sense   = 0.74;   % mA

% Transmit current for single coil excitation (measured approx)
% In the paper they observed ~220 mA when a single coil is active during tx.
params.currents.tx_single = 220;  % mA (single coil transmit current)

% Supply voltage (V) and time-step (seconds per step)
params.V = 3.3;       % volts
params.dt = 1e-3;     % seconds per simulation time-step (1 ms). Adjust as needed.

% Convert to energy per time-step (Joules): I(mA) -> A = I/1000; Power = V*I(A); Energy_per_step = Power * dt
params.energy_per_step.idle    = (params.currents.idle/1000)    * params.V * params.dt; % J per step
params.energy_per_step.receive = (params.currents.receive/1000) * params.V * params.dt;
params.energy_per_step.sense   = (params.currents.sense/1000)   * params.V * params.dt;
% tx energy will be calculated per-packet using coil multipliers (see coil_tx_params.m)

%% Coil configuration multipliers (used by coil_tx_params helper)
% These represent how many coil excitations (or effective current multiplier)
% are used for different configs and packet types. Values capture paper behaviour.
%
% Interpretation:
%  - sequential: each logical packet is sent once per coil (3 times) -> longer airtime but lower instantaneous power per coil
%  - simultaneous: excite 3 coils together -> high instantaneous current (~3x)
%  - hybrid: WakeUp on all 3 coils (3x), subsequent ACK/Data on strongest single coil (1x)
%
params.coilConfig = config;
switch lower(config)
    case 'sequential'
        params.coil.multiplier.W    = 3; % WakeUp sent sequentially on each coil (three transmissions)
        params.coil.multiplier.ACK  = 3;
        params.coil.multiplier.Data = 3;
        params.coil.timeMultiplier  = 3; % duration multiplier (each packet takes 3x time)
        params.coil.currentMultiplier = 1; % per-transmission current ~ single coil (we model multiplicative time instead)
    case 'simultaneous'
        params.coil.multiplier.W    = 1; % single transmission but all 3 coils excited -> higher instantaneous current
        params.coil.multiplier.ACK  = 1;
        params.coil.multiplier.Data = 1;
        params.coil.timeMultiplier  = 1; % time stays same
        params.coil.currentMultiplier = 3; % 3x current when transmitting (approx)
    case 'hybrid'
        params.coil.multiplier.W    = 1; % We will model WakeUp as "3-coil excitation" via currentMultiplier but single transmit time
        params.coil.multiplier.ACK  = 1; % ACK/Data use single coil
        params.coil.multiplier.Data = 1;
        params.coil.timeMultiplier  = 1;
        % for hybrid we will treat W specially in coil_tx_params (so set currentMultiplier=1 here)
        params.coil.currentMultiplier = 1;
    otherwise
        error('Unknown coil configuration: %s', config);
end

%% Traffic generation parameter
% lambda is the per-node probability to generate a data packet in a time-step
% (tune this to produce light/heavy traffic). Example small lambda for sporadic traffic.
params.traffic_lambda = 5e-4;  % ~0.0005 probability per node per time-step

%% Initial energy per node (Joules)
% Choose a value to allow many transmissions; here we set to a number that will allow
% enough lifetime for the simulation length. This value is arbitrary (tune to taste).
% Example: choose initial energy equivalent to a small battery: e.g., 1000 J (very large) -> for demo use smaller
params.E_init = 0.5; % Joules (you can increase to 5 or 10 to avoid node death in short sims)

%% Initialize nodes array
nodes = repmat(struct(), 1, N);
for i = 1:N
    nodes(i).id = i;
    nodes(i).state = 'Idle';        % 'Idle','Sense','Transmit','Receive','Backoff','Sleep'
    nodes(i).energy = params.E_init;% remaining energy (J)
    nodes(i).tx_queue = {};         % cell array of packets waiting to send
    nodes(i).current_tx = [];       % current packet being transmitted (struct) or []
    nodes(i).timer = 0;             % general purpose countdown timer (time-steps)
    nodes(i).isDead = false;        % true when energy <= 0
    nodes(i).last_tx_time = -inf;
    nodes(i).waiting_for_ack = false;
    nodes(i).ack_deadline = -inf;   % time-step by which ACK must arrive (if waiting)
    nodes(i).stats.success = 0;     % successful data packets sent
    nodes(i).stats.collisions = 0;
    nodes(i).stats.txAttempts = 0;
end

% Attach to params
params.nodes = nodes;

%% Initialize channel struct
channel.state = 'free';     % 'free' or 'busy'
channel.transmissions = []; % array of structs {node_id, pktType, timeLeft, txEnergyTotal}
channel.currentCarrier = false; % boolean if any carrier active
params.channel = channel;

%% Convenience values (for plotting/units)
params.info.V = params.V;
params.info.dt = params.dt;
params.info.energy_per_step = params.energy_per_step;
params.currents.Tx = 0.22;   % A (220 mA)
params.currents.Rx = 0.049;  % A (49 mA)
params.tdur.Tx = 0.005;      % 5 ms
params.tdur.Rx = 0.005;      % 5 ms

%% Display initialization summary
fprintf('Initialized simulation: N=%d, T=%d, config=%s\n', N, T, config);
fprintf('Timing (W,ACK,Data) = (%d, %d, %d) steps\n', params.tau_txW, params.tau_txAck, params.tau_txData);
fprintf('Energy-per-step (idle/sense/receive) in microJ: %.3e, %.3e, %.3e\n', ...
    params.energy_per_step.idle*1e6, params.energy_per_step.sense*1e6, params.energy_per_step.receive*1e6);

end
