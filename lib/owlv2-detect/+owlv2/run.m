function [exitCode, stdout] = run(input, text, kvargs)
    %%RUN Run the default OWLv2-Detect general pipeline

    arguments
        input = []
        text = []
        kvargs.Crop = []
        kvargs.Filter = []
        kvargs.Model = []
        kvargs.BatchSize = []
        kvargs.DetectionThreshold = []
        kvargs.LogLevel = []
    end

    projectDir = owlv2.install();

    command = buildOwlv2Command("", input, text, kvargs);
    [exitCode, stdout] = uv.run(command, "Project", projectDir);
    % [exitCode, stdout] = uv.run(command, "Project", projectDir, "UpdateCallbackFcn", createLiveStdoutCallback());
end