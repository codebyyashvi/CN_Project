function node = node_step(node, channel, params, t)
% node_step.m
% Advances the state of a single node by one time-step.
% Handles transitions between Idle, Sense, Transmit, Receive, and Backoff.
% Also updates energy consumption based on state.

% If node is dead, skip all actions
if node.isDead
    return;
end

dt = params.dt; % time per step
Eps = params.energy_per_step; % energy per-step (idle/sense/receive)
config = params.config;

% ------------------ STATE MACHINE -------------------
switch node.state
    
    %% 1. IDLE STATE
    case 'Idle'
        % Node consumes small idle energy each step
        node.energy = node.energy - Eps.idle;
        
        % If node has something to send in queue and not waiting for ACK → Sense channel
        if ~isempty(node.tx_queue) && ~node.waiting_for_ack
            node.state = 'Sense';
            node.timer = params.tau_sense;
        end

    %% 2. SENSE STATE
    case 'Sense'
        node.energy = node.energy - Eps.sense;
        node.timer = node.timer - 1;
        
        if node.timer <= 0
            % Channel check
            if strcmp(channel.state,'free')
                % Channel free → Transmit WakeUp
                node.state = 'Transmit';
                node.current_tx.type = 'W'; % WakeUp packet
                [dur, eTotal] = coil_tx_params('W', config, params);
                node.current_tx.duration = dur;
                node.current_tx.energyCost = eTotal;
                node.timer = dur;
            else
                % Channel busy → backoff
                node.state = 'Backoff';
                node.timer = ceil(params.tau_wait_base * (0.5 + rand())); % random backoff
            end
        end

    %% 3. TRANSMIT STATE
    case 'Transmit'
        node.energy = node.energy - (node.current_tx.energyCost / max(1,node.current_tx.duration));
        
        node.timer = node.timer - 1;
        
        if node.timer <= 0
            % Transmission finished
            pktType = node.current_tx.type;
            
            switch pktType
                case 'W' % WakeUp
                    % After WakeUp → wait for ACK
                    node.waiting_for_ack = true;
                    node.ack_deadline = t + params.tau_noAck;
                    node.state = 'Idle';
                    node.current_tx = [];
                    
                case 'Data'
                    % Data sent successfully
                    node.stats.success = node.stats.success + 1;
                    % Pop queue
                    if ~isempty(node.tx_queue)
                        node.tx_queue(1) = [];
                    end
                    node.waiting_for_ack = false;
                    node.state = 'Idle';
                    node.current_tx = [];
                    
                otherwise
                    % Generic finish
                    node.state = 'Idle';
                    node.current_tx = [];
            end
        end
        
    %% 4. BACKOFF STATE
    case 'Backoff'
        node.energy = node.energy - Eps.idle;
        node.timer = node.timer - 1;
        if node.timer <= 0
            node.state = 'Sense'; % retry sensing
            node.timer = params.tau_sense;
        end
        
    %% 5. RECEIVE STATE
    case 'Receive'
        node.energy = node.energy - Eps.receive;
        node.timer = node.timer - 1;
        if node.timer <= 0
            node.state = 'Idle';
        end

    otherwise
        % Unrecognized state — treat as Idle
        node.state = 'Idle';
end

% -------------------- ACK timeout --------------------
if node.waiting_for_ack && (t >= node.ack_deadline)
    % ACK timeout → retransmit WakeUp (go back to sensing)
    node.waiting_for_ack = false;
    node.state = 'Sense';
    node.timer = params.tau_sense;
    node.stats.collisions = node.stats.collisions + 1;
end

% Prevent negative energy
if node.energy < 0
    node.energy = 0;
    node.isDead = true;
end

end
