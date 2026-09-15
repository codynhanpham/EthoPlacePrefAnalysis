function looD2 = looBaselineD2(Xwt, minLambda)
    %LOOBASELINED2 Leave-one-out Mahalanobis D2 of each baseline subject.
    %
    %   looD2 = outlier.internal.looBaselineD2(Xwt, minLambda)
    %
    %   Each baseline subject is scored against the remaining n-1 baseline
    %   subjects (shrinkage Mahalanobis D2 on its observed features). The
    %   resulting values form the empirical baseline null used both for
    %   calibrated empirical p-values (similarity ranking) and for multivariate
    %   outlier detection (outlier.excludeBaselineSubjects).
    %
    %   Inputs:
    %       Xwt       - [nBaseline x p] baseline feature matrix (NaN allowed)
    %       minLambda - starting shrinkage lambda in [0, 1]
    %
    %   Output:
    %       looD2 - [nBaseline x 1] LOO D2 per baseline subject (NaN where the
    %               subject could not be scored)
    %
    %   See also: outlier.internal.mahalanobisScores

    nWT = size(Xwt, 1);
    looD2 = nan(nWT, 1);
    for i = 1:nWT
        keep = true(nWT, 1);
        keep(i) = false;
        [d2i, ~] = outlier.internal.mahalanobisScores(Xwt(keep, :), Xwt(i, :), minLambda);
        looD2(i) = d2i;
    end
end
