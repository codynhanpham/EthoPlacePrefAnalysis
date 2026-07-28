function [status, elapsedTime, outputDestination] = runSLEAP(modelPaths, videoFiles, kvargs)
    %%RUNSLEAP Run SLEAP-NN prediction on specified video files.
    arguments
        modelPaths (1,:) cell
        videoFiles (1,:) {mustBeFile}
        kvargs.Options (1,1) struct = struct()
        kvargs.UpdateCallbackFcn (1,1) function_handle = @(varargin) []
    end

    [isAvailable, ~] = io.sleap.available();
    if ~isAvailable
        error('io:sleap:runSLEAP:Unavailable', ...
            'SLEAP is not available. Please install it with io.sleap.install().');
    end

    videoFiles = cellstr(videoFiles);
    outputDestination = fullfile(fileparts(videoFiles{1}), 'sleap');
    if ~isfolder(outputDestination)
        mkdir(outputDestination);
    end

    % Use the project-local uv executable returned by install().
    [uvpath, sleapdir] = io.sleap.install();

    quotedVideos = cellfun(@(p) sprintf('"%s"', p), videoFiles, 'UniformOutput', false);
    quotedModels = cellfun(@(p) sprintf('"%s"', p), modelPaths, 'UniformOutput', false);
    cmd = sprintf('"%s" run --project "%s" sleap-nn predict --data_path %s --model_paths %s --output_path "%s"', ...
        uvpath, sleapdir, strjoin(quotedVideos, ' '), strjoin(quotedModels, ' '), outputDestination);

    optionNames = fieldnames(kvargs.Options);
    for i = 1:numel(optionNames)
        name = optionNames{i};
        value = kvargs.Options.(name);
        if ismember(name, {'CONFIG_ROOT', 'model_paths', 'coordsUnit', 'arena'}) || isempty(value)
            continue;
        end
        optionName = ['--' strrep(name, '_', '-')];
        if islogical(value) && isscalar(value)
            if value
                cmd = sprintf('%s %s', cmd, optionName);
            end
        elseif isnumeric(value) && isscalar(value)
            cmd = sprintf('%s %s %g', cmd, optionName, value);
        elseif ischar(value) || (isstring(value) && isscalar(value))
            cmd = sprintf('%s %s "%s"', cmd, optionName, value);
        end
    end

    startTime = tic;
    exitCode = io.dlc.system.execute(cmd, kvargs.UpdateCallbackFcn);
    elapsedTime = toc(startTime);
    status = (exitCode == 0);
    if exitCode ~= 0
        error('io:sleap:runSLEAP:ExecutionFailed', ...
            'SLEAP execution failed with exit code %d (elapsed time: %.2f seconds)', exitCode, elapsedTime);
    end
end