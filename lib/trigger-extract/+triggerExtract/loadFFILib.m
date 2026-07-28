function loadFFILib(libName, options)
    arguments
        libName {mustBeTextScalar} = 'trigger_extract' % Set to the Rust ddl/so name without extension
        options.ffiProjRoot {mustBeTextScalar, mustBeFolder} = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'private', 'trigger-extract') % Set to the root directory of the FFI project (for Rust projects, this is the directory containing Cargo.toml)
        options.relLibPath {mustBeTextScalar} = 'target/release/' % Optional relative path to the .dll/.so/.dylib from the FFI project root if it's other than the default target/release/
    end

    if libisloaded(libName)
        return;
    end

    libName = char(libName);
    options.relLibPath = char(options.relLibPath);
    if ispc
        libFileName = libName;
    else
        libFileName = ['lib', libName];
    end
    libFullPath = fullfile(options.ffiProjRoot, options.relLibPath, [libFileName, '.', getLibExtension()]);
    if ~isfile(libFullPath)
        error('Library file not found: %s', libFullPath);
    end

    warninglog = '';
    try
        [notfound, warninglog] = loadlibrary( ...
            libFullPath, ... % Full path to the library file
            fullfile(options.ffiProjRoot, 'bindings.h') ...
        );
        
        if ~isempty(notfound)
            error('Could not load library: %s', strjoin(notfound, ', '));
        end
    catch ME
        if ~isempty(warninglog)
            warning('Warning while loading library: %s', warninglog);
        end
        rethrow(ME);
    end
end

function ext = getLibExtension()
    if ispc
        ext = 'dll';
    elseif ismac
        ext = 'dylib';
    else
        ext = 'so';
    end
end