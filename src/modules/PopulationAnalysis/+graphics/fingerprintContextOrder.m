function colOrder = fingerprintContextOrder(fp)
    %FINGERPRINTCONTEXTORDER Canonical metric-context ordering for fingerprint figures.
    %
    %   colOrder = graphics.fingerprintContextOrder(fp)
    %
    %   Returns column indices into fp.colLabels ordered by tier
    %   [exploration | baseline | stim_all | per-stim | delta], then protocol,
    %   stimulus, metric family (cohort.internal.metricFamily), and metric
    %   name, so contexts of the same family are contiguous inside each
    %   tier/protocol/stimulus block. All fingerprint figures use this
    %   ordering so context columns appear in the same order across heatmap,
    %   radar, dot plots, and PCA.
    %
    %   See also: cohort.internal.metricFamily

    arguments
        fp struct
    end

    colLabels = fp.colLabels;
    tierOrder = ["exploration", "baseline", "stim_all", "per-stim", "delta"];
    tierCat = categorical(string(colLabels.Tier), tierOrder, 'Ordinal', true);
    family = cohort.internal.metricFamily(string(colLabels.Metric));
    [~, colOrder] = sortrows([string(double(tierCat)), ...
        string(colLabels.Protocol), string(colLabels.Stimulus), string(family), string(colLabels.Metric)]);
    colOrder = colOrder(:);
end
