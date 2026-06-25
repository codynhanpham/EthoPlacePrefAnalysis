function [canRun, state] = canRunWithCuda(newValue)
    %%CANRUNWITHCUDA Persistent global CUDA capability state for ffmpeg.
    %
    %   canRun = ffmpeg.utils.canRunWithCuda()
    %   Returns true if ffmpeg is known to run successfully with CUDA
    %   hardware acceleration flags. This is a single global state shared
    %   across all ffmpeg commands in the namespace - if one command can
    %   run with CUDA, all are assumed to be able to.
    %
    %   The first time it is queried, it defaults to the result of
    %   ffmpeg.cuda.available() (i.e. whether nvidia-smi reports a GPU).
    %   This is only a proxy - it does NOT guarantee the ffmpeg binary was
    %   built with CUDA support. Callers should attempt a CUDA command and
    %   update the state on failure so subsequent calls skip straight to
    %   the default (-hwaccel auto) path.
    %
    %   canRun = ffmpeg.utils.canRunWithCuda(false)
    %   Marks ffmpeg as unable to run with CUDA. Persisted for the
    %   duration of the MATLAB session.
    %
    %   canRun = ffmpeg.utils.canRunWithCuda(true)
    %   Marks ffmpeg as confirmed able to run with CUDA.
    %
    %   [canRun, state] = ffmpeg.utils.canRunWithCuda(___)
    %   Also returns the state logical for inspection/debugging.
    %
    % Inputs:
    %   newValue - (logical, optional) set the cached state. Omit to only query.
    %
    % Outputs:
    %   canRun - (logical) whether CUDA is currently considered usable for ffmpeg
    %   state  - (logical) same as canRun (for debugging/inspection)
    %
    % See also: ffmpeg.cuda.available, ffmpeg.run, ffmpeg.horzSplit, ffmpeg.vertSplit

    arguments
        newValue = []  % empty (query) or scalar logical (set)
    end

    % Validate: must be empty or a scalar logical
    if ~isempty(newValue)
        if ~(islogical(newValue) && isscalar(newValue))
            error('ffmpeg:utils:canRunWithCuda:InvalidArgument', ...
                'newValue must be empty or a scalar logical.');
        end
    end

    persistent cachedState
    if isempty(cachedState)
        % Default to the nvidia-smi proxy check. This does NOT verify
        % that the ffmpeg binary itself supports CUDA - callers must
        % update the state on first actual attempt.
        cachedState = ffmpeg.cuda.available();
    end

    if ~isempty(newValue)
        cachedState = newValue;
    end

    canRun = cachedState;
    state = cachedState;
end
