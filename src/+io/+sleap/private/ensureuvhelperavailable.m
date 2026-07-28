function [uvpath, helperResolved] = ensureuvhelperavailable(thisdir, verbose)
    helperResolved = false;
    if isempty(meta.package.fromName('uv'))
        [helperRoot, found] = bootstrapuvhelpernamespace(thisdir, verbose);
        if ~found
            error('%s', buildmissinguvhelpererror(thisdir));
        end
        helperResolved = true;
        if verbose
            fprintf('Added uv helper root to MATLAB path for this session: %s\n', helperRoot);
        end
    end

    if isempty(which('uv.install'))
        error('%s', buildmissinguvhelpererror(thisdir));
    end
    [uvpath, ~] = uv.install();
end
