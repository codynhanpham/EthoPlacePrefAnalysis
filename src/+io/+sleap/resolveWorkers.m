function workers = resolveWorkers(workersArg, userConfig, nVideos)
    %%RESOLVEWORKERS Resolve the effective number of parallel SLEAP prediction workers.
    %   INTERNAL HELPER: intended only for io.sleap.predict and other functions in
    %   the io.sleap namespace. It lives in the public package (rather than
    %   private/) solely so that the unit tests in tests/+io/+sleap/ can reach it
    %   (MATLAB private-folder visibility is folder-based and does not extend to
    %   same-package functions in the tests/ root). Not part of the public API.
    %
    %   workers = io.sleap.resolveWorkers(workersArg, userConfig, nVideos)
    %
    %   Resolution order (precedence):
    %       1. workersArg when it is greater than 1 (explicit named argument to predict()).
    %       2. userConfig.workers when the field exists and is non-empty.
    %       3. Fallback of 1.
    %   The resolved value is then clamped to the number of input videos (nVideos).
    %
    %   Inputs:
    %       workersArg (1,1) double - Value of the 'Workers' name-value argument (already
    %           validated as a positive integer scalar by predict()'s arguments block).
    %       userConfig (1,1) struct - SLEAP user configuration; may or may not contain a
    %           'workers' field. A missing field or an empty value means "not configured".
    %       nVideos (1,1) double - Number of input videos; used for clamping.
    %
    %   Outputs:
    %       workers (1,1) double - Effective number of parallel workers (>= 1).
    %
    %   Errors:
    %       io:sleap:runSLEAP:InvalidWorkers - userConfig.workers is defined but is not a
    %           positive integer scalar.

    arguments
        workersArg (1,1) double
        userConfig (1,1) struct
        nVideos (1,1) double
    end

    if ~isfinite(workersArg) || workersArg < 1 || workersArg ~= floor(workersArg)
        error('io:sleap:runSLEAP:InvalidWorkers', ...
            'Workers argument must be a positive integer scalar, got: %s', describeValue(workersArg));
    end

    if workersArg > 1
        % An explicit named argument > 1 takes precedence over any config value.
        workers = workersArg;
    elseif isfield(userConfig, 'workers') && ~isempty(userConfig.workers)
        configWorkers = userConfig.workers;
        if ~(isnumeric(configWorkers) && isscalar(configWorkers) && isfinite(configWorkers) && ...
                configWorkers >= 1 && configWorkers == floor(configWorkers))
            error('io:sleap:runSLEAP:InvalidWorkers', ...
                'SleapUserConfig.workers must be a positive integer scalar, got: %s', describeValue(configWorkers));
        end
        workers = double(configWorkers);
    else
        % No key or no value in the config: default to sequential processing.
        workers = 1;
    end

    % Clamp to the number of input videos; more workers than videos is wasteful.
    workers = min(workers, max(nVideos, 1));
end

function txt = describeValue(value)
    %DESCRIBEVALUE Compact display of a value for error messages.
    try
        txt = strtrim(evalc('disp(value)'));
    catch
        txt = sprintf('<%s>', class(value));
    end
end
