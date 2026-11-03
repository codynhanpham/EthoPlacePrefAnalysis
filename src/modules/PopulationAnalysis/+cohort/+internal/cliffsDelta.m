function delta = cliffsDelta(x, y)
    %CLIFFSDELTA Cliff's delta between two samples (dominance statistic).
    %   delta = (#(x > y) - #(x < y)) / (numel(x) * numel(y)); pairs with
    %   x == y contribute 0. Bounded to [-1, 1]; +1 means every x exceeds
    %   every y. Same convention as the CliffDelta column produced by
    %   cohort.fingerprintStats (which adds a label-swap permutation test on
    %   top of this statistic). NaN inputs propagate: pre-filter callers.
    x = x(:);
    y = y(:);
    if isempty(x) || isempty(y)
        delta = NaN;
        return;
    end
    delta = sum(sign(x - y'), 'all') / (numel(x) * numel(y));
end
