function pth = localappdata()
    %%LOCALAPPDATA Returns known local app data directory based on OS
    %   On Windows, this is %LOCALAPPDATA%
    %   On Linux, this is ~/.local/share/
    %   On MacOS, this is ~/Library/Application Support/

    if ispc
        pth = getenv('LOCALAPPDATA');
    elseif isunix && ~ismac
        pth = fullfile(getenv('HOME'), '.local', 'share');
    elseif ismac
        pth = fullfile(getenv('HOME'), 'Library', 'Application Support');
    else
        error('Unsupported platform');
    end
end