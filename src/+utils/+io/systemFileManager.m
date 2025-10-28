function systemFileManager(location)
    location = fullfile(location);
    if isempty(location) || (~isfolder(location) && ~isfile(location))
        return;
    end

    location = char(location);

    if ispc
        C = evalc(['!explorer ' location]);

    elseif isunix
        if ismac
            C = evalc(['!open ' location]);

        else
            fMs = {...
                'xdg-open'   % most generic one
                'gvfs-open'  % successor of gnome-open
                'gnome-open' % older gnome-based systems               
                'kde-open'   % older KDE systems
            };
            C = '.';
            ii = 1;
            while ~isempty(C)                
                C = evalc(['!' fMs{ii} ' ' location]);
                ii = ii +1;
            end

        end
    else
        error('Unrecognized operating system.');
    end

    if ~isempty(C)
        error(['Error while opening directory in default file manager.\n',...
            '%s'], C); 
    end

end