function utils_plot(results, configs, N_values)
% utils_plot.m
% Plots collision-based energy and current wastage metrics
% (Matches the graphs shown in the MI-MAC research paper)

figure('Name','MI-MAC Energy and Current Wastage Analysis');
tiledlayout(3,1);

% -------- Plot 1: Total Energy Wasted due to Collisions --------
nexttile;
hold on;
for c = 1:length(configs)
    cfg = configs{c};
    energyWasted = arrayfun(@(r) ...
        r.(cfg).energy_wasted_tx + r.(cfg).energy_wasted_rx, results);
    plot(N_values, energyWasted, '-o', 'LineWidth', 1.8, 'DisplayName', cfg);
end
title('Total Energy Wasted due to Collisions');
xlabel('Number of Nodes (N)');
ylabel('Energy (Joules)');
legend('Location','northwest');
grid on;

% -------- Plot 2: Current Wasted by Transmitting Nodes --------
nexttile;
hold on;
for c = 1:length(configs)
    cfg = configs{c};
    currentTx = arrayfun(@(r) r.(cfg).current_wasted_tx, results);
    plot(N_values, currentTx, '-s', 'LineWidth', 1.8, 'DisplayName', cfg);
end
title('Current Wasted by Transmitting Nodes');
xlabel('Number of Nodes (N)');
ylabel('Current (A)');
legend('Location','northwest');
grid on;

% -------- Plot 3: Current Wasted by Receiving Nodes --------
nexttile;
hold on;
for c = 1:length(configs)
    cfg = configs{c};
    currentRx = arrayfun(@(r) r.(cfg).current_wasted_rx, results);
    plot(N_values, currentRx, '-^', 'LineWidth', 1.8, 'DisplayName', cfg);
end
title('Current Wasted by Receiving Nodes');
xlabel('Number of Nodes (N)');
ylabel('Current (A)');
legend('Location','northwest');
grid on;

sgtitle('Energy and Current Wastage due to Collisions in MI-MAC Protocol');
end
