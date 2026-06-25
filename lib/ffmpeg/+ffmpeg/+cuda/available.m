function bool = available()
    %%AVAILABLE Check if CUDA is available on the system for FFmpeg.
    %
    %   bool = ffmpeg.cuda.available()
    %
    % Output:
    %   bool - true if CUDA is available, false otherwise

    % CACHE: save the last result, if a system check has already been performed, it's unlikely to change during the same MATLAB session
    persistent cachedResult
    if ~isempty(cachedResult)
        bool = cachedResult;
        return
    end

    % Try to run `nvidia-smi` to check if NVIDIA GPU is available
    [status, ~] = system('nvidia-smi');
    bool = (status == 0);
    cachedResult = bool;
end