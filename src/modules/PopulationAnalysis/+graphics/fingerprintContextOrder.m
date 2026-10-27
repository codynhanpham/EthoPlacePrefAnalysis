function colOrder = fingerprintContextOrder(fp)
    %FINGERPRINTCONTEXTORDER Canonical metric-context ordering for fingerprint figures.
    %
    %   colOrder = graphics.fingerprintContextOrder(fp)
    %
    %   Returns column indices into fp.colLabels ordered by tier
    %   [exploration | baseline | stim_all | per-stim | delta], then protocol,
    %   stimulus, and metric name. All fingerprint figures use this ordering
    %   so context columns appear in the same order across heatmap, radar,
    %   dot plots, and PCA.

    arguments
        fp struct
    end

    colLabels = fp.colLabels;
    tierOrder = ["exploration", "baseline", "stim_all", "per-stim", "delta"];
    tierCat = categorical(string(colLabels.Tier), tierOrder, 'Ordinal', true);
    [~, colOrder] = sortrows([string(double(tierCat)), ...
        string(colLabels.Protocol), string(colLabels.Stimulus), string(colLabels.Metric)]);
    colOrder = colOrder(:);
end
