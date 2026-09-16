function fit = fitShrunkInverse(Xwt, pat, minLambda)
    %FITSHRUNKINVERSE Shrunk inverse covariance fit on complete baseline rows.
    %
    %   fit = outlier.internal.fitShrunkInverse(Xwt, pat, minLambda)
    %
    %   Fits the mean and inverse covariance of the baseline rows that are
    %   complete (all-finite) on the feature subset selected by the logical
    %   pattern `pat`, using Ledoit-Wolf-style shrinkage toward a scaled
    %   identity. Lambda is raised from `minLambda` in steps of 0.1 until the
    %   shrunk covariance is well conditioned (rcond > 1e-10); the last resort
    %   is full shrinkage to the scaled identity (lambda = 1).
    %
    %   Returns an empty struct fields when no fit is possible (e.g. fewer
    %   complete baseline rows than features + 2).
    %
    %   Output struct fields:
    %       fit.mu     - [p x 1] baseline mean on the selected features
    %       fit.Sinv   - [p x p] inverse shrunk covariance
    %       fit.lambda - shrinkage lambda used (NaN when no fit)

    fit = struct('mu', [], 'Sinv', [], 'lambda', NaN);
    cols = find(pat);
    p = numel(cols);
    if p == 0
        return;
    end
    Xw = Xwt(:, cols);
    ok = all(isfinite(Xw), 2);
    Xw = Xw(ok, :);
    n = size(Xw, 1);
    if n < 2
        return;   % at least two rows are needed to estimate covariance
    end

    mu = mean(Xw, 1)';
    Xc = Xw - mu';
    S = (Xc' * Xc) / (n - 1);

    % Shrink toward (trace(S)/p) * I; raise lambda until well-conditioned.
    shrinkTarget = trace(S) / p;
    lambdas = minLambda:0.1:1;
    Sinv = [];
    lamUsed = NaN;
    for lam = lambdas
        Ss = (1 - lam) * S + lam * shrinkTarget * eye(p);
        if rcond(Ss) > 1e-10
            Sinv = inv(Ss);
            lamUsed = lam;
            break;
        end
    end
    if isempty(Sinv)
        % Last resort: full shrinkage to scaled identity.
        if shrinkTarget > 0
            Sinv = eye(p) / shrinkTarget;
            lamUsed = 1;
        else
            return;
        end
    end
    fit.mu = mu;
    fit.Sinv = Sinv;
    fit.lambda = lamUsed;
end
