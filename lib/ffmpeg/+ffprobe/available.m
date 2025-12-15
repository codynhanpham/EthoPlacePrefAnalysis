function [bool, bin] = available()
    %%AVAILABLE Check if ffprobe is available on the system, either via system path or portable binaries.
    %
    % [bool, bin] = ffprobe.available()
    %
    % Outputs:
    %   bool (logical): true if ffprobe is available
    %   bin (char): path to ffprobe binary, if available, otherwise empty
    %
    % If you do not have ffprobe installed system/user-wide, grab the executables for your OS at https://www.ffmpeg.org/download.html and place them in the "bin" folder located in this package '/lib/ffmpeg/+ffmpeg/bin'

    persistent cachedFFprobeAvailable cachedFFprobeBin
    [status, ~] = system('ffprobe -version');
    if ~isempty(cachedFFprobeAvailable) && ~isempty(cachedFFprobeBin) && status == 0
        bool = cachedFFprobeAvailable;
        bin = cachedFFprobeBin;
        return
    end

    if status == 0
        bool = true;
        % Log the base output of system commands (some can inject leading warning/error messages before actual command output)
        [~, basesystemoutput] = system('echo');
        basesystemoutput = strtrim(basesystemoutput);
        if ispc
            [~, bin] = system('where ffprobe');
            bin = strtrim(bin);
        else
            [~, bin] = system('which ffprobe');
            bin = strtrim(bin);
        end
        if startsWith(bin, basesystemoutput)
            bin = strtrim(extractAfter(bin, strlength(basesystemoutput)));
        end
        return
    end

    % If not found in system path, check portable binaries
    if ispc
        bin = fullfile(fileparts(mfilename('fullpath')), '..', 'bin', 'ffprobe.exe');
    else
        bin = fullfile(fileparts(mfilename('fullpath')), '..', 'bin', 'ffprobe');
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

    cachedFFprobeAvailable = bool;
    cachedFFprobeBin = bin;
end