function unloadFFILib(libName)
    arguments
        libName {mustBeTextScalar} = 'trigger_extract' % Set to the Rust ddl/so name without extension
    end

    if libisloaded(libName)
        unloadlibrary(libName);
    end
end