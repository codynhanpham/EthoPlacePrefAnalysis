function out = fingerprintPipeline(inputTables, kvargs)
    %%FINGERPRINTPIPELINE End-to-end cohort fingerprint pipeline.
    %
    %   out = cohort.fingerprintPipeline(inputTables)
    %
    %   Inputs:
    %       inputTables - EITHER an aggregate cross-strain standardizedTables
    %           struct array (exactly 2 ordered protocol tables; strain per
    %           subject comes from the metadata 'Gene' column), OR a cell array
    %           where each element is one strain's 2-element pair. Table ORDER
    %           is semantic: table 1's pre-stimulus window is the
    %           exploration/habituation period; table 2's is the baseline.
    %
    %   Name-Value Pair Arguments:
    %       - 'ReferenceGenotype': reference genotype within each strain. Default 'WT'.
    %       - 'ReferenceGenotypeByStrain': per-strain reference overrides
    %         ({strain, genotype, ...} pairs, struct, or dictionary). Default {}.
    %       - 'MinCohortN': minimum cohort/reference n for stats. Default 4.
    %       - 'NPerm': permutation resamples. Default 10000.
    %       - 'NBoot': bootstrap resamples for cohort median CI. Default 2000.
    %       - 'Whitelist': fingerprint whitelist struct override. Default curated.
    %       - 'EntropyBinSizeCm': arenaEntropy bin size. Default 5.
    %       - 'MidlineZoneHalfWidthCm': zoneOccupancy half-width. Default 10.
    %       - 'SlopeBinSec': speedSlope bin width. Default 60.
    %       - 'StimulusIncludesTrailingISI': passed to all metrics. Default true.
    %       - 'MetricsToInclude': subset of cohort metrics. Default all.
    %       - 'IncludePooledSex': flagged pooled-sex cohort rows. Default true.
    %       - 'MakeFigures': generate the four fingerprint figures. Default true.
    %       - 'RadarClampZ': display clamp (robust-z units) for the radar
    %         figure. Default 3.
    %       - 'RadarRadialUnit': radar effect unit, "z" (default) or
    %         "cliffsDelta" (rank-based dominance from statsTable).
    %       - 'SavePath': full path to an output .mat; per-table CSVs are
    %         written alongside with the same basename. Empty = no save.
    %         The parent directory must exist. Errors if any output file
    %         already exists unless Overwrite=true. Default ''.
    %
    %   Outputs (struct):
    %       perAnimalWide  - struct array (one per strain group) with .Stimulus
    %                        and .PreStimulus per-animal wide metric tables.
    %       perAnimalLong  - concatenated long per-animal table (all tiers).
    %       cohortTable    - descriptive cohort table (see cohort.fingerprint).
    %       fingerprint    - struct from cohort.fingerprint (zMatrix, labels, perAnimalZ, ...).
    %       statsTable     - Cliff's delta / permutation / FDR table.
    %       mahalTable     - Mahalanobis severity table.
    %       pcaStruct      - PCA diagnostic output (empty when MakeFigures=false).
    %       figures        - struct of figure handles (empty when MakeFigures=false).
    %       strainGroups   - string vector of strain group labels.
    %
    %   See also: cohort.summary, cohort.longify, cohort.fingerprint,
    %       cohort.fingerprintStats, cohort.internal.adaptPipelineInput

    arguments
        inputTables
        kvargs.ReferenceGenotype {mustBeTextScalar} = 'WT'
        kvargs.ReferenceGenotypeByStrain {} = {}
        kvargs.MinCohortN (1,1) double {mustBePositive, mustBeInteger} = 4
        kvargs.NPerm (1,1) double {mustBePositive, mustBeInteger} = 10000
        kvargs.NBoot (1,1) double {mustBePositive, mustBeInteger} = 2000
        kvargs.Whitelist struct = struct()
        kvargs.EntropyBinSizeCm (1,1) double {mustBePositive, mustBeFinite} = 5
        kvargs.MidlineZoneHalfWidthCm (1,1) double {mustBePositive, mustBeFinite} = 10
        kvargs.SlopeBinSec (1,1) double {mustBePositive, mustBeFinite} = 60
        kvargs.StimulusIncludesTrailingISI (1,1) logical = true
        kvargs.MetricsToInclude cell = {}
        kvargs.IncludePooledSex (1,1) logical = true
        kvargs.MakeFigures (1,1) logical = true
        kvargs.RadarClampZ (1,1) double {mustBePositive, mustBeFinite} = 3
        kvargs.RadarRadialUnit {mustBeTextScalar} = "z"
        kvargs.AlignProtocols (1,1) logical = true % reorder per-strain protocol pairs by stimfileName similarity so protocol slots mean the same thing across strains
        kvargs.SavePath {mustBeTextScalar} = ''
        kvargs.Overwrite (1,1) logical = false % allow replacing existing SavePath output files
    end

    groups = cohort.internal.adaptPipelineInput(inputTables);
    strainGroups = strings(numel(groups), 1);
    for g = 1:numel(groups)
        strainGroups(g) = groups{g}.strainLabel;
    end

    % Align each strain group's 2 protocol slots by stimfileName similarity
    % (joined tables carry their variations in a cell; canonical keys make
    % variations of the same protocol match each other). Reordering fixes
    % strain pairs that were passed in flipped order; low similarity warns.
    protocolAlignment = [];
    if numel(groups) > 1
        if kvargs.AlignProtocols
            [groups, protocolAlignment] = cohort.internal.alignProtocolSlots(groups);
            for g = 1:height(protocolAlignment)
                if protocolAlignment.Swapped(g)
                    fprintf(['Protocol alignment: group %s tables swapped to match the first strain group ' ...
                        '(slot 1 similarity %.2f, slot 2 similarity %.2f).\n'], ...
                        protocolAlignment.StrainGroup(g), ...
                        protocolAlignment.Slot1Similarity(g), protocolAlignment.Slot2Similarity(g));
                end
            end
        end
    end

    perAnimalWide = struct('StrainGroup', strings(0), 'Stimulus', cell(0), 'PreStimulus', cell(0));
    longParts = cell(numel(groups), 1);

    for g = 1:numel(groups)
        stdPair = groups{g}.tables;
        protocolLabels = cohort.internal.validateProtocolTables(stdPair);
        stimLabels = cohort.metrics.utils.getOutputStimNames(stdPair, {});

        wideStim = cohort.summary(stdPair, ...
            Period='stimulus', ...
            StimulusIncludesTrailingISI=kvargs.StimulusIncludesTrailingISI, ...
            MetricsToInclude=kvargs.MetricsToInclude, ...
            EntropyBinSizeCm=kvargs.EntropyBinSizeCm, ...
            MidlineZoneHalfWidthCm=kvargs.MidlineZoneHalfWidthCm, ...
            SlopeBinSec=kvargs.SlopeBinSec);

        widePre = cohort.summary(stdPair, ...
            Period='pre-stimulus', ...
            StimulusIncludesTrailingISI=kvargs.StimulusIncludesTrailingISI, ...
            MetricsToInclude=kvargs.MetricsToInclude, ...
            EntropyBinSizeCm=kvargs.EntropyBinSizeCm, ...
            MidlineZoneHalfWidthCm=kvargs.MidlineZoneHalfWidthCm, ...
            SlopeBinSec=kvargs.SlopeBinSec);

        perAnimalWide(g).StrainGroup = strainGroups(g);
        perAnimalWide(g).Stimulus = wideStim;
        perAnimalWide(g).PreStimulus = widePre;

        longParts{g} = cohort.longify(wideStim, widePre, ...
            ProtocolLabels=protocolLabels, StimLabels=stimLabels);
    end

    perAnimalLong = vertcat(longParts{:});

    fp = cohort.fingerprint(perAnimalLong, ...
        Whitelist=kvargs.Whitelist, ...
        ReferenceGenotype=kvargs.ReferenceGenotype, ...
        ReferenceGenotypeByStrain=kvargs.ReferenceGenotypeByStrain, ...
        MinCohortN=kvargs.MinCohortN, ...
        NBoot=kvargs.NBoot, ...
        IncludePooledSex=kvargs.IncludePooledSex);

    st = cohort.fingerprintStats(perAnimalLong, fp, ...
        NPerm=kvargs.NPerm, ...
        MinCohortN=kvargs.MinCohortN);

    % Surface all-ineligible runs loudly: an empty statsTable / all-NaN zMatrix
    % saved without comment reads as "no differences found" downstream.
    if height(st.statsTable) == 0 || ~any(isfinite(fp.zMatrix), 'all')
        reasonSummary = 'n/a';
        ineligibleRows = fp.cohortTable(~fp.cohortTable.statsEligible & ~fp.cohortTable.PooledSex, :);
        if ~isempty(ineligibleRows.Reason)
            reasons = string(ineligibleRows.Reason);
            [uReasons, ~, iu] = unique(reasons);
            counts = accumarray(iu, 1);
            reasonSummary = strjoin(uReasons + " x" + counts, ", ");
        end
        warning('cohort:fingerprintPipeline:NoEligibleCohorts', ...
            ['No eligible cohort x context comparisons were produced (statsTable has %d rows; zMatrix all-NaN: %d). ' ...
            'Check cohort sizes against MinCohortN and reference genotype labels. Ineligibility reasons: %s'], ...
            height(st.statsTable), all(isnan(fp.zMatrix), 'all'), reasonSummary);
    end

    pcaStruct = struct();
    figuresOut = struct();
    if kvargs.MakeFigures
        figHeat = graphics.fingerprintHeatmap(fp, st.statsTable);
        [pcaStruct, figPca] = graphics.fingerprintPca(fp);
        figDots = graphics.fingerprintDotPlots(fp);
        figRadar = graphics.fingerprintRadar(fp, ...
            StatsTable=st.statsTable, PerAnimalLong=perAnimalLong, ...
            RadialUnit=kvargs.RadarRadialUnit, ClampZ=kvargs.RadarClampZ);
        figuresOut.heatmap = figHeat;
        figuresOut.pca = figPca;
        figuresOut.dotPlots = figDots;
        figuresOut.radar = figRadar;
    end

    out = struct();
    out.perAnimalWide = perAnimalWide;
    out.perAnimalLong = perAnimalLong;
    out.cohortTable = fp.cohortTable;
    out.fingerprint = fp;
    out.statsTable = st.statsTable;
    out.mahalTable = st.mahalTable;
    out.pcaStruct = pcaStruct;
    out.figures = figuresOut;
    out.strainGroups = strainGroups;
    out.protocolAlignment = protocolAlignment;

    if strlength(string(kvargs.SavePath)) > 0
        savePathStr = char(string(kvargs.SavePath));
        [parentDir, baseName] = fileparts(savePathStr);
        if ~isfolder(parentDir)
            error('cohort:fingerprintPipeline:MissingSaveDir', ...
                'SavePath parent directory does not exist: %s', parentDir);
        end

        matPath = fullfile(parentDir, [baseName, '.mat']);
        csvSpecs = { ...
            out.perAnimalLong, '_perAnimalLong.csv'; ...
            out.cohortTable, '_cohortTable.csv'; ...
            out.statsTable, '_statsTable.csv'; ...
            out.mahalTable, '_mahalTable.csv'; ...
            out.fingerprint.perAnimalZ, '_perAnimalZ.csv'};
        csvExtNames = [{'.mat'}; csvSpecs(:, 2)];
        finalPaths = [{matPath}; fullfile(parentDir, baseName + string(csvSpecs(:, 2)))];

        % Guard against silently clobbering previous results.
        existing = finalPaths(cellfun(@(p) isfile(char(p)), finalPaths));
        if ~isempty(existing) && ~kvargs.Overwrite
            error('cohort:fingerprintPipeline:SavePathExists', ...
                ['SavePath output file(s) already exist:\n%s\nPass Overwrite=true to replace them, ' ...
                'or choose a different SavePath.'], strjoin(cellstr(existing), newline));
        end

        % Write everything into a temporary directory first, then move the
        % files into place, so a mid-sequence failure cannot leave a
        % half-updated artifact set.
        tmpDir = fullfile(parentDir, [baseName, '.partial']);
        if isfolder(tmpDir)
            rmdir(tmpDir, 's');
        end
        mkdir(tmpDir);
        save(fullfile(tmpDir, [baseName, '.mat']), '-struct', 'out');
        for i = 1:size(csvSpecs, 1)
            writetable(csvSpecs{i, 1}, fullfile(tmpDir, string(baseName) + csvSpecs{i, 2}));
        end
        for i = 1:numel(finalPaths)
            movefile(fullfile(tmpDir, [baseName, csvExtNames{i}]), char(finalPaths(i)));
        end
        rmdir(tmpDir, 's');
        out.savePath = string(matPath);
    end
end
