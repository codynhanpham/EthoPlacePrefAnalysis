function exportInfo = saveProgressionStatsTables(stats, outputDir, runStamp)
    %%SAVEPROGRESSIONSTATSTABLES Export progression analysis tables to TSV.
    %
    % exportInfo = saveProgressionStatsTables(stats, outputDir, runStamp)

    arguments
        stats (1,1) struct
        outputDir (1,1) string
        runStamp (1,1) string
    end

    if strlength(outputDir) == 0 || strlength(runStamp) == 0
        error('saveProgressionStatsTables:invalidPath', 'outputDir and runStamp must be non-empty.');
    end

    outputDir = char(outputDir);
    runStamp = char(runStamp);

    exportInfo = struct();
    exportInfo.outputDir = outputDir;
    exportInfo.commandWindowLogTxt = fullfile(outputDir, ['mecp2_pilot_stats_' runStamp '_command_window.log']);
    exportInfo.commandWindowLogTsv = fullfile(outputDir, ['mecp2_pilot_stats_' runStamp '_command_window.tsv']);
    exportInfo.summaryTsv = fullfile(outputDir, ['mecp2_pilot_stats_' runStamp '_summary.tsv']);

    analysisTbl = buildProgressionExportTable(stats);
    writeTsvTable(analysisTbl, exportInfo.commandWindowLogTsv);

    if isfield(stats, 'summary') && istable(stats.summary)
        writeTsvTable(stats.summary, exportInfo.summaryTsv);
    else
        writeTsvTable(emptyExportTable(), exportInfo.summaryTsv);
    end
end

function writeTsvTable(tbl, filePath)
    filePath = char(string(filePath));
    if isempty(filePath)
        error('saveProgressionStatsTables:emptyFileName', 'FILENAME must be a non-empty character vector or string scalar.');
    end
    writetable(tbl, filePath, 'FileType', 'text', 'Delimiter', '\t');
end

function tbl = emptyExportTable()
    tbl = table();
end
