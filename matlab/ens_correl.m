function corr = ens_correl(base_var, base_time, state_var)
% ens_correl  Computes correlation of a variable at a time to a time series of
% another variable (could be the same one)

%Extract sample of base at base time
base_ens = base_var(base_time, :);

% size(base_ens)
% size(state_var)

% Loop through time to correlate with the other ensemble series
num_times = size(state_var, 1);
for i = 1:num_times
   x = corrcoef(base_ens, state_var(i, :));
   corr(i) = x(1, 2);
end 
