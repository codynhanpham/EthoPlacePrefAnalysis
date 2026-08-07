function cleanup = clearLinuxLibraryPath()
%CLEARLINUXLIBRARYPATH Temporarily clear MATLAB's Linux library path.
%
% System-installed or portable FFmpeg binaries can be incompatible with
% MATLAB's custom LD_LIBRARY_PATH. The returned onCleanup object restores
% the original value when it is cleared or goes out of scope.

    if isunix && ~ismac
        oldPath = getenv('LD_LIBRARY_PATH');
        setenv('LD_LIBRARY_PATH', '');
        cleanup = onCleanup(@() setenv('LD_LIBRARY_PATH', oldPath));
    else
        cleanup = onCleanup(@() []);
    end
end
