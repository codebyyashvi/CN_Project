% mi_mac_sim.m
% Main driver for MI-MAC protocol simulation
% Save this file in a folder along with the helper .m files:
% init_sim.m, node_step.m, channel_step.m, coil_tx_params.m, utils_plot.m
%
% After saving all files, run this script in MATLAB.

clearvars; close all; clc;

rng(12345); % repeatable results (change/remove for randomness)

%% ---------------- Simulation control ----------------
configs = {'sequential', 'simultaneous', 'hybrid'}; % coil configs to test
N_values = [5, 10, 15, 20, 25, 30]; % number of nodes to simulate (you can expand to [5 10 20 50])
trials = 10;      % number of trials to average per config
T = 10000;        % time steps per trial (increase for longer runs)

show_progress = true; % display progress messages

% Where to store results
results = struct();

%% Loop over network sizes (you can run multiple N values)
for n_idx = 1:length(N_values)
    N = N_values(n_idx);
    fprintf('=== Running experiments for N = %d nodes ===\n', N);
    
    % Pre-allocate per-config results
    config_results = struct();
    
    for c = 1:length(configs)
        cfg = configs{c};
        fprintf('\n-- Configuration: %s --\n', cfg);
        
        % Stats accumulators
        total_throughput = zeros(trials,1);
        total_collisions = zeros(trials,1);
        avg_energy_remaining = zeros(trials,1);
        total_bytes_transmitted = zeros(trials,1);
        nodes_dead_fraction = zeros(trials,1);
        
        for trial = 1:trials
            if show_progress && mod(trial,1)==0
                fprintf('  Trial %d/%d ... ', trial, trials);
            end
            
            % Initialize simulation structures and parameters
            params = init_sim(N, T, cfg); %#ok<NASGU> % helper file
            % init_sim returns 'params' struct and also initial 'nodes' and 'channel' if needed
            nodes = params.nodes;          % nodes array struct
            channel = params.channel;      % channel struct
            stats = init_stats(N);         % local stats struct
            
            % run time loop
            for t = 1:T
                % 1) optionally generate traffic (simple Poisson-like)
                nodes = generate_traffic(nodes, params, t);
                
                % 2) Node decisions (state-machine step)
                for i = 1:N
                    nodes(i) = node_step(nodes(i), channel, params, t); % helper file
                end
                
                % 3) Channel resolves transmissions / collisions
                [channel, nodes, stats] = channel_step(channel, nodes, params, stats, t); % helper file
                
                % 4) Energy accounting / timers update (done mostly inside node_step/channel_step)
                % (some bookkeeping)
                % update node death
                for i = 1:N
                    if nodes(i).energy <= 0 && ~nodes(i).isDead
                        nodes(i).isDead = true;
                        nodes(i).energy = 0;
                    end
                end
                
                % optional early stop if all nodes dead
                if all([nodes.isDead])
                    % fprintf('All nodes dead at t=%d (trial %d)\n', t, trial);
                    break;
                end
            end % time loop
            
            % Collect trial-level results
            total_throughput(trial) = stats.successfulData; % packets
            total_collisions(trial) = stats.collisions;
            avg_energy_remaining(trial) = mean([nodes.energy]);
            total_bytes_transmitted(trial) = stats.bytesTransmitted;
            nodes_dead_fraction(trial) = sum([nodes.isDead]) / N;
            % Store new collision energy/current metrics
            energy_wasted_tx(trial) = stats.energy_wasted_tx;
            energy_wasted_rx(trial) = stats.energy_wasted_rx;
            current_wasted_tx(trial) = stats.current_wasted_tx;
            current_wasted_rx(trial) = stats.current_wasted_rx;
            
            if show_progress
                fprintf('done (succ=%d, coll=%d)\n', stats.successfulData, stats.collisions);
            end
        end % trials
        
        % Aggregate configuration results
        % config_results.(cfg).throughput_mean = mean(total_throughput) / T; % packets per time-step
        % config_results.(cfg).throughput_std  = std(total_throughput) / T;
        % config_results.(cfg).collisions_mean = mean(total_collisions);
        % config_results.(cfg).energy_mean     = mean(avg_energy_remaining);
        % config_results.(cfg).bytes_mean      = mean(total_bytes_transmitted);
        % config_results.(cfg).nodes_dead_fraction = mean(nodes_dead_fraction);
        config_results.(cfg).energy_wasted_tx = mean(energy_wasted_tx);
        config_results.(cfg).energy_wasted_rx = mean(energy_wasted_rx);
        config_results.(cfg).current_wasted_tx = mean(current_wasted_tx);
        config_results.(cfg).current_wasted_rx = mean(current_wasted_rx);
        
        % store for this config
        results(n_idx).N = N;
        results(n_idx).(cfg) = config_results.(cfg);
    end % configs loop
end % N_values

%% Plot results using helper
utils_plot(results, configs, N_values); % helper file - will plot comparisons

fprintf('\nSimulation complete. Results stored in variable ''results''.\n');
fprintf('You can adjust T, trials, or N_values at the top of mi_mac_sim.m for more experiments.\n\n');

%% ----------------- Nested helper functions -----------------
function stats = init_stats(N)
    stats.successfulData = 0;
    stats.collisions = 0;
    stats.bytesTransmitted = 0;
    stats.activeTransmissions = 0;
    stats.timeline = []; % optional
end

function nodes = generate_traffic(nodes, params, t)
    % Simple traffic generator:
    % Each node gets a new data packet with small probability lambda per time-step.
    %
    % This is intentionally simple; you can replace with a Poisson arrival
    % or scheduled traffic.
    lambda = params.traffic_lambda; % e.g., 0.0008
    Nloc = length(nodes);
    for ii = 1:Nloc
        if ~nodes(ii).isDead && rand() < lambda
            % enqueue a data packet (push to tx_queue)
            pkt.type = 'Data';
            pkt.size = params.packetSizes.Data;
            pkt.txAttempts = 0;
            nodes(ii).tx_queue{end+1} = pkt; %#ok<AGROW>
        end
    end
end
