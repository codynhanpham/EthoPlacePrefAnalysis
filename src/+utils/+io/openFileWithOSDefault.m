function status = openFileWithOSDefault(filePath)
    %%OPENFILEWITHOSDEFAULT Opens a file using the operating system's default application for this file type.
    %
    %   status = utils.io.openFileWithOSDefault(filePath)
    %
    %   Inputs:
    %       filePath (text scalar): Full path to the file to be opened.
    %
    %   Outputs:
    %       status (logical): True if the file was opened successfully, false otherwise.
    %
    %   See also: utils.io.systemFileManager

    arguments
        filePath {mustBeTextScalar, mustBeFile}
    end

    status = true;
    filePath = char(filePath);

    if ispc
        try
            winopen(filePath);
        catch
            status = false;
        end

    elseif ismac
        [exitCode, ~] = system(sprintf('open %s', shellQuote(filePath)));
        status = exitCode == 0;

    elseif isunix
        fMs = {...
            'xdg-open'   % most generic one
            'gvfs-open'  % successor of gnome-open
            'gnome-open' % older gnome-based systems
            'kde-open'   % older KDE systems
        };

        status = false;
        for ii = 1:numel(fMs)
            [exitCode, ~] = system(sprintf('%s %s', fMs{ii}, shellQuote(filePath)));
            if exitCode == 0
                status = true;
                break;
            end
        end
    else
        status = false;
    end

end

function q = shellQuote(path)
    path = char(path);
    q = ['"' strrep(path, '"', '\"') '"'];
end