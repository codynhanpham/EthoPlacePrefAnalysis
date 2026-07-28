function ok = sleapdoctor(sleapdir, kvargs)
    arguments
        sleapdir (1,:) char
        kvargs.Verbose (1,1) logical = false
    end
    if ~isfolder(sleapdir) || ~isfolder(fullfile(sleapdir, '.venv'))
        ok = false;
        return;
    end

    currentdir = pwd;
    cleanup = onCleanup(@() cd(currentdir));
    cd(sleapdir);
    [status, cmdOut] = uv.cmd('run sleap doctor');
    notfounderrincl = {'Failed to spawn: `sleap`','Caused by: program not found'};

    if status ~= 0
        if any(contains(cmdOut, notfounderrincl))
            ok = false;
            return;
        end
        ok = false;
        return;
    end

    if kvargs.Verbose
        fprintf('SLEAP doctor check passed successfully. STDOUT:\n%s\n\n', cmdOut);
    end
    ok = true;
end
