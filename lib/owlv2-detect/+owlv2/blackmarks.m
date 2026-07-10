function [exitCode, stdout] = blackmarks(input, kvargs)
    %%BLACKMARKS Run the OWLv2 black-marks detection pipeline

    arguments
        input
        kvargs.Crop = []
        kvargs.Filter = []
        kvargs.Model = []
        kvargs.BatchSize = []
        kvargs.DetectionThreshold = []
        kvargs.LogLevel = []
        kvargs.DurationRange = []
        kvargs.SampleFrameCount = []
        kvargs.TopNMarks = []
        kvargs.Text = []
    end

    projectDir = owlv2.install();

    text = kvargs.Text;
    command = buildOwlv2Command("black-marks", input, text, kvargs);
    [exitCode, stdout] = uv.run(command, "Project", projectDir);
end