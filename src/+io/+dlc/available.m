function [bool, bin] = available()
    %%AVAILABLE Check if the DLC toolbox is available
    %   This returns true if ./private/DLCTool/DLCTool.exe exists (relative to this file)
    %   AND that system('DLCtool.exe -h') returns a successful exit code.
    %
    %   [bool, bin] = dlc.available()
    %
    %   Outputs:
    %       bool (logical): true if DLC toolbox is available
    %       bin (char): path to DLC binary, if available, otherwise empty

    thisfilepath = fileparts(mfilename('fullpath'));
    dlctooldirpath = fullfile(thisfilepath, 'private', 'DLCTool');

    if ispc()
        dlctoolpath = fullfile(dlctooldirpath, 'DLCTool.exe');
    else
        dlctoolpath = fullfile(dlctooldirpath, 'DLCTool');
    end

    dlcbinExists = isfile(dlctoolpath);
    bin = '';
    if ~dlcbinExists
        bool = false;
        return;
    end

    % Check if the binary runs successfully
    cmd = sprintf('"%s" -h', dlctoolpath);
    [status, ~] = system(cmd);
    bool = (status == 0);
    if bool
        bin = utils.path.canonicalize(char(dlctoolpath));
    end
end