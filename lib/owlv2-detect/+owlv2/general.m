function [exitCode, stdout] = general(input, text, kvargs)
    %%GENERAL Run the explicit OWLv2 general detection pipeline

    arguments
        input
        text
        kvargs.Crop = []
        kvargs.Filter = []
        kvargs.Model = []
        kvargs.BatchSize = []
        kvargs.DetectionThreshold = []
        kvargs.LogLevel = []
    end

    projectDir = owlv2.install();

    command = buildOwlv2Command("general", input, text, kvargs);
    [exitCode, stdout] = uv.run(command, "Project", projectDir);
end