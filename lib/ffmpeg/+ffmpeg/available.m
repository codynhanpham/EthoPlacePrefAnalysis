function [bool, bin] = available()
    %%AVAILABLE Check if ffmpeg is available on the system, either via system path or portable binaries.
    %
    % [bool, bin] = ffmpeg.available()
    %
    % Outputs:
    %   bool (logical): true if ffmpeg is available
    %   bin (char): path to ffmpeg binary, if available, otherwise empty
    %
    % If you do not have ffmpeg installed system/user-wide, grab the executables for your OS at https://www.ffmpeg.org/download.html and place them in the "bin" folder located in this package '/lib/ffmpeg/bin'

    persistent cachedFFmpegAvailable cachedFFmpegBin
    
    [status, ~] = system('ffmpeg -version');

    if ~isempty(cachedFFmpegAvailable) && ~isempty(cachedFFmpegBin) && status == 0
        bool = cachedFFmpegAvailable;
        bin = cachedFFmpegBin;
        return
    end

    if status == 0
        bool = true;
        % Log the base output of system commands (some can inject leading warning/error messages before actual command output)
        [~, basesystemoutput] = system('echo');
        basesystemoutput = strtrim(basesystemoutput);
        if ispc
            [~, bin] = system('where ffmpeg');
            bin = strtrim(bin);
        else
            [~, bin] = system('which ffmpeg');
            bin = strtrim(bin);
        end
        if startsWith(bin, basesystemoutput)
            bin = strtrim(extractAfter(bin, strlength(basesystemoutput)));
        end
        return
    end

    % If not found in system path, check portable binaries
    if ispc
        bin = fullfile(fileparts(mfilename('fullpath')), '..', 'bin', 'ffmpeg.exe');
    else
        bin = fullfile(fileparts(mfilename('fullpath')), '..', 'bin', 'ffmpeg');
    end
    if isfile(bin)
        [status, ~] = system(['"', bin, '" -version']);
        if status == 0
            bool = true;
            bin = ffmpeg.utils.canonicalize(char(bin));
            return
        end
    end
    bool = false;
    bin = '';

    cachedFFmpegAvailable = bool;
    cachedFFmpegBin = bin;
end