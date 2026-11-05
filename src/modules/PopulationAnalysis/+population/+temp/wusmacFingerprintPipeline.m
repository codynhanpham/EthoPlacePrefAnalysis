function out = wusmacFingerprintPipeline()
    %WUSMACFINGERPRINTPIPELINE Cross-cohort behavioral fingerprint for the WU-SMAC L3/L4 strains.
    %
    %   out = wusmacFingerprintPipeline()
    %
    %   Driver for cohort.fingerprintPipeline over the per-strain
    %   standardizedTables.mat files produced by
    %   population.stats.populationPositionOverTime (one 2-table protocol pair
    %   per strain). Each file must contain a variable named
    %   'standardizedTables' (or exactly one struct variable) holding the
    %   strain's 1x2 pair; table order is semantic:
    %       table 1 pre-stimulus = exploration/habituation
    %       table 2 pre-stimulus = baseline
    %
    %   Strains are processed as strain-split groups (reference genotype is
    %   matched within each strain, default 'WT'). Results (MAT + CSVs +
    %   figures) are written to .../WU-SMAC_L3_L4/fingerprint/ with a
    %   timestamped basename so reruns never clobber previous outputs.
    %
    %   The result is also assigned to 'wusmacFingerprintOut' in the base
    %   workspace for interactive inspection.
    %
    %   See also: cohort.fingerprintPipeline, population.stats.populationPositionOverTime

    %% Inputs - per-strain standardizedTables.mat files (1x2 protocol pairs)
    STANDARDIZED_TABLES = {
        % "D:/JOBS/WashU_Neuroscience/Behavior/WU-SMAC/PlacePreference/POPULATION/WU-SMAC/WU-SMAC_L3_L4/012 TSC2/L3/012_TSC2_standardizedTables.mat", ...
        % "D:/JOBS/WashU_Neuroscience/Behavior/WU-SMAC/PlacePreference/POPULATION/WU-SMAC/WU-SMAC_L3_L4/014 SCN1A/L3/014_SCN1A_standardizedTables.mat", ...
        % "D:/JOBS/WashU_Neuroscience/Behavior/WU-SMAC/PlacePreference/POPULATION/WU-SMAC/WU-SMAC_L3_L4/016 FBN1/L3/016_FBN1_standardizedTables.mat", ...
        % "D:/JOBS/WashU_Neuroscience/Behavior/WU-SMAC/PlacePreference/POPULATION/WU-SMAC/WU-SMAC_L3_L4/020 CACNA1A/L3/020_CACNA1A_standardizedTables.mat", ...
        % "D:/JOBS/WashU_Neuroscience/Behavior/WU-SMAC/PlacePreference/POPULATION/WU-SMAC/WU-SMAC_L3_L4/021 ZBTB10/L3/021_ZBTB10_standardizedTables.mat", ...
        % "D:/JOBS/WashU_Neuroscience/Behavior/WU-SMAC/PlacePreference/POPULATION/WU-SMAC/WU-SMAC_L3_L4/023 GRIN2A/L3/023_GRIN2A_standardizedTables.mat", ...
        % "D:/JOBS/WashU_Neuroscience/Behavior/WU-SMAC/PlacePreference/POPULATION/WU-SMAC/WU-SMAC_L3_L4/024 PTEN/L3/024_PTEN_standardizedTables.mat", ...
        % "D:/JOBS/WashU_Neuroscience/Behavior/WU-SMAC/PlacePreference/POPULATION/WU-SMAC/WU-SMAC_L3_L4/026 KDM5B/L3/026_KDM5B_standardizedTables.mat" ...


        "D:\JOBS\WashU_Neuroscience\Behavior\WU-SMAC\PlacePreference\POPULATION\In-House\Mecp2\20260908_standardizedTable_All.mat"
    };

    %% Pipeline options
    opts = struct();
    opts.ReferenceGenotype = 'WT';         % within-strain reference label (case-insensitive)
    opts.ReferenceGenotypeByStrain = {};   % e.g. {'strainB', 'HET', ...} for strains without WT
    opts.MinCohortN = 4;
    opts.NPerm = 10000;
    opts.NBoot = 2000;
    % opts.NPerm = 500;
    % opts.NBoot = 200;
    opts.IncludePooledSex = true;
    opts.RadarClampZ = 1.25;                % radar display clamp (radial units)
    opts.RadarRadialUnit = "z";  % "z" or "cliffsDelta" (rank-based dominance)
    opts.MakeFigures = true;

    %% Load the per-strain pairs WITHOUT inspecting contents beyond shape
    fprintf('Loading %d per-strain standardizedTables files...\n', numel(STANDARDIZED_TABLES));
    strainPairs = cell(numel(STANDARDIZED_TABLES), 1);
    for i = 1:numel(STANDARDIZED_TABLES)
        thisPath = char(STANDARDIZED_TABLES{i});
        if ~isfile(thisPath)
            error('population:temp:wusmacFingerprintPipeline:MissingInput', ...
                'Input file not found: %s', thisPath);
        end

        loaded = load(thisPath);
        stdTables = extractStandardizedTables(loaded, thisPath);
        strainPairs{i} = stdTables;
        fprintf('  [%d/%d] %s -> %s (%d tables)\n', i, numel(STANDARDIZED_TABLES), ...
            strrep(thisPath, '\', '/'), class(stdTables), numel(stdTables));
    end

    %% Output location: sibling 'fingerprint' folder under the shared cohort root
    %  Each input lives at <root>/<strain>/L3/<file>.mat; derive <root>.
    firstPath = char(STANDARDIZED_TABLES{1});
    cohortRoot = fileparts(fileparts(fileparts(firstPath)));
    outDir = fullfile(cohortRoot, 'fingerprint');
    if ~isfolder(outDir)
        mkdir(outDir);
    end
    baseName = sprintf('wusmacFingerprint_%s', char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));

    %% Run the cross-cohort fingerprint
    fprintf('Running cohort.fingerprintPipeline (%d strain groups)...\n', numel(strainPairs));
    out = cohort.fingerprintPipeline(strainPairs, ...
        ReferenceGenotype=opts.ReferenceGenotype, ...
        ReferenceGenotypeByStrain=opts.ReferenceGenotypeByStrain, ...
        MinCohortN=opts.MinCohortN, ...
        NPerm=opts.NPerm, ...
        NBoot=opts.NBoot, ...
        IncludePooledSex=opts.IncludePooledSex, ...
        MakeFigures=opts.MakeFigures, ...
        RadarClampZ=opts.RadarClampZ, ...
        RadarRadialUnit=opts.RadarRadialUnit, ...
        SavePath=fullfile(outDir, [baseName, '.mat']));

    %% Additional radar variant: grid-less, marker-less overview
    if opts.MakeFigures
        [figRadarNoGrid, radarEffects] = graphics.fingerprintRadar(out.fingerprint, ...
            StatsTable=out.statsTable, PerAnimalLong=out.perAnimalLong, ...
            RadialUnit=opts.RadarRadialUnit, ShowGrid=false, ShowMarkers=false, ...
            ClampZ=opts.RadarClampZ);
        out.figures.radarNoGrid = figRadarNoGrid;
        out.radarEffects = radarEffects; % long table of unclamped effect values (Strain/Family/Effect/Kind/Value)
    end

    %% Save figures alongside the results
    if opts.MakeFigures
        figureFiles = struct( ...
            'heatmap', @(fig) saveas(fig, fullfile(outDir, [baseName, '_heatmap.png'])), ...
            'pca', @(fig) saveas(fig, fullfile(outDir, [baseName, '_pca.png'])), ...
            'dotPlots', @(fig) saveas(fig, fullfile(outDir, [baseName, '_dotPlots.png'])), ...
            'radar', @(fig) saveas(fig, fullfile(outDir, [baseName, '_radar.png'])), ...
            'radarNoGrid', @(fig) saveas(fig, fullfile(outDir, [baseName, '_radarNoGrid.png'])));
        figFields = fieldnames(figureFiles);
        for i = 1:numel(figFields)
            fig = out.figures.(figFields{i});
            if isgraphics(fig, 'figure')
                figureFiles.(figFields{i})(fig);
            end
        end
    end

    %% Console summary
    printSummary(out);

    assignin('base', 'wusmacFingerprintOut', out); % for interactive inspection
    fprintf('Done. Outputs written to:\n  %s\n', strrep(outDir, '\', '/'));
end


function stdTables = extractStandardizedTables(loaded, sourcePath)
    %EXTRACTSTANDARDIZEDTABLES Pull the 1x2 standardizedTables struct out of a loaded MAT.
    %   Prefers the conventional variable name 'standardizedTables'; falls
    %   back to the single variable when the file contains exactly one.
    varNames = fieldnames(loaded);
    if ismember('standardizedTables', varNames)
        stdTables = loaded.standardizedTables;
    elseif isscalar(varNames)
        stdTables = loaded.(varNames{1});
    else
        error('population:temp:wusmacFingerprintPipeline:AmbiguousMatVariable', ...
            ['%s contains %d variables and none is named ''standardizedTables''. ' ...
            'Save the 1x2 pair under that variable name.'], sourcePath, numel(varNames));
    end

    if ~isstruct(stdTables)
        error('population:temp:wusmacFingerprintPipeline:NotAStruct', ...
            '%s: expected a struct array, got %s.', sourcePath, class(stdTables));
    end
    % Deeper shape/order validation (exactly 2 tables, subjects in both,
    % pre-stim + stimulus rows present) is performed by
    % cohort.internal.validateProtocolTables with actionable errors.
end


function printSummary(out)
    %PRINTSUMMARY Compact console summary of a fingerprint run.
    ct = out.cohortTable;
    st = out.statsTable;
    fprintf('\n=== WU-SMAC fingerprint summary ===\n');
    fprintf('Strain groups: %s\n', strjoin(out.strainGroups, ', '));
    fprintf('Cohorts (strain x genotype x sex, sex-specific): %d rows in cohortTable, %d in zMatrix\n', ...
        height(ct(~ct.PooledSex, :)), height(out.fingerprint.rowLabels));
    fprintf('Metric contexts in fingerprint: %d\n', height(out.fingerprint.colLabels));

    tierCounts = groupsummary(out.perAnimalLong, 'Tier');
    disp(tierCounts);

    if ~isempty(st)
        nSig = nnz(st.QFDR <= 0.05);
        fprintf('statsTable: %d comparisons, %d with q <= 0.05\n', height(st), nSig);
        if nSig > 0
            sig = sortrows(st(st.QFDR <= 0.05, :), 'QFDR');
            disp(sig(1:min(10, height(sig)), {'Strain', 'Genotype', 'Sex', 'Tier', 'Stimulus', 'Metric', 'Z', 'CliffDelta', 'QFDR'}));
        end
    else
        fprintf('statsTable: EMPTY (check cohort sizes vs MinCohortN and reference genotype labels).\n');
    end

    if ~isempty(out.mahalTable)
        fprintf('mahalTable (top 10 by MeanD2):\n');
        m = sortrows(out.mahalTable, 'MeanD2', 'descend');
        disp(m(1:min(10, height(m)), {'Strain', 'Genotype', 'Sex', 'NAnimals', 'NFeatures', 'MeanD2'}));
    end
end
