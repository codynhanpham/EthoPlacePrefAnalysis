function [d2, lambdaUsed] = mahalanobisScores(Xwt, Xtargets, minLambda)
    %MAHALANOBISSCORES Shrinkage Mahalanobis D2 of targets vs a baseline matrix.
    %
    %   [d2, lambdaUsed] = outlier.internal.mahalanobisScores(Xwt, Xtargets, minLambda)
    %
    %   Pairwise-complete: each target row is scored on its observed (finite)
    %   features only, against a shrinkage-covariance fit of the baseline
    %   subjects that are complete on that same feature subset. Fits are cached
    %   per missingness pattern.
    %
    %   Inputs:
    %       Xwt       - [nBaseline x p] baseline feature matrix (NaN allowed)
    %       Xtargets  - [nTargets  x p] feature matrix to score (NaN allowed)
    %       minLambda - starting shrinkage lambda in [0, 1] (auto-raised until
    %                   the covariance is well conditioned)
    %
    %   Outputs:
    %       d2         - [nTargets x 1] Mahalanobis D2 (NaN where no fit was
    %                    possible, e.g. too few complete baseline rows)
    %       lambdaUsed - [nTargets x 1] shrinkage lambda actually used per target
    %
    %   See also: outlier.internal.fitShrunkInverse, outlier.internal.looBaselineD2

    nTe = size(Xtargets, 1);
    d2 = nan(nTe, 1);
    lambdaUsed = nan(nTe, 1);
    cache = containers.Map('KeyType', 'char', 'ValueType', 'any');

    for i = 1:nTe
        pat = isfinite(Xtargets(i, :));
        key = mat2str(pat);
        if isKey(cache, key)
            fit = cache(key);
        else
            fit = outlier.internal.fitShrunkInverse(Xwt, pat, minLambda);
            cache(key) = fit;
        end
        % No-fit is signalled by empty fields (a 1x1 struct is never isempty).
        if isempty(fit.mu) || isempty(fit.Sinv)
            continue;
        end
        lambdaUsed(i) = fit.lambda;
        x = Xtargets(i, pat)' - fit.mu;
        d2(i) = x' * fit.Sinv * x;
    end
end
